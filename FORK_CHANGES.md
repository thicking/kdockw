# KDockW changes carried forward from Krema

KDockW preserves selected work developed while this repository was presented as
a Krema fork. The file and commit history remains intact; commit authorship is
not rewritten. This ledger describes current KDockW behavior and links to the
original commits. The [changelog](CHANGELOG.md) records the dated project
history; the old Krema release notes remain in the
[history archive](docs/history/krema-changelog.md).

## Retained enhancements

| Area | Current behavior | Verification and limits |
|---|---|---|
| Russian KI18n and language choice | Russian catalog covers settings, menus, tooltips, accessibility text, and notifications; users can choose System default, Russian, or English. | `msgfmt` and unit/QML tests pass, including config persistence and live binding updates. A visual language check in an installed Wayland session is still required. |
| Launch feedback | Launch-icon bounce ends after at most five complete cycles and can finish early after a new window appears. | QML coverage includes the cap, early completion, repeated and simultaneous launches, and late startup notification. |
| Plasma task-manager drops | Reads the task launcher URL from `text/x-orgkdeplasmataskmanager_taskurl`; URI-list and `.desktop` handling remain available. | The opaque task-button payload is not decoded. |
| File-drag activation | Activates an existing application window after a configurable hover delay without reading or consuming dragged file URLs. | The user manually verified multiple Dolphin file drops through the dock on Plasma 6.6.6 / Wayland; `.desktop` launcher pinning continued to work. Recheck after installing KDockW's new desktop entry. |
| Parabolic-zoom background geometry | Keeps the blur effect enabled while replacing its region as the dock background changes size. | Geometry and effect-state tests pass. The absence of visual flicker still needs checking in a real Wayland session. |
| TaskManager diagnostics | Logs task rows and role changes without recording window titles. | Logging does not change KDE filtering and cannot prove every launcher/KWin setup. |
| PipeWire diagnostics | Logs capture state and retains one experimental CPU-readable-buffer retry when the stream has no first frame. | This is not a confirmed general fix for black previews or cross-GPU DMA-BUF import. |
| NVIDIA PRIME guidance | Records observed hybrid-GPU symptoms, the saved CPU preview compatibility setting, and process-local diagnostic overrides. | The A/B result applies to one TUXEDO OS / Intel + NVIDIA configuration; the exact DMA-BUF failure is unknown. |

## Independent KDockW identity

The GitHub repository is now standalone (`isFork: false`, no parent). The
executable, KConfig file, KI18n domain, QML import URI, private KWin callback,
desktop ID, XDG autostart entry, app icon, and AppStream ID use KDockW
identifiers. The English and Russian migration guides document the old names
and the explicit backup, copy, verification, and rollback path. Migration is
never run automatically. The independent roadmap is available in
[English](ROADMAP.md) and [Russian](ROADMAP.ru.md).

Standard KDE/Wayland protocol names and KWin's `dock`/`tooltip` layer-shell
namespaces remain unchanged. They are protocol contracts, not product labels.

## Historical source

The preceding implementation commits remain available in Git. For example:

- [Russian catalog](https://github.com/thicking/kdockw/commit/732e57b)
- [Bounded launch bounce](https://github.com/thicking/kdockw/commit/c804cf0)
- [Plasma task-manager URL drops](https://github.com/thicking/kdockw/commit/9d61ea3)
- [TaskManager diagnostics](https://github.com/thicking/kdockw/commit/0907fe7)
- [PipeWire diagnostics](https://github.com/thicking/kdockw/commit/b463773)
- [NVIDIA and TUXEDO OS guides](https://github.com/thicking/kdockw/commit/caa7ac1)
- [Manual Wayland file-drag acceptance record](https://github.com/thicking/kdockw/commit/34d142d)
- [Activate a running window during external file drag](https://github.com/thicking/kdockw/commit/f60dbae)
- [Keep blur regions aligned during dock zoom](https://github.com/thicking/kdockw/commit/40f1bb9)
- [KDockW rebrand and new identifiers](https://github.com/thicking/kdockw/commit/b82b896)
- [App icon and workspace assets](https://github.com/thicking/kdockw/commit/bb0c47e)
- [Independent repository links and identity guide](https://github.com/thicking/kdockw/commit/c2efdae)
- [Application language selector](https://github.com/thicking/kdockw/commit/0563eb6)
- [Language persistence and dynamic application](https://github.com/thicking/kdockw/commit/9dbfb00)

KDockW is based on the original project [Krema](https://github.com/isac322/krema),
originally created by Byeonghoon Yoo. It develops independently; no automatic
upstream synchronization is configured. See [README](README.md) for the
project's origin, retained license, and current build instructions.
