#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Starts the real kdockw binary with a standard Qt option (-platform wayland,
# which must still be accepted) on the private KWin/session-bus session
# provided by run-with-kwin.sh, waits until it owns com.thicking.kdockw on the
# bus, then runs a second `kdockw --version`: it must print the version and
# exit 0 without being swallowed by the first instance's KDBusService, and
# the first instance must keep running.
#
# Usage: version-while-running.sh <kdockw-binary> <expected-version-string>

set -eu

bin=$1
expected=$2

terminate() {
    target_pid=$1
    kill -TERM "$target_pid" 2>/dev/null || true
    tries=0
    while kill -0 "$target_pid" 2>/dev/null; do
        state=$(ps -o stat= -p "$target_pid" 2>/dev/null || true)
        case $state in
            "" | Z*) break ;;
        esac
        tries=$((tries + 1))
        if [ "$tries" -ge 50 ]; then
            kill -KILL "$target_pid" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
    wait "$target_pid" 2>/dev/null || true
}

"$bin" -platform wayland >/dev/null 2>&1 &
pid=$!
cleanup() {
    terminate "$pid"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

tries=0
while ! timeout --kill-after=1s 2s busctl --user list 2>/dev/null | grep -q 'com\.thicking\.kdockw'; do
    tries=$((tries + 1))
    if [ "$tries" -gt 300 ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "first kdockw instance did not register com.thicking.kdockw" >&2
        exit 1
    fi
    sleep 0.1
done

out=$(timeout --kill-after=2s 15s "$bin" --version)

if ! kill -0 "$pid" 2>/dev/null; then
    echo "first instance exited while --version ran" >&2
    exit 1
fi

if [ "$out" != "$expected" ]; then
    echo "expected: $expected" >&2
    echo "got:      $out" >&2
    exit 1
fi

echo "$out"
