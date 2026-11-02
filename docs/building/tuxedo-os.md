# Build and install KDockW on TUXEDO OS

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

From the KDockW source directory:

```sh
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

The `release` preset disables tests. To run the QML and other tests, configure
the `dev` preset, build it, and use the repository's `dev` test preset instead.
TUXEDO OS's `catch2` package provides Catch2 3, which the test configuration
requires.

KDockW uses KI18n catalogs. The Russian catalog is built from
`src/po/ru/kdockw.po` and installed under the locale directory as
`kdockw.mo`. The application also adds the build-tree catalog directory when
run directly from `build/release/bin/kdockw`, so translations work both before
and after installation. The desktop file contains the translated static
metadata; runtime UI strings come from KI18n. KDockW follows the KDE/Qt system
locale on first start. The **Settings → General → Language** page can instead
select Russian or English; the choice is stored in `kdockwrc` and applies to
KDockW immediately without changing Plasma's locale or the user's environment.

After installation, retain the installed desktop ID
`com.thicking.kdockw.desktop` and its `X-KDE-Wayland-Interfaces` entry. That entry
declares the KWin Wayland interfaces the application uses. Do not replace the
standard desktop file with a custom service shortcut or change its ID. For
PRIME-specific service setup and diagnostics, see
[`../troubleshooting/nvidia-prime-wayland.md`](../troubleshooting/nvidia-prime-wayland.md).

## Optional systemd user service

If KDockW needs a controlled process environment, install the checked-in user
service template. It starts the installed binary directly and removes only the
listed PRIME and Qt backend variables from that service:

```sh
install -D -m 644 packaging/systemd/kdockw.service \
  ~/.config/systemd/user/kdockw.service
systemctl --user daemon-reload
systemctl --user enable --now kdockw.service
```

For the full one-starter migration sequence and rollback, see
[`../migration/krema-to-kdockw.md`](../migration/krema-to-kdockw.md).

`Application::makeAboutData()` sets the desktop ID to `com.thicking.kdockw` by
default, so this service does not need a wrapper or the optional
`--desktopfile` override. KDockW accepts that KDE command-line option, but it
is not needed for the standard installed desktop entry.

To prevent duplicate instances, choose one login starter: either the installed
XDG autostart entry or the systemd user service. When using the service, first
save any existing user override, then mask the system autostart entry for this
user with the same desktop-file name:

```sh
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/com.thicking.kdockw.autostart.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
```

Keep `/usr/local/share/applications/com.thicking.kdockw.desktop` installed and
unchanged, including its `X-KDE-Wayland-Interfaces` line. If desired, add a
separate launcher at `~/.local/share/applications/kdockw-service.desktop`:

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

Do not change the original KDockW desktop file's `Exec` to point to a wrapper.
On the reproduced setup, a wrapper in that file coincided with missing
unpinned tasks, launch feedback, and previews. Preserve the normal desktop ID
so KWin can associate the application with its declared Wayland interfaces.

## Updating and removing

Update the source tree, then repeat the configure/build/install commands. The
install step replaces files under `/usr/local`; it does not manage a custom
systemd user unit or user-created service shortcut. Review the changelog before
restarting the dock.

To remove a source installation, use the same configured build tree:

```sh
sudo cmake --build build/release --target uninstall
```

The release configuration in this repository exposes this target. If another
build configuration does not provide it, remove only the files listed in that
build's `install_manifest.txt`. Do not use a broad `rm -rf /usr/local` command.
Disable and remove only a user-created KDockW service or launcher, and restore
the user's prior autostart choice.
