"""Boundary tests for scripts/release_aur.py (pure PKGBUILD/.SRCINFO decisions).

Run: python3 -m unittest discover -s tests/release
"""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import release_aur  # noqa: E402
from release_common import ReleaseContext, ReleaseError  # noqa: E402

SHA = "a" * 64
URL = "https://github.com/thicking/kdockw/releases/download/v1.2.3/kdockw-1.2.3.tar.gz"
TEMPLATE = (ROOT / "packaging/arch/PKGBUILD").read_text(encoding="utf-8")


def make_context(
    version: str = "1.2.3", sha256: str = SHA, source_url: str = URL
) -> ReleaseContext:
    tmp = Path(tempfile.gettempdir())
    return ReleaseContext(
        repository="thicking/kdockw",
        tag=f"v{version}",
        version=version,
        commit="0" * 40,
        source_dir=tmp,
        archive=tmp / f"kdockw-{version}.tar.gz",
        sha256=sha256,
        source_url=source_url,
        work_dir=tmp,
        notes_path=tmp / "notes.md",
        debian_revision="1",
    )


def srcinfo(
    version: str, rel: str = "1", source: str | None = None, sha: str = SHA
) -> str:
    source = source or f"kdockw-{version}.tar.gz::{URL}"
    return (
        f"pkgbase = kdockw\n\tpkgver = {version}\n\tpkgrel = {rel}\n"
        f"\tdepends = qt6-base>=6.8\n\tsource = {source}\n\tsha256sums = {sha}\n\npkgname = kdockw\n"
    )


class RenderPkgbuildTest(unittest.TestCase):
    def test_pins_version_source_hash_and_resets_pkgrel(self) -> None:
        out = release_aur.render_pkgbuild(TEMPLATE.replace("pkgrel=1", "pkgrel=4"), version="1.2.3",
                                          source_url=URL, sha256=SHA)  # fmt: skip
        self.assertIn("\npkgver=1.2.3\n", out)
        self.assertIn("\npkgrel=1\n", out)
        self.assertIn(f'source=("$pkgname-$pkgver.tar.gz::{URL}")', out)
        self.assertIn(f"sha256sums=('{SHA}')", out)
        self.assertNotIn("SKIP", out)

    def test_comment_after_checksum_array_is_not_treated_as_array_syntax(self) -> None:
        out = release_aur.render_pkgbuild(
            TEMPLATE, version="1.2.3", source_url=URL, sha256=SHA
        )
        self.assertIn(f"sha256sums=('{SHA}')", out)
        self.assertNotIn("SKIP", out)
        context = make_context()
        release_aur.validate_generated_srcinfo(
            srcinfo(
                context.version,
                source=release_aur.expected_source(context),
                sha=context.sha256,
            ),
            context,
        )

    def test_multiline_array_and_quoted_parentheses_are_replaced(self) -> None:
        multiline = TEMPLATE.replace(
            "source=(\"$pkgname-$_pkgsrcver.tar.gz::https://github.com/thicking/kdockw/archive/refs/tags/v$_pkgsrcver.tar.gz\")",
            "source=(\n  \"old (source)\" # previous source\n)",
        ).replace(
            "sha256sums=('SKIP') # No independent KDockW release archive exists yet.",
            "sha256sums=(\n  'SKIP' # temporary\n) # replaced during release",
        )
        out = release_aur.render_pkgbuild(
            multiline, version="1.2.3", source_url=URL, sha256=SHA
        )
        self.assertIn(f'source=("$pkgname-$pkgver.tar.gz::{URL}")', out)
        self.assertIn(f"sha256sums=('{SHA}')", out)
        self.assertNotIn("SKIP", out)

    def test_publication_renderer_rejects_missing_verified_sha256(self) -> None:
        with self.assertRaises(ReleaseError):
            release_aur.render_pkgbuild(
                TEMPLATE, version="1.2.3", source_url=URL, sha256="SKIP"
            )

    def test_preserves_dependencies_arch_license_and_functions(self) -> None:
        out = release_aur.render_pkgbuild(
            TEMPLATE, version="1.2.3", source_url=URL, sha256=SHA
        )
        for marker in (
            "arch=(",
            "license=(",
            "depends=(",
            "makedepends=(",
            "build() {",
            "package() {",
        ):
            start = TEMPLATE.index(marker)
            block = TEMPLATE[start : TEMPLATE.index("\n", start)]
            self.assertIn(block, out)
        depends = TEMPLATE[
            TEMPLATE.index("depends=(") : TEMPLATE.index(
                ")", TEMPLATE.index("depends=(")
            )
        ]
        self.assertIn(depends, out)
        self.assertNotIn("archive/v$pkgver", out)

    def test_rejects_unsafe_inputs(self) -> None:
        for kwargs in (
            {"version": "1.2.3-rc1", "source_url": URL, "sha256": SHA},
            {
                "version": "1.2.3",
                "source_url": "http://example.com/x.tar.gz",
                "sha256": SHA,
            },
            {"version": "1.2.3", "source_url": URL + "$(id)", "sha256": SHA},
            {"version": "1.2.3", "source_url": URL, "sha256": "A" * 64},
        ):
            with self.subTest(kwargs=kwargs), self.assertRaises(ReleaseError):
                release_aur.render_pkgbuild(TEMPLATE, **kwargs)

    def test_rejects_ambiguous_template(self) -> None:
        with self.assertRaises(ReleaseError):
            release_aur.render_pkgbuild(
                TEMPLATE + "\npkgver=9.9.9\n",
                version="1.2.3",
                source_url=URL,
                sha256=SHA,
            )


class ClassifyRemoteTest(unittest.TestCase):
    def test_older_remote_is_planned(self) -> None:
        state, _, extra = release_aur.classify_remote(
            srcinfo("0.10.0"), make_context("1.2.3")
        )
        self.assertEqual(state, "planned")
        self.assertEqual(extra["aur_version"], "0.10.0-1")

    def test_numeric_not_lexical_ordering(self) -> None:
        state, _, _ = release_aur.classify_remote(
            srcinfo("0.9.0"), make_context("0.10.0")
        )
        self.assertEqual(state, "planned")

    def test_newer_remote_blocks_downgrade(self) -> None:
        state, _, _ = release_aur.classify_remote(
            srcinfo("1.10.0"), make_context("1.2.3")
        )
        self.assertEqual(state, "blocked")

    def test_equal_version_is_already_published(self) -> None:
        state, _, extra = release_aur.classify_remote(
            srcinfo("1.2.3", rel="2"), make_context("1.2.3")
        )
        self.assertEqual(state, "already_published")
        self.assertTrue(extra["source_matches"])

    def test_equal_version_with_other_source_is_not_rewritten(self) -> None:
        other = (
            "kdockw-1.2.3.tar.gz::https://github.com/thicking/kdockw/archive/v1.2.3.tar.gz"
        )
        state, detail, extra = release_aur.classify_remote(srcinfo("1.2.3", source=other, sha="b" * 64),
                                                           make_context("1.2.3"))  # fmt: skip
        self.assertEqual(state, "already_published")
        self.assertFalse(extra["source_matches"])
        self.assertIn("different source", detail)

    def test_missing_srcinfo_is_first_upload(self) -> None:
        state, _, extra = release_aur.classify_remote(None, make_context())
        self.assertEqual(state, "planned")
        self.assertIsNone(extra["aur_version"])


class MissingPackageGuardTest(unittest.TestCase):
    def test_status_reports_absent_aur_package_without_git_clone(self) -> None:
        context = make_context()
        with (
            mock.patch.object(release_aur, "_aur_package_exists", return_value=False),
            mock.patch.object(release_aur, "clone_remote") as clone,
        ):
            report = release_aur.status(context)
        clone.assert_not_called()
        self.assertEqual(report["status"], "blocked")
        self.assertIn("does not exist yet", report["detail"])

    def test_publish_does_not_clone_or_push_when_package_is_absent(self) -> None:
        context = make_context()
        context = ReleaseContext(**{**context.__dict__, "source_dir": ROOT})
        with (
            mock.patch.object(release_aur, "_aur_package_exists", return_value=False),
            mock.patch.object(release_aur, "clone_remote") as clone,
        ):
            report = release_aur.publish(context)
        clone.assert_not_called()
        self.assertEqual(report["status"], "blocked")
        self.assertIn("no clone or push was attempted", report["detail"])


class GeneratedSrcinfoTest(unittest.TestCase):
    def test_accepts_matching_srcinfo(self) -> None:
        release_aur.validate_generated_srcinfo(srcinfo("1.2.3"), make_context())

    def test_rejects_mismatch(self) -> None:
        with self.assertRaises(ReleaseError):
            release_aur.validate_generated_srcinfo(
                srcinfo("1.2.3", sha="b" * 64), make_context()
            )

    def test_docker_uses_readable_snapshot_for_private_stage_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stage = Path(tmp) / "private-stage"
            stage.mkdir(mode=0o700)
            pkgbuild = stage / "PKGBUILD"
            pkgbuild.write_text("pkgname=kdockw\n", encoding="utf-8")
            pkgbuild.chmod(0o600)
            observed: dict[str, Path] = {}

            def inspect_command(argv, **kwargs):  # noqa: ANN001
                volume = argv[argv.index("--volume") + 1]
                source = Path(volume.split(":", 1)[0])
                mounted_pkgbuild = source / "PKGBUILD"
                observed["source"] = source
                self.assertNotEqual(source, stage.resolve())
                self.assertEqual(source.stat().st_mode & 0o777, 0o755)
                self.assertEqual(mounted_pkgbuild.stat().st_mode & 0o777, 0o644)
                self.assertEqual(
                    mounted_pkgbuild.read_text(encoding="utf-8"),
                    pkgbuild.read_text(encoding="utf-8"),
                )
                self.assertTrue(kwargs["timeout"] > 0)
                return srcinfo("1.2.3")

            with (
                mock.patch.object(
                    release_aur.shutil,
                    "which",
                    side_effect=lambda name: (
                        "/usr/bin/docker" if name == "docker" else None
                    ),
                ),
                mock.patch.object(release_aur, "command", side_effect=inspect_command),
            ):
                text, tool = release_aur.generate_srcinfo(stage)

            self.assertEqual(
                tool,
                f"makepkg in {release_aur.ARCH_IMAGE} ({release_aur.ARCH_PLATFORM})",
            )
            self.assertEqual(text, srcinfo("1.2.3"))
            self.assertFalse(observed["source"].exists(), "temporary snapshot must be cleaned")
            self.assertEqual(sorted(path.name for path in stage.iterdir()), ["PKGBUILD"])

    @unittest.skipUnless(
        shutil.which("makepkg") or shutil.which("docker"), "neither makepkg nor docker"
    )
    def test_generated_srcinfo_matches_context_without_writing_stage(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stage = Path(tmp)
            (stage / "PKGBUILD").write_text(
                release_aur.render_pkgbuild(
                    TEMPLATE, version="1.2.3", source_url=URL, sha256=SHA
                ),
                encoding="utf-8",
            )
            text, _ = release_aur.generate_srcinfo(stage)
            release_aur.validate_generated_srcinfo(text, make_context())
            self.assertIn("depends = kpipewire", text)
            self.assertEqual(sorted(p.name for p in stage.iterdir()), ["PKGBUILD"])


if __name__ == "__main__":
    unittest.main()
