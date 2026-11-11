# Window preview capture and diagnostics

## Capture path

KDockW uses KDE TaskManager and KWin's screencasting support to capture window
previews:

1. `PreviewPopup.qml` reads the task's window IDs from the TaskManager model.
2. Each `PreviewThumbnail.qml` creates a KDE
   `TaskManager.ScreencastingRequest`, which resolves the window UUID to a
   PipeWire node ID.
3. A `PipeWire.PipeWireSourceItem` connects to that node and renders frames as
   a Qt Quick item in KDockW's preview surface.
4. The normal path allows DMA-BUF so compatible GPU buffers can be imported
   without a CPU-to-GPU copy. KPipeWire may instead negotiate CPU-readable
   buffers if DMA-BUF is unavailable or disallowed.

The popup uses a separate, pre-mapped Qt Quick Wayland surface. Thumbnail
delegates are retained across routine model changes so their screencast streams
can pause and resume rather than being recreated for every update.

## Preview card layout

`PreviewPopup.qml` keeps the existing Wayland surface and reports the outer
shadow bounds to `PreviewController`, so placement and input-region geometry
include the visual effect. The initial visual review found the card had used
`Kirigami.Theme.backgroundColor` from the Window color set, which can be white
independently of the dock. The card, thumbnail backing, and existing
Firefox/app-name tooltip use `DockView.backgroundColor` (the resolved panel
style, tint/accent, and opacity) with a theme fallback only when the panel color
is transparent. Inactive thumbnails have a separate one-logical-pixel neutral
outline; its grayscale shade is selected from sRGB relative luminance of the
configured card color composited over the known KDE window surface. This is a
stable estimate for translucent cards, not a reading of wallpaper or the
actual blurred compositor output. Hover modestly increases contrast without
changing the neutral hue. The active window keeps the existing two-pixel
`Kirigami.Theme.highlightColor` outline. The inactive border is a lightweight
rounded Rectangle over the frame; it does not change capture viewport geometry
or add an offscreen layer. Card text retains its contrast-selected foreground,
and radius and soft shadow use existing dock settings. A single-window preview
keeps the approved red-circle close control in the top-right of the shared
header. Grouped previews put one matching control beside each window title and
omit the shared header close control. The tooltip change is styling only; the
separate Application Name Tooltip task still owns its behavior and switching
rules.

The app name is a compact card header; each window title sits immediately above
its own thumbnail. A grouped close action resolves that thumbnail's UUID against
the live child rows immediately before calling TaskManager, so a stale delegate
index cannot redirect it to a neighboring window. If the UUID has already
disappeared, the action does nothing. Thumbnail activation remains separate
from the close control. There is no arrow. Opacity animates on show/hide; the
controller's
existing geometry and edge placement remain in charge of screen bounds. For
Panel Inherit and Acrylic styles, the existing KWin blur/contrast helpers are
applied to the rounded card region on the same preview surface and updated when
style, opacity, or radius changes. No additional Wayland surface is created.

The PipeWire source is a custom `QQuickItem`. In the controlled owner A/B on
Plasma 6 / Wayland with CPU-only capture, the direct image path rendered the
same window correctly while the `MultiEffect`-masked path displayed no frame.
This confirms the regression lies in the additional QML composition path; it
does not identify a Qt/KPipeWire internal failure. The permanent candidate
therefore uses a direct `PipeWireSourceItem`, with no `MultiEffect`, wrapper
layer, or texture conversion around the source. The source stays visible and at
default opacity.

All application previews use one stable outer 16:10 card. The image fills the
card's inner area; only an active-window border reduces the viewport by its
stroke width. A custom `RoundedClipItem` installs a rounded `QSGClipNode` around
the direct PipeWire source. Its clip radius follows the inner card contour, so
the full viewport is filled and the image corners follow the card. The source
uses proportional centered Cover sizing; excess content is cropped equally
from opposite edges, with no stretching. Pixel output still requires manual
confirmation in the target KWin/Wayland renderer. Corner-fill overlays remain
unsuitable because flat colors can replace content incorrectly over
translucent cards or KWin blur. Each window title remains one elided line
constrained to the same outer slot.

When TaskManager marks a window minimized after KDockW has received a frame
while it was visible, `ClippedPipeWireSourceItem` retains its current scene-
graph subtree for as long as that source item remains alive. KWin can replace a
minimized window's stream with a placeholder, and `ready` only means a first
frame arrived; it does not prove that later frames still contain the window.
The source node alone is therefore not a durable frame cache across hiding or
recreating the popup.

While a preview row is visible and has received a frame, KDockW snapshots the
rendered thumbnail with `QQuickItem::grabToImage()` no more often than every
1.5 seconds. Snapshots are normalized to premultiplied RGBA, scaled to at most
640×400 and 1 MiB, then retained in a process-local cache capped at 32 images
and 32 MiB total. Its byte accounting uses `QImage::sizeInBytes()`. Restored-
window frames are eviction candidates before minimized-window frames. If all
entries are minimized, the hard limits still evict the least-recently-used
frame. Entries do not expire by age and remain keyed by the exact window UUID.
The cached image is shown for that UUID while minimized and after the popup is
recreated; a reused delegate resets its live source when its UUID changes.
The RAM cap covers cached image buffers; temporary readback buffers and
Qt Quick/GPU textures are outside that cache accounting.

Before the popup has ever been opened, `PreviewFramePrefetcher.qml` can seed
that cache for the foreground window. It starts one temporary
`ScreencastingRequest`/PipeWire source at a time, captures one rounded thumbnail
after the first real frame, then destroys the source. It does not run background
streams for every window. A short timeout bounds a missing first frame; if the
window is minimized or loses foreground before a frame is available, the
attempt stops and the app icon remains the fallback. A later restore or
activation can permit one new attempt. Opening the regular popup cancels the
background stream so it cannot add to the live preview's stream count. The
cache remains in memory only; when a UUID is absent from the settled
TaskManager model on two checks, its cached image and attempt state are removed.
The capture path still requests the PipeWire source's actual window stream size;
only the one-shot `grabToImage()` target is limited to the thumbnail's physical
pixel dimensions (maximum 640×400).

The prefetcher reports opt-in counters and elapsed times in diagnostic builds
(`KDOCKW_TASK_DIAGNOSTICS=1` and `KDOCKW_PREVIEW_METRICS=1`): queued/active
UUID, node/ready transition, readback target, cache result, and stream lifetime.
It never records frame pixels or window titles. The source cost is transient
but begins with a full-resolution PipeWire stream; actual CPU/GPU and latency
measurements still require the owner's Wayland session.

The preview surface size is derived from its actual content rows rather than
from a layout that fills the card and would otherwise create a circular
implicit-size dependency. The thumbnail row explicitly reports its width and
uses the delegate's measured implicit height. This keeps the card's left,
right, and bottom insets equal to the configured padding for each size preset.

The first rounded clipping implementation was structurally incorrect. Its
`RoundedClipItem::updatePaintNode()` returned a custom `QSGClipNode`, assuming
QML child items would be attached beneath that custom paint node. Qt 6 instead
uses a separate internal child container: a custom paint node and the QML
child-item nodes are siblings unless the built-in `QQuickItem::clip` path has
installed Qt's internal clip node. Qt's private `childContainerNode()` and
`QQuickWindow` synchronization code confirm that distinction. Therefore the
custom QSGClipNode never enclosed the sibling `PipeWireSourceItem`; changing
triangle topology alone could not affect its frames.

The current candidate subclasses KPipeWire's public `PipeWireSourceItem` and
wraps the exact node returned by its `updatePaintNode()` in a `QSGClipNode`.
That clip node is the root returned for the source item's own paint subtree;
KPipeWire's `PipeWireRenderNode` and its screen/cursor/damage `QSGImageNode`
children become descendants of the clip. KPipeWire's header exposes the
overridable method, and no private Qt/KPipeWire API or system library change is
used. The existing QML `clip: true` center-50% experiment is kept separate; it
uses Qt's built-in clip hierarchy and compares QML `Image` with PipeWire in the
same QML parent structure.

Rounded clip geometry remains explicit `DrawTriangles`, but that was not the
structural fix. The PipeWire source still renders directly with no offscreen
texture or `MultiEffect`. Opt-in scene-graph diagnostics report node types and
parent/child relationships plus source and clip geometry; they do not record
window titles or frame pixels. The earlier owner test showing leakage after
the triangle change is preserved as evidence that rejected that candidate.

The KPipeWire 6.6.4 source used by the tested Plasma stack implements
`PipeWireSourceItem::updatePaintNode()` as a regular `QSGNode` container with
`QSGImageNode` children. CPU-only frames become Qt Quick textures from images;
the DMA-BUF path wraps imported native OpenGL textures. The item is not a
`QSGRenderNode`, so no custom render-node stencil/scissor handling is involved.
This source inspection and the Qt topology implementation establish the
geometry failure mechanism; visual clipping still requires owner verification
on the real Wayland renderer.

Diagnostic builds support `KDOCKW_PREVIEW_CLIP_TEST=raw|center50|rounded` and
`KDOCKW_PREVIEW_SOURCE_TEST=pipewire|image` for same-session comparison. The
values are consumed and removed from the process environment before child
launches. The preview-redesign launcher accepts capture mode, clip mode, source
mode, and optional `trace`; production builds always use the direct PipeWire
source and rounded source-local clip. QML tests assert that center50 uses
Qt's built-in clip for both QML Image and PipeWire with the same item hierarchy.
Unit tests assert that the source render root is a child of the returned clip
node. Neither test tier claims GPU stencil or KWin visual acceptance.

The saved settings are `PreviewThumbnailSize` (120–320 px, default 200),
`PreviewMaximumHeight` (80–300 px, default 180), `PreviewCardPadding` (4–24 px,
default 8), and `PreviewDockGap` (0–32 px, default 2). Width and height define
the stable 16:10 outer preview; stream dimensions only change the centered Cover
rectangle. Before stream dimensions arrive, sizing uses the 1.6:1 fallback.
The previous thumbnail-width key is unchanged, so old user values remain
effective. These settings are saved through KConfig and the dock gap reapplies
the existing layer-shell margins live.

The icon, QML scene, popup, and preview input/blur regions use logical
coordinates local to their own layer-shell surface. QML maps the image and
delegate to the dock scene with `mapToItem(null, ...)`; preview placement does
not treat `mapToGlobal()` or a top-level window position as an output
coordinate. This matters on Wayland, where clients may not know a top-level
surface's global position ([Qt window positioning](https://doc.qt.io/qt-6/application-windows.html)).

For the edge facing the preview, let `d` be the icon's resting distance from
the corresponding edge of the dock surface, `m` the dock's actual LayerShell
margin, `g` the configured gap, and `s` the popup's shadow inset. The preview
margin is `M = m + d + g - s`; for top/left, `d` is the local icon edge, and
for bottom/right, it is the dock surface extent minus that edge. Floating
padding is already inside the dock surface and its icon-local geometry; it is
not an additional output-edge margin. The popup is positioned inside its
transparent surface using a fixed maximum-zoom anchor, keeping the card clear
of the icon without following its animation.

The preview surface uses LayerShell exclusive zone `-1`. KWin 6.6.6's
`LayerShellV1Integration::rearrangeLayer()` anchors negative-zone surfaces to
the output geometry; zone `0` instead uses the evolving work area. KWin first
applies positive exclusive zones, including the dock's reservation, then lays
out zone-zero surfaces. The old preview zone `0` therefore moved the whole
preview surface away from the dock's reserved area, while the application also
applied its icon-derived margin. That reservation was the systematic extra
gap. The protocol documents `-1` as opting out of movement to accommodate
other surfaces' exclusive zones ([wlr-layer-shell protocol](https://github.com/swaywm/wlr-protocols/blob/master/unstable/wlr-layer-shell-unstable-v1.xml)); the corresponding [KWin 6.6.6 layout code](https://github.com/KDE/kwin/blob/v6.6.6/src/layershellv1integration.cpp) uses output geometry for negative zones and work-area geometry otherwise.

For the observed 1920×1080 output, 136 px dock surface, icon rest edge 83 px,
34.92 px zoom overflow, and 2 px requested gap, the actual dock LayerShell
margin is 0 px; the 3 px floating inset is inside the dock surface. Using the
actual margin gives preview margin `M = 0 + (136 - 83) + 2 - 8 = 47 px`.
The prior `M=50 px` also counted the floating inset, while zone zero let KWin
shift the preview to its reduced work area.

The popup's cross-axis offset is fixed at the maximum expected zoom overflow,
not the animated per-frame overflow. On bottom/right edges this positions the
card for the largest icon from the moment it appears; on top/left it uses the
corresponding outward edge. The card no longer follows the icon during
zoom-in/zoom-out. Along-axis centering may still change when the hovered task
changes. The fixed anchor is refreshed when icon geometry, zoom settings, or
dock edge changes. If zoom is disabled (`maxZoomFactor == 1`), the overflow
and extra anchor offset are zero. At the maximum expected zoom, the visible gap
matches the configured `PreviewDockGap` after accounting for the card shadow;
at lesser animated scales the preview deliberately remains at that maximum
anchor. Geometry tests cover all four edges; real compositor placement still
requires owner verification.

## Preview sharpness and pixel scale

The normal preview path does not render through an intermediate QML layer:
KPipeWire's source scene-graph subtree (including its image node) is wrapped by
the rounded clip and rendered directly. The Cover geometry gives the source
one proportional logical-size scale; the QQuickWindow then maps that geometry
to output pixels using the screen DPR. Rounded clipping does not create a
second texture pass.

KPipeWire exposes `streamSize`, but diagnostics observed transient dimensions
while the source was not ready and still connecting. The values included
3801189×2097152 and 116×7929972; the latter produced a Cover item over 13.6
million logical pixels high. Both occurred with `ready=false` before a valid
frame. Cover now keeps the 1.6:1 fallback until a frame is ready, then accepts
only positive dimensions up to 32768 per side, at most 268435456 pixels, and
an aspect ratio in [1/32, 32]. Invalid updates retain the last valid ratio;
changing UUID resets it for the new window.

For the recorded valid CPU-only example, the PipeWire frame was 1581×904 pixels,
the viewport 196×121 logical pixels, and DPR 1. The Cover content was about
211.62×121 physical pixels, so the frame was downsampled about 7.5× in each
axis after centered horizontal cropping. This establishes substantial source
downscaling for that sample; it does not establish the cause of the remaining
visual softness or justify changing the production sampling filter. Production
filtering remains unchanged; a diagnostic-only Linear override is available for
controlled visual A/B.

Source inspection of KPipeWire 6.6.4 and Qt 6.10.2 established the sampler
baseline: `PipeWireSourceItem::updatePaintNode()` creates a `QSGImageNode` but
does not call `setFiltering()` or `setMipmapFiltering()`. Qt's default image
node uses `Nearest` filtering and `None` for mipmap filtering. CPU frames are
wrapped with `QQuickWindow::createTextureFromImage()` without a mipmap option;
the DMA-BUF path also imports a texture without mip levels. This explains the
configured sampling behavior, but does not prove that it causes the reported
softness. The diagnostic candidate can override the screen image node to
`Linear` without introducing another texture or processing pass. No visual,
performance, or memory comparison has yet been measured. Mipmap A/B is not
available on these current textures because they report no mip levels.

Preview size choices are Compact 180×113, Standard 220×138, Enlarged 260×163,
and Large 320×200 logical pixels. They write the existing
`PreviewThumbnailSize` and `PreviewMaximumHeight` keys. No new key or default
migration is introduced; existing custom values remain custom until a preset
is selected. The 16:10 slot, Cover crop, and card sizing remain driven by the
same runtime properties.

In a diagnostic build only, opt-in `KDOCKW_PREVIEW_METRICS=1` logs
size-only capture metrics: PipeWire frame pixels, window DPR, logical and
physical viewport/Cover sizes, mapped source bounds, `paintedRect`, and whether
DMA-BUF is active. It records no window/app names, UUIDs, frame pixels, or
screenshots. Local-only diagnostic launchers enabled this flag explicitly;
normal builds and diagnostic runs without the opt-in do not emit these records.
The local comparison harness exposed baseline and Linear sampler modes, but no
visual or performance result established Linear as an improvement. Its
optional Scene Graph trace reports image-node geometry, filter, mipmap filter,
texture size, and mipmap availability once per distinct state; it stores no
frames. The launcher itself is not part of a clean checkout.

## Minimized-window lifecycle

`PreviewThumbnail.qml` must keep its `PipeWireSourceItem` visible while the task
is minimized. Hiding a KPipeWire source item clears its `ready` state and calls
`PipeWireSourceStream::setActive(false)`; the previous QML fallback also showed
the app icon unconditionally for minimized tasks. Together those behaviors
explained why a ready preview changed to an icon at minimize time.

When the source remains active, KPipeWire retains the last received texture in
the source item. KWin may continue to deliver current frames, or it may stop
producing new frames for a minimized window; either way KDockW displays the most
recent frame that KWin already authorized and delivered. This is an in-memory
PipeWire/scene-graph texture, not a screenshot file or a separate persistent
cache. Closing the popup stops streams through normal QQuickItem visibility;
closing a task destroys its thumbnail delegate and source. When a reused grouped
delegate receives another window UUID, KDockW recreates its source and hides its
old texture until the new source has delivered a frame.

The app-name tooltip uses a clearance gap based on the hovered dock item's live
zoom scale and configured icon size. This keeps it outside the enlarged icon on
all four edges; it does not change which launcher/window states show a tooltip
or how preview/tooltip transitions are triggered.

For grouped tasks, a thumbnail's UUID comes from that child row's own
`WinIdList`, not from indexing the group's aggregate list. TaskManager derives
the parent list by concatenating its children, while child rows retain their
individual IDs. This keeps a surviving thumbnail bound to the right window when
an earlier child row is removed and the aggregate parent role is still catching
up.

The minimized-window path keeps the selected capture mode: Auto still prefers
DMA-BUF and retains its bounded no-first-frame CPU retry; Compatibility mode
continues to use CPU-readable buffers and can use more CPU. The implementation
adds no second image allocation, but real RAM/VRAM and frame activity still need
checking on the target Wayland compositor. Automated QML tests cannot establish
whether a particular KWin version emits live frames while minimized; verify
that in the owner's Plasma/Wayland session.

Keep `PipeWireSourceItem` at its default opacity. The application icon is a
separate item stacked above the source until `ready` becomes true. An earlier
implementation bound the source item's opacity directly to `ready`; a live
Wayland test then showed a black thumbnail for both normal and minimized
Telegram windows. The saved log confirms a valid UUID-to-node mapping,
`Streaming`, `ready=true`, and `usingDmaBuf=true`, but contains no pixel data, so
it cannot locate the black output at DMA-BUF import versus Qt Quick presentation.
The opacity binding was removed to restore the source's prior scene-graph
rendering path. This correction still needs visual confirmation in both `auto`
and `cpu-only` modes.

## Interpreting capture properties

`PipeWireSourceItem` exposes:

| Property | What it tells us | What it does not prove |
|---|---|---|
| `state` | PipeWire source lifecycle: Error, Unconnected, Connecting, Paused, Streaming | That the frame is visible in the Qt Quick scene |
| `ready` | KPipeWire has received its first frame | That frame pixels are non-black or that texture import/presentation succeeded |
| `streamSize` | Source dimensions, updated after the first frame | That the buffer has a compatible GPU format or modifier |
| `usingDmaBuf` | Whether the active stream uses DMA-BUF | That another GPU can import the buffer correctly |
| `error()` | KPipeWire's current error text when the stream is in Error | KWin compositor errors or all graphics API/import failures |

The black-preview investigation must distinguish three stages:

1. **Source:** did KWin publish a node and did the stream receive a frame?
2. **GPU buffer import:** was the DMA-BUF format/modifier importable by the GPU
   used by KDockW's Qt Quick renderer?
3. **Qt Quick presentation:** did the imported or CPU-backed texture reach the
   scene graph and appear in the thumbnail?

Current KDockW logs report source state and transport metadata. They do not
read, save, hash, or log screenshot pixels. Therefore `ready=true` alongside a
black thumbnail leaves the import and presentation stages open.

The owner subsequently accepted the minimized-preview implementation after
manual testing on KDE Plasma 6 / Wayland and reported that previews work for
open and minimized windows in CPU-only mode. This is runtime acceptance for
that mode and hardware; it does not establish DMA-BUF behavior. The preserved
black-preview log describes an earlier `auto` run and remains relevant
technical debt, but does not prove DMA-BUF is the cause. No pixel capture or
DMA-BUF workaround has been added.

## User-selectable capture mode

Window Preview settings keeps **Automatic (DMA-BUF)** as the default. The
**Compatibility mode (CPU)** option is saved in `kdockwrc` and creates each
`PipeWireSourceItem` with `allowDmaBuf=false`. Toggling the option tears down
and recreates active thumbnail streams so the new mode takes effect without
restarting KDockW. The Loader owns each source item; deactivation destroys the
old stream before the replacement is activated. Auto alone retains the
bounded no-first-frame retry described below. CPU compatibility mode may use
more CPU time.

`KDOCKW_PREVIEW_CAPTURE_MODE=auto|cpu-only` remains available for technical
experiments. When set to a supported value, it overrides the saved setting for
the current process only; it is read when `PreviewController` is created and
is never written back to `kdockwrc`. `auto` forces the normal DMA-BUF-preferred
path and `cpu-only` forces CPU-readable buffers. An unset or unsupported value
uses the saved setting (unsupported values are logged). The environment
override is intentionally not a UI setting.

## Preview image Raw/Masked diagnostic A/B

The former diagnostic build exposed
`KDOCKW_PREVIEW_RENDER_MODE=raw|masked` solely to compare QML composition.
The owner then confirmed on Plasma 6 / Wayland with identical CPU-only source,
capture settings, and card geometry that Raw rendered the Yandex Browser frame
and Masked rendered no frame. This isolates the regression to the additional
masked composition path. That switch and effect path are removed from the
candidate; Raw is now the only implementation. The source has no wrapper,
MultiEffect, or offscreen layer. Diagnostic logs retain only non-content source
state and geometry metadata; they do not read or save frame pixels.

The earlier candidate used an inset, rectangular QQuick viewport. The current
candidate fills the inner card and uses a rounded scene-graph clip node around
the direct source. QML tests exercise portrait, square, wide, and ultrawide
source geometries across four dock edges and DPR 1.0–2.0, plus the shared
viewport dimensions and rounded radius. These tests verify geometry and direct
item ownership, not actual PipeWire pixels or compositor output. Live
confirmation is still required. The existing minimized-window and child
UUID/grouping behavior is preserved by the same source lifecycle and regression
tests.

## Application-name tooltip and layer-shell bounds

The tooltip is an in-scene `Kirigami.ShadowedRectangle`, with no separate
popup surface or parent clipping item. Its text/background geometry is inside
the dock's `main.qml` root. The confirmed clipping cause was the layer-shell
cross-axis reserve: horizontal docks used a fixed 36 px even though the tooltip
needs its own extent plus icon zoom gap and shadow. Vertical docks reserved only
a fixed width. `DockView::tooltipReserve` is now bound to the tooltip's measured
cross-axis extent, maximum zoom growth, gap, and shadow, and updates the surface
size for every edge. Along-screen coordinates are clamped to the surface; long
labels are elided to the available screen width. QML tests verify full bounds
and clearance, but only live Wayland acceptance can verify the compositor's
final output.

## Process-local override and Auto retry

Set `KDOCKW_PREVIEW_CAPTURE_MODE` for the KDockW process only to override the
saved setting and select the retry behavior:

| Value | Effect |
|---|---|
| unset / unsupported | Use the saved setting |
| `auto` | Force normal DMA-BUF-preferred behavior; the bounded no-first-frame retry remains available |
| `cpu-only` | Force every `PipeWireSourceItem` to start with DMA-BUF disallowed; the Auto retry is disabled |

An environment override is read when `PreviewController` is created. Unknown
values are logged as unsupported and fall back to the saved setting. The
setting and override affect only KDockW; they do not change Plasma or child
processes' environment.

## User-reported A/B result

On TUXEDO OS 24.04.5 with Plasma 6.6.6, Qt 6.10.2, Intel Iris Xe and NVIDIA
RTX 4050 (driver 580.178.04), the user compared the same Wayland and XWayland
windows while Qt Quick used OpenGL on the NVIDIA renderer. In Auto,
`usingDmaBuf=true`, `ready=true`, KPipeWire reported no error, but thumbnails
were black. With CPU-only, `usingDmaBuf=false` and the thumbnails displayed
correctly; KPipeWire was again Streaming and ready with no reported error.
This user-reported A/B supports a path-specific DMA-BUF compatibility issue on
that machine. It does not establish the internal failing import/API operation
or a defect affecting all Intel/NVIDIA/AMD systems. KDockW does not inspect
pixels or automatically switch modes based on black-frame detection.

The Auto retry runs once per thumbnail only when the stream reaches Streaming
but no first frame arrives within 1.5 seconds. It reconstructs the item without
DMA-BUF and logs `captureMode: cpu-fallback`. It is retained as an experimental
fallback for the no-first-frame case covered by the project's controlled E2E
fixture. It is not activated by `ready=true`, does not prove or repair a black
frame that KPipeWire has already received, and is not a general hybrid-GPU fix.

## Safe A/B procedure on Wayland

Do not run two KDockW instances at once. Close the current instance through its
normal quit action and verify it exited before each diagnostic launch. Use the
same windows and repeat the same sequence for each launch. For ordinary use,
prefer the saved Compatibility mode setting in KDockW rather than a diagnostic
environment override.

Start with the current process environment:

```sh
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=auto /usr/local/bin/kdockw
```

Then close KDockW and compare CPU-only capture, still inheriting the same
process environment:

```sh
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only /usr/local/bin/kdockw
```

Finally close KDockW and repeat the Auto case with only the known PRIME and
Qt-renderer overrides removed from this process:

```sh
env -u DRI_PRIME \
    -u __GLX_VENDOR_LIBRARY_NAME \
    -u __NV_PRIME_RENDER_OFFLOAD \
    -u __VK_LAYER_NV_optimus \
    -u QSG_RHI_BACKEND \
    QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=auto /usr/local/bin/kdockw
```

These commands assume the installed binary path shown. For a source build,
substitute `build/release/bin/kdockw`. A process started this way is not a
desktop-file launch; record that difference. Do not change the desktop file,
global variables, driver settings, or KWin configuration for the comparison.

Qt documents `QSG_INFO=1` as enabling Qt Quick scene-graph initialization
information, useful for identifying the selected graphics API and renderer.
Depending on the API and driver, the output may also identify the graphics
device. See [Qt Quick scene-graph diagnostics](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html).

For each mode, note the Qt Quick backend/device reported at startup, the
`[kdockw.preview]` state/size/`dmaBuf`/`captureMode` lines, whether the thumbnail
is correct or black, and whether closing/reopening the popup changes it. Repeat
with one Wayland-native window and one XWayland window. Do not capture or persist
window pixels or titles for diagnostics; a user-provided screenshot may be
shared separately if desired.

## What would confirm a cause or fix

- **Source/no-frame issue:** node ID or stream state fails, or `ready` remains
  false. Compare Auto's bounded fallback with CPU-only.
- **DMA-BUF import issue:** the same window is black in Auto, but displays
  correctly in CPU-only, while source dimensions and first-frame readiness are
  comparable. Repeat after closing and reopening, and compare the renderer/GPU.
  This is strong evidence of a path-specific issue, not alone proof of the exact
  failing driver/API call.
- **Renderer/environment association:** Auto becomes correct only when the
  PRIME/Qt variables are cleared for KDockW, while backend/device or graphics
  errors differ. Repeat the ordinary environment and cleared environment more
  than once; this does not establish which variable is causal if several were
  cleared together.
- **Presentation issue:** Auto and CPU-only both receive first frames but remain
  black. Investigate Qt Quick texture/item presentation or compositor output;
  do not infer DMA-BUF as the cause from `ready=true` alone.

An automatic fix is confirmed only after a regression test covers the located
failure and the user verifies thumbnails in the real hybrid-GPU Wayland session,
including both Wayland-native and XWayland windows. Automated mocks and software
renderers cannot validate cross-GPU DMA-BUF import.

## Startup method

KDockW's installed XDG autostart entry is its only supported automatic login
startup path. The normal application desktop file and manual invocation remain
available and launch the same executable. The standard desktop ID and
KWin Wayland-interface declaration must remain intact. Earlier user-created
`kdockw.service` units can be migrated using
[`../migration/systemd-to-xdg-autostart.md`](../migration/systemd-to-xdg-autostart.md).

If window tasks or previews do not appear after installing a desktop entry,
check that KWin resolves the installed application desktop ID and that the
entry declares the required `org_kde_plasma_window_management` interface.
Metadata alone does not prove that a particular client received the
permission; verify behavior in the target Plasma Wayland session.
