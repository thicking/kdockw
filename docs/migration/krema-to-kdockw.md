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
| `krema.service` | `kdockw.service` | New optional user unit with PRIME and Qt override cleanup. |
| Krema XDG autostart entry | KDockW XDG autostart entry | Choose only one login starter: XDG autostart or systemd user service. |

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
desktop entry and its direct `Exec=/usr/local/bin/kdockw` intact; a separate
launcher will start the service.

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

## 3. Switch one login starter after testing

Keep the old service and autostart file until KDockW has been checked. If
Krema currently starts through a user service, disable it first:

```sh
systemctl --user disable --now krema.service
```

If that unit did not exist, skip this command. Preserve any user override
before masking the old XDG autostart entry. The old installed file was named
`com.bhyoo.krema.autostart.desktop`; the same-name override hides it for this
user:

```sh
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/com.bhyoo.krema.autostart.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
```

Choose one KDockW login mechanism:

### Use the NVIDIA-clean systemd user service

Install the checked-in unit template and start it:

```sh
install -D -m 644 packaging/systemd/kdockw.service \
  ~/.config/systemd/user/kdockw.service
systemctl --user daemon-reload
systemctl --user enable --now kdockw.service
```

The unit starts `/usr/local/bin/kdockw` directly and clears inherited
`DRI_PRIME`, `__GLX_VENDOR_LIBRARY_NAME`, `__NV_PRIME_RENDER_OFFLOAD`,
`__VK_LAYER_NV_optimus`, and `QSG_RHI_BACKEND` variables for this service only.
It does not edit the global session environment or driver configuration.

Hide the KDockW XDG autostart entry for this user so the service is the only
login starter:

```sh
cat > ~/.config/autostart/com.thicking.kdockw.autostart.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
```

Create an optional menu shortcut that requests service start:

```sh
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/kdockw-service.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KDockW (service)
Comment=Start KDockW through the user service
Exec=systemctl --user start kdockw.service
Icon=com.thicking.kdockw
Terminal=false
Categories=Utility;
StartupNotify=false
EOF
kbuildsycoca6
```

### Use XDG autostart

Do not enable `kdockw.service`. Leave
`com.thicking.kdockw.autostart.desktop` active and ensure no KDockW service is
enabled. If you created a `Hidden=true` override while testing the service,
restore its saved previous version or remove that override.

## 4. Verify, then keep the rollback path

After starting KDockW, verify the process, configuration, desktop registration,
and service environment:

```sh
systemctl --user status kdockw.service
systemctl --user show kdockw.service -p UnsetEnvironment
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
does not stop services, change autostart, or delete the KDockW config. To
switch back from the service, disable it and restore your saved autostart
override or original unit:

```sh
systemctl --user disable --now kdockw.service
```

Re-enable the old service only if it was enabled before migration. Keep the
KDockW configuration and migration backup until you have confirmed the
rollback. No migration or rollback command deletes the old application.
