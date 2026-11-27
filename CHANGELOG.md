# KDockW changelog

This file records KDockW's independent project history. The original Krema
releases and their notes are preserved in the
[archived Krema changelog](docs/history/krema-changelog.md). See
[FORK_CHANGES.md](FORK_CHANGES.md) for a behavior-focused summary of changes
carried forward from the Krema-based development period.

## [Unreleased]

### Added

- Added a Trash widget. It shows a full or empty trash can, moves files dropped on it to the trash, opens the trash on click, and offers Empty Trash with confirmation in its right-click menu.

## [0.7.2] - 2026-11-25

KDockW 0.7.2 improves file drops on auto-hidden docks and notification badge updates.

### Fixed

- Kept an auto-hidden dock visible under the pointer after a file is dropped.
- Opening one window no longer clears the badge for every other notification from the same app.
- Thanks to @svan71 for the first external contribution to KDockW and the auto-hide file drop fix.

### Known Issues

- A notification badge may occasionally remain after a notification is read or removed. It may clear later; the cause is not yet known.

## [0.7.1] - 2026-11-21

KDockW 0.7.1 makes shadow settings easier to adjust, adds flexible media volume control, and improves window selection from previews.

### Added

- Added Automatic, Player Volume Only, and Computer Volume modes to the media widget.
- Automatic uses player volume when supported and switches to the computer's default sound output if the player cannot change its own volume.
- Kept existing v0.7.0 settings in Player Volume Only mode; new configurations use Automatic.

### Improved

- Made shadow direction easier to set with a live preview, a 0–359° slider, precise numeric entry, and a section for advanced options.

### Fixed

- Fixed selecting the exact window shown in a Window Preview, including a specific window in a group.
- Kept shadow previews responsive while changing and saving settings.

## [0.7.0] - 2026-11-20

KDockW 0.7.0 adds a built-in media player and improves how its controls, popups, and dock icons respond to the cursor.

### Added

- Added Compact, Controls, and Expanded media player layouts, with track details, artwork, and playback progress.
- Added an interactive popup for playback controls, seeking, and player volume when supported.
- Added automatic display of the active player, with manual selection when several players are available.
- Added controls for when the widget appears, whether it shows artwork and paused players, how long stopped players remain visible, and how the popup opens.

### Improved

- Let users set the Expanded layout width from 200 to 300 logical pixels in 5-pixel steps. Long track details shorten to fit instead of widening the widget.
- Kept playback controls easy to reach while preserving room for neighboring dock icons.

### Fixed

- Fixed opening the media popup across the full widget, including its playback buttons, and kept it open while moving between the widget and popup.
- Fixed magnification when moving between the media widget, its popup, and other dock items.
- Kept the popup and selected player stable while media details or playback state refresh.
- Fixed running-window indicators when grouped application windows are added or removed.
- Fixed Window Preview timing and media-popup transitions so neighboring previews remain available.

## [0.6.0] - 2026-11-17

KDockW 0.6.0 adds built-in dock widgets and an application launcher with three distinct layouts.

### Added

- Added a widget manager for separators and fixed spacers. Set their size, visibility, order, and placement at the start, center, or end of the dock.
- Added the macOS Launchpad layout: a searchable app grid with saved folders.
- Added the Windows Start layout: pinned apps, search, and a separate list of all applications.
- Added the KDE Hierarchical layout, which follows the system's nested application menu without changing it.
- Added keyboard navigation, favorites, saved launcher styles, and one-time import of Plasma favorites without changing Plasma settings.
- Added style-specific launcher icons and the option to save a custom icon.
- Limited new setups to one Launcher because its layout and favorites are shared; existing duplicates are kept and can be removed manually.

### Improved

- Let users place built-in widgets among pinned apps while keeping running tasks and Folder Stacks working as before.
- Matched the built-in separator to the standard task separator and kept both aligned as dock contents change.
- Adapted launcher windows to the available screen space and the active KDE color and icon themes.
- Kept launcher popups usable with the keyboard and made them close on Escape or an outside click.

### Fixed

- Fixed a crash when creating a Launchpad folder.
- Made the widget manager available from the dock context menu, including when the dock has no built-in widgets.
- Made each launcher layout distinct and kept its app icons, folders, and navigation controls visible and readable.
- Kept widget manager controls readable in narrow and scaled windows.
- Updated one task's icon without needlessly reloading the icons of other tasks.

## [0.5.1] - 2026-11-13

KDockW 0.5.1 improves space for maximized windows, clarifies application actions, and adds Fedora 45 packages.

### Added

- Added a saved 0–20 px gap between the dock and maximized windows. Changes apply immediately and work on all four dock edges.
- Added Fedora 45 with Qt 6.11 to the release package targets.

### Improved

- Grouped dock controls under a KDockW submenu while keeping application actions, Desktop Actions, pinning, and new-instance commands available.
- Separated closing a window or app group from quitting KDockW.

### Fixed

- Kept the dock's screen area reserved after unlock when its position and size have not changed.
- Kept pinned app names and active-window selection current on Qt 6.11, including windows on other screens.

## [0.5.0] - 2026-11-12

KDockW 0.5.0 adds Folder Stacks, so folders can live alongside apps on the dock.

### Added

- Added Folder Stacks: drop a folder on the dock to keep it there, browse nested folders, and open files with their usual applications.
- Added saved ordering for pinned apps and Folder Stacks, plus a choice of theme or image icon for each stack.

### Improved

- Made Folder Stack popups usable with mouse and keyboard, with clear selection and menus that close on Escape or an outside click.
- Kept folder previews, icons, and task ordering consistent as windows open and close.

### Fixed

- Prevented duplicate app icons after reordering pinned apps and running windows.
- Kept the selected window preview on the remaining window when another window in its group closes.
- Kept Folder Stack popups in position while dock icons magnify.

Known issue at release time: maximized windows could overlap the dock after locking and unlocking Plasma. This was fixed in v0.5.1.

Fedora 45 packages were not part of v0.5.0; support was added in v0.5.1.

## [0.4.3] - 2026-11-11

KDockW 0.4.3 keeps more minimized-window previews available and improves language support in installed packages.

### Improved

- Kept more minimized-window previews available while many other windows are open.

### Fixed

- Loaded the translations that come with KDockW, avoiding older translation files elsewhere on the system.
- Included the Russian translations in RPM packages.

### Removed

- Stopped providing Arch Linux packages. Release packages for this version cover Debian 13, Ubuntu 26.04 LTS, and Fedora 45.

## [0.4.2] - 2026-11-10

KDockW 0.4.2 improves window previews and sets more useful animation defaults for new configurations.

### Improved

- Set Spring Speed to 90% and Launch Bounce Speed to 70% for new configurations; saved preferences are unchanged.
- Closed Window Preview after a window is activated, restored, or minimized.

### Fixed

- Kept minimized-window previews available when reopening them and kept grouped previews usable after selecting a window.
- Kept previews in place as dock icons move and fitted grouped previews to the available screen width.
- Kept Follow Active on the correct screen when several window updates arrive together.
- Improved window preview reliability with software graphics rendering.
- Completed missing Russian accessibility labels.

## [0.4.0] - 2026-11-09

KDockW 0.4.0 adds adjustable spring magnification, launch and attention animations, and more control over dock visibility and window previews.

### Added

- Added adjustable launch bounce, attention, and click animations, with controls for intensity, speed, and height.
- Added adjustable Spring magnification. It is the default for new configurations; Classic remains available and saved preferences are preserved.
- Added a 220 ms slide and fade when the dock's existing visibility rules hide or reveal it. The animation can be disabled and does not turn on auto-hide.
- Added a Window Preview hide delay from 0 to 1500 ms, separate from the dock's own hide delay.

### Improved

- Set the new-configuration attention animation duration to 3 seconds and increased the default launch bounce height without changing saved settings.
- Kept attention animations tied to app or window urgency; notification counts alone do not trigger them.

### Fixed

- Kept enlarged icons, tooltips, and preview cards positioned correctly along every dock edge and across multiple screens.
- Kept pinned apps in order when their windows open and made Follow Active move to the screen of the newly activated window.
- Kept minimized-window previews available when previews reopen and avoided missing frames on software renderers.
- Added Russian translations for the animation, dock visibility, and preview-delay settings.

## [0.3.1] - 2026-11-07

KDockW 0.3.1 adds optional release notifications and easier controls for grouped window previews.

### Added

- Added an optional checker for stable KDockW releases, with KDE notifications and a link to the release page. Updates are never downloaded or installed automatically.

### Improved

- Moved update-check settings to Settings → About.
- Added a separate close button to each window in a grouped preview.

## [0.3.0] - 2026-11-07

KDockW 0.3.0 adds customizable window previews, app badges, and clearer app identification.

### Added

- Added live previews for open and minimized windows, including separate previews for grouped windows and a CPU-based capture option.
- Added four preview sizes and controls for the preview card's background, transparency, corners, border, spacing, and distance from the dock.
- Added customizable running-app badges with a live preview, plus app-name tooltips and icon transparency settings. Badges use red and white by default.

### Improved

- Made grouped-window close controls easier to identify. Badges use the Number style, Medium text weight, and red-and-white colors by default; saved settings are preserved.

### Fixed

- Kept preview cards close to the dock and preserved window proportions at every preview size.
- Kept app tooltips on-screen while icons magnify and restored dock hover after pointer reconnection.

## [0.1.0] - 2026-11-03

KDockW 0.1.0 is the first stable standalone release of the KDE Plasma dock for Wayland.

### Added

- Added adjustable dock spacing and alignment for all four screen edges.
- Added five running-app indicator styles, with controls for position, size, and color.
- Added an optional CPU-based window preview mode for systems where automatic capture is not compatible.
- Added English and Russian interface language choices.
- Provided packages for the Arch, Debian, Fedora, openSUSE, and Ubuntu releases available at the time.

### Improved

- Set 40 px icons, 13 px spacing, and 1.7× magnification as part of the first-run appearance for new installations; previously saved preferences remain unchanged.
- Made KDockW independently versioned while retaining credit to the original Krema project and its author.

### Fixed

- Kept running-app indicators and previews on the selected screen and within the dock.
- Made language choices apply to the open settings and persist between launches.
- Included translated interface text in RPM packages.

### Removed

- Switched to the desktop's standard autostart setting instead of providing a separate service template; existing user services are left unchanged.

Compatibility note: the CPU preview mode was tested on one hybrid Intel/NVIDIA system and may not solve capture problems on every graphics setup.

## 2026-11-02 — Independent KDockW project

These changes prepared KDockW as a standalone application before its first stable release.

### Added

- Added an English/Russian language choice for the dock and its settings.
- Added KDockW application branding, its own settings identity, and a migration and rollback path from the earlier project.

### Improved

- Updated the app icon and logo while retaining credit to the original Krema project and its author.

### Fixed

- Made language selection apply immediately and remain saved across settings pages and launches.
- Kept the dock background blur visible while icons zoom.
- Activated a running application when files are dragged over its dock icon, without interrupting the file drop.

## 2026-11-01 — Improvements carried forward into KDockW

These user-facing improvements were made during development before KDockW's first stable release.

### Added

- Added a Russian translation for the dock, settings, menus, accessibility labels, and notifications.

### Improved

- Made launch bounce stop sooner when the launched app window appears.

### Fixed

- Allowed launcher links from the Plasma task manager to be dropped on the dock alongside files and desktop launchers.
