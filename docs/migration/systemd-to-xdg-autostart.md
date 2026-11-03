# Migrate KDockW startup from a user systemd unit to XDG autostart

KDockW now supports XDG autostart as its only automatic login startup
mechanism. This guide is for users who created or installed a `kdockw.service`
with an earlier checkout. Migration is manual: installing or updating KDockW
does not inspect or alter user units, overrides, desktop shortcuts, or running
processes.

For Russian, see [systemd-to-xdg-autostart.ru.md](systemd-to-xdg-autostart.ru.md).

## 1. Inspect the current state

These commands only inspect the user unit and process list. A missing unit is
normal:

```sh
systemctl --user is-enabled kdockw.service || true
systemctl --user is-active kdockw.service || true
systemctl --user status --no-pager kdockw.service || true
systemctl --user show kdockw.service -p FragmentPath -p DropInPaths --no-pager || true
pgrep -a -x kdockw || true
```

Record whether the unit is enabled, active, or disabled. `FragmentPath` and
`DropInPaths` identify the unit and local overrides. Do not edit package-owned
files under `/usr`, `/usr/local`, or `/etc` as though they were user files. If a
path is outside your home directory, use the owning package's documented
removal/update method or ask the administrator.

## 2. Back up user-owned files

Create a private, timestamped backup directory and copy any files that exist.
These commands do not remove or change the originals:

```sh
backup="$HOME/.local/state/kdockw/migrations/systemd-to-xdg-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup"

for path in \
  "$HOME/.config/systemd/user/kdockw.service" \
  "$HOME/.config/systemd/user/kdockw.service.d" \
  "$HOME/.local/share/systemd/user/kdockw.service" \
  "$HOME/.local/share/systemd/user/kdockw.service.d" \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" \
  "$HOME/.local/share/applications/kdockw-service.desktop"; do
  if [ -e "$path" ]; then
    cp -a --parents "$path" "$backup"
  fi
done
printf 'Backup: %s\n' "$backup"
```

If `systemctl show` reported another user-owned fragment or drop-in path, copy
that path into the same backup before changing or moving it. Keep the backup
until login startup has been verified.

## 3. Disable the old login starter

If `kdockw.service` is enabled, disable it without `--now`:

```sh
systemctl --user disable kdockw.service
```

This prevents a later systemd login start and does not stop an active KDockW
process. Do not stop or kill a running dock during migration. Let a
service-started instance exit normally or at normal logout. If you later choose
to remove a user-owned unit, first confirm it is inactive, then move the
original into the backup directory and reload the user manager. Do not delete a
unit or override before verifying its backup.

## 4. Restore XDG autostart

The installed entry is `com.thicking.kdockw.autostart.desktop`. Its `Exec`
launches the configured `kdockw` binary directly. Locate the installed copy:

```sh
test -f /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
grep '^Exec=' /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
```

A same-name file under `~/.config/autostart/` overrides the installed entry.
Inspect it before changing anything:

```sh
grep -nE '^(Hidden|Exec|OnlyShowIn)=' \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" 2>/dev/null || true
```

If it contains `Hidden=true`, keep the backup from step 2. Either edit the file
to remove that key while preserving unrelated custom entries, or, if the file
exists only to mask the system entry, move it into the backup:

```sh
mv "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" "$backup/"
```

Do not create a wrapper. Keep `com.thicking.kdockw.desktop` and its
`X-KDE-Wayland-Interfaces` line unchanged. Manual launch remains supported.
KDockW registers a unique KDE D-Bus application service, so later desktop
launches are forwarded to the existing instance; still check the process list
after login.

If you created `kdockw-service.desktop`, it is only a menu shortcut. After
backing it up, move it out of the applications directory if you no longer want
a shortcut to the retired unit:

```sh
if [ -e "$HOME/.local/share/applications/kdockw-service.desktop" ]; then
  install -d "$backup/retired-shortcuts"
  mv "$HOME/.local/share/applications/kdockw-service.desktop" "$backup/retired-shortcuts/"
fi
```

## 5. Verify at the next login

After the next Plasma login, check:

```sh
systemctl --user is-enabled kdockw.service || true
pgrep -a -x kdockw || true
```

The old unit should not be enabled, and there should be one KDockW process.
Launch KDockW from its application entry or manually to verify both paths.
Use `/usr/bin/kdockw` for a `/usr` installation or `/usr/local/bin/kdockw`
for the TUXEDO guide's default prefix.

## Roll back

If XDG autostart fails, check the desktop `Exec`, install prefix, and whether a
same-name override still contains `Hidden=true`. Restore only the user-owned
files that you backed up, to their original paths. For example:

```sh
unit_backup="$backup$HOME/.config/systemd/user/kdockw.service"
if [ -e "$unit_backup" ]; then
  install -d "$HOME/.config/systemd/user"
  cp -a "$unit_backup" "$HOME/.config/systemd/user/"
fi

override_backup="$backup$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop"
if [ -e "$override_backup" ]; then
  install -d "$HOME/.config/autostart"
  cp -a "$override_backup" "$HOME/.config/autostart/"
fi
```

Also restore any user-owned drop-ins from the backup. Do not copy a user
backup over a package-owned unit. Restore the exact pre-migration autostart
state: if the systemd unit was your only login starter and there was no
previous user autostart override, mask the system XDG entry before re-enabling
the unit:

```sh
if [ ! -e "$override_backup" ]; then
  install -d "$HOME/.config/autostart"
  cat >"$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" <<'EOF'
[Desktop Entry]
Hidden=true
EOF
fi
```

Then reload the manager and enable the unit only if it was enabled before
migration:

```sh
systemctl --user daemon-reload
systemctl --user enable kdockw.service
```

Before starting that unit, ensure the XDG-launched KDockW instance has exited
normally and restore the previous autostart override. Do not copy a user
backup over a package-owned unit.
