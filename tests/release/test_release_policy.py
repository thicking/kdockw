from __future__ import annotations

import sys
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import release  # noqa: E402
from release_common import ReleaseError  # noqa: E402


class GitHubOnlyReleasePolicyTest(unittest.TestCase):
    def test_github_is_the_only_active_publication_channel(self) -> None:
        self.assertEqual(release.CHANNELS, ("github",))
        self.assertEqual(set(release.INACTIVE_ADAPTERS), {"aur", "obs", "copr", "ppa"})

    def test_all_means_github_only_for_publish_and_status(self) -> None:
        parser = release._parser()
        for command in ("publish", "status"):
            args = [command, "--context", "unused", "--channel", "all"]
            self.assertEqual(parser.parse_args(args).channel, "all")

    def test_inactive_channels_are_rejected_by_cli_and_publish_guard(self) -> None:
        parser = release._parser()
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["publish", "--context", "unused", "--channel", "aur"])
        with self.assertRaises(ReleaseError):
            release.publish(None, ["copr"], Path("."), release.PINNED_SIGNERS, execute=False)

    def test_policy_docs_keep_package_matrix_and_release_channel_distinct(self) -> None:
        runbook = (ROOT / "docs/releasing/release-process.md").read_text(encoding="utf-8")
        self.assertIn("only active publication channel", runbook)
        self.assertIn("Distro E2E", runbook)
        self.assertIn("AUR, OBS, COPR, and Launchpad/PPA", runbook)
        matrix = (ROOT / "tests/distro/targets.tsv").read_text(encoding="utf-8")
        self.assertIn("fedora-44", matrix)
        ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("scripts/check_distro_releases.py", ci)
        self.assertIn("GitHub Release", runbook)


if __name__ == "__main__":
    unittest.main()
