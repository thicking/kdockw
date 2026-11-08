# KDockW

<p align="center"><img src="branding/logo/kdockw-logo.png" alt="KDockW logo with its app icon and dock illustration" width="768"></p>

<p align="center"><strong>KDockW — KDE Dock for Wayland</strong></p>

<p align="center"><strong>A native Wayland dock for KDE Plasma 6.</strong></p>

<p align="center"><a href="README.ru.md">🇷🇺 Русский</a> · <a href="README.md">🇬🇧 English</a></p>

<p align="center">

[![Status](https://img.shields.io/badge/Status-Active_development-blue.svg)](#roadmap)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-3978D4.svg)](https://kde.org/plasma-desktop/)
[![Qt 6](https://img.shields.io/badge/Qt-6.8+-41cd52.svg)](https://www.qt.io/)

</p>

<p align="center">
  <a href="#installation">Build and install</a> ·
  <a href="ROADMAP.md">Roadmap</a> ·
  <a href="ROADMAP.ru.md">Русский</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="docs/migration/krema-to-kdockw.md">Migration from Krema</a> ·
  <a href="docs/migration/krema-to-kdockw.ru.md">на русском</a> ·
  <a href="https://thicking.github.io/kdockw/">Project website</a>
</p>

KDockW is an independent KDE Plasma 6 dock for Wayland and a spiritual successor to Latte Dock. Written in C++23 with Qt 6 and KDE Frameworks 6, it provides parabolic icon zoom, window previews, app grouping, launch feedback, and Plasma integration.

KDockW is an independently developed fork of the open-source Krema project, built with help from AI coding agents. I set requirements and make product decisions, then test and review changes on real KDE Plasma / Wayland systems. Krema's Git history and original authorship are preserved; see [Origins and Credits](#origins-and-credits) for details.

## Why KDockW?

KDockW started as a personal project. I wanted a modern, customizable dock with smooth animations and live window previews for KDE Plasma 6 on Wayland, but existing options did not quite suit my needs. I focused on everyday usability, visual quality, KDE integration, and the features I wanted on my own desktop.

## KDockW in Action

Classic Zoom, dock animations, and live window previews:

https://github.com/user-attachments/assets/da075b0f-4fcf-4d15-a608-a3b91eddcfcf

## Screenshots

<p align="center">
  <img src="docs/screenshots/kdockw-classic-zoom.png" alt="KDockW dock with the Firefox icon enlarged by Classic Zoom">
</p>
<p align="center"><sub>Classic Zoom magnifies the hovered app while keeping the full dock visible.</sub></p>

<table width="100%">
  <tr>
    <td align="center" width="50%">
      <img src="docs/screenshots/kdockw-window-preview.png" alt="Live Yandex Browser window preview above the KDockW dock" width="560"><br>
      <sub>Live preview of an open window.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/screenshots/kdockw-dock-overview.png" alt="KDockW dock with pinned apps and notification badges" width="560"><br>
      <sub>Dock overview with pinned applications and notification badges.</sub>
    </td>
  </tr>
</table>

## Project Highlights

- **Native KDE Plasma 6 / Wayland** — A standalone dock that follows KDE and Wayland desktop conventions.
- **Smooth dock interaction** — Classic Zoom, adjustable animation, launch feedback, and configurable running-app indicators.
- **Live window previews** — Preview open and minimized windows, browse grouped apps, and activate a window with a click.
- **Personalized appearance** — Adjust panel styling, icon opacity, notification badges, and preview-card sizes.
- **Verified Linux packages** — KDockW packages are published on GitHub Releases. Starting with v0.3.2, the required release matrix covers Debian 13, Ubuntu 26.04 LTS, and Fedora 45.

For implementation and troubleshooting details, see the [window-preview architecture and diagnostics](docs/architecture/window-previews.md), [KDE TaskManager model notes](docs/kde/taskmanager-models.md), and [NVIDIA PRIME / Wayland troubleshooting](docs/troubleshooting/nvidia-prime-wayland.md). Optional task-model diagnostics log row and role changes without recording window titles.

## Features

### Core Dock
- **Parabolic Zoom** — macOS-style magnification on hover that pushes neighbouring icons aside, with an optional in-place style
- **Zoom Animation** — Pick a hover zoom preset: Natural (default, eases in and out like the macOS Dock), Quick, Relaxed, or Instant; or switch to Custom to set zoom-in and zoom-out duration and easing separately
- **Launch Feedback** — The launch icon bounces until a window appears, or for at most five complete cycles
- **Icon Size Normalization** — Auto-detects icon padding and scales for uniform appearance
- **Content Padding and Alignment** — Set independent 0–64 px insets on all four sides of the dock and align its icons to the start, center, or end; changes apply immediately and are saved
- **Running App Indicators** — Configure Dot, Line, Pill, Glow, or Bar markers, their placement, size, and color
- **First-Run Appearance** — The default layout uses 40 px icons, 13 px spacing, 8/8/8/0 px insets, 1.7 zoom, and a tinted `#4b4144` panel with shadow
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
- **PipeWire Thumbnails** — Live window previews on hover
- **Capture Compatibility** — Keep Auto (DMA-BUF preferred) or enable saved CPU mode if previews appear black; CPU mode may increase processor usage
- **Multi-Window List** — All windows of grouped apps shown together; the optional grouped click action opens this list even with hover previews off
- **Preview Card Layout** — Set thumbnail width and maximum height, preserve window proportions, and adjust card padding and its gap from the dock
- **Click-to-Activate** — Click a preview to switch to that window
- **Preview Close Button** — Close windows directly from the preview popup

### Notifications & Attention
- **Notification Badges** — Badge count on dock icons via D-Bus and SmartLauncher Unity API
- **Badge Display Modes** — Choose between Number, Dot, or Off
- **Running App Indicators** — Choose Dot, Line, Pill, Glow, or Bar, place markers at the screen edge or dock interior, and set their size and color
- **6 Attention Animations** — Bounce, Wiggle, Pulse, Glow, Dot Color, and Blink
- **Task Progress Bar** — Progress indicator on dock icons (e.g. file copy in Dolphin)
- **Do Not Disturb** — Attention animations suppressed when system DND is active
- **Auto-Stop** — Attention animations stop after a configurable duration (3s by default)
- **Release Update Checker** — Check stable KDockW GitHub Releases automatically or on demand, receive a KDE notification, and open the release page; updates are never downloaded or installed automatically

### Multi-Monitor & Virtual Desktops
- **Multi-Monitor Modes** — Primary monitor only, All monitors, Follow active screen, or Selected monitors
- **Per-Screen Settings** — Override icon size, edge, visibility mode per monitor
- **Follow Active Triggers** — Mouse, focus, or composite trigger for dock follows
- **Virtual Desktop Filtering** — Show all desktops, dim other desktops, or current only
- **Automatic Startup** — Launches on login, enforces single instance

Choose **Selected monitors** in Settings → Monitors & Desktops, then enable the switches for the output names you want. Each selected connected output with usable geometry gets a dock. Primary-display changes and unselected monitor connections or disconnections leave retained docks and previews in place. Disconnected selections stay listed and can be removed by turning their switches off.

If the selection is empty or no selected output is usable, KDockW shows a temporary dock on the primary display and a warning in Settings. The saved selection stays unchanged; reconnecting a selected monitor restores its dock and removes the fallback. Switching to another mode hides the selection controls without clearing the saved names.

In `kdockwrc`, `MonitorMode=3` means `SelectedScreens`; `SelectedOutputs` is a string list of exact output names such as `eDP-1` and `HDMI-A-1`. Existing values remain `0=PrimaryOnly` (default), `1=AllScreens`, and `2=FollowActive`.

### Integration & Accessibility
- **KDE Native Integration** — Kirigami UI, KDE color schemes, Plasma theme colors
- **Wayland Native** — Built on Layer Shell protocol for proper dock behavior
- **Smart Visibility** — Always visible, auto-hide, or dodge windows modes
- **Drag & Drop** — Reorder dock items, drop files onto apps, add launchers by dragging .desktop files, and optionally activate a running app after hovering dragged files over its icon
- **Settings UI** — Kirigami-based settings dialog (FormCard) with a system, Russian, or English language selector
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

KDockW 0.4.0 is the latest stable release. Download the source archive, release packages, and checksums from the [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.0). See the [release process](docs/releasing/release-process.md), [versioning policy](docs/releasing/versioning.md), and, on TUXEDO OS, the [build guide](docs/building/tuxedo-os.md) for current Qt/KDE package names and release-build instructions.

### Linux package targets

The v0.4.0 release provides packages for Debian 13, Ubuntu 26.04 LTS, and Fedora 45. These are the required package-build and Distro E2E targets; older compatibility recipes are available for manual checks but are not release assets. The previous v0.3.1 release retains its original 12 verified package assets. GitHub Releases is the only publication channel.

Building KDockW from source requires Qt 6.8 or newer and KDE Frameworks 6.0 or newer.

| Package | Release target |
| --- | --- |
| .deb | Debian 13; Ubuntu 26.04 LTS |
| .rpm | Fedora 45 |

Install a downloaded package with the system package manager:

```bash
sudo apt install ./kdockw-0.4.0-debian-13.deb
sudo apt install ./kdockw-0.4.0-ubuntu-26.04.deb
sudo dnf install ./kdockw-0.4.0-fedora-45.rpm
```

```bash
git clone --branch main --single-branch https://github.com/thicking/kdockw.git kdockw
cd kdockw
cmake --preset release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build --preset release -j 4
sudo cmake --install build/release
```

With the commands above, the executable is installed as `/usr/local/bin/kdockw`; distro builds commonly use `/usr/bin/kdockw`. The matching XDG autostart entry launches that binary directly. The application desktop ID declares the KWin Wayland interfaces required by previews and activation. For Krema settings migration, read the [manual migration and rollback guide](docs/migration/krema-to-kdockw.md) ([на русском](docs/migration/krema-to-kdockw.ru.md)). If an older checkout created `kdockw.service`, see the [systemd-to-XDG migration guide](docs/migration/systemd-to-xdg-autostart.md) ([на русском](docs/migration/systemd-to-xdg-autostart.ru.md)). Installing KDockW does not remove Krema or alter user startup files.

To update the checkout, pull from `https://github.com/thicking/kdockw` and rebuild. CMake's configured build provides an `uninstall` target; otherwise remove only paths listed in that build's `install_manifest.txt`.

KDockW follows the system language by default. Open **Settings → General → Language** to choose **System default**, **Русский**, or **English**. The selected language is saved in `kdockwrc` and the KDockW interface updates immediately; this setting does not change Plasma's language or process-wide locale environment.

## Known Limitations

- On a hybrid-GPU system, Automatic (DMA-BUF) has produced black previews. If this happens, try **Settings → Window Preview → Compatibility mode (CPU)**; it restored previews on the tested system and may increase CPU usage.
- If the Russian translation catalog is unavailable, KDockW displays its English source strings.

## Roadmap

See the current development roadmap in [English](ROADMAP.md) or [Russian](ROADMAP.ru.md).

## Origins and Credits

KDockW is based on [Krema](https://github.com/isac322/krema), originally created by Byeonghoon Yoo, and is developed independently. The Git history and original file-level copyright notices are retained. KDockW is distributed under [GPL-3.0-or-later](LICENSES/GPL-3.0-or-later.txt), and all required license notices remain in the repository.

## Contributing

Contributions are welcome. Please open an issue to discuss a proposal before submitting a pull request.
