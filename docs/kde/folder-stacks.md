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

## Dock icon and popup

The dock icon uses the existing `image://icon/` provider with the theme name
`folder`, just like application icons. Its source size is the logical icon size
multiplied by the current maximum zoom factor, while its rendered bounds remain
the unzoomed dock-icon size. This avoids enlarging a rest-size texture during
Spring Magnification and preserves the icon provider's QIcon/DPR handling.

The popup content item is an explicit `Item` sized by Controls, with an
anchored `ColumnLayout` inside it. The fill-height `GridView` has a useful
minimum and preferred height, so a layout pass cannot collapse it to a
one-pixel minimum while the native window is being sized. The popup is a
`Popup.Window` (`Qt::Popup`) parented to the
dock scene. That creates a separate native Wayland popup surface: the dock's
explicit input region can remain limited to the panel, and the compositor
routes popup input to the popup surface. An in-scene `Popup.Item` is incorrect
here because the dock layer-shell input mask excludes the popup area, sending
those clicks through to the window below. A native popup also uses the Qt/KWin
outside-dismissal path rather than relying on an input region that spans other
applications.

Popup bounds are calculated in logical coordinates from the dock's assigned
`QScreen::geometry()` and the layer-shell surface origin derived from its edge
and size. The popup opens beside the icon, chooses the side with available
space, and clamps to that output (including non-zero multi-monitor origins).
Grid cells adapt to the popup width, filenames stay on one elided line, and the
Grid scrolls vertically. Folder navigation keeps the popup open; selecting a
file or opening the current directory in Dolphin closes it. Escape, native
outside dismissal, and deactivation of the popup's own window close it. No
global pointer hook is used.

Before the first `Popup.Window` is created, `FolderStackItem` starts the KIO
listing and waits for `FolderStackModel.loading` to become false. It then
calculates the final requested geometry and creates the native popup with the
content item's implicit size pinned to that same requested rectangle. This is
needed because the initial `Popup.Window` surface could otherwise commit at
the content's small implicit width before the first GridView layout, while its
position had already been calculated for the larger requested width. Wayland
popup position is established with that initial surface commit; changing the
QML x/y afterward does not reliably reposition the existing xdg_popup.

Popup diagnostics distinguish `before-open`, `content-ready`, `opened`,
`geometry-changed`, and `window-position-updated`. They include requested
parent-local and screen coordinates, parent window geometry, the inferred
parent origin, and actual popup window geometry. Spring's transformed icon
bounds are logged separately from the stable rest-slot anchor used for the
initial native placement. After dismissal, hover is recalculated only if the
Wayland pointer-focus tracker reports that the pointer is back on the dock.

`FolderStackItem` does not install a competing pointer `MouseArea`. Click and
press-hold drag gestures use `main.qml`'s dock-wide hit test, which resolves
both ends of a pinned reorder through stable presentation-model entry IDs.

The Folder Stack card reuses the Window Preview presentation tokens: the
resolved dock surface color, contrast-selected foreground, 27% foreground
outline, configured `PreviewCardPadding`, dock corner radius, and the same
light-derived shadow. Its native window reserves the same `2 * smallSpacing`
shadow margin as the preview surface; the visible card is inset within that
margin. The path heading uses the preview's demi-bold text treatment, and the
vertical scrollbar uses a slim rounded track and a theme-contrast thumb.

Popup placement follows the Window Preview's resting icon edge. The card edge
is separated from the icon by `PreviewDockGap + iconSize * (maxZoomFactor - 1)`
logical pixels, matching the preview's configured dock gap and maximum Spring
overflow. The popup's outer window includes its shadow margin when calculating
available space and clamping to the selected screen. Horizontal placement
continues to center on the stable Folder Stack slot; vertical placement stays
centered along the icon. This applies symmetrically to top, bottom, left, and
right docks and retains the existing first-commit sizing for `Popup.Window`.

The existing `QMenu::popup()` context menu is the repository's Wayland
precedent for a native popup parented to the layer-shell dock. Keep the Folder
Stack popup as a native Qt popup rather than creating a second permanent
layer-shell surface; the latter would need its own focus restoration and could
not observe outside clicks without claiming input over other applications.

The Folder Stack's QML context `Menu` is also a `Popup.Window`, with Escape and
press-outside close policies. Its own native window observes deactivation to
dismiss when the user switches applications. The theme icon action closes the
menu first and queues `KIconDialog` for the next event-loop turn, releasing the
Wayland popup grab before the dialog opens. Since the dock surface is a
`QQuickWindow` and `KIconDialog` accepts only a `QWidget` parent, the chooser
uses the dock's native window as its transient parent; the selected KDE theme
name is then saved to the stack's typed entry record by stable ID.

The card composites the configured translucent dock color over the current
theme background and makes the popup surface opaque, so its 4.5:1 text contrast
does not depend on the application behind it. Selected and hovered cells
choose a foreground against their composited highlight color.

Grid hover uses `MouseArea.hoverEnabled` and updates the active index without
changing focus. Keyboard navigation keeps a separate visual mode: arrow keys
show an inset theme-highlight fill and thin border, while hover uses a weaker
fill. Moving the pointer away removes only the hover state; GridView focus and
its active index remain available for subsequent keyboard navigation. Text
colors are chosen against each composited cell fill to keep at least 4.5:1
contrast. Cell and icon geometry is unchanged.

Folder icon choices live in the version-2 typed entry record, keyed by the
Folder Stack UUID. The KDE `KIconDialog` stores theme icon names; Qt's platform
file chooser stores validated local image URLs. The existing shared dock
tooltip uses the displayed directory name and is suppressed while the native
folder popup is open.

For manual Plasma/Wayland acceptance, build the diagnostic configuration and
run `tools/kdockw-v050-dev-start` from the project root. The launcher refuses
to start while another KDockW process is running, uses isolated diagnostic
settings, and temporarily registers `com.thicking.kdockw` for KWin Wayland
permissions. After testing, run `tools/kdockw-v050-dev-stop-and-restore` to
stop the diagnostic service and restore the prior desktop entry. Do not invoke
the stable launcher while the diagnostic service is active.

## Build integration

The model APIs are supplied by the existing KF6 KIO development dependency:
Debian packaging already requires `libkf6kio-dev`, and OBS metadata already
requires `cmake(KF6KIO)`. The source links the specific imported targets it
uses (`KF6::KIOWidgets` and the existing `KF6::KIOGui`).
