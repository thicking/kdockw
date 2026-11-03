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
window previews. The working arrangement keeps the original desktop ID and
KWin interface declaration, runs the binary directly from a user service, and
uses a separate `kdockw-service.desktop` shortcut that starts that service.
These are observations from the stated configuration, not evidence that PRIME
variables or desktop wrappers cause the same symptoms on every system.

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

## Startup choice and optional user service

KDockW's installed XDG autostart entry is the recommended default; the
systemd user service is optional and is not required for KWin screencasting.
On the reproduced setup, running KDockW with inherited PRIME and Qt backend
overrides removed coincided with previews returning. Those variables were
cleared together, so the observation neither identifies which value mattered
nor proves a universal cause. The normal installed desktop entry remained
`com.thicking.kdockw.desktop`, including its
`X-KDE-Wayland-Interfaces` declaration. A separate menu shortcut can start the
optional service; do not rename or replace the normal desktop ID.

Create `~/.config/systemd/user/kdockw.service` (back up an existing file
first):

```ini
[Unit]
Description=KDockW Dock
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kdockw
Restart=on-failure
RestartSec=3
UnsetEnvironment=DRI_PRIME __GLX_VENDOR_LIBRARY_NAME __NV_PRIME_RENDER_OFFLOAD __VK_LAYER_NV_optimus QSG_RHI_BACKEND

[Install]
WantedBy=graphical-session.target
```

`Application::makeAboutData()` sets the desktop ID to `com.thicking.kdockw` by
default. The `--desktopfile` option is supported by KDE's `KAboutData` command
line setup, but is not needed for this service. Keep the project's normal
desktop file and its `X-KDE-Wayland-Interfaces` value intact.

Before changing any original desktop entry's `Exec`, restore it to the direct
KDockW binary (`/usr/local/bin/kdockw` for this installation). Do not put a
wrapper in that desktop file. Create the separate service launcher as
`~/.local/share/applications/kdockw-service.desktop`:

```sh
mkdir -p ~/.local/share/applications
```

```ini
[Desktop Entry]
Type=Application
Name=KDockW (service)
Comment=Start KDockW through the user service
Exec=systemctl --user start kdockw.service
Icon=com.thicking.kdockw
Terminal=false
Categories=Utility;
StartupNotify=false
```

Use only one login starter. The KDockW autostart entry installed by this CMake
project is named `com.thicking.kdockw.autostart.desktop`; to use the service,
override that entry for this user with
`~/.config/autostart/com.thicking.kdockw.autostart.desktop`:

```ini
[Desktop Entry]
Hidden=true
```

Save any existing user override before replacing it.

Before adapting an existing unit, save it. For example:

```sh
mkdir -p ~/.config/systemd/user
test ! -e ~/.config/systemd/user/kdockw.service || \
  cp -a ~/.config/systemd/user/kdockw.service ~/.config/systemd/user/kdockw.service.before-prime
```

After creating or editing the unit:

```sh
systemctl --user daemon-reload
systemctl --user enable --now kdockw.service
```

To restore the saved unit, copy it back, reload systemd, and restart KDockW.
Restore any previous user autostart override. If there was no unit or override
before this change, disable the service and remove only the user-created unit,
mask, and shortcut:

```sh
systemctl --user disable --now kdockw.service
rm ~/.config/systemd/user/kdockw.service
rm ~/.config/autostart/com.thicking.kdockw.autostart.desktop
rm ~/.local/share/applications/kdockw-service.desktop
systemctl --user daemon-reload
```

Restore the user's previous autostart choice separately. Do not remove
`/usr/local/share/applications/com.thicking.kdockw.desktop` or change system GPU,
driver, KWin, or SDDM configuration as part of this workaround.

## Comparing preview capture paths

The process-local `KDOCKW_PREVIEW_CAPTURE_MODE` variable selects:

- `auto` (default): normal DMA-BUF-preferred capture and the bounded retry if a
  Streaming source does not provide a first frame.
- `cpu-only`: disallow DMA-BUF when each `PipeWireSourceItem` is first created;
  do not run the Auto no-first-frame retry.

This is a diagnostic control, not a regular settings option. It only affects
the process started with the variable. Do not run two KDockW instances at once.
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
not have the exact environment of a desktop-file or user-service launch, so
record the launch method. `QSG_INFO=1` enables Qt Quick scene-graph startup
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

Inspect only the relevant environment variables for the running service:

```sh
pid=$(systemctl --user show kdockw.service --property=MainPID --value)
tr '\0' '\n' <"/proc/$pid/environ" |
  grep -E '^(DRI_PRIME|__GLX_VENDOR_LIBRARY_NAME|__NV_PRIME_RENDER_OFFLOAD|__VK_LAYER_NV_optimus|QSG_RHI_BACKEND)='
```

With `UnsetEnvironment`, this command should print no matching lines unless
the process sets one itself. Avoid dumping the complete process environment:
it may contain unrelated private values.

KDockW logs capture mode, preview transitions, readiness, stream size, actual
DMA-BUF selection, and KPipeWire's error string with the `[kdockw.preview]`
prefix. For the optional service:

```sh
journalctl --user -b -u kdockw.service -o cat | grep '\[kdockw.preview\]'
```

For a directly launched process, query its PID:

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
