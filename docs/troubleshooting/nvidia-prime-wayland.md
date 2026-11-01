# NVIDIA PRIME and Wayland troubleshooting

This note records a problem reproduced on one hybrid-GPU system. It is not
evidence of a general defect in NVIDIA hardware, drivers, or all Wayland
systems.

## Reproduced setup and symptoms

- TUXEDO OS 24.04.5 (Ubuntu 24.04 Noble base)
- KDE Plasma 6.6.6, Qt 6.10.2
- Wayland session
- Intel Iris Xe integrated graphics and NVIDIA RTX 4050

The observed symptoms were black live window thumbnails in Krema, missing
unpinned running applications when Krema was started through a nonstandard
desktop launcher, and launch feedback that continued while KWin startup or
window information was unavailable. During the black-preview reproduction,
the logs included `GL_INVALID_OPERATION (0x502): <image> and
<target> are incompatible`. On this machine, starting Krema after clearing
`DRI_PRIME`, `__GLX_VENDOR_LIBRARY_NAME`, `__NV_PRIME_RENDER_OFFLOAD`,
`__VK_LAYER_NV_optimus`, and `QSG_RHI_BACKEND` restored the preview. Because
the variables were cleared together, this did not isolate which one caused the
observed rendering error.

An experiment that changed the original Krema desktop entry to launch through
a `krema-wrapper` coincided with missing unpinned tasks, launch animation, and
window previews. The working arrangement keeps the original desktop ID and
KWin interface declaration, runs the binary directly from a user service, and
uses a separate `krema-service.desktop` shortcut that starts that service.
These are observations from the stated configuration, not evidence that PRIME
variables or desktop wrappers cause the same symptoms on every system.

KPipeWire reported stream state and readiness separately. On this machine the
preview could enter streaming without receiving a usable first frame. Krema's
no-first-frame retry asks KPipeWire to reconnect without DMA-BUF; this is a
diagnostic fallback, not a confirmed fix for cross-GPU DMA-BUF import. A black
thumbnail can also result from KWin permissions, stream setup, buffer import,
or rendering. Compare the logs below before attributing the cause.

## PRIME and Qt environment variables

These variables can change GPU selection or rendering. They are not a blanket
Krema configuration and should only be used for controlled diagnosis.

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

## User service configuration

On the reproduced setup, the working user service removed inherited PRIME and
Qt backend overrides for Krema. The normal installed desktop entry remained
`com.bhyoo.krema.desktop`, including its project-provided
`X-KDE-Wayland-Interfaces` declaration for the KWin interfaces Krema uses.
The service runs the Krema binary directly; a separate menu shortcut starts
the service. Do not rename or replace the normal desktop ID.

Create `~/.config/systemd/user/krema.service` (back up an existing file
first):

```ini
[Unit]
Description=Krema Dock
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/krema
Restart=on-failure
RestartSec=3
UnsetEnvironment=DRI_PRIME __GLX_VENDOR_LIBRARY_NAME __NV_PRIME_RENDER_OFFLOAD __VK_LAYER_NV_optimus QSG_RHI_BACKEND

[Install]
WantedBy=graphical-session.target
```

`Application::makeAboutData()` sets the desktop ID to `com.bhyoo.krema` by
default. The `--desktopfile` option is supported by KDE's `KAboutData` command
line setup, but is not needed for this service. Keep the project's normal
desktop file and its `X-KDE-Wayland-Interfaces` value intact.

Before changing any original desktop entry's `Exec`, restore it to the direct
Krema binary (`/usr/local/bin/krema` for this installation). Do not put a
wrapper in that desktop file. Create the separate service launcher as
`~/.local/share/applications/krema-service.desktop`:

```sh
mkdir -p ~/.local/share/applications
```

```ini
[Desktop Entry]
Type=Application
Name=Krema (service)
Comment=Start Krema through the user service
Exec=systemctl --user start krema.service
Icon=com.bhyoo.krema
Terminal=false
Categories=Utility;
StartupNotify=false
```

Use only one login starter. The Krema autostart entry installed by this CMake
project is named `com.bhyoo.krema.autostart.desktop`; to use the service,
override that entry for this user with
`~/.config/autostart/com.bhyoo.krema.autostart.desktop`:

```ini
[Desktop Entry]
Hidden=true
```

Save any existing user override before replacing it.

Before adapting an existing unit, save it. For example:

```sh
mkdir -p ~/.config/systemd/user
test ! -e ~/.config/systemd/user/krema.service || \
  cp -a ~/.config/systemd/user/krema.service ~/.config/systemd/user/krema.service.before-prime
```

After creating or editing the unit:

```sh
systemctl --user daemon-reload
systemctl --user enable --now krema.service
```

To restore the saved unit, copy it back, reload systemd, and restart Krema.
Restore any previous user autostart override. If there was no unit or override
before this change, disable the service and remove only the user-created unit,
mask, and shortcut:

```sh
systemctl --user disable --now krema.service
rm ~/.config/systemd/user/krema.service
rm ~/.config/autostart/com.bhyoo.krema.autostart.desktop
rm ~/.local/share/applications/krema-service.desktop
systemctl --user daemon-reload
```

Restore the user's previous autostart choice separately. Do not remove
`/usr/local/share/applications/com.bhyoo.krema.desktop` or change system GPU,
driver, KWin, or SDDM configuration as part of this workaround.

## Diagnostics

Inspect only the relevant environment variables for the running service:

```sh
pid=$(systemctl --user show krema.service --property=MainPID --value)
tr '\0' '\n' <"/proc/$pid/environ" |
  grep -E '^(DRI_PRIME|__GLX_VENDOR_LIBRARY_NAME|__NV_PRIME_RENDER_OFFLOAD|__VK_LAYER_NV_optimus|QSG_RHI_BACKEND)='
```

With `UnsetEnvironment`, this command should print no matching lines unless
the process sets one itself. Avoid dumping the complete process environment:
it may contain unrelated private values.

Krema logs preview transitions, readiness, stream size, DMA-BUF selection, and
KPipeWire's error string with the `[krema.preview]` prefix. Read only those
messages from the service journal:

```sh
journalctl --user -b -u krema.service -o cat | grep '\[krema.preview\]'
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
