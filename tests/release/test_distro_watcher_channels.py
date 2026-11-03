from __future__ import annotations

import sys
import unittest
from pathlib import Path
from urllib.error import HTTPError
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import check_distro_releases as watcher  # noqa: E402


class MissingChannelTest(unittest.TestCase):
    def test_absent_copr_is_classified_as_unconfigured(self) -> None:
        watcher.COPR_PROJECT_MISSING = False
        with mock.patch.object(
            watcher.urllib.request,
            "urlopen",
            side_effect=HTTPError(watcher.COPR_PROJECT_API, 404, "not found", {}, None),
        ):
            self.assertEqual(watcher.fetch_copr_tracked(), set())
        self.assertTrue(watcher.COPR_PROJECT_MISSING)

    def test_absent_ppa_is_classified_as_unconfigured(self) -> None:
        watcher.PPA_PROJECT_MISSING = False
        with mock.patch.object(
            watcher.urllib.request,
            "urlopen",
            side_effect=HTTPError(watcher.LP_SOURCES_API, 404, "not found", {}, None),
        ):
            self.assertEqual(watcher.fetch_ppa_tracked(watcher.LaunchpadInfo()), set())
        self.assertTrue(watcher.PPA_PROJECT_MISSING)

    def test_non_404_still_remains_an_unknown_source(self) -> None:
        with mock.patch.object(
            watcher.urllib.request,
            "urlopen",
            side_effect=HTTPError(watcher.COPR_PROJECT_API, 503, "unavailable", {}, None),
        ):
            self.assertIsNone(
                watcher.fetch_json(watcher.COPR_PROJECT_API, "COPR", missing_ok=True)
            )

    def test_ci_image_source_label_points_to_kdockw_repository(self) -> None:
        script = (ROOT / "tests/distro/build-ci-image.sh").read_text(encoding="utf-8")
        self.assertIn(
            'org.opencontainers.image.source=https://github.com/thicking/kdockw', script
        )
        self.assertNotIn(
            'org.opencontainers.image.source=https://github.com/isac322/krema', script
        )


if __name__ == "__main__":
    unittest.main()
