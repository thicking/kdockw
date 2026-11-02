<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="branding/logo/krema-lockup-dark.svg">
    <img src="branding/logo/krema-lockup.svg" alt="Krema — KDE Plasma 6 dock" height="96">
  </picture>
</h1>

<p align="center"><strong>Krema — Community Fork</strong></p>

<p align="center"><a href="README.ru.md">🇷🇺 Русский</a> · <a href="README.md">🇬🇧 English</a></p>

<p align="center"><strong>The zooming dock for KDE Plasma 6, native to Wayland.</strong></p>

<p align="center">

[![WIP](https://img.shields.io/badge/Status-Work_in_Progress-yellow.svg)](#roadmap)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-a8682f.svg)](https://kde.org/plasma-desktop/)
[![Qt 6](https://img.shields.io/badge/Qt-6.8+-41cd52.svg)](https://www.qt.io/)
[![Website](https://img.shields.io/badge/Website-krema.bhyoo.com-d69a5e.svg)](https://krema.bhyoo.com/)

</p>

<p align="center">
  <a href="https://krema.bhyoo.com/">Upstream website</a> ·
  <a href="#installation">Install</a> ·
  <a href="ROADMAP.md">Roadmap</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

> **Community fork:** This public repository is a modified version of [isac322/krema](https://github.com/isac322/krema), originally created by Byeonghoon Yoo. It keeps the upstream project and license, and adds a Russian KI18n catalog, targeted fixes, diagnostics, and setup documentation. This fork is based on upstream v0.12.0 and is maintained separately from upstream `master`.

## Fork Enhancements

| Area | What this fork adds |
|---|---|
| Russian localization | 256 translated KI18n messages for the UI, settings, context menus, tooltips, accessibility text, and notifications. |
| Launch feedback | Launch-icon bounce stops after at most five complete cycles and finishes after the current cycle when a new window appears. This is separate from configurable attention animations. |
| Plasma task-manager drag and drop | Reads the launch URL from `text/x-orgkdeplasmataskmanager_taskurl`; existing URL and desktop-file drops remain supported. |
| External file drag hover | After a configurable delay, activates an existing window under a dragged file without consuming the drag. Launcher-only tasks are ignored; grouped tasks raise their active or most recently used window. |
| TaskManager diagnostics | Debug logs describe task insertion, removal, and role changes without logging window titles. They aid diagnosis and do not change TaskManager filtering. |
| PipeWire preview diagnostics | Logs stream state and retries once with CPU-readable buffers if streaming produces no first frame. This fallback is experimental and is not a confirmed general DMA-BUF fix. |
| NVIDIA PRIME guidance | Documents the observed hybrid-GPU behavior and a per-user service setup for one TUXEDO OS / Wayland configuration. |
| TUXEDO OS guide | Documents dependencies, release build, `/usr/local` installation, translation catalogs, desktop identity, and user-service setup. |

See [FORK_CHANGES.md](FORK_CHANGES.md) for implementation details, verification status, limitations, and the corresponding commits.

Krema is an actively developed KDE Plasma 6 dock. Some upstream features are still in progress; see the [upstream roadmap](https://github.com/isac322/krema/blob/master/ROADMAP.md).

A lightweight, high-performance dock for KDE Plasma 6 — spiritual successor to [Latte Dock](https://github.com/KDE/latte-dock).

Krema brings back the beloved dock experience for KDE Plasma users who miss Latte Dock. Built from scratch with C++23, Qt 6, and KDE Frameworks 6, it delivers smooth parabolic zoom animations, live window previews via PipeWire, and deep native integration with the Plasma desktop.

## Why Krema?

- **Your dock is back** — Krema picks up where Latte Dock left off, purpose-built for Plasma 6
- **A dock that speaks Plasma** — Uses KDE's own frameworks (Kirigami, KConfig, KColorScheme, KGlobalAccel) and respects your theme, shortcuts, and desktop conventions
- **Lightweight by design** — GPU-accelerated rendering via QRhi, Wayland-native via Layer Shell, lazy resource allocation
- **Make it yours** — 4 background styles including acrylic frosted glass, configurable zoom, spacing, and position

## Screenshots

<img src="branding/screenshots/dock-zoom.png" alt="Krema dock with parabolic zoom — icons magnify smoothly as the pointer glides across them" width="100%">

<table>
  <tr>
    <td><img src="branding/screenshots/dock-overview.png" alt="Krema dock along the bottom of a Plasma desktop, pinned launchers with running-app indicators below open Dolphin and Konsole windows"></td>
    <td><img src="branding/screenshots/settings.png" alt="Krema settings window — Kirigami form cards controlling icon size, spacing, zoom and behavior"></td>
  </tr>
</table>

## Features

### Core Dock
- **Parabolic Zoom** — macOS-style magnification on hover that pushes neighbouring icons aside, with an optional in-place style
- **Zoom Animation** — Pick a hover zoom preset: Natural (default, eases in and out like the macOS Dock), Quick, Relaxed, or Instant; or switch to Custom to set zoom-in and zoom-out duration and easing separately
- **Icon Size Normalization** — Auto-detects icon padding and scales for uniform appearance
- **Indicator Dots** — Visual markers for running applications
- **Pin/Unpin** — Keep favorite apps in the dock
- **Context Menu** — Right-click for pin, close, new instance, and the app's own actions like "New Private Window" (KDE Breeze native)
- **Mouse Wheel Cycling** — Scroll to switch between windows of the same app
- **Single-Window Click Action** — Activate by default; optionally minimize the active window with a left click, while clicking a minimized or background window still restores or focuses it
- **Grouped-Window Click Action** — Cycle through windows by default, or independently choose previews of all windows or minimize only the currently active window; with no active group window, the minimize choice restores or focuses the most recently used window

### Visual Styles
- **Panel-Inherit** — Match your Plasma panel style automatically
- **Transparent** — Fully transparent dock background
- **Tinted** — Custom color with adjustable opacity
- **Acrylic / Frosted Glass** — Blur + noise texture effect

### Window Previews
- **PipeWire Thumbnails** — Live GPU-efficient window previews on hover
- **Multi-Window List** — All windows of grouped apps shown together; the optional grouped click action opens this list even with hover previews off
- **Click-to-Activate** — Click a preview to switch to that window
- **Preview Close Button** — Close windows directly from the preview popup

### Notifications & Attention
- **Notification Badges** — Badge count on dock icons via D-Bus and SmartLauncher Unity API
- **Badge Display Modes** — Choose between Number, Dot, or Off
- **6 Attention Animations** — Bounce, Wiggle, Pulse, Glow, Dot Color, and Blink
- **Task Progress Bar** — Progress indicator on dock icons (e.g. file copy in Dolphin)
- **Do Not Disturb** — Attention animations suppressed when system DND is active
- **Auto-Stop** — Attention animations stop after configurable duration (default 5s)

### Multi-Monitor & Virtual Desktops
- **Multi-Monitor Modes** — Primary monitor only, All monitors, Follow active screen, or Selected monitors
- **Per-Screen Settings** — Override icon size, edge, visibility mode per monitor
- **Follow Active Triggers** — Mouse, focus, or composite trigger for dock follows
- **Virtual Desktop Filtering** — Show all desktops, dim other desktops, or current only
- **Automatic Startup** — Launches on login, enforces single instance

Choose **Selected monitors** in Settings → Monitors & Desktops, then enable the switches for the output names you want. Each selected connected output with usable geometry gets a dock. Primary-display changes and unselected monitor connections or disconnections leave retained docks and previews in place. Disconnected selections stay listed and can be removed by turning their switches off.

If the selection is empty or no selected output is usable, Krema shows a temporary dock on the primary display and a warning in Settings. The saved selection stays unchanged; reconnecting a selected monitor restores its dock and removes the fallback. Switching to another mode hides the selection controls without clearing the saved names.

In `kremarc`, `MonitorMode=3` means `SelectedScreens`; `SelectedOutputs` is a string list of exact output names such as `eDP-1` and `HDMI-A-1`. Existing values remain `0=PrimaryOnly` (default), `1=AllScreens`, and `2=FollowActive`.

### Integration & Accessibility
- **KDE Native Integration** — Kirigami UI, KDE color schemes, Plasma theme colors
- **Wayland Native** — Built on Layer Shell protocol for proper dock behavior
- **Smart Visibility** — Always visible, auto-hide, or dodge windows modes
- **Drag & Drop** — Reorder dock items, drop files onto apps, add launchers by dragging .desktop files, and optionally activate a running app after hovering dragged files over its icon
- **Settings UI** — Kirigami-based settings dialog (FormCard) for easy customization
- **Keyboard Accessibility** — Full keyboard navigation with AT-SPI screen reader support

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Meta+\` | Toggle dock visibility |
| Meta+1-9 | Activate Nth app |
| Meta+Shift+1-9 | Launch new instance of Nth app |
| Meta+Alt+D | Focus dock for keyboard navigation |
| Arrow keys | Navigate between dock items / preview thumbnails |
| Enter | Activate focused item |
| Escape | Exit keyboard navigation |

In Selected monitors mode, Toggle Dock and app-number shortcuts target the selected primary display, then the first selected output in the adopted compositor order, then the saved selection order. Focus Dock uses the dock on the cursor's screen when available; a cursor on an unselected output falls back to the same order.

## Installation

### Install this fork (recommended)

This fork currently has no GitHub Releases or advertised fork-specific binary
packages. Build its `main` branch to get the changes documented above:

```bash
git clone --branch main --single-branch https://github.com/thicking/krema.git
cd krema
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

See the [TUXEDO OS build guide](docs/building/tuxedo-os.md) for the package
list, translation installation, desktop-file/KWin integration, and optional
systemd user service. The source build requires CMake 3.22+, Qt 6.8+, KDE
Frameworks 6, KDE Plasma 6, Wayland 1.22+, and GCC 13+ or Clang 17+.

To update an existing source checkout of this fork:

```bash
git pull --ff-only origin main
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

The configured CMake build provides an `uninstall` target:

```bash
sudo cmake --build build/release --target uninstall
```

If a different build does not provide that target, remove only the paths listed
in that build's `install_manifest.txt`; do not delete `/usr/local` broadly.

> **Ubuntu 24.04 Noble:** the original Krema PPA currently has no Noble
> `Release`/`InRelease` file (HTTP 404, checked 2026-11-01), and its OBS Ubuntu
> 24.04 repository URL also returns 404. Noble's stock Qt/KDE packages do not
> meet this source tree's Qt 6.8+/KDE Frameworks 6 requirements. TUXEDO OS 24.04
> provides a newer Qt/KDE stack and is documented as a source-build target in
> the guide above.

### Packages for the original upstream project

The package repositories below are maintained by [isac322/krema](https://github.com/isac322/krema).
They install upstream Krema, **not this fork's commits**. Use them only if you
want the upstream package build. The listed versions reflect the upstream
README at the time this fork was audited; consult the live upstream README for
changes.

| Distribution | Upstream channel | Versions listed upstream | Package page |
|---|---|---|---|
| Arch Linux / Manjaro | AUR | Rolling | [AUR](https://aur.archlinux.org/packages/krema) |
| Fedora | COPR | 42, 43, 44, Rawhide | [COPR](https://copr.fedorainfracloud.org/coprs/isac322/krema/) |
| openSUSE | OBS | Tumbleweed, Slowroll, Leap 16.0 | [OBS](https://build.opensuse.org/package/show/home:isac322/krema) |
| Ubuntu | Launchpad PPA / OBS | 25.04, 25.10, 26.04, 26.10 (OBS) | [PPA](https://launchpad.net/~isac322/+archive/ubuntu/krema) · [OBS](https://download.opensuse.org/repositories/home:/isac322/) |
| Debian | OBS | 13 (Trixie) | [OBS repository](https://download.opensuse.org/repositories/home:/isac322/Debian_13/) |

See the [upstream installation instructions](https://github.com/isac322/krema#installation)
for the current package commands and availability. No upstream package is a
substitute for building this fork.

## Known Limitations

- The Russian catalog compiles and contains 256 translated messages. Automatic
  language selection was not revalidated in a live Plasma session during this
  documentation audit.
- The no-first-frame CPU-buffer retry is experimental. It is covered by a QML
  test for the retry path, but it has not been established as a general fix for
  black previews or cross-GPU DMA-BUF import.
- The Plasma task URL MIME parser and launch-bounce lifecycle have QML coverage;
  a real external Plasma-to-Krema drag and live dock behavior still depend on
  the target Wayland session and were not part of the documentation audit.
- TaskManager logging adds evidence about model rows and roles; it does not
  change KDE's task filtering or guarantee that every desktop launcher exposes
  the KWin interfaces Krema needs.
- This fork is based on upstream v0.12.0. Upstream `master` has since advanced;
  the fork is not automatically synchronized with those later changes.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full development roadmap.

## Acknowledgments

Krema is a spiritual successor to [Latte Dock](https://github.com/KDE/latte-dock), which served the KDE community for years as the go-to dock application. We are grateful for the Latte Dock project and the community that built and maintained it. Krema aims to carry that spirit forward for KDE Plasma 6.

## Contributing

Contributions are welcome! Please open an issue to discuss your idea before submitting a pull request.

## License

Krema is licensed under [GPL-3.0-or-later](LICENSES/GPL-3.0-or-later.txt).
