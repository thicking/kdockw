#!/usr/bin/env python3
"""Regression coverage for locale paths in extracted distro packages."""

from __future__ import annotations

import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests" / "distro"))
import check_package_locale  # noqa: E402


def make_mo(messages: dict[str, str]) -> bytes:
    """Build the small GNU MO catalog needed by the package checker."""
    entries = sorted(
        (key.encode("utf-8"), value.encode("utf-8"))
        for key, value in messages.items()
    )
    count = len(entries)
    originals_offset = 28
    translations_offset = originals_offset + count * 8
    strings_offset = translations_offset + count * 8

    originals = bytearray()
    translations = bytearray()
    original_table: list[tuple[int, int]] = []
    translated_table: list[tuple[int, int]] = []
    for original, _translated in entries:
        original_table.append((len(original), strings_offset + len(originals)))
        originals.extend(original + b"\0")
    translations_offset_data = strings_offset + len(originals)
    for _original, translated in entries:
        translated_table.append(
            (len(translated), translations_offset_data + len(translations))
        )
        translations.extend(translated + b"\0")

    header = struct.pack(
        "<7I", 0x950412DE, 0, count, originals_offset, translations_offset, 0, 0
    )
    tables = b"".join(struct.pack("<2I", *item) for item in original_table)
    tables += b"".join(struct.pack("<2I", *item) for item in translated_table)
    return header + tables + originals + translations


class PackageLocalePathTest(unittest.TestCase):
    def test_default_path_matches_extracted_usr_prefix(self) -> None:
        messages = {
            "": "Project-Id-Version: KDockW 0.4.3\n",
            **check_package_locale.REQUIRED_TRANSLATIONS,
        }
        with tempfile.TemporaryDirectory(prefix="kdockw-package-locale-") as temp:
            package_root = pathlib.Path(temp)
            catalog = (
                package_root
                / "usr/share/locale/ru/LC_MESSAGES/kdockw.mo"
            )
            catalog.parent.mkdir(parents=True)
            catalog.write_bytes(make_mo(messages))

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tests/distro/check_package_locale.py"),
                    str(package_root),
                    "0.4.3",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verified 12 Russian settings translations", result.stdout)


if __name__ == "__main__":
    unittest.main()
