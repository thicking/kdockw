# KDockW changelog

This file records KDockW's independent project history. The original Krema
releases and their notes are preserved in the
[archived Krema changelog](docs/history/krema-changelog.md). See
[FORK_CHANGES.md](FORK_CHANGES.md) for a behavior-focused summary of changes
carried forward from the Krema-based development period.

## [Unreleased]

The current local candidate targets v0.1.2. It has not been published.

### Changed

- Set the local application and package metadata version to 0.1.2. This
  candidate has not been published.

### Added

- Added live, saved window-preview layout controls: thumbnail width, maximum
  thumbnail height with source aspect-ratio preservation, card padding, and the
  dock gap. New defaults are 200 px, 180 px, 8 px, and 8 px; existing saved
  thumbnail widths remain intact.
- Redesigned the preview as a compact, rounded, translucent card with a thin
  border, soft shadow, application header, and per-window title. The popup has
  no arrow and fades in and out.
- Followed the dock's resolved panel color, opacity, radius, shadow and rounded
  KWin blur/contrast region in the preview and existing app-name tooltip. Kept a
  stable preview slot across window shapes, rendered PipeWire frames directly,
  and used a clipped center-crop Cover viewport without an offscreen effect
  layer. The app-name tooltip gap now follows icon zoom.
- Completed the accepted preview redesign with rounded Scene Graph clipping on
  the PipeWire source subtree, minimized-window previews, a fixed 16:10 card,
  centered Cover crop, and tooltip bounds that remain clear during icon zoom.
  CPU-only remains available as a compatibility capture mode.

- Added live, saved badge text weight and size controls, with Medium (500) and
  100% as factory defaults. Explicitly saved user choices, including Bold (700),
  continue to take precedence over factory defaults.
- Added independent, saved badge background and text color settings with the
  requested red and white defaults, a live badge preview, contrast feedback,
  and a joint reset action. Existing badge counts and text rendering remain
  unchanged.
- Made the preview close button readable before hover with a KDE-themed surface
  and outline; hover now visibly marks the close action while retaining the
  existing window-close icon and grouped-window behavior.

### Changed

- Changed the factory badge text weight from Bold (700) to Medium (500). The
  text size remains 100%, and Number remains the default notification style.

### Fixed

- Applied rounded clipping to the PipeWire frame's own scene-graph subtree,
  instead of placing a clip node beside the QML child that needed clipping.
- Fixed rounded preview clipping on Qt 6 scene-graph backends by replacing
  unsupported triangle-fan clip geometry with explicitly triangulated geometry,
  without adding an offscreen PipeWire texture layer.
- Filled the inner window-preview area with centered Cover-cropped frames and
  rounded the viewport through scene-graph clipping, while keeping PipeWire
  frames on the direct rendering path.
- Prevented the application-name tooltip from being clipped at the dock's
  Wayland surface edge by reserving its full size, maximum-zoom clearance, and
  shadow, and clamping its along-screen position.
- Owner manual acceptance on KDE Plasma 6 / Wayland confirmed working
  previews for open and minimized windows in CPU-only mode. DMA-BUF/auto remains
  technical debt; it is not recorded as verified or as a confirmed cause of the
  earlier black-preview report.
- Kept the PipeWire source active for minimized-window previews, retained the
  last received texture in memory, and bound each grouped thumbnail to its own
  window UUID. The source keeps its default scene-graph opacity; the app icon
  covers it until the first frame arrives.
- Unified icon opacity across active, inactive, and minimized apps with a saved,
  live 50–100% control that affects icon images only. Legacy per-state opacity
  keys remain for configuration compatibility but no longer affect rendering.
- Kept notification badge digits out of the scaled badge texture, rendered them
  with Qt's text renderer, and selected a theme-aware foreground that meets
  WCAG AA contrast against opaque badge fills.

## [0.1.0] - 2026-11-03

KDockW 0.1.0 is the first stable standalone release of this KDE Plasma 6 dock
for Wayland. It brings configurable dock layout and running-app indicators,
saved CPU-compatible window previews, and reliability improvements carried
forward from the Krema-based development period.

### Added

- Added configurable running-app indicators: Dot, Line, Pill, Glow, and Bar
  styles, screen-edge or dock-interior placement, adjustable size and color,
  with a live preview and saved preferences.
- Added independently adjustable 0–64 logical-pixel content padding for all four
  dock edges, plus start/center/end alignment. Changes apply immediately and are
  saved; the Icons page includes a reset-to-defaults action.
- Added a saved CPU-compatible window-preview capture option. Auto remains the
  default, and changing the option recreates active preview streams.

### Changed

- Adopted the configured KDockW appearance as the planned 0.1.0 first-run
  defaults: 40 px icons, 13 px spacing, asymmetric content padding, 1.7 zoom,
  a tinted panel and shadow, matching opacity and indicator settings, and
  separated pinned and running applications.
  Saved user values continue to override these defaults; CPU-only preview and
  personal launcher/monitor data remain excluded.
- Established KDockW's independent versioning and updated About copyright
  attribution to retain Krema's contributor attribution and identify Byeonghoon
  Yoo as its original author.
- Updated the About page with KDockW's independent maintainer, Krema's original
  author, the Wayland-focused product description, and the current application
  icon.

### Fixed

- Kept running-app indicators within the dock panel and Wayland surface on all
  four screen edges, including with small content padding, without letting the
  decorative marker band enlarge the transparent input region.
- Kept each dock and its window previews tied to the selected monitor when
  Wayland recalculates a layer surface's Qt screen during output geometry
  changes.
- Fixed the About page so its description, copyright, and author roles follow
  the selected KDockW language while the page is open. The settings search hint
  now follows the same language choice instead of Plasma's locale.
- Fixed RPM packages so they include the compiled KI18n translation catalogs.
- Fixed the language selector popup so all three options are visible, and
  restored the General page's access to the shared settings singleton. Language
  choices now save after user selection, persist across page navigation and
  launches, and apply across the open settings sidebar and page.

### Removed

- Removed the project-provided `kdockw.service` template. XDG autostart is now
  the only supported automatic login startup path; existing user units are
  left untouched and have a separate manual migration guide.

## 2026-11-02 — Independent KDockW project

### Changed

- Established the KDockW product identity, executable and desktop IDs, settings
  file, translation domain, QML URI, application metadata, and explicit
  migration/rollback tools. [Rebrand commit](https://github.com/thicking/kdockw/commit/b82b896)
- Integrated the KDockW app icon and logo, then corrected the pinned Flatpak
  icon resource. [Workspace and assets](https://github.com/thicking/kdockw/commit/bb0c47e),
  [Flatpak icon](https://github.com/thicking/kdockw/commit/d84e169)
- Moved the development checkout to its current workspace and updated brand
  assets. [Workspace commit](https://github.com/thicking/kdockw/commit/bb0c47e)
- Detached the GitHub repository from the original fork network. This was a
  GitHub repository-metadata change, not a source commit; the repository now
  reports `isFork: false` and has no parent. [Repository](https://github.com/thicking/kdockw)
- Updated current repository links and documented the independent naming and
  attribution policy. [Branding documentation](https://github.com/thicking/kdockw/commit/c2efdae)

### Added

- Added a saved application language choice for System default, Russian, or
  English. [Language selector](https://github.com/thicking/kdockw/commit/0563eb6)

### Fixed

- Kept the language choice synchronized with the settings selector, saved it
  across page and process recreation, and updated existing translations.
  [Persistence fix](https://github.com/thicking/kdockw/commit/9dbfb00)
- Kept compositor blur enabled while background geometry follows parabolic
  zoom. [Background fix](https://github.com/thicking/kdockw/commit/40f1bb9)
- Activated an existing application window while files are dragged over its
  dock icon, without consuming the drag. [Feature](https://github.com/thicking/kdockw/commit/f60dbae)
  · [Manual Wayland acceptance record](https://github.com/thicking/kdockw/commit/34d142d)

## 2026-11-01 — Improvements carried forward into KDockW

These changes were made while the repository was still presented as a Krema
fork. They remain part of KDockW's source history; prior Krema release notes
remain in the archive above.

### Added

- Added a Russian KI18n catalog for the dock, settings, menus, accessibility
  labels, and notifications. [Localization](https://github.com/thicking/kdockw/commit/732e57b)
- Added TaskManager model diagnostics that avoid logging window titles.
  [Diagnostics](https://github.com/thicking/kdockw/commit/0907fe7)
- Added diagnostic logging for PipeWire capture and an experimental CPU-readable
  buffer retry when no first frame arrives. The retry is not a confirmed general
  fix for DMA-BUF import failures. [Diagnostics and retry](https://github.com/thicking/kdockw/commit/b463773)
- Documented the observed NVIDIA PRIME behavior and user-service workaround on
  one TUXEDO hybrid-GPU configuration. [Troubleshooting guide](https://github.com/thicking/kdockw/commit/caa7ac1)

### Fixed

- Limited launch-icon bounce to five full cycles, with earlier completion when
  the launched window appears. [Launch feedback](https://github.com/thicking/kdockw/commit/c804cf0)
- Accepted launcher URLs supplied by the Plasma task manager while retaining
  URI-list and `.desktop` drops. [Task-manager drops](https://github.com/thicking/kdockw/commit/9d61ea3)
