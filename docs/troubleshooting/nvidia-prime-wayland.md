# NVIDIA PRIME and Wayland troubleshooting

This note records a problem reproduced on one hybrid-GPU system. It is not
evidence of a general defect in NVIDIA hardware, drivers, or all Wayland
systems.

## Reproduced setup and symptoms

- TUXEDO OS 24.04.5 (Ubuntu 24.04 Noble base)
- KDE Plasma 6.6.6, Qt 6.10.2
- Wayland session
- Intel Iris Xe integrated graphics and NVIDIA RTX 4050

The observed symptoms were black live window thumbnails in KDockW, missing
unpinned running applications when KDockW was started through a nonstandard
desktop launcher, and launch feedback that continued while KWin startup or
window information was unavailable. During the black-preview reproduction,
the logs included `GL_INVALID_OPERATION (0x502): <image> and
<target> are incompatible`. On this machine, starting KDockW after clearing
`DRI_PRIME`, `__GLX_VENDOR_LIBRARY_NAME`, `__NV_PRIME_RENDER_OFFLOAD`,
`__VK_LAYER_NV_optimus`, and `QSG_RHI_BACKEND` restored the preview. Because
the variables were cleared together, this did not isolate which one caused the
observed rendering error.

An experiment that changed the original KDockW desktop entry to launch through
a `kdockw-wrapper` coincided with missing unpinned tasks, launch animation, and
window previews. Keep the application desktop ID and KWin interface
declaration intact, and use the project's XDG autostart entry or launch the
binary directly. These are observations from the stated configuration, not
evidence that PRIME variables or desktop wrappers cause the same symptoms on
every system.

KPipeWire reports stream state and first-frame readiness separately. A
`ready=true` observation means KPipeWire received a first frame; it does not
prove the pixels are non-black or that GPU-buffer import and Qt Quick
presentation succeeded. Conversely, Streaming with `ready=false` means no
first frame has arrived yet. KDockW's one-shot retry reconnects that
no-first-frame stream without DMA-BUF. It is an experimental fallback, not a
confirmed fix for a black frame or cross-GPU DMA-BUF import. Diagnose source,
GPU import, and scene-graph presentation as separate stages; see the
[window-preview architecture note](../architecture/window-previews.md).

## PRIME and Qt environment variables

These variables can change GPU selection or rendering. They are not a blanket
KDockW configuration and should only be used for controlled diagnosis.

| Variable | Typical scope |
| --- | --- |
| `DRI_PRIME` | Mesa GPU selection, commonly for an individual process. |
| `__GLX_VENDOR_LIBRARY_NAME` | Selects the GLX vendor, commonly `nvidia` for an offloaded GLX application. |
| `__NV_PRIME_RENDER_OFFLOAD` | Enables NVIDIA PRIME render offload for supported NVIDIA driver paths. |
| `__VK_LAYER_NV_optimus` | Selects the NVIDIA Optimus Vulkan layer behavior; `NVIDIA_only` is commonly used for a targeted Vulkan test. |
| `QSG_RHI_BACKEND` | Selects Qt Quick's scene-graph backend, for example `opengl` or `vulkan`. |

Do not export these globally to Plasma as a first troubleshooting step. Test
one variable on a temporary command, then remove it. Changing the Qt Quick
backend can affect the whole UI renderer and does not by itself prove or repair
DMA-BUF import between GPUs.

## Login startup and application identity

The installed `com.thicking.kdockw.autostart.desktop` is KDockW's only
automatic login starter. It launches the configured `kdockw` binary directly.
The regular application entry remains `com.thicking.kdockw.desktop` and must
retain its `X-KDE-Wayland-Interfaces` declaration; do not rename it, replace
its `Exec` with a wrapper, or add a second startup shortcut.

On the reproduced setup, running KDockW with inherited PRIME and Qt backend
overrides removed coincided with previews returning. Those variables were
cleared together, so the observation neither identifies which value mattered
nor proves a universal cause. Keep GPU and Qt variables local to controlled
diagnostic launches; do not change global Plasma environment, driver, KWin, or
SDDM configuration. The `--desktopfile` option exists for KDE command-line
compatibility but is not needed for the project's standard desktop entries.

Users with an existing `kdockw.service`, a custom unit override, or a
`Hidden=true` XDG override can follow the separate
[systemd-to-XDG migration guide](../migration/systemd-to-xdg-autostart.md).
That procedure is manual and backs up user files before changes.

## Choosing and comparing preview capture paths

The normal UI setting is in **Settings → Window Preview → Compatibility mode
(CPU)**. It is off by default, which means Automatic (DMA-BUF preferred). Turn
it on when previews show a black rectangle. The setting is saved in
`~/.config/kdockwrc` and changing it recreates existing preview streams. CPU
mode may increase CPU usage. This is a supported workaround for the reported
configuration, not a universal NVIDIA fix.

To check it in the running desktop session, keep the same Wayland-native or
XWayland window open, open KDockW Settings → Window Preview, and switch
Compatibility mode off and on. The preview stream should be recreated without
restarting KDockW. In the journal, the per-thumbnail capture diagnostics should
show `captureMode: auto` with DMA-BUF allowed when off and
`captureMode: cpu-only` with DMA-BUF disabled when on. Confirm the visible
thumbnail as well; these log fields report stream metadata, not pixel content.
The saved option is `CpuOnlyPreviewCapture` in the `[General]` group of
`~/.config/kdockwrc`.

The process-local `KDOCKW_PREVIEW_CAPTURE_MODE` variable remains available for
technical A/B experiments. A supported value overrides the saved value only
for that process and is not written back to the configuration:

| Value | Effect |
|---|---|
| unset | Use the saved UI setting |
| `auto` | Force Auto (DMA-BUF preferred) and its bounded no-first-frame retry |
| `cpu-only` | Force capture without DMA-BUF; no Auto retry |

Do not run two KDockW instances at once.
Close the existing instance normally and verify that it has exited before each
launch. Use one launch at a time:

```sh
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=auto /usr/local/bin/kdockw
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only /usr/local/bin/kdockw
```

Then compare Auto with only the listed process environment overrides removed:

```sh
env -u DRI_PRIME \
    -u __GLX_VENDOR_LIBRARY_NAME \
    -u __NV_PRIME_RENDER_OFFLOAD \
    -u __VK_LAYER_NV_optimus \
    -u QSG_RHI_BACKEND \
    QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=auto /usr/local/bin/kdockw
```

Substitute `build/release/bin/kdockw` for a source build. Direct launches may
not have the exact environment of a desktop-file launch, so record the launch
method. `QSG_INFO=1` enables Qt Quick scene-graph startup
diagnostics; depending on the backend and driver these report the selected
graphics API and may identify its device. It does not force a backend or GPU.

Use the same open windows and repeat for one Wayland-native and one XWayland
window. Record the renderer/device output, KDockW's mode and capture metadata,
whether the thumbnail is black, and whether reopening it changes the result.
Do not capture or write window pixels or titles into persistent diagnostics.
Compare `ready`, `streamSize`, `usingDmaBuf`, and `captureMode`; `ready=true`
alone cannot distinguish import from presentation errors. A black Auto image
that becomes correct in CPU-only is evidence for a path-specific buffer/import
problem, but still needs repetition and GPU/backend correlation before
assigning a precise cause. If both modes receive frames and stay black, inspect
scene-graph presentation and compositor output instead.

For the full protocol and confirmation criteria, see
[`../architecture/window-previews.md`](../architecture/window-previews.md).

## Logs

Inspect only the relevant environment variables for the running KDockW process:

```sh
pid=$(pgrep -n -x kdockw) || { echo 'KDockW process not found'; exit 1; }
tr '\0' '\n' <"/proc/$pid/environ" |
  grep -E '^(DRI_PRIME|__GLX_VENDOR_LIBRARY_NAME|__NV_PRIME_RENDER_OFFLOAD|__VK_LAYER_NV_optimus|QSG_RHI_BACKEND)='
```

This prints only the listed variables. Avoid dumping the complete process
environment: it may contain unrelated private values.

KDockW logs capture mode, preview transitions, readiness, stream size, actual
DMA-BUF selection, and KPipeWire's error string with the `[kdockw.preview]`
prefix. Query the running process by PID:

```sh
pid=$(pgrep -n -x kdockw) || { echo 'KDockW process not found'; exit 1; }
journalctl --user _PID="$pid" --since '5 minutes ago' -o cat --no-pager |
  grep '\[kdockw.preview\]'
```

Look for whether the stream reached `Streaming`, whether `ready` became true,
whether `streamSize` was populated, whether `usingDmaBuf` changed, and whether
the no-first-frame retry occurred. If no stream-state messages appear, check
that the process was launched with the expected desktop ID and that its
desktop entry retains the KWin interface declaration. This logging does not
identify every driver or compositor-side failure; reproduce with a normal
window and an XWayland window before drawing a broader conclusion.

## References

- [NVIDIA Optimus and multi-GPU systems](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/latest/optimus-laptops-and-multi-gpu-desktop-systems.html)
- [Qt Quick scene-graph renderer selection](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph-renderer.html)
- [TUXEDO OS release model and package sources](https://www.tuxedocomputers.com/en/How-does-the-TUXEDO-OS-release-model-work.tuxedo)
