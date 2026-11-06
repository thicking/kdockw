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
independently of the dock. The card, thumbnail backing, close button, and the
existing Firefox/app-name tooltip now use `DockView.backgroundColor` (the
resolved panel style, tint/accent, and opacity) with a theme fallback only when
the panel color is transparent. Text and the thin outline select a foreground
with at least 4.5:1 contrast against that resolved surface. Radius and soft
shadow use the existing dock settings. The tooltip change is styling only; the
separate Application Name Tooltip task still owns its behavior and switching
rules.

The app name is a compact card header; each window title sits immediately above
its own thumbnail. Existing activation and close actions remain attached to the
thumbnail. There is no arrow. Opacity animates on show/hide; the controller's
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
default 8), and `PreviewDockGap` (0–32 px, default 8). Width and height define
the stable 16:10 outer preview; stream dimensions only change the centered Cover
rectangle. Before stream dimensions arrive, sizing uses the 1.6:1 fallback.
The previous thumbnail-width key is unchanged, so old user values remain
effective. These settings are saved through KConfig and the dock gap reapplies
the existing layer-shell margins live.

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
