# KDockW changelog

This file records KDockW's independent project history. No standalone KDockW
release has been tagged yet, so the entries below do not assign KDockW version
numbers. The original Krema releases and their notes are preserved in the
[archived Krema changelog](docs/history/krema-changelog.md). See
[FORK_CHANGES.md](FORK_CHANGES.md) for a behavior-focused summary of changes
carried forward from the Krema-based development period.

## [Unreleased]

### Changed

- Updated the About page with KDockW's independent maintainer, Krema's original
  author, the Wayland-focused product description, and the current application
  icon.

### Fixed

- Fixed the language selector popup so all three options are visible, and
  restored the General page's access to the shared settings singleton. Language
  choices now save after user selection, persist across page navigation and
  launches, and apply across the open settings sidebar and page.

### Changed

- Replaced the inherited Krema roadmap and release history with an independent,
  evidence-based English/Russian KDockW roadmap and dated project changelog.

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
