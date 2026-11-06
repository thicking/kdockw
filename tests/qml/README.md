# QML component tests (Tier 1)

Qt Quick Test suites that load KDockW's **real** QML files from `src/qml`
(`main.qml`, `DockItem.qml`, `PreviewPopup.qml`, `PreviewThumbnail.qml`) and
check their behavior headless (`QT_QPA_PLATFORM=offscreen`, software scene
graph). No compositor, D-Bus, PipeWire, or KWin is needed.

## Run

```sh
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON
cmake --build build --target kdockw_qml_tests
ctest --test-dir build -R qml --output-on-failure
```

Each `tst_*.qml` file is its own ctest entry (`qml_tst_*`, label `qml`). To
run a single test function directly:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=Basic \
  build/bin/kdockw_qml_tests -input tests/qml/tst_dockitem_zoom.qml test_peakAtHoveredItemEqualsMaxZoom
```

The tests reference `src/qml` by relative path (`../../src/qml`), so run them
from the source tree. They must not be copied into the build directory.

## Suites

| File | Component under test | Covers |
|---|---|---|
| `tst_dockitem_zoom.qml` | `DockItem.qml` + `ZoomAnimationProfile.qml` | Hover zoom fed by the production zoom layout (`DockView.zoomLayout`): the peak equals `maxZoomFactor` at the hovered item, falloff is symmetric and monotonic, neighbours are attenuated, zoom stays at 1.0 outside the panel and beyond the Gaussian range, sigma scales with icon size, the max-zoom setting applies live, zoom eases in and settles back to the rest layout for both styles, zoom animation presets resolve their zoom-in/zoom-out duration and easing (Natural eases in slower than Quick, Instant snaps), custom zoom-in and zoom-out durations follow their own timelines (a 0 ms zoom-in snaps while zoom-out still animates), In place tracks the pointer along the dock without lag, the Scale and Translate transforms match `currentScale`/`currentOffset`, Parabolic pushes neighbours aside with constant gaps and keeps the hovered icon under the pointer, In place scales around fixed centres with overlap, and each edge grows away from the screen edge |
| `tst_dockitem_geometry.qml` | `DockItem.qml` | Item size from `iconSize` and the configurable indicator reserve per edge, live resize when indicator size changes, icon `sourceSize` covering max zoom, icon provider URL and cache-busting, placeholder initial, icon opacity for active/minimized/background/drag-source windows, dimming of other virtual desktops |
| `tst_dockitem_indicators.qml` | `DockItem.qml` | Running indicators driven by `IsWindow`/`ChildCount` (capped at 3), live role updates, five shape styles and both positions on all four edges, indicator bounds within their reserved cell, active/minimized styling; badge count (`99+` overflow), number/dot/off modes and scaling, Unity LauncherEntry priority and activation clearing; progress bar; attention triggers, DND suppression, auto-stop, blink restoring icon opacity; accessible description |
| `tst_dock_main.qml` | `main.qml` | One delegate per task, including insertion/removal of an unpinned running task; layout, content padding/alignment and both indicator positions on all four edges, transparent input regions excluding the indicator band, panel sizing and centering, vertical docks, zoom through real hit testing, Parabolic background growth/neighbour displacement and In place behavior, preview display, click/wheel dispatch, launch bounce, keyboard navigation, drop handling, and press-hold drag reorder |
| `tst_preview_popup.qml` | `PreviewPopup.qml` + `PreviewThumbnail.qml` | Visibility follows the controller; single-window versus grouped thumbnails (titles, window IDs, active/minimized); a lagging `WinIdList` limits the thumbnail count; incremental updates keep existing delegates (and so their PipeWire streams); app switches rebuild the thumbnails; a removed parent hides the popup; thumbnail click activates the right window and close closes it; thumbnail size follows the setting; the size is reported to the controller; keyboard focus ring; placement per edge; hover keeps the preview open and cancels keyboard navigation |
| `tst_rounded_clip.qml` | clipped PipeWire source geometry | Source-local rounded viewport, clip radius, and center50 mode; the headless software scene graph does not validate target stencil pixels |
| `tst_tooltip_bounds.qml` | `main.qml` | Complete tooltip bounds, reserve for tooltip + maximum zoom + shadow, and placement on all four edges; also run at DPR 1.25, 1.5, and 2.0 |

## How the C++ backends are replaced

Production code exposes C++ objects as `com.thicking.kdockw` singletons
(`DockModel`, `DockSettings`, `NotificationTracker`, `LauncherEntryTracker`)
and as per-engine context properties (`DockView`, `DockActions`,
`DockContextMenu`, `DockVisibility`, `PreviewController`). `main.cpp`
(`QUICK_TEST_MAIN_WITH_SETUP`) prepends `mocks/` to the QML import path, so
the same identifiers resolve to test doubles:

- `mocks/com/thicking/kdockw/*.qml`: QML singletons with the properties and
  methods the QML uses. Defaults mirror `src/config/kdockw.kcfg`. Action
  methods record `{ name, args }` into `calls`, which you can query with
  `callsTo(name)`. `KDockWMocks.resetAll()` restores every mock and runs in each
  `init()`.
- `DockModel.tasksModel` is a C++ `MockTasksModel` (a `QStandardItemModel`
  with TaskManager role names). Tests populate it with
  `addTask({ display, IsWindow, ChildCount, IsActive, AppId, WinIdList, ... })`,
  `addChildTask(row, {...})`, `setTaskData(row, role, value)`, and
  `removeTask(row)`. `DockModel.iconName()`, `appId()`, `isPinned()`
  (`IsLauncher`), and `isOnCurrentDesktop()` read from those rows.
- `DockView.zoomLayout()` is not a copy: it calls the C++ `ZoomLayoutEngine`
  singleton (`kdockw.test`), which runs the production
  `kdockw::computeDockZoom` (`src/utils/zoomcalculator.h`) exactly as
  `DockView::zoomLayout` does. `DockItemRow.qml` feeds DockItem through the
  same pipeline as `main.qml` (zoom cursor, `zoomAmount` eased by
  `ZoomAnimationProfile` on entering and leaving, for both zoom styles).
- `LauncherEntryTracker` (Unity LauncherEntry state) is keyed by the task's
  `LauncherUrlWithoutIcon` role; tests set state with
  `LauncherEntryTracker.setEntry(url, { count, countVisible, urgent, progress, progressVisible })`.
- `org.kde.taskmanager` (`AbstractTasksModel` role enum,
  `ScreencastingRequest`) and `org.kde.pipewire` (`PipeWireSourceItem`) are
  C++ mocks registered in `qmltestmocks.cpp`. Type-less `qmldir` files under
  `mocks/` shadow the installed plugins.
- Preview-popup tests verify that the process-local CPU-only capture mode
  disables DMA-BUF at item creation and that Auto's one-shot no-first-frame
  retry is bounded. The mock has no PipeWire frames, so these tests do not
  validate GPU import or visible thumbnail pixels; use
  [`../../docs/architecture/window-previews.md`](../../docs/architecture/window-previews.md)
  for real Wayland/GPU diagnostics.
- `i18n()` comes from the real `KLocalization::setupLocalizedContext`, as in
  `DockView`.

`TestCase` is an invisible item. Each file therefore has a visible root `Item`
with a `stage` child that fixtures are parented to. Without it, effective
visibility, Row/Flow layout, and pointer delivery would not work.

Internal items have no `objectName`, so `TestUtils.js` finds them by the
properties they expose (for example, the indicator `Flow` or the badge's
`Text.Fit` label).

## Conventions

- Assertions use `tryCompare`/`tryVerify`, not fixed sleeps. Timers under test
  (hover delay, launch safety net, attention duration) are shortened through
  settings where the QML allows it.
- A test only runs QML from `src/qml` plus the mocks. Do not copy application
  QML into this directory.
- Add a new suite by creating `tst_<name>.qml` and listing it in
  `KDOCKW_QML_TEST_FILES` in `CMakeLists.txt`.

## Not covered here

- Real rendering: icons (the `image://icon` provider is absent),
  shaders/`MultiEffect` (software backend), and PipeWire frames. Tier 2
  (`tests/appium`, a real KWin session) covers these.
- `SettingsDialog.qml` and `settings/*.qml`: the integration test
  `tests/integration/test_settings_lifecycle.cpp` loads every page in a KWin
  session, and Tier 2 drives them.
- The external file drop in `main.qml` (`DropArea` with URLs). Qt Quick Test
  has no API to synthesize a drag carrying MIME data.
