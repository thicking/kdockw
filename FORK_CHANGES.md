# KDockW changes carried forward from Krema

KDockW preserves the useful work developed while this repository was a Krema
fork. The file and commit history remains intact; commit authorship is not
rewritten. This ledger describes current KDockW behavior and points to the
historical commits on the repository's earlier `thicking/krema` path.

## Retained enhancements

| Area | Current behavior | Verification and limits |
|---|---|---|
| Russian KI18n | Russian catalog covers settings, menus, tooltips, accessibility text, and notifications; other locales retain English source strings. | Catalog compiles with `msgfmt`; 256 translations were recorded. A live KDockW Wayland locale check is still required after its desktop ID is installed. |
| Launch feedback | Launch-icon bounce ends after at most five complete cycles and can finish early after a new window appears. | QML coverage includes the cap, early completion, repeated and simultaneous launches, and late startup notification. |
| Plasma task-manager drops | Reads the task launcher URL from `text/x-orgkdeplasmataskmanager_taskurl`; URI-list and `.desktop` handling remain available. | The opaque task-button payload is not decoded. |
| File-drag activation | Activates an existing application window after a configurable hover delay without reading or consuming dragged file URLs. | The user manually verified multiple Dolphin file drops through the dock on Plasma 6.6.6 / Wayland; `.desktop` launcher pinning continued to work. Recheck after installing KDockW's new desktop entry. |
| TaskManager diagnostics | Logs task rows and role changes without recording window titles. | Logging does not change KDE filtering and cannot prove every launcher/KWin setup. |
| PipeWire diagnostics | Logs capture state and retains one experimental CPU-readable-buffer retry when the stream has no first frame. | This is not a confirmed general fix for black previews or cross-GPU DMA-BUF import. |
| NVIDIA PRIME guidance | Records the observed hybrid-GPU symptoms and a user-service workaround that clears selected environment overrides. | The observations apply to one TUXEDO OS / Intel + NVIDIA configuration. |

## Independent KDockW identity

The executable, KConfig file, KI18n domain, QML import URI, private KWin
callback, desktop ID, app icon, AppStream ID, and optional user service now use
KDockW identifiers. The migration guide documents the old names and provides
an explicit backup, copy, verification, and rollback path. Migration is never
run automatically.

Standard KDE/Wayland protocol names and KWin's `dock`/`tooltip` layer-shell
namespaces remain unchanged. They are protocol contracts, not product labels.

## Historical source

The preceding implementation commits remain available in Git. For example:

- [Russian catalog](https://github.com/thicking/krema/commit/732e57b)
- [Bounded launch bounce](https://github.com/thicking/krema/commit/c804cf0)
- [Plasma task-manager URL drops](https://github.com/thicking/krema/commit/9d61ea3)
- [TaskManager diagnostics](https://github.com/thicking/krema/commit/0907fe7)
- [PipeWire diagnostics](https://github.com/thicking/krema/commit/b463773)
- [NVIDIA and TUXEDO OS guides](https://github.com/thicking/krema/commit/caa7ac1)
- [Manual Wayland file-drag acceptance record](https://github.com/thicking/krema/commit/34d142d)

KDockW is based on the original project [Krema](https://github.com/isac322/krema),
originally created by Byeonghoon Yoo. It develops independently; no automatic
upstream synchronization is configured. See [README](README.md) for the
project's origin, retained license, and current build instructions.
