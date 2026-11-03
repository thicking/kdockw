#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

# source_version <CMakeLists.txt> -> canonical KDOCKW_VERSION
source_version() {
    awk -F '"' '/^set\(KDOCKW_VERSION "/ { print $2; exit }' "$1"
}
