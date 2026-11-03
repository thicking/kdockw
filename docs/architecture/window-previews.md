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
normal quit action and verify it exited before each diagnostic launch. Do not
stop or edit a user service as part of this test; if a service owns the instance,
use its existing normal stop procedure and restore its prior running state
afterward. Use the same windows and repeat the same sequence for each launch.

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
systemd unit, global variables, driver settings, or KWin configuration for the
comparison.

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

KDockW's installed XDG autostart entry is the normal recommended startup path.
A systemd user service is optional: it can control per-process environment,
restart policy, or explicit start/stop, but it is not required for previews.
Choose only one login starter. When evaluating an optional service, keep the
standard desktop ID and KWin Wayland-interface declaration intact.
