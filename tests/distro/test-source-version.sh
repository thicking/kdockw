#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
# shellcheck source=tests/distro/source-version.sh
. "$script_dir/source-version.sh"

for version in 0.1.0-dev 0.1.0; do
    cmake_file="$tmpdir/CMakeLists.txt"
    printf 'set(KDOCKW_VERSION "%s")\n' "$version" > "$cmake_file"
    actual="$(source_version "$cmake_file")"
    [[ "$actual" == "$version" ]] || {
        echo "expected canonical version '$version', got '$actual'" >&2
        exit 1
    }
done
