# Changes in the Krema community fork

This file records only the changes maintained by `thicking/krema`; it does
not replace the upstream [Krema changelog](CHANGELOG.md). The fork's `main`
branch is based on upstream tag `v0.12.0` (`d15dae0`) and adds the commits
listed below. Upstream `master` has advanced independently since that base.

## Implemented changes

### Russian KI18n catalog

- **Change:** Added the `ru` KI18n catalog, wired it into CMake installation,
  and made the build-tree catalog available when running the release binary
  directly. Added Russian desktop metadata and correct plural forms.
- **Reason:** Make the complete user interface usable in Russian while leaving
  other locales on the existing English source strings.
- **Components:** `src/po/ru/krema.po`, `src/CMakeLists.txt`, `src/main.cpp`,
  application metadata, and QML strings.
- **Verification:** `msgfmt --check --statistics` reported 256 translated
  messages; the catalog compiled to the release build tree. The Qt Quick test
  suites passed (216 tests in the recorded run).
- **Limitations:** Locale selection in a live Plasma session was not repeated
  as part of this documentation audit.
- **Commit:** [`732e57b`](https://github.com/thicking/krema/commit/732e57b).

### Bounded application-launch bounce

- **Change:** Separated the launch-tracking state from the visual bounce
  session. The launch icon completes at most five cycles; when a new window or
  activation arrives sooner, it stops after the current cycle.
- **Reason:** KDE startup notification can remain pending long after the
  launched window is usable.
- **Components:** `src/qml/DockItem.qml` and `tests/qml/tst_dock_main.qml`.
- **Verification:** QML tests cover the five-cycle cap, early window arrival,
  repeated launch, simultaneous launches, and late startup notification.
- **Limitations:** The configurable six-style attention animation is separate
  and unchanged. Real startup timing can still vary with KWin and the
  application.
- **Commit:** [`c804cf0`](https://github.com/thicking/krema/commit/c804cf0).

### Plasma task-manager launcher URL drops

- **Change:** Read the plain launcher URL supplied with Plasma's task-manager
  drag under `text/x-orgkdeplasmataskmanager_taskurl`. The opaque task-button
  payload is not decoded. Existing URI-list and desktop-file handling remains.
- **Reason:** Plasma task-manager drags do not necessarily provide an ordinary
  `.desktop` file path.
- **Components:** `src/qml/main.qml`, `docs/kde/drag-and-drop.md`, and QML tests.
- **Verification:** QML tests cover the task URL parser and missing MIME case.
- **Limitations:** The real source-to-dock drag was not exercised in a live
  Wayland Plasma session during this audit; available MIME data depends on the
  drag source.
- **Commit:** [`9d61ea3`](https://github.com/thicking/krema/commit/9d61ea3).

### Activate running windows while hovering external file drags

- **Change:** Added a default-on Behavior setting that requests activation of an
  existing task after a configurable 300–1500 ms hover delay (700 ms default).
  The timer is canceled on exit, target change, drop, or drag cancellation. The
  hover path does not read or forward file URLs. Existing handling when files
  are actually dropped on the dock is unchanged. Grouped tasks target the
  active or most recently used child; a launcher with no window is ignored.
- **Reason:** Let users carry a file drag across the dock to a window without
  releasing it or making Krema open the file on hover.
- **Components:** `src/config/krema.kcfg`, `src/models/dockactions.*`,
  `src/qml/main.qml`, `src/qml/settings/BehaviorPage.qml`, KI18n catalog,
  and QML/KWin regression tests.
- **Verification:** The release build passed. All five QML test suites passed,
  including delay, repeated hover, target change, cancellation, multi-file
  payload, and no-file-data cases. The KWin TaskManager suite passed 12 test
  cases (244 assertions), including single-window, grouped-window, and
  launcher-only activation checks. KI18n compiled with 256 translated
  messages. The user manually confirmed on KDE Plasma 6.6.6 / Wayland that
  dragging multiple files from Dolphin over Krema activates the browser, keeps
  the drag usable, and allows dropping into the target app. The user also
  confirmed that pinning `.desktop` launchers still works.

### TaskManager diagnostics

- **Change:** Added debug records for inserted and removed task rows and for
  role changes, including app ID, window/startup/launcher state, and pinned
  status. Window titles are not logged.
- **Reason:** Provide evidence when diagnosing missing unpinned applications
  without changing task selection or filtering behavior.
- **Components:** `src/models/dockmodel.cpp` and the synthetic unpinned-task
  QML test.
- **Verification:** Release build and QML tests passed in the recorded run.
- **Limitations:** This is diagnostic logging, not a fix to KDE TaskManager
  filtering. The synthetic model test does not prove every KWin, activity,
  output, or desktop-launcher configuration.
- **Commit:** [`0907fe7`](https://github.com/thicking/krema/commit/0907fe7).

## Experimental preview change

### PipeWire capture diagnostics and one CPU-buffer retry

- **Change:** Log PipeWire state, readiness, stream size, DMA-BUF usage, and
  KPipeWire error text. If a visible stream remains in `Streaming` without a
  first frame for 1.5 seconds, recreate it once with DMA-BUF disabled.
- **Reason:** Distinguish a stream that never starts from one that starts but
  does not deliver a frame, and provide an alternate buffer path for diagnosis.
- **Components:** `src/qml/PreviewThumbnail.qml`, QML mocks, and preview tests.
- **Verification:** The QML test verifies the retry switches to
  CPU-readable buffers. User-reported testing on one TUXEDO OS / Intel +
  NVIDIA setup found that clearing inherited PRIME and Qt backend variables
  restored previews.
- **Limitations:** The test does not exercise KWin, a physical GPU, DMA-BUF
  import, or the observed `GL_INVALID_OPERATION` on hardware. The CPU retry is
  experimental and is not established as a general fix for black thumbnails
  or cross-GPU import. See the [NVIDIA PRIME guide](docs/troubleshooting/nvidia-prime-wayland.md).
- **Commit:** [`b463773`](https://github.com/thicking/krema/commit/b463773).

## Documentation and repository navigation

### TUXEDO OS and NVIDIA PRIME guides

- **Change:** Added an English source-build guide for TUXEDO OS and a
  configuration-specific hybrid-GPU troubleshooting guide. The latter records
  the observed variables and user-service workaround without recommending
  global driver changes.
- **Reason:** Make the tested install and diagnostic steps reproducible.
- **Components:** `docs/building/tuxedo-os.md`,
  `docs/troubleshooting/nvidia-prime-wayland.md`, and links in both READMEs.
- **Verification:** Package names were checked against the configured Noble /
  TUXEDO package metadata; the Noble PPA and OBS Release URLs returned 404 on
  2026-11-01. Local documentation links and Markdown whitespace checks passed.
- **Limitations:** TUXEDO OS and NVIDIA PRIME observations describe the stated
  configuration only. They do not establish a universal driver or KWin defect.
- **Commit:** [`caa7ac1`](https://github.com/thicking/krema/commit/caa7ac1).

### Russian README and fork overview

- **Change:** Added a Russian README and links between the English and Russian
  versions. The README audit/realignment is tracked in the current documentation
  commit.
- **Reason:** Explain which repository users are viewing, distinguish fork
  changes from upstream packages, and link installation and troubleshooting
  information in both languages.
- **Components:** `README.md`, `README.ru.md`, and this file.
- **Verification:** Local links, command references, package/source distinction,
  and the parallel README section structure were checked.
- **Limitations:** Upstream package availability can change; the package table
  links to upstream-maintained sources and is explicitly not a list of fork
  packages.
- **Commits:** [Russian README](https://github.com/thicking/krema/commit/1890a79),
  [NVIDIA/TUXEDO guides](https://github.com/thicking/krema/commit/caa7ac1).
  The README alignment and this ledger are part of the current documentation
  commit.
