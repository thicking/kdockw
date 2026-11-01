# Build and install Krema on TUXEDO OS

This guide targets TUXEDO OS 24.04 (Ubuntu 24.04 Noble base) with the newer
Qt 6 and KDE Frameworks packages supplied by the configured TUXEDO OS
repositories. The exact versions available change with repository updates;
check the installed Qt/KDE versions before building.

## Build dependencies

Install the development packages provided by the TUXEDO/Ubuntu repositories:

```sh
sudo apt update
sudo apt install \
  build-essential cmake ninja-build extra-cmake-modules gettext catch2 \
  qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-wayland-dev \
  qt6-shadertools-dev libwayland-dev libwayland-bin \
  libkf6windowsystem-dev libkf6config-dev libkf6coreaddons-dev \
  libkf6dbusaddons-dev libkf6i18n-dev libkf6globalaccel-dev \
  libkf6colorscheme-dev libkf6iconthemes-dev libkf6crash-dev \
  libkf6xmlgui-dev libkf6service-dev libkf6kio-dev libkf6jobwidgets-dev \
  libkf6itemmodels-dev libkirigami-dev kirigami-addons-dev \
  liblayershellqtinterface-dev plasma-workspace-dev libkpipewire-dev
```

The `libwayland-dev` entry is required once; it is listed with the Wayland
development tools above. Install `catch2` as well if you will build the test
suite. Use the versions from TUXEDO OS repositories together: mixing a newer
Qt/KDE runtime with Noble's older development packages can produce ABI or
configuration mismatches.

## Release build and installation

From the Krema source directory:

```sh
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

The `release` preset disables tests. To run the QML and other tests, configure
the `dev` preset, build it, and use the repository's `dev` test preset instead.
TUXEDO OS's `catch2` package provides Catch2 3, which the test configuration
requires.

Krema uses KI18n catalogs. The Russian catalog is built from
`src/po/ru/krema.po` and installed under the locale directory as
`krema.mo`. The application also adds the build-tree catalog directory when
run directly from `build/release/bin/krema`, so translations work both before
and after installation. The desktop file contains the translated static
metadata; runtime UI strings come from KI18n.

After installation, retain the installed desktop ID
`com.bhyoo.krema.desktop` and its `X-KDE-Wayland-Interfaces` entry. That entry
declares the KWin Wayland interfaces the application uses. Do not replace the
standard desktop file with a custom service shortcut or change its ID. For
PRIME-specific service setup and diagnostics, see
[`../troubleshooting/nvidia-prime-wayland.md`](../troubleshooting/nvidia-prime-wayland.md).

## Optional systemd user service

If Krema needs a controlled process environment, use a user service that
starts the installed binary with its standard desktop ID:

```ini
[Unit]
Description=Krema Dock
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/krema --desktopfile com.bhyoo.krema
Restart=on-failure
RestartSec=3
UnsetEnvironment=DRI_PRIME __GLX_VENDOR_LIBRARY_NAME __NV_PRIME_RENDER_OFFLOAD __VK_LAYER_NV_optimus QSG_RHI_BACKEND

[Install]
WantedBy=graphical-session.target
```

Save it as `~/.config/systemd/user/krema.service`, then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now krema.service
```

To prevent duplicate instances, choose one login starter: either the installed
XDG autostart entry or the systemd user service. When using the service,
disable the separate XDG autostart entry for this user, while keeping
`com.bhyoo.krema.desktop` installed and available to KWin. A separate menu
shortcut may run `systemctl --user start krema.service`, but it should use its
own desktop filename and `Icon=com.bhyoo.krema` rather than taking over the
application's desktop ID.

## Updating and removing

Update the source tree, then repeat the configure/build/install commands. The
install step replaces files under `/usr/local`; it does not manage a custom
systemd user unit or user-created service shortcut. Review the changelog before
restarting the dock.

To remove a source installation, use the same configured build tree:

```sh
sudo cmake --build build/release --target uninstall
```

If the generated build does not provide an `uninstall` target, remove only the
files installed by that build, using its `install_manifest.txt` as the exact
file list. Do not use a broad `rm -rf /usr/local` command. Disable and remove
only a user-created Krema service or launcher, and restore the user's prior
autostart choice.
