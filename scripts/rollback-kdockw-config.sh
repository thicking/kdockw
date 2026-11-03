#!/usr/bin/env bash
set -euo pipefail

backup_dir="${1:?Usage: rollback-kdockw-config.sh BACKUP_DIR}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
source_backup="$backup_dir/kremarc"
current_config="$config_dir/kremarc"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "Run this rollback as your desktop user, not as root." >&2
    exit 1
fi

if [[ ! -f "$source_backup" ]]; then
    echo "Backup does not contain kremarc: $backup_dir" >&2
    exit 1
fi
if pgrep -u "$(id -u)" -x kdockw >/dev/null 2>&1; then
    echo "KDockW is running. Close it before restoring the old settings." >&2
    exit 1
fi

mkdir -p -- "$config_dir"
if [[ -e "$current_config" ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    rollback_copy="$backup_dir/kremarc-before-rollback-$stamp"
    cp -a -- "$current_config" "$rollback_copy"
    printf 'Saved current Krema config to %s\n' "$rollback_copy"
fi
temp_config="$(mktemp "$config_dir/.kremarc.XXXXXX")"
trap '[[ -z "${temp_config:-}" ]] || rm -f -- "$temp_config"' EXIT
install -m "$(stat -c '%a' -- "$source_backup")" -- "$source_backup" "$temp_config"
cmp -s -- "$source_backup" "$temp_config"
mv -f -- "$temp_config" "$current_config"
temp_config=""
cmp -s -- "$source_backup" "$current_config"
printf 'Restored Krema settings to %s\n' "$current_config"
printf 'KDockW config, desktop entry and user startup entries were not removed or changed.\n'
