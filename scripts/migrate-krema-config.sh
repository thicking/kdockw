#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
source_config="$config_dir/kremarc"
target_config="$config_dir/kdockwrc"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/kdockw/migrations"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "Run this migration as your desktop user, not as root." >&2
    exit 1
fi

if ! command -v pgrep >/dev/null 2>&1; then
    echo "pgrep is required to check whether the old dock is running." >&2
    exit 1
fi
if pgrep -u "$(id -u)" -x krema >/dev/null 2>&1; then
    echo "Krema is running. Close it before copying its last saved settings." >&2
    exit 1
fi
if [[ ! -f "$source_config" ]]; then
    echo "No existing Krema config found at: $source_config" >&2
    exit 1
fi
if [[ -e "$target_config" ]]; then
    echo "KDockW config already exists; refusing to overwrite: $target_config" >&2
    exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$backup_root/$stamp"
if [[ -e "$backup_dir" ]]; then
    echo "Backup path already exists; refusing to overwrite: $backup_dir" >&2
    exit 1
fi
mkdir -p -- "$backup_dir"
cp -a -- "$source_config" "$backup_dir/kremarc"
temp_config="$(mktemp "$config_dir/.kdockwrc.XXXXXX")"
trap '[[ -z "${temp_config:-}" ]] || rm -f -- "$temp_config"' EXIT
install -m "$(stat -c '%a' -- "$source_config")" -- "$source_config" "$temp_config"
if ! cmp -s -- "$source_config" "$temp_config"; then
    echo "Config verification failed; the original is unchanged. Backup: $backup_dir" >&2
    exit 1
fi
if [[ -e "$target_config" ]]; then
    echo "KDockW config appeared during migration; refusing to overwrite: $target_config" >&2
    exit 1
fi
mv -- "$temp_config" "$target_config"
temp_config=""
cp -- "$target_config" "$backup_dir/kdockwrc-migrated"

if ! cmp -s -- "$source_config" "$target_config"; then
    echo "Config verification failed after migration; inspect the backup at $backup_dir" >&2
    exit 1
fi

sha256sum -- "$source_config" "$target_config" >"$backup_dir/SHA256SUMS"
cat >"$backup_dir/README.txt" <<EOF
KDockW settings migration snapshot
Created: $stamp
Source: $source_config
Target: $target_config
The source configuration was not modified or removed.
Restore Krema settings with: scripts/rollback-kdockw-config.sh "$backup_dir"
EOF

printf 'Copied settings and pinned launchers to %s\n' "$target_config"
printf 'Backup: %s\n' "$backup_dir"
printf 'Original Krema settings were left in place. No startup entries were changed.\n'
