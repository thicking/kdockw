#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

# source_version <CMakeLists.txt> -> canonical KDOCKW_VERSION
# This file may be sourced by package scripts or executed by CI to print the
# version. Keep both interfaces in sync by delegating the CLI to the function.
source_version() {
    awk -F '"' '/^set\(KDOCKW_VERSION "/ { print $2; exit }' "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "usage: $0 <CMakeLists.txt>" >&2
        exit 64
    fi
    source_version "$1"
fi
