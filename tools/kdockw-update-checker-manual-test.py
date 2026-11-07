#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 KDockW Contributors

"""Run a diagnostic KDockW build against a loopback-only fake Releases API."""

from __future__ import annotations

import argparse
from collections.abc import Mapping
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BINARY = ROOT / "build/update-checker-notification-e2e/bin/kdockw"
DEFAULT_STATE = ROOT / "diagnostics/update-checker-notification-e2e"
API_PATH = "/repos/thicking/kdockw/releases"
DESKTOP_ID = "kdockw-update-checker-notification-e2e"
DESKTOP_STORAGE_ID = f"{DESKTOP_ID}.desktop"
WAYLAND_INTERFACES = "org_kde_plasma_window_management,zkde_screencast_unstable_v1"
DEFAULT_XDG_DATA_DIRS = "/usr/local/share:/usr/share"
SESSION_REQUIRED = (
    "XDG_RUNTIME_DIR",
    "WAYLAND_DISPLAY",
    "DBUS_SESSION_BUS_ADDRESS",
    "XDG_CURRENT_DESKTOP",
    "KDE_SESSION_VERSION",
)
PLASMA_ENVIRONMENT_KEYS = frozenset(
    SESSION_REQUIRED
    + (
        "XDG_DATA_HOME",
        "XDG_DATA_DIRS",
        "XDG_CONFIG_HOME",
        "XDG_CONFIG_DIRS",
        "XDG_CACHE_HOME",
    )
)
LAUNCHED_PROCESS_ENVIRONMENT_KEYS = frozenset(
    PLASMA_ENVIRONMENT_KEYS
    | {
        "KDOCKW_DIAGNOSTIC_CONFIG",
        "KDOCKW_DIAGNOSTIC_RELEASE_MOCK",
        "KDOCKW_DIAGNOSTIC_RELEASE_API_URL",
        "KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG",
    }
)


def running_kdockw_pids() -> list[int]:
    result = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if (proc / "comm").read_text(encoding="utf-8").strip() == "kdockw":
                result.append(int(proc.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return result


def require_no_running_kdockw(pids: list[int]) -> None:
    if pids:
        raise RuntimeError("another KDockW is already running (PID(s): " + ", ".join(map(str, pids)) + ")")


def verify_launched_process(pid: int, binary: Path, expected_environment: Mapping[str, str]) -> None:
    """Verify executable and only the required session/mock vars via /proc."""
    proc = Path(f"/proc/{pid}")
    try:
        actual_binary = (proc / "exe").resolve()
        raw_environment = (proc / "environ").read_bytes()
    except OSError as error:
        raise RuntimeError(f"cannot inspect diagnostic process {pid}: {error}") from error
    if actual_binary != binary:
        raise RuntimeError(f"started process {pid} has unexpected executable: {actual_binary}")

    actual: dict[str, str] = {}
    for item in raw_environment.split(b"\0"):
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        name = key.decode("ascii", errors="ignore")
        if name in LAUNCHED_PROCESS_ENVIRONMENT_KEYS:
            actual[name] = value.decode("utf-8", errors="replace")
    mismatched = [
        name for name in LAUNCHED_PROCESS_ENVIRONMENT_KEYS
        if name in expected_environment and actual.get(name) != expected_environment[name]
    ]
    if mismatched:
        raise RuntimeError("diagnostic process environment mismatch for: " + ", ".join(sorted(mismatched)))


def make_release(version: str) -> bytes:
    return json.dumps(
        [
            {
                "url": f"https://api.github.com/repos/thicking/kdockw/releases/{version}",
                "assets_url": f"https://api.github.com/repos/thicking/kdockw/releases/{version}/assets",
                "upload_url": f"https://uploads.github.com/repos/thicking/kdockw/releases/{version}/assets{{?name,label}}",
                "html_url": f"https://github.com/thicking/kdockw/releases/tag/kdockw-v{version}",
                "id": 900000000 + int(version.rsplit(".", 1)[1]),
                "tag_name": f"kdockw-v{version}",
                "target_commitish": "main",
                "name": f"KDockW v{version} (local test fixture)",
                "draft": False,
                "prerelease": False,
                "created_at": "2026-11-07T00:00:00Z",
                "published_at": "2026-11-07T00:00:00Z",
                "assets": [],
                "tarball_url": f"https://api.github.com/repos/thicking/kdockw/tarball/kdockw-v{version}",
                "zipball_url": f"https://api.github.com/repos/thicking/kdockw/zipball/kdockw-v{version}",
                "body": "Local notification test fixture. No release was created on GitHub.",
            }
        ],
        separators=(",", ":"),
    ).encode("utf-8")


def desktop_exec_token(path: Path) -> str:
    escaped = str(path).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"' if any(char.isspace() for char in str(path)) else escaped


def diagnostic_desktop_entry(binary: Path) -> str:
    """Register KWin permissions without overriding KDockW's runtime desktop ID."""
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=KDockW Update Checker E2E\n"
        "NoDisplay=true\n"
        "Terminal=false\n"
        f"Exec={desktop_exec_token(binary)}\n"
        f"X-KDE-Wayland-Interfaces={WAYLAND_INTERFACES}\n"
    )


def ensure_diagnostic_desktop_metadata(
    binary: Path, user_data_home: Path, checker: Path, environment: Mapping[str, str]
) -> Path:
    """Reuse the existing launcher pattern: exact Exec, KWin grants, KService check."""
    desktop_file = user_data_home / "applications" / DESKTOP_STORAGE_ID
    contents = diagnostic_desktop_entry(binary)
    if desktop_file.exists():
        if desktop_file.read_text(encoding="utf-8") != contents:
            raise RuntimeError(f"refusing to overwrite a different diagnostic desktop entry: {desktop_file}")
    else:
        desktop_file.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(desktop_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(descriptor, "w", encoding="utf-8") as entry:
            entry.write(contents)
    subprocess.run(["desktop-file-validate", str(desktop_file)], check=True, env=dict(environment))
    subprocess.run(["kbuildsycoca6"], check=True, env=dict(environment))
    subprocess.run([str(checker), str(binary), DESKTOP_STORAGE_ID], check=True, env=dict(environment))
    return desktop_file


def terminate_on_sigterm(_signum: int, _frame: object) -> None:
    raise KeyboardInterrupt


def parse_environment(text: str) -> dict[str, str]:
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def active_plasmashell_environment(expected_runtime_dir: Path) -> dict[str, str]:
    """Read only session/XDG variables from this user's plasmashell process."""
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / "comm").read_text(encoding="utf-8").strip() != "plasmashell":
                continue
            values: dict[str, str] = {}
            for item in (proc / "environ").read_bytes().split(b"\0"):
                if b"=" not in item:
                    continue
                key, value = item.split(b"=", 1)
                name = key.decode("ascii", errors="ignore")
                if name in PLASMA_ENVIRONMENT_KEYS:
                    values[name] = value.decode("utf-8", errors="replace")
            if Path(values.get("XDG_RUNTIME_DIR", "/nonexistent")).resolve() == expected_runtime_dir.resolve():
                return values
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return {}


def resolve_plasma_environment(
    manager: Mapping[str, str],
    *,
    plasma: Mapping[str, str] | None = None,
    home: Path,
    expected_runtime_dir: Path,
    socket_is_available=lambda path: path.is_socket(),
) -> dict[str, str]:
    """Use live Plasma values for session/XDG paths and manager values as fallback."""
    session = dict(manager)
    for name, value in (plasma or {}).items():
        if name in PLASMA_ENVIRONMENT_KEYS and value:
            session[name] = value
    missing = [name for name in SESSION_REQUIRED if not session.get(name)]
    if missing:
        raise RuntimeError("Plasma/systemd session lacks required variable(s): " + ", ".join(missing))

    runtime = Path(session["XDG_RUNTIME_DIR"]).resolve()
    if runtime != expected_runtime_dir.resolve():
        raise RuntimeError("resolved runtime directory is not this user's session")
    if "KDE" not in session["XDG_CURRENT_DESKTOP"].split(":") or session["KDE_SESSION_VERSION"] != "6":
        raise RuntimeError("resolved environment is not KDE Plasma 6")
    wayland_socket = runtime / session["WAYLAND_DISPLAY"]
    if not socket_is_available(wayland_socket):
        raise RuntimeError("the active Plasma Wayland socket is unavailable")
    expected_bus = f"unix:path={runtime}/bus"
    if not session["DBUS_SESSION_BUS_ADDRESS"].startswith(expected_bus):
        raise RuntimeError("resolved environment is not attached to this user's D-Bus session")

    # Apply XDG specification defaults when the manager omitted optional paths.
    # Never substitute terminal XDG paths: they may belong to another shell setup.
    session.setdefault("XDG_DATA_HOME", str(home / ".local/share"))
    session.setdefault("XDG_CONFIG_HOME", str(home / ".config"))
    session.setdefault("XDG_CACHE_HOME", str(home / ".cache"))
    session.setdefault("XDG_CONFIG_DIRS", "/etc/xdg")
    if not session.get("XDG_DATA_DIRS"):
        session["XDG_DATA_DIRS"] = DEFAULT_XDG_DATA_DIRS
    session.setdefault("HOME", str(home))
    session.setdefault("PATH", os.environ.get("PATH", os.defpath))
    return session


def validate_plasma_session() -> dict[str, str]:
    """Return a validated Plasma environment from the user manager, not the shell."""
    runtime_dir = Path(f"/run/user/{os.getuid()}")
    # A terminal may have stale or customized XDG variables. Pin only this
    # systemctl query to the current user's standard manager bus/runtime path.
    manager_query_environment = os.environ.copy()
    manager_query_environment["XDG_RUNTIME_DIR"] = str(runtime_dir)
    manager_query_environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime_dir}/bus"
    result = subprocess.run(
        ["systemctl", "--user", "show-environment"],
        check=True,
        capture_output=True,
        text=True,
        env=manager_query_environment,
    )
    manager = parse_environment(result.stdout)
    plasma = active_plasmashell_environment(runtime_dir)
    return resolve_plasma_environment(manager, plasma=plasma, home=Path.home(), expected_runtime_dir=runtime_dir)


def start_local_release_mock() -> tuple[ThreadingHTTPServer, threading.Thread]:
    """Bind only to loopback; any bind/start failure must abort before KDockW launches."""
    server = ThreadingHTTPServer(("127.0.0.1", 0), ReleasesHandler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, name="kdockw-release-mock", daemon=True)
    thread.start()
    return server, thread


def diagnostic_process_environment(
    plasma_environment: Mapping[str, str], config_file: Path, opened_log: Path, data_dir: Path, api_url: str
) -> dict[str, str]:
    """Add only the diagnostic config/mock paths to the active Plasma environment."""
    environment = dict(plasma_environment)
    environment["KDOCKW_DIAGNOSTIC_CONFIG"] = str(config_file)
    environment["KDOCKW_DIAGNOSTIC_RELEASE_MOCK"] = "1"
    environment["KDOCKW_DIAGNOSTIC_RELEASE_API_URL"] = api_url
    environment["KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG"] = str(opened_log)
    existing_data_dirs = environment.get("XDG_DATA_DIRS", DEFAULT_XDG_DATA_DIRS)
    environment["XDG_DATA_DIRS"] = str(data_dir) + os.pathsep + existing_data_dirs
    return environment


class ReleasesHandler(BaseHTTPRequestHandler):
    server_version = "KDockWLocalReleasesMock/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path != API_PATH:
            self.send_error(404)
            return

        version = self.headers.get("X-KDockW-Diagnostic-Release", "0.3.1")
        if version not in {"0.3.1", "0.3.2"}:
            self.send_error(400)
            return

        etag = f'"kdockw-local-{version}"'
        print(f"[local mock] GET {API_PATH}: returning {version}", flush=True)
        if self.headers.get("If-None-Match") == etag:
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        body = make_release(version)
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.github+json; charset=utf-8")
        self.send_header("ETag", etag)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string: str, *args: object) -> None:
        # Keep the log limited to endpoint/status lines; never print request headers.
        print(f"[local mock] {format_string % args}", flush=True)


def run_diagnostic_session(
    binary: Path, state_dir: Path, reset_state: bool, plasma_environment: Mapping[str, str]
) -> int:
    config_file = state_dir / "kdockwrc"
    opened_log = state_dir / "opened-release-urls.log"
    data_dir = state_dir / "data"
    notifyrc_dir = data_dir / "knotifications6"
    notifyrc_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "src/kdockw.notifyrc", notifyrc_dir / "kdockw.notifyrc")
    if reset_state:
        for path in (config_file, opened_log):
            path.unlink(missing_ok=True)
    if not config_file.exists():
        config_file.write_text(
            "[General]\nLanguage=ru\nCheckForUpdatesAutomatically=true\nNotifyAboutUpdates=true\n",
            encoding="utf-8",
        )

    server, server_thread = start_local_release_mock()

    api_url = f"http://127.0.0.1:{server.server_port}{API_PATH}"
    environment = diagnostic_process_environment(plasma_environment, config_file, opened_log, data_dir, api_url)
    print(f"Running diagnostic KDockW: {binary}")
    print("Runtime Desktop ID: com.thicking.kdockw (the standard KDockW identity)")
    print(f"Isolated config and checker state: {config_file}")
    print(f"Mock-only API: {environment['KDOCKW_DIAGNOSTIC_RELEASE_API_URL']}")
    print(f"Diagnostic notification metadata: {notifyrc_dir / 'kdockw.notifyrc'}")
    print(f"Release-open action log: {opened_log}")
    print("The mock serves only stable fixtures 0.3.1 and 0.3.2 on 127.0.0.1. Close KDockW normally to exit.", flush=True)

    runner = None
    old_sigterm_handler = signal.signal(signal.SIGTERM, terminate_on_sigterm)
    try:
        runner = subprocess.Popen([str(binary)], env=environment)
        verify_launched_process(runner.pid, binary, environment)
        print(f"Verified process {runner.pid}: diagnostic config/mock and Plasma session environment match.", flush=True)
        return runner.wait()
    except KeyboardInterrupt:
        if runner and runner.poll() is None:
            runner.send_signal(signal.SIGINT)
            try:
                runner.wait(timeout=5)
            except subprocess.TimeoutExpired:
                runner.terminate()
        return 130
    finally:
        if runner and runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=5)
            except subprocess.TimeoutExpired:
                runner.kill()
                runner.wait(timeout=5)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=2)
        signal.signal(signal.SIGTERM, old_sigterm_handler)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY, help="diagnostic KDockW executable")
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE, help="private local diagnostic state directory")
    parser.add_argument("--reset-state", action="store_true", help="remove only this test's config and URL log before launch")
    args = parser.parse_args()

    binary = args.binary.expanduser().resolve()
    state_dir = args.state_dir.expanduser().resolve()
    build_dir = binary.parent.parent
    cache = build_dir / "CMakeCache.txt"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error(f"diagnostic binary not found or not executable: {binary}")
    if not cache.is_file() or "KDOCKW_DIAGNOSTIC_BUILD:BOOL=ON" not in cache.read_text(encoding="utf-8", errors="replace"):
        parser.error(f"refusing to run a binary not configured with KDOCKW_DIAGNOSTIC_BUILD=ON: {build_dir}")

    metadata_checker = build_dir / "bin/kdockw_diagnostic_metadata_check"
    if not metadata_checker.is_file() or not os.access(metadata_checker, os.X_OK):
        parser.error(f"KService metadata checker is missing or not executable: {metadata_checker}")

    try:
        plasma_environment = validate_plasma_session()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"Refusing to launch outside the active Plasma session: {error}", file=sys.stderr)
        return 2

    try:
        require_no_running_kdockw(running_kdockw_pids())
    except RuntimeError as error:
        print(f"Refusing to start another KDockW. Stop the current instance yourself first; {error}", file=sys.stderr)
        return 2

    try:
        user_data_home = Path(plasma_environment["XDG_DATA_HOME"]).expanduser().resolve()
        desktop_file = ensure_diagnostic_desktop_metadata(binary, user_data_home, metadata_checker, plasma_environment)
        print(f"KWin permission metadata registered by KService: {desktop_file}")
        return run_diagnostic_session(binary, state_dir, args.reset_state, plasma_environment)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Diagnostic launch refused or failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
