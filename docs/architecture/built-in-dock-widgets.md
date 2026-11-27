# Built-in Dock Widget Model

## Scope

The widget model is an internal part of the dock, not a public plugin API.
Application Launcher styles, Media Player Controls, and future Folder Stack
extensions can share the persisted item and presentation path.

## Model boundaries

- `DockEntriesModel` owns the persisted sequence of pinned tasks, Folder Stacks,
  and built-in widget descriptors. TaskManager remains authoritative for live
  applications and windows.
- `DockEntriesCodec` reads v1/v2 task and Folder Stack formats and v3 widget
  descriptors, and writes v5. Widget descriptors store stable ID, kind,
  start/center/end slot, visibility, and supported size. Configuration cannot
  load an executable or QML component.
- `DockPresentationModel` merges TaskManager rows with saved descriptors. A
  widget row has no task index. Start/center/end slot rank is stable, and the
  relative order within each slot follows the saved model order.
- `DockItem` renders separators and spacers inside the existing dock surface.
  A separator is a visible theme-derived line perpendicular to the dock's
  primary axis; its line length follows the saved slot extent with clear
  insets. A fixed spacer remains empty. Both use logical pixels on the primary
  axis for all four edges and HiDPI scale factors.
- A QML manager operates directly on `DockEntriesModel`: add/remove, reorder,
  resize, change slot, and toggle visibility. Its persistent entry point is a
  dock-level right-click menu and does not depend on a built-in widget being
  present. The manager is an adaptive, scrollable card list with a
  screen-clamped preferred width and no horizontal scrolling; left-clicking
  empty dock space has no manager side effect. Model changes use the existing
  `entriesChanged` persistence path.
- `DockView` and Layer Shell continue to own output selection, surface
  geometry, exclusive zones, and input regions. Widgets create no surfaces.

## Persistence and lifecycle

The persisted entry ID is the identity of a built-in item. Adding, removing, or
editing an entry emits the existing save signal. TaskManager launcher
synchronization replaces only Task records and retains widgets and Folder
Stacks. Hidden widgets stay in the saved model and manager but are omitted from
live presentation rows. Presentation rows have no window geometry publication
or TaskManager launcher identity. The Application Launcher currently supports
one newly added row because style and Start pins are global settings; loading
does not remove or rewrite pre-existing duplicate rows.

The Media Player Controls widget follows the same saved-entry lifecycle but its
presentation row is runtime-gated by the shared `MediaPlayerController`. One
entry is seeded at the end of the dock once when a configuration first opens;
the one-time marker prevents restoring it after the user removes it. The widget
is the only row for all discovered MPRIS sessions; selecting a player does not
create or persist another dock entry. Its three display modes change the row's
primary extent while retaining the same stable entry ID and saved order.

The v3 separator migrates to visible with automatic size (`size=0`). Version 4
stores explicit size and visibility. Version 5 stores whether an Application
Launcher icon is a user override. Earlier launcher entries infer an override
from their saved icon name; new entries use a style-specific theme icon until
the user chooses an icon. The override is retained across style changes and
configuration reloads. Fixed spacers accept 4–512 logical
pixels; separators can use automatic size or an explicit 4–512 logical-pixel
primary slot extent while keeping the same orientation-aware mark.

Slot placement is independent of screen orientation: `start` and `end` refer
to the dock's primary axis. Built-in widgets can be long-pressed and dragged
among pinned dock entries. A move adopts the target widget's slot (or center
when dropped on a pinned app or Folder Stack), then persists both slot and
order through `DockEntriesModel`; dynamic TaskManager rows remain outside this
reorder path. Application and Folder Stack drag behavior is otherwise
unchanged. Spring zoom receives a per-row primary extent. The Application
Launcher icon can magnify; separators and spacers retain configured extents.
Real extents feed neighboring icon centres, offsets, and background growth.

The current content-wrapping `Flow` has no free-space allocator. A stretching
spacer is therefore not enabled: allocating remaining screen space would
change dock width/height and exclusive-zone geometry. Add it only with a
separately tested layout allocation contract.

## Trash widget

- One Trash widget per dock (`widgetKind` `trash`, ID prefix `widget:trash:`).
  It stores no icon and no size; it is icon-sized and magnifies like an
  application icon.
- `TrashState` (owned by `DockModel`, exposed as `DockModel.trashState`)
  follows KIO's `trashrc` `[Status] Empty` key with `KDirWatch`, so the icon
  switches between `user-trash` and `user-trash-full` without listing
  `trash:/`. See [docs/kde/trash.md](../kde/trash.md).
- Left-click and Enter open `trash:/` in the file manager. Right-click shows
  its own native menu (Open, Empty Trash, then the KDockW submenu); Empty Trash
  is disabled while the trash is empty and uses KDE's standard confirmation.
- It is the only built-in widget that is a file-drop target. Files, folders,
  and `.desktop` files dropped on it move to the trash through
  `KIO::DeleteOrTrashJob`, which records the move for Undo; they are never
  pinned as launchers or Folder Stacks. Plasma task drags carry no files and
  are rejected.

## Application Launcher backend contract

The Application Launcher reuses the widget descriptor and presentation path.
It does not copy the system menu into a persistent database or introduce an
extension/plugin API.

- Build the hierarchy from `KServiceGroup::root()` and recursively consume
  `entries(false, true, true)` in XDG Menu order. Groups become categories or
  folders; application rows keep their `KService::Ptr` identity. Initial root
  traversal is scheduled in short event-loop batches so popup creation does
  not synchronously walk the full service tree.
- Use KDE service catalog APIs and `KService` metadata for
  localized name, generic name, keywords, categories, icon, menu ID, and storage
  ID. Cache service objects in memory; persist stable service references and
  user-owned pins/folder choices only.
- Filter `NoDisplay`, `Hidden`, `OnlyShowIn`/`NotShowIn`, and unavailable
  `TryExec` entries. Desktop entry identity de-duplicates alternate paths.
- Keep the current `KService` objects and catalog records in memory only.
  Search filters those existing localized metadata records; KSycoca database
  changes coalesce into a catalog refresh. This avoids reparsing desktop
  metadata on every debounced keystroke.
- `ApplicationCatalog` is owned by the dock model and replaces its in-memory
  application and menu records on refresh. Launcher QML views are owned by the
  popup `Loader`; switching styles or closing the popup releases the loaded
  view. Integration tests tear down the test application's QObject owners
  before destroying `QApplication`.
- Launch applications and desktop actions through
  `KIO::ApplicationLauncherJob`; `Exec` is never parsed or passed to a shell.
- `ApplicationLauncherState` persists the selected style, ordered Start pins,
  user-created Launchpad folder records and the Launchpad root item order.
  Folder IDs are stable UUIDs; each record stores its name and ordered
  application service IDs. Membership is unique across folders and a foldered
  application is not also emitted as a root tile. Removing a member or deleting
  its folder returns that application to the root order. These records live in
  KDockW settings and do not change XDG entries or Plasma favorites. Start pins
  remain stable service IDs and survive temporary removal from the current
  catalog. On the first Start view, an optional Plasma Kicker favorites model is
  read once; favorites map to current catalog IDs, invalid or repeated items
  are skipped, and existing Start pins are never overwritten. The attempted/
  status marker is persisted, so removing pins later does not import them again.
  The Kicker QML module is private and optional. The read-only
  `Kicker.RootModel` is explicitly refreshed on source initialization, and
  import waits for its `refreshed` readiness signal; an unavailable model
  leaves Start usable and reports that favorites could not be imported. KDockW
  does not write to Plasma favorites. The installed Plasma/Kicker private API
  and real-user favorite mapping still require manual runtime verification.
- A single native popup loads one of three distinct QML layouts. macOS Launchpad
  shows every application in an adaptive icon grid paginated by available full
  rows. Only the active page is bound to the GridView. Dots, wheel and keyboard
  navigation share the same bounded page-change path. Search covers the full
  catalog and resets pagination. User folders are separate from KService groups
  and expose create, move, add/remove, rename and delete actions through app and
  folder context menus. Windows Start uses a pinned-app grid on its home page and a
  separate all-applications page with locale-sorted letter sections. Activating
  a section heading opens an alphabet grid; choosing a letter returns to the
  full list scrolled to that section, without filtering away other apps. KDE
  Hierarchical presents the original XDG menu order as a grid of category
  folders with previews made from up to four real child application icons, and
  prepends a virtual Favorites folder backed by the same persisted favorites as
  Windows Start;
  nested groups and app tiles remain navigable with breadcrumbs. Its search
  continues to cover the entire catalog. All views use the same catalog and
  KIO launch path. Application and category icons use the existing
  `image://icon/` provider, which resolves the active KDE icon theme/file icons
  and falls back to an application icon. Tile and popup colors derive from the
  resolved KDockW dock surface and contrast-aware foreground, while controls
  use the same attached Kirigami palette for light and dark themes.
- The popup uses a fully opaque surface independent of dock background
  opacity. Its preferred viewport is 900x600 for Launchpad, 680x600 for Start,
  and 800x600 for KDE Hierarchical, clamped to the selected output. Its content
  Loader is activated before opening the native Popup.Window so the first
  configure uses the populated page size.
- The popup chooses style-specific preferred dimensions and clamps them to the
  available screen space along either axis for all four dock edges. Grid columns
  adapt to the resulting viewport; page changes within a style keep the popup
  dimensions stable. Its content root has explicit implicit dimensions matching
  the requested viewport, and each fill-height catalog view has a useful
  minimum size before the first native Wayland surface commit. It closes on
  outside click, Escape, dock hide, output change, and after a successful
  launch, and reloads its view when the style changes. Actual Wayland popup
  placement, fractional-scaling rendering, live theme changes, and owner
  confirmation of favorites mapping remain visual review items.

### Fourth Launcher refinement

Launchpad paging reuses its existing page model. During a page change, only the
current and target page models are bound to two clipped GridViews; both translate
horizontally for 380 ms with an ease-in/ease-out cubic curve. The active page indicator tracks
the target. A new input while transitioning first completes the current target,
then starts the next bounded transition. Search changes, layout changes, and
popup close cancel an in-flight transition and reset its offset. The duration
uses Kirigami's configured long-duration setting, so zero-duration system motion
settings produce an immediate page change. No timer, shader, or always-loaded
page set is used.

Folder menu actions are derived from the current entry and folder context:
root applications can create a folder or move to one; applications inside a
folder can be extracted or moved to another folder; user folders can be opened,
renamed, or deleted. Create/rename share a themed dialog with trimmed-name,
empty-name, and case-insensitive duplicate validation. Folder deletion confirms
that applications return to the root without deleting their desktop entries.
Membership remains unique through `ApplicationLauncherState` persistence.

All three context menus map the source-tile point into the Qt Quick Controls
overlay and use the same resolved KDockW/Kirigami surface and foreground colors.
Qt's `Menu.popup(parent, point)` positioner handles available screen space and
submenu side selection; tests cover the menu action policy and theme colors,
while real edge placement and contrast still require Plasma/Wayland review.
Launchpad's QML contains no attached horizontal ScrollBar/ScrollIndicator; its
GridView is now non-interactive, vertical-only, and uses floored cell widths
within a clipped page region. The source does not prove the origin of the stripe
seen in the owner's screenshot; the visual artifact remains to be rechecked.

The Windows Start home already conditionally displays its “All applications”
button. Fourth-cycle regressions now verify its visibility, non-zero geometry,
screen-bound placement, and transition to the complete list for the loaded page.
The reported screenshot did not identify its exact candidate build, so a
source-level regression was not established.

## Verification status

The live TaskManager icon-role preflight is diagnostic-only: `DockPresentationModel`
forwards a DecorationRole-only notification with that same narrow role list. Its
diagnostic trace gate must include DecorationRole independently of the broader
presentation-change predicate, because that predicate also adds DisplayRole.
Qt's empty `dataChanged` role list means all roles may have changed and must be
interpreted accordingly by the preflight assessor. This observability correction
does not change task presentation or icon invalidation behavior.

Automated model, catalog-filtering, metadata, persistence, three-style QML,
settings, icon-provider, magnification, and four-edge popup-bound checks pass
in the current v0.6.0-dev builds. The measurable catalog test observed 112
applications on this host, a 0 ms first-load request, 52 ms until the initial
catalog was ready, 0 ms for 40 warm `ensureLoaded()` calls, and 28 ms for 80
in-memory searches. This does not measure interactive frame pacing or CPU/GPU
load during real popup rendering.

Full Production Release CTest passed **214/214** and full Diagnostic Release
CTest passed **221/221** during the fourth refinement. The first Production
run had one stale assertion expecting a synchronous page change; the focused
rerun passed after waiting for the 380 ms transition. The subsequent full
Production and Diagnostic runs both passed. The real Kicker source probe loaded
successfully but returned zero favorites, so it could not validate mapping of
real Plasma favorite IDs. Owner feature acceptance is 19/29; the widget/model/
launcher cards remain `review`. No new Plasma/Wayland visual acceptance was
performed; menu placement, the screenshot stripe, animation feel, real favorite
mapping, and DPI/light-dark rendering remain owner checks.

### Fifth Launcher acceptance corrections

The Launchpad move-to-folder `Menu` remains in the native popup tree while the
folder model changes. Its enabled state and child actions track folder
availability; its `visible` property is not bound to the mutating model. Folder
creation/rename close the context menu before opening a dialog, and deletion
closes it before showing confirmation. This avoids re-entering
`QQuickMenu::setVisible()` from the synchronous `launchpadFoldersChanged`
notification that accompanies `ApplicationLauncherState::createLaunchpadFolder()`.
The regression test runs folder creation, membership changes, extraction,
rename, delete, save, and reload through the production QML page and C++ state.

The outgoing Launchpad GridView must not have an anchor that overrides its
animated `x`. It stays on the current page model while the incoming view binds
to the target model; both translate with the same `slideOffset` and
`transitionDirection`. The incoming view is emptied when `pageTransitioning`
becomes false, keeping only the current page's delegates after the 380 ms
transition. Tests cover synchronized geometry, forward/back movement, page
indicators, wheel input, rapid selection, search and popup close.

The folder-name TextField supplies an explicit Kirigami-resolved background,
foreground, placeholder, focus, and selection palette. The real-popup visual
stand uses `ApplicationLauncherPopup.qml`, production `ApplicationCatalog`,
and `ApplicationLauncherState`; it opens the Start home/full-list paths, a
Hierarchical Favorites/category path, and the Launchpad create-folder flow. A
private test Sycoca cache and read-only system icon-theme provider produce
reviewable screenshots without changing the user's configuration. The test
runner retains mock providers for other QML tests.

## Plasma Favorites source

The standalone dock cannot construct Kicker's private `RootModel` with its
Plasma applet interface, so that model may report an empty favorites list even
when Kickoff has saved favorites. `PlasmaFavoritesReader` instead reads the
configured Kickoff applet IDs from `plasma-org.kde.plasma.desktop-appletsrc`,
asks ActivityManager for the current activity, and reads the matching and
global Kickoff `ordering` entries from `kactivitymanagerd-statsrc`. It performs
no writes to either Plasma file. The current activity entries are returned
before global entries, with duplicates removed.

Windows Start waits for the snapshot and catalog, preserves the current
KDockW pin order, then appends matching Plasma favorites once. A legacy
`existingPinsPreserved` marker permits a single migration retry because an
older importer skipped all Plasma favorites when any KDockW pin existed. The
reader's real-session snapshot was available and contained eight raw favorite
references in the tested session; the diagnostic popup could not be opened
without a real input event in that earlier session. The owner later accepted
the favorite behavior in the final real Plasma/Wayland functional review.

The fifth owner review reported 10/25 criteria. The old report's expected
`visual-review-diagnostic` path differed from the standard v0.6.0 launcher
path, but the precise executable used by that owner observation was not
captured, so stale QML is not established as the cause of the missing buttons.
Current offscreen popup screenshots show Start navigation and Hierarchical
Back in their loaded views. This stand does not replace real Plasma/Wayland
acceptance; the owner subsequently accepted the feature in the final review.

## Task-zone separator invalidation

The boundary between pinned and running tasks is derived by calling the
`DockPresentationModel::isPinnedDockIndex()` invokable. QML does not track that
invokable's reads as binding dependencies, so `taskZoneBoundary` explicitly
reads `dockRepeater.layoutRevision`. `DockRepeater` increments this revision
when presentation rows move, layout changes, or the model resets. That causes
the separator boundary to be recomputed after same-count cross-zone reorders,
when the row count alone would not invalidate the binding. The QML regression
repartitions rows after reordering and verifies the separator returns.
