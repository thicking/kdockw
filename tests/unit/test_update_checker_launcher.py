#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Regression tests for the local Update Checker diagnostic launcher."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER_PATH = ROOT / "tools/kdockw-update-checker-manual-test.py"
SPEC = importlib.util.spec_from_file_location("kdockw_update_checker_manual_test", LAUNCHER_PATH)
assert SPEC and SPEC.loader
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class PlasmaEnvironmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.home = Path("/home/tester")
        self.runtime = Path("/run/user/1000")
        self.manager = {
            "XDG_RUNTIME_DIR": str(self.runtime),
            "WAYLAND_DISPLAY": "wayland-0",
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path={self.runtime}/bus",
            "XDG_CURRENT_DESKTOP": "KDE",
            "KDE_SESSION_VERSION": "6",
            "XDG_DATA_DIRS": "/opt/plasma/share:/usr/local/share:/usr/share",
            "XDG_CONFIG_DIRS": "/etc/xdg",
        }

    def resolve(self, plasma: dict[str, str] | None = None) -> dict[str, str]:
        return launcher.resolve_plasma_environment(
            self.manager,
            plasma=plasma,
            home=self.home,
            expected_runtime_dir=self.runtime,
            socket_is_available=lambda _path: True,
        )

    def test_matching_terminal_and_manager_xdg_values(self) -> None:
        resolved = self.resolve()
        self.assertEqual(resolved["XDG_DATA_DIRS"], self.manager["XDG_DATA_DIRS"])

    def test_different_terminal_xdg_data_dirs_do_not_override_manager(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_DATA_DIRS": "/terminal/only/share"}):
            resolved = self.resolve()
        self.assertEqual(resolved["XDG_DATA_DIRS"], self.manager["XDG_DATA_DIRS"])

    def test_unset_terminal_xdg_values_do_not_block_launch(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            resolved = self.resolve()
        self.assertEqual(resolved["XDG_DATA_DIRS"], self.manager["XDG_DATA_DIRS"])

    def test_missing_optional_manager_data_dirs_use_xdg_default(self) -> None:
        self.manager.pop("XDG_DATA_DIRS")
        self.assertEqual(self.resolve()["XDG_DATA_DIRS"], launcher.DEFAULT_XDG_DATA_DIRS)

    def test_missing_manager_value_is_filled_from_live_plasma(self) -> None:
        self.manager.pop("WAYLAND_DISPLAY")
        plasma = {"WAYLAND_DISPLAY": "wayland-0", "XDG_DATA_DIRS": "/plasma/share:/usr/share"}
        resolved = self.resolve(plasma)
        self.assertEqual(resolved["WAYLAND_DISPLAY"], "wayland-0")
        self.assertEqual(resolved["XDG_DATA_DIRS"], "/plasma/share:/usr/share")

    def test_missing_required_value_in_manager_and_plasma_is_rejected(self) -> None:
        self.manager.pop("WAYLAND_DISPLAY")
        with self.assertRaisesRegex(RuntimeError, "WAYLAND_DISPLAY"):
            self.resolve({})

    def test_live_plasma_xdg_values_override_stale_manager_values(self) -> None:
        plasma = {"XDG_DATA_DIRS": "/plasma/share:/usr/share"}
        self.assertEqual(self.resolve(plasma)["XDG_DATA_DIRS"], "/plasma/share:/usr/share")

    def test_unavailable_wayland_socket_is_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Wayland socket"):
            launcher.resolve_plasma_environment(
                self.manager,
                home=self.home,
                expected_runtime_dir=self.runtime,
                socket_is_available=lambda _path: False,
            )


class DesktopMetadataTests(unittest.TestCase):
    def test_diagnostic_entry_has_exact_binary_and_kwin_interfaces(self) -> None:
        binary = Path("/tmp/build with spaces/kdockw")
        entry = launcher.diagnostic_desktop_entry(binary)
        self.assertIn(f'Exec="{binary}"', entry)
        self.assertIn("X-KDE-Wayland-Interfaces=" + launcher.WAYLAND_INTERFACES, entry)

    def test_kservice_failure_aborts_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            with mock.patch.object(launcher.subprocess, "run", side_effect=[None, None, subprocess.CalledProcessError(1, "checker")]):
                with self.assertRaises(subprocess.CalledProcessError):
                    launcher.ensure_diagnostic_desktop_metadata(
                        Path("/tmp/kdockw"), home, Path("/tmp/metadata-check"), {"PATH": os.environ.get("PATH", "")}
                    )
            self.assertTrue((home / "applications" / launcher.DESKTOP_STORAGE_ID).is_file())

    def test_already_running_processes_are_refused(self) -> None:
        launcher.require_no_running_kdockw([])
        with self.assertRaisesRegex(RuntimeError, r"PID\(s\): 1234"):
            launcher.require_no_running_kdockw([1234])

    def test_launched_process_executable_and_environment_are_verified(self) -> None:
        environment = {
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "XDG_DATA_DIRS": "/tmp/isolated-data:/usr/share",
            "KDOCKW_DIAGNOSTIC_CONFIG": "/tmp/isolated/kdockwrc",
            "KDOCKW_DIAGNOSTIC_RELEASE_MOCK": "1",
        }
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(2)"], env={**os.environ, **environment})
        try:
            launcher.verify_launched_process(child.pid, Path(sys.executable).resolve(), environment)
            with self.assertRaisesRegex(RuntimeError, "KDOCKW_DIAGNOSTIC_RELEASE_MOCK"):
                launcher.verify_launched_process(
                    child.pid,
                    Path(sys.executable).resolve(),
                    {**environment, "KDOCKW_DIAGNOSTIC_RELEASE_MOCK": "0"},
                )
        finally:
            child.terminate()
            child.wait(timeout=2)

    def test_direct_launch_preserves_standard_runtime_identity_and_plasma_environment(self) -> None:
        plasma_environment = {
            "XDG_DATA_DIRS": "/plasma/share:/usr/share",
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "WAYLAND_DISPLAY": "wayland-0",
        }
        environment = launcher.diagnostic_process_environment(
            plasma_environment,
            Path("/tmp/isolated/kdockwrc"),
            Path("/tmp/isolated/open.log"),
            Path("/tmp/isolated/data"),
            "http://127.0.0.1:12345/repos/thicking/kdockw/releases",
        )
        self.assertEqual(environment["XDG_RUNTIME_DIR"], "/run/user/1000")
        self.assertEqual(environment["XDG_DATA_DIRS"], "/tmp/isolated/data:/plasma/share:/usr/share")
        self.assertEqual(environment["KDOCKW_DIAGNOSTIC_CONFIG"], "/tmp/isolated/kdockwrc")
        self.assertEqual(environment["KDOCKW_DIAGNOSTIC_RELEASE_MOCK"], "1")
        self.assertEqual(environment["KDOCKW_DIAGNOSTIC_RELEASE_API_URL"], "http://127.0.0.1:12345/repos/thicking/kdockw/releases")
        self.assertEqual(environment["KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG"], "/tmp/isolated/open.log")

        launcher_source = LAUNCHER_PATH.read_text(encoding="utf-8")
        self.assertIn("subprocess.Popen([str(binary)], env=environment)", launcher_source)
        self.assertNotIn("systemd-run", launcher_source)
        self.assertNotIn("--desktopfile", launcher_source)
        self.assertEqual(launcher.DESKTOP_ID, "kdockw-update-checker-notification-e2e")
        application_source = (ROOT / "src/app/application.cpp").read_text(encoding="utf-8")
        self.assertIn('setDesktopFileName(QStringLiteral("com.thicking.kdockw"))', application_source)

    def test_mock_bind_failure_propagates_before_application_launch(self) -> None:
        session_environment = {
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "WAYLAND_DISPLAY": "wayland-0",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
            "XDG_CURRENT_DESKTOP": "KDE",
            "KDE_SESSION_VERSION": "6",
            "XDG_DATA_HOME": "/tmp/kdockw-data",
            "XDG_DATA_DIRS": "/tmp/kdockw-state:/usr/share",
            "XDG_CONFIG_HOME": "/tmp/kdockw-config",
            "XDG_CONFIG_DIRS": "/etc/xdg",
            "XDG_CACHE_HOME": "/tmp/kdockw-cache",
        }
        with tempfile.TemporaryDirectory() as temp:
            with (
                mock.patch.object(launcher, "ThreadingHTTPServer", side_effect=OSError("port unavailable")),
                mock.patch.object(launcher.subprocess, "Popen") as launch,
            ):
                with self.assertRaisesRegex(OSError, "port unavailable"):
                    launcher.run_diagnostic_session(Path("/tmp/kdockw"), Path(temp), True, session_environment)
            launch.assert_not_called()

    def test_mock_api_serves_only_loopback_release_fixtures(self) -> None:
        server, thread = launcher.start_local_release_mock()
        try:
            self.assertEqual(server.server_address[0], "127.0.0.1")
            request = Request(
                f"http://127.0.0.1:{server.server_port}{launcher.API_PATH}",
                headers={"X-KDockW-Diagnostic-Release": "0.3.2"},
            )
            with urlopen(request, timeout=2) as response:
                payload = response.read().decode("utf-8")
            self.assertIn('"tag_name":"kdockw-v0.3.2"', payload)
            self.assertIn('"draft":false', payload)
            self.assertIn('"prerelease":false', payload)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
