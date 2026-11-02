#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Starts the real kdockw binary with the given arguments on the private
# KWin/session-bus session provided by run-with-kwin.sh and checks the desktop
# file name it ends up with (com.thicking.kdockw by default; --desktopfile, which
# `kdockw --help` advertises, must override it). KDBusService exports the
# application object, so QGuiApplication::desktopFileName is read over D-Bus.
#
# Usage: desktop-file-name.sh <kdockw-binary> <expected-desktop-file-name> [kdockw args...]

set -eu

bin=$1
expected=$2
shift 2

"$bin" "$@" >/dev/null 2>&1 &
pid=$!
cleanup() {
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' INT TERM

tries=0
while ! busctl --user list 2>/dev/null | grep -q 'com\.thicking\.kdockw'; do
    tries=$((tries + 1))
    if [ "$tries" -gt 300 ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "kdockw did not register com.thicking.kdockw" >&2
        exit 1
    fi
    sleep 0.1
done

got=$(busctl --user get-property com.thicking.kdockw /MainApplication \
    org.qtproject.Qt.QGuiApplication desktopFileName)
if [ "$got" != "s \"$expected\"" ]; then
    echo "expected: s \"$expected\"" >&2
    echo "got:      $got" >&2
    exit 1
fi
echo "$got"
