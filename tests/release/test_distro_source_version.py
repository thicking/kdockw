# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 KDockW contributors

"""The distro artifact workflow invokes the source-version helper directly."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tests/distro/source-version.sh"


class DistroSourceVersionTests(unittest.TestCase):
    def test_cli_prints_canonical_cmake_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cmake = Path(directory) / "CMakeLists.txt"
            cmake.write_text('set(KDOCKW_VERSION "0.1.0")\n', encoding="utf-8")

            result = subprocess.run([str(HELPER), str(cmake)], check=True, text=True, capture_output=True)

        self.assertEqual(result.stdout, "0.1.0\n")

    def test_cli_rejects_missing_argument(self) -> None:
        result = subprocess.run([str(HELPER)], text=True, capture_output=True)

        self.assertEqual(result.returncode, 64)
        self.assertIn("usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
