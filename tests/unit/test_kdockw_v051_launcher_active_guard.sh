#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
launcher="${repo_root}/tools/kdockw-v051-dev-start"
stable_binary="$(command -v kdockw || true)"
[[ -x "$stable_binary" ]] || { printf 'SKIP: stable KDockW executable is unavailable.\n'; exit 0; }
stable_binary="$(/usr/bin/readlink -f -- "$stable_binary")"
[[ "$("$stable_binary" --version)" == 'kdockw 0.5.0' ]] \
    || { printf 'SKIP: installed executable is not stable KDockW v0.5.0.\n'; exit 0; }

runtime_dir="/run/user/$(id -u)"
real_manager_env="$(/usr/bin/systemctl --user show-environment 2>/dev/null || true)"
wayland_display="$(sed -n 's/^WAYLAND_DISPLAY=//p' <<<"$real_manager_env")"
[[ -S "${runtime_dir}/${wayland_display}" && -S "${runtime_dir}/bus" ]] \
    || { printf 'SKIP: no live Plasma Wayland and D-Bus sockets for launcher preflight.\n'; exit 0; }

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/kdockw-launcher-guard.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT
mkdir -p "${temporary_dir}/bin" "${temporary_dir}/data" "${temporary_dir}/cache"

cat > "${temporary_dir}/manager-environment" <<EOF
XDG_RUNTIME_DIR=${runtime_dir}
WAYLAND_DISPLAY=${wayland_display}
DBUS_SESSION_BUS_ADDRESS=unix:path=${runtime_dir}/bus
XDG_CURRENT_DESKTOP=KDE
KDE_SESSION_VERSION=6
XDG_DATA_DIRS=/usr/local/share:/usr/share
XDG_DATA_HOME=${temporary_dir}/data
XDG_CACHE_HOME=${temporary_dir}/cache
EOF

cat > "${temporary_dir}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --user && "$2" == show-environment ]]; then
    cat "$KDOCKW_TEST_MANAGER_ENV"
    exit 0
fi
if [[ "$1" == --user && "$2" == is-active ]]; then
    exit 3
fi
printf 'Unexpected systemctl invocation in launcher guard test: %s\n' "$*" >&2
exit 97
EOF

cat > "${temporary_dir}/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -x && "$2" == kdockw ]] || exit 97
: > "$KDOCKW_TEST_PGREP_REACHED"
printf '987654\n'
EOF

cat > "${temporary_dir}/bin/readlink" <<EOF
#!/usr/bin/env bash
for argument in "\$@"; do
    if [[ "\$argument" == /proc/987654/exe ]]; then
        printf '%s\\n' '${stable_binary}'
        exit 0
    fi
done
exec /usr/bin/readlink "\$@"
EOF

cat > "${temporary_dir}/bin/cmake" <<'EOF'
#!/usr/bin/env bash
: > "$KDOCKW_TEST_CMAKE_REACHED"
printf 'Launcher must stop before build/install in this test.\n' >&2
exit 98
EOF

cat > "${temporary_dir}/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
: > "$KDOCKW_TEST_SYSTEMD_RUN_REACHED"
printf 'Launcher must not start a second dock in this test.\n' >&2
exit 99
EOF

chmod +x "${temporary_dir}/bin/"*

set +e
launcher_output="$(
    PATH="${temporary_dir}/bin:/usr/local/bin:/usr/bin:/bin" \
    KDOCKW_TEST_MANAGER_ENV="${temporary_dir}/manager-environment" \
    KDOCKW_TEST_PGREP_REACHED="${temporary_dir}/pgrep-reached" \
    KDOCKW_TEST_CMAKE_REACHED="${temporary_dir}/cmake-reached" \
    KDOCKW_TEST_SYSTEMD_RUN_REACHED="${temporary_dir}/systemd-run-reached" \
        "$launcher" --wayland-debug 2>&1
)"
launcher_status=$?
set -e

[[ "$launcher_status" -eq 1 ]] || {
    printf 'Expected launcher refusal status 1, got %s:\n%s\n' "$launcher_status" "$launcher_output" >&2
    exit 1
}
[[ "$launcher_output" == *'KDockW is already running; launch refused'* ]] || {
    printf 'Launcher did not refuse at the active-stable-process guard:\n%s\n' "$launcher_output" >&2
    exit 1
}
[[ -f "${temporary_dir}/pgrep-reached" ]] || {
    printf 'Launcher did not reach the active-process guard.\n' >&2
    exit 1
}
[[ ! -e "${temporary_dir}/cmake-reached" && ! -e "${temporary_dir}/systemd-run-reached" ]] || {
    printf 'Launcher crossed the safety guard and attempted install or startup.\n' >&2
    exit 1
}

printf 'Diagnostic launch branch reached the stable-process guard and stopped before install/start.\n'
