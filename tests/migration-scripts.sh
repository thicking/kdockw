#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?Usage: migration-scripts.sh SOURCE_DIR}"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

home="$temp_root/home"
config_dir="$home/config"
state_dir="$home/state"
bin_dir="$temp_root/bin"
mkdir -p -- "$config_dir" "$state_dir" "$bin_dir"
cat >"$bin_dir/pgrep" <<'SH'
#!/usr/bin/env sh
exit 1
SH
chmod +x "$bin_dir/pgrep"

cat >"$config_dir/kremarc" <<'CONFIG'
[General]
PinnedLaunchers=file:///usr/share/applications/org.kde.dolphin.desktop,applications:firefox.desktop
IconSize=56

[Screen-eDP-1]
Edge=2
IconSize=64
CONFIG
chmod 640 "$config_dir/kremarc"
cp -- "$config_dir/kremarc" "$temp_root/original"

run_as_config_user() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        chown -R nobody:nobody "$temp_root"
        runuser -u nobody -- env HOME="$home" XDG_CONFIG_HOME="$config_dir" XDG_STATE_HOME="$state_dir" \
            PATH="$bin_dir:/usr/local/bin:/usr/bin:/bin" "$@"
    else
        env HOME="$home" XDG_CONFIG_HOME="$config_dir" XDG_STATE_HOME="$state_dir" \
            PATH="$bin_dir:/usr/local/bin:/usr/bin:/bin" "$@"
    fi
}

run_as_config_user "$source_dir/scripts/migrate-krema-config.sh"
cmp -s "$temp_root/original" "$config_dir/kremarc"
cmp -s "$config_dir/kremarc" "$config_dir/kdockwrc"
[[ "$(stat -c '%a' "$config_dir/kdockwrc")" == 640 ]]
backup_file="$(find "$state_dir/kdockw/migrations" -name kdockwrc-migrated -print -quit)"
[[ -n "$backup_file" ]]
cmp -s "$config_dir/kdockwrc" "$backup_file"

printf '[General]\nIconSize=72\n' >"$config_dir/kdockwrc"
if run_as_config_user "$source_dir/scripts/migrate-krema-config.sh"; then
    echo "Migration unexpectedly overwrote an existing KDockW config." >&2
    exit 1
fi
grep -q 'IconSize=72' "$config_dir/kdockwrc"

backup_dir="$(dirname "$backup_file")"
run_as_config_user "$source_dir/scripts/rollback-kdockw-config.sh" "$backup_dir"
cmp -s "$temp_root/original" "$config_dir/kremarc"
grep -q 'IconSize=72' "$config_dir/kdockwrc"

echo "Migration and rollback scripts passed the isolated config-preservation checks."
