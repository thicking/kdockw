from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import check_distro_releases as watcher  # noqa: E402


class GitHubMatrixWatcherTest(unittest.TestCase):
    def test_target_parser_uses_distro_versions_not_external_repo_fields(self) -> None:
        path = ROOT / "tests/distro/targets.tsv"
        targets = watcher.parse_targets(path)
        self.assertIn((44,), targets["fedora"])
        self.assertIn((26, 4), targets["ubuntu"])
        self.assertIn((13,), targets["debian"])
        self.assertIn((16, 0), targets["opensuse-leap"])

    def test_detection_queries_only_upstream_release_dates(self) -> None:
        versions = {
            "fedora": [{"cycle": "44", "releaseDate": "2026-04-28"}],
            "ubuntu": [{"cycle": "26.04", "releaseDate": "2026-04-23"}],
            "debian": [{"cycle": "13", "releaseDate": "2025-08-09"}],
            "opensuse": [{"cycle": "16.0", "releaseDate": "2025-10-01"}],
        }

        def fetch(url: str, _what: str):
            distro = url.rsplit("/", 1)[-1].removesuffix(".json")
            return versions[distro]

        with mock.patch.object(watcher, "fetch_json", side_effect=fetch) as request:
            targets = {slug: {key} for slug, key in (
                ("fedora", (44,)), ("ubuntu", (26, 4)),
                ("debian", (13,)), ("opensuse-leap", (16, 0)),
            )}
            gaps, incomplete = watcher.detect(targets)

        self.assertEqual(gaps, [])
        self.assertFalse(incomplete)
        urls = [call.args[0] for call in request.call_args_list]
        self.assertEqual(urls, [watcher.EOL_API.format(distro=name) for name in ("fedora", "ubuntu", "debian", "opensuse")])
        self.assertFalse(any(host in url for url in urls for host in ("opensuse.org", "fedorainfracloud", "launchpad.net")))

    def test_new_release_creates_one_github_matrix_gap(self) -> None:
        releases = {
            "fedora": [{"cycle": "44", "releaseDate": "2026-04-28"}, {"cycle": "45", "releaseDate": "2026-11-01"}],
            "ubuntu": [{"cycle": "26.04", "releaseDate": "2026-04-23"}],
            "debian": [{"cycle": "13", "releaseDate": "2025-08-09"}],
            "opensuse": [{"cycle": "16.0", "releaseDate": "2025-10-01"}],
        }

        def fetch(url: str, _what: str):
            return releases[url.rsplit("/", 1)[-1].removesuffix(".json")]

        targets = {slug: {key} for slug, key in (
            ("fedora", (44,)), ("ubuntu", (26, 4)),
            ("debian", (13,)), ("opensuse-leap", (16, 0)),
        )}
        with mock.patch.object(watcher, "fetch_json", side_effect=fetch):
            gaps, incomplete = watcher.detect(targets)

        self.assertFalse(incomplete)
        self.assertEqual([(gap.distro, gap.version, gap.key) for gap in gaps], [
            ("Fedora", "45", "fedora:45:github")
        ])
        self.assertIn("GitHub package matrix", gaps[0].title)
        self.assertIn("tests/distro/targets.tsv", watcher.build_body(gaps[0]))

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
