# Folder Stack File Model (KF6 KIO)

Verified against the installed KF6 headers in `/usr/include/KF6/`.

## Asynchronous directory model

`KDirModel` (`KIOWidgets/kdirmodel.h`) is a `QAbstractItemModel` backed by
KIO directory listing. `openUrl(url, flags)` starts an asynchronous listing;
`Reload` bypasses the cache for a directory that has not yet been listed.
`itemForIndex()` returns a `KFileItem`, which supplies the URL, display name,
directory/symlink flags, and theme icon name. The internal `KDirLister` is
available from `dirLister()` and handles updates to the current local folder.

Use one lazily active model for the visible Folder Stack popup. Keep auto error
dialogs disabled and present a translated popup state on `jobError`; stop
listing when the popup closes. Do not scan a directory synchronously on the
GUI thread.

## Opening files and folders

`KIO::OpenUrlJob` (`KIOGui/kio/openurljob.h`) resolves a URL's MIME type and
default application. Construct it with the URL, configure a UI delegate only
when needed, and call `start()`; never call `exec()` in the UI path. Folder
navigation uses the directory model and does not change the pinned root URL.

The Folder Stacks MVP accepts only absolute local `file://` URLs. The pinned
entry model validates this scheme and the directory model lists asynchronously.
`OpenUrlJob` remains responsible for opening files with the desktop's default
application.

## Build integration

The model APIs are supplied by the existing KF6 KIO development dependency:
Debian packaging already requires `libkf6kio-dev`, and OBS metadata already
requires `cmake(KF6KIO)`. The source links the specific imported targets it
uses (`KF6::KIOWidgets` and the existing `KF6::KIOGui`).
