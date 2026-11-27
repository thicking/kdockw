# Trash (KIO)

Verified against the KF6 headers in `/usr/include/KF6/` (KIO 6.x) and used by
the built-in Trash widget (`src/models/trashstate.{h,cpp}`).

## Full or empty state

KIO's trash worker keeps the state in `trashrc`, a `KConfig::SimpleConfig`
file in `QStandardPaths::GenericConfigLocation`:

```ini
[Status]
Empty=true
```

The worker rewrites this file whenever the trash changes between empty and
non-empty. Dolphin reads the same key. The file does not exist until the first
item is trashed; a missing file means empty.

`KDirWatch::addFile()` on the path reports `created`, `dirty`, and `deleted`,
so the widget re-reads the key on each signal instead of listing `trash:/`.

## Moving files to the trash

```cpp
#include <KIO/DeleteOrTrashJob> // KIOWidgets
auto *job = new KIO::DeleteOrTrashJob(urls, KIO::AskUserActionInterface::Trash,
                                      KIO::AskUserActionInterface::DefaultConfirmation, parent);
job->start();
```

- `DeleteOrTrashJob` (since KF 5.100) asks for confirmation through
  `KIO::WidgetAskUserActionHandler` unless the job's UI delegate implements
  `AskUserActionInterface`. The dock is a `QApplication`, so the widget dialog
  is available.
- `DefaultConfirmation` skips the dialog when the user ticked "Do not ask
  again"; KDE's default for trashing is not to ask.
- For `Trash` the job records the move with `KIO::FileUndoManager`, so Undo
  in Dolphin restores the items.
- `trash:/` URLs cannot be trashed again; the widget filters them out.

## Emptying the trash

```cpp
auto *job = new KIO::DeleteOrTrashJob({}, KIO::AskUserActionInterface::EmptyTrash,
                                      KIO::AskUserActionInterface::DefaultConfirmation, parent);
job->start();
```

The URL list is ignored for `EmptyTrash`. On success the widget sends
Plasma's standard `Trash: emptied` event (`plasma_workspace.notifyrc`) with
`KNotification::DefaultEvent`, as Dolphin does, which plays the system sound.

## Opening the trash

`KIO::OpenUrlJob(QUrl("trash:/"))` with
`KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr)`
opens the trash in the default file manager and reports errors itself.

## Icons

`user-trash` and `user-trash-full` are freedesktop icon names provided by
Breeze and other KDE themes.
