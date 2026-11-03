# Manual migration from Krema to KDockW

This migration is opt-in. Installing KDockW does not read, move, overwrite, or
delete Krema's files, disable its autostart, or enable a KDockW service. Run the
steps below only after reviewing KDockW in your own Plasma session. They do not
change NVIDIA, KWin, Plasma, or SDDM configuration.

## Identity map and compatibility

| Previous Krema identity | KDockW identity | Compatibility decision |
|---|---|---|
| `/usr/local/bin/krema` | `/usr/local/bin/kdockw` | New executable; both can coexist. |
| `com.bhyoo.krema.desktop` | `com.thicking.kdockw.desktop` | New desktop ID. Its file declares the existing KWin Wayland interfaces. |
| `~/.config/kremarc` | `~/.config/kdockwrc` | Same KConfig groups, keys, values, and launcher URLs; copied byte-for-byte by the script. |
| KI18n domain `krema` | KI18n domain `kdockw` | New catalog name; Russian translations are retained. |
| QML URI `com.bhyoo.krema` | `com.thicking.kdockw` | Private import used only by this application and its tests. |
| KWin pointer watcher `com.bhyoo.krema.*` | `com.thicking.kdockw.*` | Private callback interface; updated at both ends. |
| Legacy `krema.service` | No KDockW unit equivalent | KDockW uses its XDG autostart entry; an old Krema unit remains under the user's control. |
| Krema XDG autostart entry | KDockW XDG autostart entry | KDockW installs `com.thicking.kdockw.autostart.desktop` and launches its binary directly. |

The KWin permission metadata values
`org_kde_plasma_window_management`, `org_kde_plasma_activation_feedback`,
and `zkde_screencast_unstable_v1` remain unchanged. KWin matches those
permissions against the installed desktop ID. The layer-shell namespaces
`dock` and `tooltip` remain unchanged because KWin interprets them as window
types, not product names. Standard TaskManager, KPipeWire, notification, and
Unity LauncherEntry protocol names also remain unchanged.

## 1. Install and check KDockW before migrating

Build and install KDockW using the [TUXEDO OS guide](../building/tuxedo-os.md).
Confirm these files exist before switching any login behavior:

```sh
test -x /usr/local/bin/kdockw
test -f /usr/local/share/applications/com.thicking.kdockw.desktop
grep '^X-KDE-Wayland-Interfaces=' /usr/local/share/applications/com.thicking.kdockw.desktop
```

The desktop file should list the three interfaces above. Keep this standard
desktop entry and its direct `Exec=/usr/local/bin/kdockw` intact; the installed
XDG autostart entry launches KDockW at login.

## 2. Copy the complete configuration

Close Krema normally so it has saved the latest settings. Then run this from
the source checkout as your desktop user:

```sh
scripts/migrate-krema-config.sh
```

The script refuses to run as root, refuses to overwrite an existing KDockW
configuration, and refuses to copy while a process named `krema` is running.
It copies the whole `kremarc` file, including pinned launchers and per-screen
groups, to `kdockwrc`, verifies the copy, and keeps the original in place. The
timestamped backup is saved under
`~/.local/state/kdockw/migrations/`. It makes no systemd or autostart changes.

If you use a non-default `XDG_CONFIG_HOME` or `XDG_STATE_HOME`, the script
honors those variables. Do not copy only the `[General]` group: per-screen
settings are in the same file.

## 3. Switch to KDockW XDG autostart after testing

If Krema currently starts through a user service, inspect and disable it for
future logins:

```sh
systemctl --user is-enabled krema.service || true
systemctl --user is-active krema.service || true
systemctl --user disable krema.service
```

Skip the last command if that unit does not exist or was already disabled.
Disabling it without `--now` does not stop a running Krema process; close Krema
normally before launching KDockW in the same session. The old installed
autostart file was named `com.bhyoo.krema.autostart.desktop`. If Krema also has
an XDG entry, preserve any existing same-name user override before disabling
that old entry.

KDockW uses the installed `com.thicking.kdockw.autostart.desktop` as its only
automatic login starter. Check whether a same-name user override hides it:

```sh
grep -nE '^(Hidden|Exec|OnlyShowIn)=' \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" 2>/dev/null || true
```

Back up a `Hidden=true` override before editing or moving it. Do not create a
wrapper or change the application desktop ID. If an older KDockW checkout
created a `kdockw.service`, follow the separate
[systemd-to-XDG migration guide](systemd-to-xdg-autostart.md).

## 4. Verify, then keep the rollback path

After the next login, verify the process, configuration, and desktop registration:

```sh
pgrep -a -x kdockw || true
grep -E '^(Exec|Icon|X-KDE-Wayland-Interfaces)=' \
  /usr/local/share/applications/com.thicking.kdockw.desktop
cmp ~/.config/kdockwrc \
  "$(find ~/.local/state/kdockw/migrations -name kdockwrc-migrated -print -quit)"
```

Then test window previews, running-app indicators, launcher grouping, pinning,
and file drops in the real Wayland session. The existing Krema configuration
and launcher stay available until this check passes.

To copy the backed-up settings back to Krema, close KDockW and pass the
timestamped backup directory printed by the migration script:

```sh
scripts/rollback-kdockw-config.sh \
  ~/.local/state/kdockw/migrations/YYYYMMDD-HHMMSS
```

The rollback script saves the current Krema config before restoring it. It
does not stop applications, change autostart, or delete the KDockW config. If
you disabled a legacy Krema service, re-enable it only if it was enabled before
migration and after KDockW has exited. Keep the KDockW configuration and
migration backup until rollback is no longer needed. No migration or rollback
command deletes the old application.
