#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

# Debian family build (debian, ubuntu) using packaging/obs/debian.* inside the
# target's builder image. Invoked by in-container.sh after the build deps are
# installed; dpkg-buildpackage re-checks Build-Depends with their versions.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Unpack the source tarball and drop the OBS debian.* files in as debian/.
src="/work/kdockw-${KDOCKW_VERSION}"
tar -xzf "/stage/kdockw-${KDOCKW_VERSION}.tar.gz" -C /work
mkdir -p "$src/debian"
install -m644 /pkg/packaging/obs/debian.control "$src/debian/control"
install -m644 /pkg/packaging/obs/debian.changelog "$src/debian/changelog"
install -m644 /pkg/packaging/obs/debian.copyright "$src/debian/copyright"
install -m755 /pkg/packaging/obs/debian.rules "$src/debian/rules"

cd "$src"
# The automatic dbgsym package stays on: dh_strip only adds the
# .gnu_debuglink section to the shipped binary when it saves the debug
# symbols, so noautodbgsym would change the tested binary.
if [[ "${KDOCKW_DIAGNOSTIC_DEBUG_SYMBOLS:-0}" == 1 ]]; then
    # Keep the normal Release optimization/packaging path but retain compiler
    # debug sections for one explicitly targeted crash-diagnostic package.
    DEB_BUILD_OPTIONS=nostrip dpkg-buildpackage -b -us -uc
else
    dpkg-buildpackage -b -us -uc
fi

# Artifacts land in the parent of the source tree (/work). Ship the binary
# .deb only; the dbgsym package (kdockw-dbgsym_*.ddeb/.deb) is never installed.
shopt -s nullglob
artifacts=(/work/kdockw_*.deb)
if (( ${#artifacts[@]} == 0 )); then
    echo "error: dpkg-buildpackage finished but produced no .deb" >&2
    exit 70
fi
cp "${artifacts[@]}" /out/
binary=$(mktemp -d /tmp/kdockw-package-locale.XXXXXX)
trap 'rm -rf "$binary"' EXIT
dpkg-deb -x "${artifacts[0]}" "$binary"
python3 "$src/tests/distro/check_package_locale.py" "$binary" "$KDOCKW_VERSION"
if [[ "${KDOCKW_DIAGNOSTIC_DEBUG_SYMBOLS:-0}" == 1 ]]; then
    if ! readelf -S "$binary/usr/bin/kdockw" | grep -q '\.debug_info'; then
        echo "error: diagnostic Debian package does not contain .debug_info" >&2
        exit 71
    fi
    echo "diagnostic debug sections verified in ${artifacts[0]}"
fi
ls -l /out
