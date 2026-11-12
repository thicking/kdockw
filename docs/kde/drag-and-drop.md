# Drag & Drop (TasksModel DnD)

> Source: `/usr/include/taskmanager/` headers

## KDockW mixed pinned entries (v0.5.0)

The dock is a `DockPresentationModel` projection of the typed
`DockEntriesModel` and TaskManager rows. With pinned/running separation on,
launcher tasks and Folder Stacks use their saved mixed order followed by
unpinned tasks. With separation off, task rows follow TaskManager's live order
and Folder Stacks remain anchored to their neighboring saved launchers. Each
launcher task and Folder Stack has a stable entry ID;
the QML delegate carries that ID through drag initiation and resolves the
drop target against the current model. Do not persist a delegate index or
reorder TaskManager rows to move a Folder Stack.

Reordering a pinned task or Folder Stack updates the typed entry sequence.
TaskManager launcher order is synchronized only for launcher entries, while
unpinned running windows retain their TaskManager order. This preserves folder
slots and avoids shifting a running task when a mixed dock order changes.
Folder drops add local directories as stacks; file drops on a launcher send
supported URLs to that application's open-URL action. Unsupported MIME data
and canceled drags leave the saved order unchanged.

Regression coverage exercises repeated mixed task/folder moves, insertion at
both ends, cancellation, v1-to-v2 persistence migration, stable IDs, and
unpinned task insert/remove while pinned entries remain present. The owner
confirmed the Folder Stack, DnD, and TaskManager acceptance on Plasma 6.6.6 /
Wayland in three consecutive 24/24 cycles. Automated and model-level tests do
not replace that live-session observation for future changes.

## Overview

TasksModel supports drag-and-drop for reordering tasks and launchers. DnD data is provided via roles (`MimeType`, `MimeData`) and reordering is done via `move()` + `syncLaunchers()`.

---

## Roles for DnD

| Role | Type | Description |
|------|------|-------------|
| `MimeType` | QString | MIME type string for the task |
| `MimeData` | QByteArray | Serialized data for the MIME type |

Common MIME types:
- `text/uri-list` — URL-based launcher tasks
- `application/x-kde-launcher-desktop` — .desktop file launchers
- `text/x-orgkdeplasmataskmanager_taskurl` — plain launcher URL supplied by Plasma task-manager drags
- `application/x-orgkdeplasmataskmanager_taskbuttonitem` — Plasma task payload; it is not itself a launcher URL

The Plasma task-manager drag source adds its launcher URL as a separate
`text/x-orgkdeplasmataskmanager_taskurl` format alongside the task payload.
The dock uses Qt Quick `DragEvent.formats` and `getDataAsString()` to read that
URL; it does not decode the opaque task-button payload. `.desktop` files and
application-menu entries continue to use `text/uri-list` where the source
provides it.

---

## Reordering

### move()

```cpp
// Move task at row to newPos within parent
bool TasksModel::move(int row, int newPos, const QModelIndex &parent = QModelIndex());
```

- Works in `SortManual` mode
- `row`: Current position in the model
- `newPos`: Target position
- `parent`: For grouped tasks, the group parent index (default = top level)
- Returns `true` if move succeeded

### syncLaunchers()

```cpp
// Persist current launcher order to config
void TasksModel::syncLaunchers();
```

- Must be called after `move()` to save the new order
- Updates the internal launcher list to match current visual order
- Without this call, launcher order reverts on next load

### Typical DnD Reorder Flow

```
1. User starts drag on task item
2. Track source index (row)
3. On drop, calculate target position
4. Call move(sourceRow, targetRow)
5. Call syncLaunchers() to persist
```

---

## Launcher Management

### Adding Launchers

```cpp
bool requestAddLauncher(const QUrl &url);
bool requestAddLauncherToActivity(const QUrl &url, const QString &activity);
```

- `url`: Can be `file:///path/to.desktop`, `applications:org.kde.dolphin.desktop`, or `preferred://browser`
- Returns `true` if launcher was added (not already present)

### Removing Launchers

```cpp
bool requestRemoveLauncher(const QUrl &url);
bool requestRemoveLauncherFromActivity(const QUrl &url, const QString &activity);
```

### Querying

```cpp
int launcherPosition(const QUrl &url) const;     // Position in model (-1 if not found)
QStringList launcherActivities(const QUrl &url);  // Activities for this launcher
```

### Launcher List

```cpp
QStringList launcherList() const;                 // All launcher URLs as strings
void setLauncherList(const QStringList &launchers); // Replace entire list
```

---

## URL Comparison

TaskManager uses `launcherUrlsMatch()` for comparing launcher URLs:

```cpp
enum UrlComparisonMode {
    Strict = 0,          // Exact match
    IgnoreQueryItems,    // Ignore query string (metadata)
};

bool launcherUrlsMatch(const QUrl &a, const QUrl &b, UrlComparisonMode mode = Strict);
```

Important: Query items often contain metadata (icon overrides, etc.) — use `IgnoreQueryItems` when comparing user-initiated URLs.

### URL Formats

| Format | Example | Description |
|--------|---------|-------------|
| File path | `file:///usr/share/applications/org.kde.dolphin.desktop` | Absolute .desktop file |
| Applications | `applications:org.kde.dolphin.desktop` | KService storage ID |
| Preferred | `preferred://browser` | Default app for category |

Supported preferred categories: `browser`, `mailer`, `terminal`, `filemanager`

Resolving preferred URLs: `TaskManager::defaultApplication(url)` returns the actual app ID.

---

## Activity-Scoped Launchers

Launchers can be scoped to specific activities:

- **All activities**: launcher activity list contains a null UUID (`{00000000-0000-0000-0000-000000000000}`)
- **Specific activities**: launcher activity list contains specific activity UUIDs
- **No activity**: launcher is visible nowhere (effectively hidden)

```cpp
// Add launcher for current activity only
model->requestAddLauncherToActivity(url, activityId);

// Add launcher for all activities
model->requestAddLauncher(url);  // defaults to all

// Check which activities
QStringList activities = model->launcherActivities(url);
```

---

## Detecting Task Type for DnD

```cpp
QModelIndex index = model->index(row, 0);

bool isLauncher = index.data(TaskManager::AbstractTasksModel::IsLauncher).toBool();
bool isWindow = index.data(TaskManager::AbstractTasksModel::IsWindow).toBool();
bool isStartup = index.data(TaskManager::AbstractTasksModel::IsStartup).toBool();
bool hasLauncher = index.data(TaskManager::AbstractTasksModel::HasLauncher).toBool();
```

### DnD Behavior by Task Type

| Source | Drop Target | Action |
|--------|-------------|--------|
| Launcher | Launcher area | Reorder (`move` + `syncLaunchers`) |
| Window | Launcher area | Pin to dock (`requestAddLauncher`) |
| External URL | Dock | Add launcher (`requestAddLauncher`) |
| Launcher | Outside dock | Remove launcher (`requestRemoveLauncher`) |

---

## AppData for External Drops

When receiving external URL drops:

```cpp
#include <taskmanager/tasktools.h>

TaskManager::AppData appData = TaskManager::appDataFromUrl(droppedUrl);

if (!appData.id.isEmpty()) {
    // Valid app found — use appData.url for requestAddLauncher
    model->requestAddLauncher(appData.url);
}
```

## Activating a task during an external file drag

KDockW's dock-wide `DropArea` already accepts URL drags so existing drops onto
an app can be delivered. The optional hover-activation path uses only
`DragEvent.hasUrls` and the pointer position; it does not read `urls`, MIME
payloads, or call `requestOpenUrls()`. A single-shot UI timer is restarted when
the pointer enters a different icon, canceled when it leaves the dock or the
drop/cancel event ends the drag, and requests `TasksModel::requestActivate()`
only for an existing window task. Dropping files on the dock still follows the
existing drop handler. While the file drag remains over KDockW, its hover
tooltip and window preview are suppressed so another popup cannot cover the
drag target; normal hover feedback resumes if the drag ends over the dock.

The setting defaults to enabled, with a 700 ms delay configurable from 300 to
1500 ms. A pinned launcher without a window is ignored. For grouped windows,
KDockW activates the already active child when present or the child with the
most recent `LastActivated` timestamp, matching the existing TaskManager
entry-window selection. The hover handler does not choose an alternate file
drop action or change the DnD source's payload.

On Wayland, Plasma 6.6's `WaylandTasksModel::requestActivate()` uses the
`org_kde_plasma_window` protocol to request the active state of the selected
window. This is the same TaskManager API used by KDockW's existing click and
keyboard activation paths; KWin remains responsible for applying its
activation policy. A QML timer test or a model-level activation test cannot
prove that a file drag from Dolphin remains continuous through activation in a
particular live KWin session, so that path still requires Wayland-session QA.
The owner confirmed the multi-file Dolphin flow on Plasma 6.6.6 / Wayland as
part of the latest three consecutive 24/24 acceptance cycles.

---

## Model Index Helpers

```cpp
// Create model index for row (needed for request* methods)
QModelIndex idx = model->makeModelIndex(row);

// For grouped tasks: child within group
QModelIndex childIdx = model->makeModelIndex(groupRow, childRow);

// Persistent index (survives model changes)
QPersistentModelIndex persistent = model->makePersistentModelIndex(row);
```
