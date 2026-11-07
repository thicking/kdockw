# Release Update Checker

KDockW checks the public GitHub Releases API asynchronously through Qt Network.
The singleton is owned by `Application`, so dock surfaces and the independent
settings QML engine share one request and one result. The checker starts at
most once at application startup and persists its automatic-attempt timestamp;
manual checks bypass that 24-hour interval but never duplicate an in-flight
request.

## HTTP and cache rules

- Production requests use only
  `https://api.github.com/repos/thicking/kdockw/releases` and never attach an
  authentication token.
- Qt's transfer timeout is 15 seconds. The decoded response is capped at
  1 MiB, and only HTTP 200 or a cache-backed HTTP 304 is considered successful.
- Requests include `If-None-Match` when a GitHub ETag is stored. A 304 reuses
  the previously validated release result.
- Redirects are limited to the same origin. The API response's `html_url` is
  accepted only when it exactly matches the canonical KDockW release URL for
  its `kdockw-vX.Y.Z` tag.
- HTTP 403/429 responses honor `Retry-After` or `X-RateLimit-Reset`; absent a
  usable header, manual retries are held for one hour. Failures never advance
  the successful-check timestamp.

The local HTTP endpoint accepted by the C++ constructor exists for tests only;
it is restricted to loopback. Automated tests do not contact GitHub.

## Release and version selection

Only non-draft, non-prerelease tags matching `kdockw-vX.Y.Z` are candidates.
Krema tags and malformed or unrelated tag names are ignored. Components are
compared numerically, not lexicographically. Installed `X.Y.Z-dev` versions
are treated as prereleases below the corresponding stable `X.Y.Z`, so the
matching stable release is offered. Equal or older versions are not announced.

## KDE notifications

Notifications use KF6 KNotifications. The `kdockw.notifyrc` file
defines the low-urgency popup event and is installed under
`knotifications6/` using ECM's `${KDE_INSTALL_KNOTIFYRCDIR}`. The notification
action opens only the canonical release URL. KDockW does not change Plasma's
Do Not Disturb setting.

The UI preferences, latest validated release, ETag, successful check time,
automatic attempt time, notification deduplication version, and rate-limit
backoff use the existing KConfigXT `General` group in `kdockwrc`.

## Manual KDE notification test

The diagnostic build has an opt-in notification test panel in Settings → About.
It is enabled only when `KDOCKW_DIAGNOSTIC_BUILD=ON` and
`KDOCKW_DIAGNOSTIC_RELEASE_MOCK=1` are set. The endpoint must be an HTTP URL
bound to the literal loopback address `127.0.0.1` or `::1` and use the Releases
API path. An invalid or missing endpoint fails closed; it never falls back to
GitHub while mock mode is selected. Production builds ignore these variables
and always use the canonical GitHub API endpoint.

`tools/kdockw-update-checker-manual-test.py` starts a loopback-only HTTP mock
and a diagnostic binary together. Before launch, it registers a separate
KService desktop entry with the exact diagnostic executable and KWin Wayland
interfaces, then verifies that KService resolves it. It does not pass
`--desktopfile`, so KDockW keeps its runtime Desktop ID `com.thicking.kdockw`.
The candidate runs directly as a child process; it does not create a systemd
unit. Its two fixtures are stable releases
`kdockw-v0.3.1` and `kdockw-v0.3.2`; requests select one through a diagnostic
header. The application uses a separate
`diagnostics/update-checker-notification-e2e/kdockwrc`
file for all settings and checker state, including ETag and notification
deduplication. It does not redirect `XDG_CONFIG_HOME` or `XDG_DATA_HOME`, and
does not change the user's `kdockwrc`. The launcher takes session and XDG
paths from the active `plasmashell` process, using the user systemd manager as
fallback; it never requires terminal XDG values to match. KService indexing
and verification use that resolved session environment. The launcher adds one
diagnostic data directory to the candidate process's `XDG_DATA_DIRS` so
KNotifications can load the test `kdockw.notifyrc`; the shell and Plasma
manager environments are not modified. Immediately after spawn, it verifies
the diagnostic executable and an allowlist of session/mock variables through
`/proc/<pid>` without printing their values.

In mock mode, the notification action is still a real KF6 KNotifications
action, but opening the release is intercepted after canonical URL validation
and appended to `opened-release-urls.log`. No browser is started. The launcher
refuses to run if another `kdockw` process exists. Do not run the test against
a currently running dock; close it manually first, then run:

```sh
cmake -S . -B build/update-checker-notification-e2e \
  -DCMAKE_BUILD_TYPE=Release -DKDOCKW_DIAGNOSTIC_BUILD=ON -DBUILD_TESTING=ON
cmake --build build/update-checker-notification-e2e --parallel
ctest --test-dir build/update-checker-notification-e2e --output-on-failure
python3 tools/kdockw-update-checker-manual-test.py --reset-state
```

The reset option removes only this test's own config and action log. Exit the
candidate with Ctrl+C in the launching terminal. The next run without
`--reset-state` preserves the diagnostic deduplication history.
