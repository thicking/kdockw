from __future__ import annotations

import sys
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import check_distro_releases as watcher  # noqa: E402


class GitHubMatrixWatcherTest(unittest.TestCase):
    def test_target_parser_uses_distro_versions_not_external_repo_fields(self) -> None:
        path = ROOT / "tests/distro/targets.tsv"
        gate_path = ROOT / "tests/distro/release-targets.txt"
        targets = watcher.parse_targets(gate_path)
        self.assertEqual(targets["fedora"], set())
        self.assertIn((26, 4), targets["ubuntu"])
        self.assertIn((13,), targets["debian"])
        self.assertEqual(set(targets), {"fedora", "ubuntu", "debian"})
        self.assertIn("opensuse-tumbleweed", path.read_text(encoding="utf-8"))

    def test_detection_queries_only_upstream_release_dates(self) -> None:
        versions = {
            "ubuntu": [
                {"cycle": "26.04", "releaseDate": "2026-04-23"},
                {"cycle": "26.10", "releaseDate": "2026-10-15"},
            ],
            "debian": [{"cycle": "13", "releaseDate": "2025-08-09"}],
        }

        def fetch(url: str, _what: str):
            distro = url.rsplit("/", 1)[-1].removesuffix(".json")
            return versions[distro]

        with mock.patch.object(watcher, "fetch_json", side_effect=fetch) as request:
            targets = {slug: {key} for slug, key in (
                ("ubuntu", (26, 4)), ("debian", (13,)),
            )}
            gaps, incomplete = watcher.detect(targets)

        self.assertEqual(gaps, [])
        self.assertFalse(incomplete)
        urls = [call.args[0] for call in request.call_args_list]
        self.assertEqual(urls, [watcher.EOL_API.format(distro=name) for name in ("ubuntu", "debian")])
        self.assertFalse(any(host in url for url in urls for host in ("opensuse.org", "fedorainfracloud", "launchpad.net")))

    def test_new_release_creates_one_github_matrix_gap(self) -> None:
        releases = {
            "ubuntu": [
                {"cycle": "26.04", "releaseDate": "2026-04-23"},
                {"cycle": "26.10", "releaseDate": "2026-10-15"},
                {"cycle": "28.04", "releaseDate": "2028-04-20"},
            ],
            "debian": [{"cycle": "13", "releaseDate": "2025-08-09"}],
        }

        def fetch(url: str, _what: str):
            return releases[url.rsplit("/", 1)[-1].removesuffix(".json")]

        targets = {slug: {key} for slug, key in (
            ("ubuntu", (26, 4)), ("debian", (13,)),
        )}
        with (
            mock.patch.object(watcher, "fetch_json", side_effect=fetch),
            mock.patch.object(watcher, "date") as frozen_date,
        ):
            frozen_date.today.return_value = date(2028, 6, 1)
            gaps, incomplete = watcher.detect(targets)

        self.assertFalse(incomplete)
        self.assertEqual([(gap.distro, gap.version, gap.key) for gap in gaps], [
            ("Ubuntu", "28.04", "ubuntu:28.04:github"),
        ])
        self.assertIn("GitHub package matrix", gaps[0].title)
        body = watcher.build_body(gaps[0])
        self.assertIn("tests/distro/release-targets.txt", body)
        self.assertNotIn("EOL alone", body)

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
