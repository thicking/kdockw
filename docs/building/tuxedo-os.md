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

`catch2` is required when building the test suite. Use Qt and KDE packages from
the configured TUXEDO repositories together; mixing a newer runtime with
Noble's older development packages can cause ABI or CMake configuration
mismatches.

## Release build and installation

From the KDockW source directory:

```sh
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

The `release` preset disables tests. To run QML and other tests, configure and
build the `dev` preset, then use CTest from `build/dev`.

KDockW uses KI18n catalogs. The Russian catalog is built from
`src/po/ru/kdockw.po` and installed as `kdockw.mo`. The application also adds
the build-tree catalog directory when run directly from
`build/release/bin/kdockw`, so translations work before and after installation.
The Settings → General → Language page can follow the system locale or select
Russian or English without changing Plasma's locale or process environment.

## XDG autostart and desktop identity

XDG autostart is KDockW's only supported automatic login startup mechanism.
CMake installs `com.thicking.kdockw.autostart.desktop` under
`KDE_INSTALL_AUTOSTARTDIR`; its `Exec` is generated from
`KDE_INSTALL_FULL_BINDIR` and runs `kdockw` directly. With the TUXEDO guide's
`/usr/local` prefix, the entry is installed at
`/etc/xdg/autostart/com.thicking.kdockw.autostart.desktop` and runs
`/usr/local/bin/kdockw`. A distro build using `/usr` installs the same entry
under `/etc/xdg/autostart` and runs `/usr/bin/kdockw`. The XDG config location
is independent of the application prefix so Plasma can discover it through
the system's `XDG_CONFIG_DIRS`.

The regular application entry remains
`com.thicking.kdockw.desktop` under `share/applications`. Its ID and
`X-KDE-Wayland-Interfaces` declaration must remain intact so KWin can associate
the application with the required window-management, activation-feedback, and
screencasting interfaces. The autostart entry and regular desktop entry both
launch the configured binary directly; do not substitute a wrapper or service
launcher. KDockW uses KDE's unique D-Bus application service to forward later
launch requests to the existing instance rather than create a second dock.

Check an installation without changing it:

```sh
test -f /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
grep '^Exec=' /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
grep -E '^(Exec|OnlyShowIn|X-KDE-Wayland-Interfaces)=' \
  /usr/local/share/applications/com.thicking.kdockw.desktop
```

If installing with prefix `/usr`, adjust the application-file path to
`/usr/share/applications/com.thicking.kdockw.desktop`. A user override with
the same autostart desktop ID in `~/.config/autostart/` takes precedence over
the installed entry; check it if login startup is disabled or behaves
unexpectedly. See the [systemd-to-XDG migration guide](../migration/systemd-to-xdg-autostart.md)
if an older checkout or local setup created a `kdockw.service`.

Manual launch remains available from the application menu or directly:

```sh
/usr/local/bin/kdockw
```

Use `/usr/bin/kdockw` for a `/usr` installation.

## Update and remove

Update the checkout and repeat the configure/build/install commands. The
install step refreshes the application and autostart entries. It does not
rewrite user configuration or user-created autostart overrides.

To remove a source installation, use the same configured build tree:

```sh
sudo cmake --build build/release --target uninstall
```

The release configuration exposes this target. Otherwise remove only the
files listed in that build's `install_manifest.txt`. Do not use a broad
`rm -rf /usr/local` command. User settings remain in `kdockwrc` unless you
remove them separately.

## Window-preview diagnostics

The supported setting is in **Settings → Window Preview → Compatibility mode
(CPU)**. Auto is the default and allows DMA-BUF; CPU compatibility disables
DMA-BUF only on KPipeWire `PipeWireSourceItem` streams. The choice is saved and
recreates active preview streams. It does not change Qt Quick's rendering
backend or GPU environment.

For a process-only A/B experiment, first close the running instance normally
and verify that it exited. Launch one mode at a time, using the installed path
or `build/release/bin/kdockw`:

```sh
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=auto /usr/local/bin/kdockw
QSG_INFO=1 KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only /usr/local/bin/kdockw
```

`KDOCKW_PREVIEW_CAPTURE_MODE` overrides the saved setting for that process; it
does not write to `kdockwrc`. The CPU mode is a compatibility option for
configurations where DMA-BUF previews are black, not a universal GPU fix. For
the detailed A/B protocol and evidence limits, see
[`../troubleshooting/nvidia-prime-wayland.md`](../troubleshooting/nvidia-prime-wayland.md)
and [`../architecture/window-previews.md`](../architecture/window-previews.md).
