#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Tier 3: run the Tier 2 AT-SPI E2E suite (tests/appium) against KDockW
# installed from its distro package, on that distro's own KWin/Qt/KF.
#
#   tests/distro/run-distro-e2e.sh <target>                    # full suite
#   tests/distro/run-distro-e2e.sh <target> test_smoke.py -x   # pytest args
#   tests/distro/run-distro-e2e.sh <target> --shell            # debug shell
#
# <target> is a row of tests/distro/targets.tsv or `arch`.
#
# 1. In the background: gets the target's runtime image (image-ref.sh
#    runtime <target>: the local tag, else ghcr.io, else a local build with
#    build-ci-image.sh), starts a container of it and, on rolling targets,
#    fully upgrades it (packages.sh upgrade).
# 2. Meanwhile builds the package with tests/distro/build-package.sh into
#    tests/distro/.cache/packages/<target>/ unless one is already there.
# 3. Installs the package into that container through the distro package
#    manager (packages.sh kdockw: its Requires/Depends must pull in kdockw's
#    runtime) and commits it as kdockw-e2e-distro:<target>.
# 4. Runs tests/appium/run-e2e.sh with that image and KDOCKW_E2E_BINARY, so
#    the session setup is exactly Tier 2's.
#
# Every phase prints `[distro] <phase>: <seconds>s`.
#
# Environment:
#   KDOCKW_DISTRO_REBUILD_PACKAGE=1   rebuild the package even if cached
#   KDOCKW_DISTRO_SKIP_IMAGE_BUILD=1  reuse an existing kdockw-e2e-distro:<target>
#                                    (steps 1 and 3 are skipped)
#   KDOCKW_CCACHE_DIR, CCACHE_MAXSIZE, KDOCKW_CI_REGISTRY, KDOCKW_ARCH_IMAGE
#                         see build-package.sh and image-ref.sh
#   KDOCKW_E2E_ARTIFACTS   default tests/appium/artifacts-distro-<target>
#   KDOCKW_E2E_PLATFORM    default linux/amd64 for arch and opensuse-slowroll
#                         (their repositories are amd64-only), else native
#   KDOCKW_E2E_SHARDS=N    run the suite as N shards concurrently (default 1,
#                         one run-e2e.sh). Shard i (0-based) gets
#                         KDOCKW_E2E_SHARD=i/N, selects every N-th collected
#                         test, and writes to <artifacts>/shard-<i>/ with a
#                         [shard i] log prefix; any shard failing fails the
#                         run. --shell cannot be sharded.
#   Any other KDOCKW_E2E_* variable of tests/appium/run-e2e.sh.

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$here/../.." && pwd)"
# shellcheck source=tests/distro/image-ref.sh
. "$here/image-ref.sh"

usage() {
    awk 'NR > 4 && /^#/ { sub(/^# ?/, ""); print; next } NR > 4 { exit }' "${BASH_SOURCE[0]}" >&2
    exit 64
}

[[ $# -ge 1 ]] || usage
target="$1"
shift

distro_target "$target" || {
    echo "error: unknown target '$target' (not in tests/distro/targets.tsv, and not 'arch')" >&2
    exit 64
}

if [[ -z "${KDOCKW_E2E_PLATFORM:-}" ]]; then
    platform="$(distro_platform "$target")"
    [[ -z "$platform" ]] || export KDOCKW_E2E_PLATFORM="$platform"
fi
platform_args=()
[[ -n "${KDOCKW_E2E_PLATFORM:-}" ]] && platform_args=(--platform "$KDOCKW_E2E_PLATFORM")

# The package cache, final image tag, and default artifact path are shared by
# runs for one target. Serialize those runs so cleanup/build cannot race with
# another process targeting the same resources.
command -v flock >/dev/null || {
    echo "error: flock is required to serialize distro E2E runs" >&2
    exit 69
}
command -v setsid >/dev/null || {
    echo "error: setsid is required to stop interrupted preparation workers cleanly" >&2
    exit 69
}
lock_file="${TMPDIR:-/tmp}/kdockw-distro-e2e-${UID:-$(id -u)}-$target.lock"
exec {target_lock_fd}>"$lock_file"
echo "[distro] waiting for target lock: $target"
flock "$target_lock_fd"

now() { date +%s; }
run_start=$(now)

packages=/usr/local/lib/kdockw-distro/packages.sh
image="kdockw-e2e-distro:$target"
skip_image="${KDOCKW_DISTRO_SKIP_IMAGE_BUILD:-0}"

# ---------------------------------------------------------------------------
# Runtime container (background) overlapped with the package build
# ---------------------------------------------------------------------------

# The runtime image pull (or local build) and a rolling target's upgrade do
# not need the package: they run in the background while it builds, in the
# container the package is later installed into.
prep_token="$target-$$-${RANDOM}"
prep_ctr="kdockw-e2e-prep-$prep_token"
prep_pid=
prep_log=
install_log=
shard_state=

remove_prep_container() {
    local prep_ctr="$1" prep_token="$2"
    local ids
    local -a owned_ids=()
    ids="$(docker ps -aq --filter "label=org.kdockw.task-id=$prep_token")" || {
        echo "[distro] warning: cannot inspect task-owned preparation container $prep_ctr" >&2
        return 1
    }
    [[ -n "$ids" ]] || return 0
    mapfile -t owned_ids <<<"$ids"
    if ! docker rm -f "${owned_ids[@]}" >/dev/null; then
        echo "[distro] warning: cannot remove task-owned preparation container $prep_ctr" >&2
        return 1
    fi
}

prep_child_cleanup() {
    local rc=$?
    if (( rc != 0 )); then
        remove_prep_container "$KDOCKW_PREP_CONTAINER" "$KDOCKW_PREP_TOKEN" || true
    fi
    return "$rc"
}

prep_worker() {
    set -euo pipefail
    local ref="$1" prep_ctr="$2" prep_token="$3" packages="$4"
    local repo="$5" here="$6" target="$7" platform="$8" t0
    local -a worker_platform_args=()
    [[ -z "$platform" ]] || worker_platform_args=(--platform "$platform")

    trap prep_child_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    t0=$(now)
    KDOCKW_DOCKER_PLATFORM="$platform" \
        "$here/build-ci-image.sh" --pull runtime "$target" >/dev/null
    echo "[distro] runtime-image: $(($(now) - t0))s"
    t0=$(now)
    docker run -d --init --name "$prep_ctr" \
        --label "org.kdockw.task-id=$prep_token" \
        "${worker_platform_args[@]}" "$ref" sleep infinity >/dev/null
    docker exec "$prep_ctr" sh "$packages" upgrade
    echo "[distro] runtime-upgrade: $(($(now) - t0))s"
    # Prefetch declared package dependencies while the package build runs;
    # packages.sh kdockw can then install from the package-manager cache.
    t0=$(now)
    docker exec "$prep_ctr" mkdir -p /tmp/kdockw-pkgdefs
    docker cp "$repo/packaging/." "$prep_ctr:/tmp/kdockw-pkgdefs"
    docker exec -e PKGDEFS=/tmp/kdockw-pkgdefs "$prep_ctr" sh "$packages" depfetch
    echo "[distro] dep-fetch: $(($(now) - t0))s"
}

export -f now remove_prep_container prep_child_cleanup prep_worker

start_prep() {
    local ref
    ref="$(ci_image_ref runtime "$target")"
    prep_log="$(mktemp -t kdockw-distro-prep.XXXXXX)"
    KDOCKW_PREP_CONTAINER="$prep_ctr" KDOCKW_PREP_TOKEN="$prep_token" \
        setsid bash -c 'prep_worker "$@"' _ "$ref" "$prep_ctr" \
            "$prep_token" "$packages" "$repo" "$here" "$target" \
            "${KDOCKW_E2E_PLATFORM:-}" >"$prep_log" 2>&1 &
    prep_pid=$!
    runtime_ref="$ref"
}

cleanup() {
    local rc=$?
    local cleanup_rc=0
    if [[ -n "$prep_pid" ]]; then
        kill -TERM -- "-$prep_pid" 2>/dev/null || true
        wait "$prep_pid" 2>/dev/null || true
        prep_pid=
    fi
    remove_prep_container "$prep_ctr" "$prep_token" || cleanup_rc=1
    (( rc != 0 || cleanup_rc == 0 )) || rc=1
    if (( rc == 0 )); then
        rm -f "${prep_log:-}" "${install_log:-}" || rc=1
        rm -rf "${shard_state:-}" || rc=1
    else
        [[ -z "$prep_log" || ! -f "$prep_log" ]] ||
            echo "[distro] retained preparation log: $prep_log" >&2
        [[ -z "$install_log" || ! -f "$install_log" ]] ||
            echo "[distro] retained install log: $install_log" >&2
        [[ -z "$shard_state" || ! -d "$shard_state" ]] ||
            echo "[distro] retained shard status: $shard_state" >&2
    fi
    return "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Blocks until the background preparation finishes; on failure shows its
# whole output and exits with its status.
await_prep() {
    local rc=0
    wait "$prep_pid" || rc=$?
    prep_pid=
    if (( rc != 0 )); then
        cat "$prep_log" >&2 || true
        exit "$rc"
    fi
    grep -E '^\[(distro|ci-image)\]' "$prep_log" || true
}

[[ "$skip_image" == 1 ]] || start_prep

pkg_dir="$here/.cache/packages/$target"
shopt -s nullglob
pkgs=("$pkg_dir"/*.rpm "$pkg_dir"/*.deb "$pkg_dir"/*.pkg.tar.zst)
shopt -u nullglob
if [[ "${KDOCKW_DISTRO_REBUILD_PACKAGE:-0}" == 1 || ${#pkgs[@]} -eq 0 ]]; then
    t0=$(now)
    rm -rf "$pkg_dir"
    KDOCKW_DOCKER_PLATFORM="${KDOCKW_E2E_PLATFORM:-}" \
        "$here/build-package.sh" "$target" "$here/.cache/packages"
    echo "[distro] package: $(($(now) - t0))s"
fi

# ---------------------------------------------------------------------------
# Package install into the runtime container -> kdockw-e2e-distro:<target>
# ---------------------------------------------------------------------------

if [[ "$skip_image" != 1 ]]; then
    t0=$(now)
    await_prep
    echo "[distro] runtime-wait: $(($(now) - t0))s"

    t0=$(now)
    install_log="$(mktemp -t kdockw-distro-install.XXXXXX)"
    if ! {
        docker cp "$pkg_dir/." "$prep_ctr:/pkgs" &&
            docker exec "$prep_ctr" sh -c "sh $packages kdockw && rm -rf /pkgs"
    } >"$install_log" 2>&1; then
        cat "$install_log" >&2
        exit 1
    fi
    echo "[distro] package-install: $(($(now) - t0))s"

    # The container runs `sleep infinity`; give the image back the runtime
    # image's CMD (run-e2e.sh passes its own command anyway).
    t0=$(now)
    changes=(--change 'WORKDIR /work')
    cmd="$(docker image inspect --format '{{json .Config.Cmd}}' "$runtime_ref")"
    [[ "$cmd" == null ]] || changes+=(--change "CMD $cmd")
    docker commit "${changes[@]}" "$prep_ctr" "$image" >/dev/null
    remove_prep_container "$prep_ctr" "$prep_token"
    echo "[distro] image-commit: $(($(now) - t0))s"
elif ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "error: KDOCKW_DISTRO_SKIP_IMAGE_BUILD=1 but there is no image $image" >&2
    exit 1
fi

# Keep the final per-target image as the reusable installed test environment.
# CI base/builder/runtime images, package/ccache outputs, and BuildKit cache are
# also reusable; this installed-binary path mounts no named build volume.

export KDOCKW_E2E_IMAGE="$image"
export KDOCKW_E2E_SKIP_BUILD=1
export KDOCKW_E2E_BINARY=/usr/bin/kdockw
export KDOCKW_E2E_DISTRO="$target"
export KDOCKW_E2E_ARTIFACTS="${KDOCKW_E2E_ARTIFACTS:-$repo/tests/appium/artifacts-distro-$target}"

# A caller may intentionally point different targets at the same artifact
# directory. Lock its canonical path before run-e2e.sh clears or writes there.
artifact_path="$(realpath -m -- "$KDOCKW_E2E_ARTIFACTS")"
artifact_key="$(printf '%s' "$artifact_path" | sha256sum | cut -c1-16)"
artifact_lock_file="${TMPDIR:-/tmp}/kdockw-distro-e2e-${UID}-artifacts-$artifact_key.lock"
exec {artifact_lock_fd}>"$artifact_lock_file"
echo "[distro] waiting for artifact lock"
flock "$artifact_lock_fd"

# ---------------------------------------------------------------------------
# Suite run: single container, or KDOCKW_E2E_SHARDS shards concurrently
# ---------------------------------------------------------------------------

shards="${KDOCKW_E2E_SHARDS:-1}"
[[ "$shards" =~ ^[0-9]+$ ]] && (( shards >= 1 )) || {
    echo "error: KDOCKW_E2E_SHARDS must be a positive integer (got '$shards')" >&2
    exit 64
}

suite_start=$(now)
finish() {
    echo "[distro] suite: $(($(now) - suite_start))s"
    echo "[distro] total: $(($(now) - run_start))s"
    exit "$1"
}

if (( shards == 1 )); then
    rc=0
    "$repo/tests/appium/run-e2e.sh" "$@" || rc=$?
    finish "$rc"
fi

# An interactive debug shell cannot be sharded.
for arg in "$@"; do
    [[ "$arg" != --shell ]] || {
        echo "error: --shell cannot be sharded (KDOCKW_E2E_SHARDS=$shards)" >&2
        exit 64
    }
done

# Each shard: one run-e2e.sh (one container, own kwin session) selecting
# KDOCKW_E2E_SHARD=i/N and writing to <artifacts>/shard-<i>. This distro path
# sets KDOCKW_E2E_BINARY, so run-e2e.sh does not mount a build volume. Status
# goes to a file (the output pipeline would mask it);
# stdout/stderr is prefixed so the shards' lines stay distinguishable.
rm -rf "$KDOCKW_E2E_ARTIFACTS"
mkdir -p "$KDOCKW_E2E_ARTIFACTS"
shard_dir="$(mktemp -d -t kdockw-e2e-shards.XXXXXX)"
shard_state="$shard_dir"
# Split the CPUs between the shards' llvmpipe renderers (kwin and kdockw);
# by default each would start one thread per CPU and oversubscribe them.
threads=$(($(getconf _NPROCESSORS_ONLN) / shards))
((threads >= 1)) || threads=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-$threads}"

for (( i = 0; i < shards; i++ )); do
    (
        export KDOCKW_E2E_SHARD="$i/$shards"
        export KDOCKW_E2E_ARTIFACTS="$KDOCKW_E2E_ARTIFACTS/shard-$i"
        [[ -z "${KDOCKW_E2E_VOLUME:-}" ]] ||
            export KDOCKW_E2E_VOLUME="${KDOCKW_E2E_VOLUME}-shard-$i"
        "$repo/tests/appium/run-e2e.sh" "$@" 2>&1
        echo "$?" >"$shard_dir/rc.$i"
    ) | awk -v s="$i" '{ print "[shard " s "] " $0; fflush() }' &
done

wait

rc=0
for (( i = 0; i < shards; i++ )); do
    shard_rc="missing"
    [[ -f "$shard_dir/rc.$i" ]] && shard_rc="$(<"$shard_dir/rc.$i")"
    [[ "$shard_rc" == 0 ]] || rc=1
done
finish "$rc"
