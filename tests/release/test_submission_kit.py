"""Boundary tests for the store submission kit and the store receipt lifecycle.

Run from the repository root:

    python3 -m unittest discover -s tests/release -p 'test_*.py'
"""

from __future__ import annotations

import hashlib
import html
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
import urllib.error
import urllib.parse
import zlib
import zipfile
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))

import prepare_submission_kit  # noqa: E402
import release_stores  # noqa: E402
from prepare_submission_kit import (  # noqa: E402
    CHANNELS,
    LFS_STAGING,
    SCHEMA_DIR,
    build_kit,
    load_submissions,
)
from release_common import ReleaseContext, ReleaseError, asset_url  # noqa: E402

COMMIT = "0123456789abcdef0123456789abcdef01234567"
OTHER_COMMIT = "fedcba9876543210fedcba9876543210fedcba98"
PNG_LFS_POINTER = (
    b"version https://git-lfs.github.com/spec/v1\noid sha256:"
    + b"0" * 64
    + b"\nsize 1\n"
)


def fixture_png(width: int, height: int) -> bytes:
    """Create a tiny valid PNG fixture with the requested pixel dimensions."""
    color = bytes((width % 251, height % 251, (width + height) % 251))
    rows = (b"\0" + color * width) * height

    def chunk(kind: bytes, body: bytes) -> bytes:
        checksum = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", checksum)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b"")
    )


def make_archive(
    version: str,
    *,
    cmake_version: str | None = None,
    commit: str = COMMIT,
    extra: dict[str, bytes] | None = None,
) -> bytes:
    """Return a gzip tarball in the release layout produced by ``git archive``."""
    root = f"kdockw-{version}"
    files = {
        f"{root}/CMakeLists.txt": f'set(KDOCKW_VERSION "{cmake_version or version}")\nproject(kdockw VERSION {version} LANGUAGES CXX)\n'.encode(),
        f"{root}/LICENSES/GPL-3.0-or-later.txt": b"GNU GENERAL PUBLIC LICENSE\n",
        f"{root}/src/main.cpp": b"int main() { return 0; }\n",
        **(extra or {}),
    }
    buffer = io.BytesIO()
    with tarfile.open(
        fileobj=buffer,
        mode="w:gz",
        format=tarfile.PAX_FORMAT,
        pax_headers={"comment": commit},
    ) as archive:
        for directory in (root, f"{root}/LICENSES", f"{root}/src"):
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            archive.addfile(info)
        link = tarfile.TarInfo(f"{root}/LICENSE")
        link.type = tarfile.SYMTYPE
        link.linkname = "LICENSES/GPL-3.0-or-later.txt"
        archive.addfile(link)
        for name, payload in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(payload))
    return buffer.getvalue()


class ReleaseFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="kdockw-kit-test-"))
        self.addCleanup(shutil.rmtree, self.tmp)

    def tagged_source(self) -> Path:
        """Copy the checked-in templates and their media into a tagged source tree."""
        source = self.tmp / "source"
        (source / SCHEMA_DIR).mkdir(parents=True)
        for channel in CHANNELS:
            schema = REPO / SCHEMA_DIR / f"{channel}.json"
            shutil.copyfile(schema, source / SCHEMA_DIR / schema.name)
            data = json.loads(schema.read_text(encoding="utf-8"))
            shutil.copyfile(
                REPO / data["description_file"], source / data["description_file"]
            )
            for item in data["media"]:
                target = source / item["source"]
                target.parent.mkdir(parents=True, exist_ok=True)
                original = (REPO / item["source"]).read_bytes()
                if original.startswith(prepare_submission_kit.LFS_PREFIX):
                    # Unit tests use synthetic local PNG bytes. Pointer parsing
                    # and real network retrieval are covered separately below.
                    original = fixture_png(item["width"], item["height"])
                target.write_bytes(original)
                # Keep receipt assertions self-contained when this fixture
                # substitutes synthetic bytes for a checked-in media file.
                if "uploaded_sha256" in item:
                    item["uploaded_sha256"] = hashlib.sha256(original).hexdigest()
            (source / SCHEMA_DIR / schema.name).write_text(
                json.dumps(data, indent=2) + "\n", encoding="utf-8"
            )
        return source

    def context(
        self, version: str, payload: bytes, source: Path, *, sha256: str | None = None
    ) -> ReleaseContext:
        archive = self.tmp / f"kdockw-{version}.tar.gz"
        archive.write_bytes(payload)
        return ReleaseContext(
            repository="thicking/kdockw",
            tag=f"v{version}",
            version=version,
            commit=COMMIT,
            source_dir=source,
            archive=archive,
            sha256=sha256 or hashlib.sha256(payload).hexdigest(),
            source_url=asset_url("thicking/kdockw", f"v{version}", version),
            work_dir=self.tmp / "work",
            notes_path=self.tmp / "notes.md",
            debian_revision="1",
        )

    def assert_refused(self, context: ReleaseContext) -> None:
        output = self.tmp / "out" / "kit"
        with self.assertRaises(ReleaseError):
            build_kit(context, output)
        self.assertFalse(output.exists(), "a refused kit must not leave output behind")
        self.assertFalse(output.with_name("kit.zip").exists())


class SubmissionKitBoundaryTest(ReleaseFixture):
    # Version binding

    def test_arbitrary_version_renders_complete_packet(self) -> None:
        payload = make_archive("9.8.7")
        context = self.context("9.8.7", payload, self.tagged_source())
        built = build_kit(context, self.tmp / "out" / "kit")
        kit = built["output"]

        sums = (kit / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(sums), 20)
        for line in sums:
            digest, name = line.split("  ", 1)
            self.assertEqual(
                hashlib.sha256((kit / name).read_bytes()).hexdigest(), digest, name
            )
        with zipfile.ZipFile(built["zip"]) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(len(archive.namelist()), 21)

        info = json.loads((kit / "kit.json").read_text(encoding="utf-8"))
        self.assertEqual(info["release"]["tag"], "v9.8.7")
        self.assertEqual(info["release"]["commit"], COMMIT)
        self.assertEqual(info["schema_baseline"]["tag"], "v0.10.0")
        self.assertEqual(
            info["templates"],
            {"source": "tagged-source", "human_review_required": False},
        )
        self.assertEqual(info["source"]["sha256"], context.sha256)

        staged = kit / "kde-store" / "downloads" / "kdockw-9.8.7.tar.gz"
        self.assertEqual(staged.read_bytes(), payload)
        self.assertEqual(
            json.loads((kit / "kde-store" / "fields.json").read_text())["Version"],
            "9.8.7",
        )
        description = (kit / "kde-store" / "description.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "https://github.com/thicking/kdockw/blob/v9.8.7/README.md#build--run",
            description,
        )
        self.assertNotIn("v0.10.0", description)
        for path in kit.rglob("*"):
            if path.suffix in {".txt", ".json"}:
                self.assertNotIn("{{", path.read_text(encoding="utf-8"), path)

        launchpad = json.loads(
            (kit / "launchpad" / "submission.json").read_text(encoding="utf-8")
        )
        self.assertTrue(
            all(item["source"].startswith("src/icons/") for item in launchpad["media"])
        )
        self.assertEqual(launchpad["submission"]["target_status"], "proposed-project")
        self.assertFalse(launchpad["published_project"])
        self.assertEqual(launchpad["observed_release"]["tag"], "v0.10.0")
        self.assertEqual(launchpad["release"]["tag"], "v9.8.7")

    def test_untagged_templates_fall_back_and_require_review(self) -> None:
        source = self.tmp / "bare-source"
        source.mkdir()
        context = self.context("9.8.7", make_archive("9.8.7"), source)
        installed = self.tagged_source()
        with mock.patch.object(prepare_submission_kit, "ROOT", installed):
            built = build_kit(context, self.tmp / "out" / "kit")
        self.assertEqual(
            built["kit"]["templates"],
            {"source": "installed-fallback", "human_review_required": True},
        )
        notes = (built["output"] / "kde-store" / "upload-order.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn("installed fallback", notes)

    def test_archive_version_must_match_context(self) -> None:
        context = self.context(
            "9.8.7", make_archive("9.8.7", cmake_version="9.8.6"), self.tagged_source()
        )
        self.assert_refused(context)

    def test_archive_root_must_match_context_version(self) -> None:
        payload = make_archive("9.8.6")
        context = self.context("9.8.7", payload, self.tagged_source())
        self.assert_refused(context)

    def test_archive_commit_must_match_context(self) -> None:
        context = self.context(
            "9.8.7", make_archive("9.8.7", commit=OTHER_COMMIT), self.tagged_source()
        )
        self.assert_refused(context)

    # Hash mismatch

    def test_context_hash_must_match_archive_bytes(self) -> None:
        payload = make_archive("9.8.7")
        context = self.context(
            "9.8.7",
            payload,
            self.tagged_source(),
            sha256=hashlib.sha256(payload + b"x").hexdigest(),
        )
        self.assert_refused(context)

    def test_archive_modified_after_context_is_refused(self) -> None:
        context = self.context("9.8.7", make_archive("9.8.7"), self.tagged_source())
        Path(context.archive).write_bytes(
            make_archive("9.8.7", extra={"kdockw-9.8.7/src/extra.cpp": b"// changed\n"})
        )
        self.assert_refused(context)

    # Path corruption

    def test_schema_media_path_escape_is_refused(self) -> None:
        source = self.tagged_source()
        schema_path = source / SCHEMA_DIR / "alternativeto.json"
        data = json.loads(schema_path.read_text(encoding="utf-8"))
        data["media"][0]["source"] = "../outside.png"
        schema_path.write_text(json.dumps(data), encoding="utf-8")
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))

    def test_unavailable_lfs_pointer_media_is_refused(self) -> None:
        source = self.tagged_source()
        data = json.loads(
            (source / SCHEMA_DIR / "kde-store.json").read_text(encoding="utf-8")
        )
        (source / data["media"][0]["source"]).write_bytes(PNG_LFS_POINTER)
        with mock.patch.object(
            prepare_submission_kit.urllib.request,
            "urlopen",
            side_effect=urllib.error.URLError("offline"),
        ):
            self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))

    def test_lfs_pointer_license_symlink_target_is_refused(self) -> None:
        payload = make_archive(
            "9.8.7",
            extra={"kdockw-9.8.7/LICENSES/GPL-3.0-or-later.txt": PNG_LFS_POINTER},
        )
        self.assert_refused(self.context("9.8.7", payload, self.tagged_source()))

    def test_lfs_pointer_additional_license_is_refused(self) -> None:
        payload = make_archive(
            "9.8.7", extra={"kdockw-9.8.7/LICENSES/CC0-1.0.txt": PNG_LFS_POINTER}
        )
        self.assert_refused(self.context("9.8.7", payload, self.tagged_source()))

    def test_unsafe_archive_member_is_refused(self) -> None:
        payload = make_archive(
            "9.8.7", extra={"kdockw-9.8.7/../escape.txt": b"escape\n"}
        )
        self.assert_refused(self.context("9.8.7", payload, self.tagged_source()))

    def test_incomplete_tagged_template_set_is_refused(self) -> None:
        source = self.tagged_source()
        (source / SCHEMA_DIR / "launchpad.json").unlink()
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))

    # Token substitution

    def test_unknown_release_token_is_refused(self) -> None:
        source = self.tagged_source()
        schema_path = source / SCHEMA_DIR / "kde-store.json"
        data = json.loads(schema_path.read_text(encoding="utf-8"))
        data["fields"]["Summary"] = "{{bogus}}"
        schema_path.write_text(json.dumps(data), encoding="utf-8")
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))

    def test_malformed_release_token_is_refused(self) -> None:
        source = self.tagged_source()
        schema_path = source / SCHEMA_DIR / "kde-store.json"
        data = json.loads(schema_path.read_text(encoding="utf-8"))
        data["fields"]["Summary"] = "KDockW {{version }"
        schema_path.write_text(json.dumps(data), encoding="utf-8")
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))


class FakeMediaResponse:
    """The ``urlopen`` result the downloader reads: headers plus a byte stream."""

    def __init__(self, body: bytes, length: int) -> None:
        self.headers = {"Content-Length": str(length)}
        self.stream = io.BytesIO(body)

    def __enter__(self) -> "FakeMediaResponse":
        return self

    def __exit__(self, *exc: object) -> None:
        return None

    def read(self, size: int = -1) -> bytes:
        return self.stream.read(size)


def lfs_pointer_bytes(payload: bytes) -> bytes:
    return (
        b"version https://git-lfs.github.com/spec/v1\noid sha256:"
        + hashlib.sha256(payload).hexdigest().encode()
        + f"\nsize {len(payload)}\n".encode()
    )


class TaggedLfsMediaTest(ReleaseFixture):
    """Template media committed as Git LFS pointers, as ``git archive`` ships them.

    Only the HTTP read is replaced: pointer parsing, size and SHA-256 checks,
    staging, and PNG validation run unchanged.
    """

    MEDIA_URL = f"https://media.githubusercontent.com/media/thicking/kdockw/{COMMIT}/"

    def pointerize(self, root: Path) -> dict[str, bytes]:
        """Create synthetic LFS pointers for staged KDockW media in this fixture."""
        payloads: dict[str, bytes] = {}
        for channel in CHANNELS:
            schema_path = root / SCHEMA_DIR / f"{channel}.json"
            data = json.loads(schema_path.read_text(encoding="utf-8"))
            for item in data["media"]:
                payload = (root / item["source"]).read_bytes()
                synthetic = f"branding/test-lfs/{channel}/{item['filename']}"
                destination = root / synthetic
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(lfs_pointer_bytes(payload))
                payloads[synthetic] = payload
                item["source"] = synthetic
            schema_path.write_text(
                json.dumps(data, indent=2) + "\n", encoding="utf-8"
            )
        return payloads

    def serve(
        self, payloads: dict[str, bytes], overrides: dict[str, bytes] | None = None
    ):
        """Patch the downloader's ``urlopen`` with a local media endpoint keyed by path."""
        bodies = {**payloads, **(overrides or {})}
        requested: list[str] = []

        def urlopen(request, timeout=None):  # noqa: ANN001
            url = request.full_url
            requested.append(url)
            self.assertTrue(url.startswith(self.MEDIA_URL), url)
            self.assertIsNotNone(timeout)
            body = bodies.get(url[len(self.MEDIA_URL) :])
            if body is None:
                raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
            return FakeMediaResponse(body, len(body))

        patcher = mock.patch.object(
            prepare_submission_kit.urllib.request, "urlopen", side_effect=urlopen
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        return requested

    def snapshot(self, root: Path) -> dict[str, bytes]:
        return {
            path.relative_to(root).as_posix(): path.read_bytes()
            for path in sorted(root.rglob("*"))
            if path.is_file()
        }

    def test_tagged_pointer_media_build_from_verified_downloads(self) -> None:
        source = self.tagged_source()
        payloads = self.pointerize(source)
        requested = self.serve(payloads)
        context = self.context("9.8.7", make_archive("9.8.7"), source)
        source_before = self.snapshot(source)
        archive_before = Path(context.archive).read_bytes()

        built = build_kit(context, self.tmp / "out" / "kit")

        stage = Path(context.work_dir) / LFS_STAGING
        staged_hashes = {path.name for path in stage.iterdir()}
        first_source_by_hash: dict[str, str] = {}
        for source_path, payload in payloads.items():
            first_source_by_hash.setdefault(
                hashlib.sha256(payload).hexdigest(), source_path
            )
        used_pointers = [
            source_path
            for digest, source_path in first_source_by_hash.items()
            if digest in staged_hashes
        ]
        self.assertEqual(
            sorted(requested), sorted(self.MEDIA_URL + rel for rel in used_pointers)
        )
        self.assertEqual(built["kit"]["templates"]["source"], "tagged-source")
        for channel in CHANNELS:
            data = built["submissions"][channel]
            for item in data["media"]:
                staged = built["output"] / channel / "media" / item["filename"]
                self.assertEqual(staged.read_bytes(), payloads[item["source"]])
            provenance = json.loads(
                (built["output"] / channel / "submission.json").read_text("utf-8")
            )
            self.assertNotIn("_media_files", provenance)
            self.assertEqual(
                [item["source"] for item in provenance["media"]],
                [item["source"] for item in data["media"]],
            )
        self.assertEqual(self.snapshot(source), source_before)
        self.assertEqual(Path(context.archive).read_bytes(), archive_before)
        self.assertEqual(
            sorted(path.name for path in stage.iterdir()),
            sorted(hashlib.sha256(payloads[rel]).hexdigest() for rel in used_pointers),
        )

        # Read-only helpers reuse the verified stage without another request.
        requested.clear()
        load_submissions(context)
        expected = release_stores.alternativeto_expected(context)
        self.assertTrue(expected["paragraphs"])
        self.assertEqual(requested, [])

        # A corrupted staged object is refetched, never trusted.
        corrupted = (
            stage
            / hashlib.sha256(payloads["branding/test-lfs/kde-store/kdockw-icon-256.png"]).hexdigest()
        )
        corrupted.write_bytes(b"\x89PNG corrupted")
        load_submissions(context)
        self.assertEqual(
            requested, [self.MEDIA_URL + "branding/test-lfs/kde-store/kdockw-icon-256.png"]
        )
        self.assertEqual(
            corrupted.read_bytes(), payloads["branding/test-lfs/kde-store/kdockw-icon-256.png"]
        )

    def test_pointer_object_hash_mismatch_is_refused(self) -> None:
        source = self.tagged_source()
        payloads = self.pointerize(source)
        rel = "branding/test-lfs/launchpad/kdockw-launchpad-icon-16.png"
        tampered = bytearray(payloads[rel])
        tampered[-1] ^= 0xFF
        self.serve(payloads, {rel: bytes(tampered)})
        context = self.context("9.8.7", make_archive("9.8.7"), source)
        self.assert_refused(context)
        staged = (
            Path(context.work_dir)
            / LFS_STAGING
            / hashlib.sha256(payloads[rel]).hexdigest()
        )
        self.assertFalse(staged.exists())

    def test_pointer_object_size_mismatch_is_refused(self) -> None:
        rel = "branding/test-lfs/launchpad/kdockw-launchpad-logo-64.png"
        for label, change in (
            ("short", lambda body: body[:-1]),
            ("long", lambda body: body + b"\x00"),
        ):
            with self.subTest(label):
                source = self.tagged_source()
                payloads = self.pointerize(source)
                self.serve(payloads, {rel: change(payloads[rel])})
                self.assert_refused(
                    self.context("9.8.7", make_archive("9.8.7"), source)
                )
                shutil.rmtree(source)

    def test_malformed_pointer_is_refused_without_download(self) -> None:
        source = self.tagged_source()
        payloads = self.pointerize(source)
        rel = "branding/test-lfs/alternativeto/kdockw-icon-256.png"
        (source / rel).write_bytes(lfs_pointer_bytes(payloads[rel]) + b"ext x\n")
        requested = self.serve(payloads)
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))
        self.assertNotIn(self.MEDIA_URL + rel, requested)

    def test_pointer_resolving_to_non_png_is_refused(self) -> None:
        source = self.tagged_source()
        payloads = self.pointerize(source)
        rel = "branding/test-lfs/launchpad/kdockw-launchpad-brand-128.png"
        not_png = b"<html>not an image</html>\n"
        (source / rel).write_bytes(lfs_pointer_bytes(not_png))
        self.serve({**payloads, rel: not_png})
        self.assert_refused(self.context("9.8.7", make_archive("9.8.7"), source))

    def test_staging_inside_source_tree_is_refused(self) -> None:
        source = self.tagged_source()
        payloads = self.pointerize(source)
        requested = self.serve(payloads)
        context = self.context("9.8.7", make_archive("9.8.7"), source)
        context = ReleaseContext(**{**context.__dict__, "work_dir": source})
        before = self.snapshot(source)
        self.assert_refused(context)
        self.assertEqual(requested, [])
        self.assertEqual(self.snapshot(source), before)

    def test_installed_fallback_pointer_media_are_resolved(self) -> None:
        installed = self.tagged_source()
        payloads = self.pointerize(installed)
        requested = self.serve(payloads)
        bare = self.tmp / "bare-source"
        bare.mkdir()
        context = self.context("9.8.7", make_archive("9.8.7"), bare)
        with mock.patch.object(prepare_submission_kit, "ROOT", installed):
            built = build_kit(context, self.tmp / "out" / "kit")
        self.assertEqual(built["kit"]["templates"]["source"], "installed-fallback")
        stage = Path(context.work_dir) / LFS_STAGING
        staged_hashes = {path.name for path in stage.iterdir()}
        first_source_by_hash: dict[str, str] = {}
        for source_path, payload in payloads.items():
            first_source_by_hash.setdefault(
                hashlib.sha256(payload).hexdigest(), source_path
            )
        used_pointers = [
            source_path
            for digest, source_path in first_source_by_hash.items()
            if digest in staged_hashes
        ]
        self.assertEqual(len(requested), len(used_pointers))
        for channel in CHANNELS:
            for item in built["submissions"][channel]["media"]:
                self.assertEqual(
                    (
                        built["output"] / channel / "media" / item["filename"]
                    ).read_bytes(),
                    payloads[item["source"]],
                )

    def test_direct_png_media_need_no_download(self) -> None:
        requested = self.serve({})
        build_kit(
            self.context("9.8.7", make_archive("9.8.7"), self.tagged_source()),
            self.tmp / "out" / "kit",
        )
        self.assertEqual(requested, [])

    def test_launchpad_status_compares_resolved_pointer_media(self) -> None:
        context = self.context("9.8.7", make_archive("9.8.7"), self.tagged_source())
        with mock.patch.object(release_stores, "http_json") as request:
            status = release_stores.launchpad_status(context)
        request.assert_not_called()
        self.assertEqual(status["status"], "blocked")
        self.assertIn("No KDockW Launchpad project", status["detail"])


@unittest.skipUnless(
    os.environ.get("KDOCKW_TEST_REAL_LFS") == "1",
    "set KDOCKW_TEST_REAL_LFS=1 to download and verify real Git LFS objects",
)
class RealLfsDownloadIntegrationTest(unittest.TestCase):
    """Opt-in network integration; deterministic unit tests above never fetch media."""

    def test_current_commit_lfs_objects_download_and_match_pointer(self) -> None:
        commit = subprocess.check_output(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True
        ).strip()
        seen: set[str] = set()
        downloaded = 0
        with tempfile.TemporaryDirectory(prefix="kdockw-real-lfs-") as tmp:
            pointer_path = Path(tmp) / "pointer"
            for channel in CHANNELS:
                schema = json.loads(
                    (REPO / SCHEMA_DIR / f"{channel}.json").read_text("utf-8")
                )
                for item in schema["media"]:
                    rel = item["source"]
                    if rel in seen:
                        continue
                    seen.add(rel)
                    pointer = subprocess.check_output(
                        ["git", "-C", str(REPO), "show", f"{commit}:{rel}"]
                    )
                    pointer_path.write_bytes(pointer)
                    parsed = prepare_submission_kit.lfs_pointer(
                        pointer_path, f"{channel} media {rel}"
                    )
                    if parsed is None:
                        continue
                    oid, size = parsed
                    url = (
                        f"{prepare_submission_kit.LFS_MEDIA_BASE}/thicking/kdockw/"
                        f"{commit}/{urllib.parse.quote(rel)}"
                    )
                    payload = prepare_submission_kit.fetch_lfs_object(url, oid, size)
                    downloaded += 1
                    self.assertEqual(len(payload), size, rel)
                    self.assertEqual(hashlib.sha256(payload).hexdigest(), oid, rel)
                    media_path = Path(tmp) / "download.png"
                    media_path.write_bytes(payload)
                    prepare_submission_kit.validate_png(
                        media_path, item["width"], item["height"], rel
                    )
        self.assertTrue(seen, "submission schemas contain no media")
        self.assertGreater(downloaded, 0, "commit contains no Git LFS media to verify")


class StoreReceiptLifecycleTest(ReleaseFixture):
    """State transitions of release_stores record/status with the public reads replaced by fixed responses."""

    def setUp(self) -> None:
        super().setUp()
        self.ctx = self.context("9.8.7", make_archive("9.8.7"), self.tagged_source())
        self.packet = self.tmp / "packet"
        release_stores.prepare(self.ctx, self.packet)
        description = (
            self.packet / "kit" / "alternativeto" / "description.txt"
        ).read_text(encoding="utf-8")
        self.paragraphs = [part for part in description.split("\n\n") if part.strip()]
        self.md5 = hashlib.md5(Path(self.ctx.archive).read_bytes()).hexdigest()
        self.receipts = Path(self.ctx.work_dir) / "store-receipts"

    # Helpers

    def record(
        self,
        store: str,
        state: str,
        reference: str | None = None,
        packet: Path | None = None,
    ) -> dict:
        return release_stores.record(
            self.ctx, self.packet if packet is None else packet, store, state, reference
        )

    def status(self, store: str) -> dict:
        return release_stores.status(self.ctx, [store])[0]

    def receipt(self, store: str) -> dict:
        return json.loads((self.receipts / f"{store}.json").read_text(encoding="utf-8"))

    def alternativeto_pages(
        self,
        *,
        paragraphs: list[str] | None = None,
        listing_status: int = 200,
        relation: bool = True,
    ):
        paragraphs = self.paragraphs if paragraphs is None else paragraphs
        # Rendered pages escape entities and reflow whitespace; the comparison must survive both.
        body = "".join(
            f"<p class='d'>\n    {html.escape(part).replace(' ', chr(10) + '  ', 3)}\n</p>"
            for part in paragraphs
        )
        listing = f'<html><body><main data-id="{release_stores.ALTERNATIVETO_ITEM}"><h1>KDockW</h1>{body}</main></body></html>'.encode()
        latte = (
            b'<a href="/software/kdockw/">KDockW</a>'
            if relation
            else b"<a href='/software/plank/'>Plank</a>"
        )

        def fetch(url: str, **_: object) -> tuple[int, bytes]:
            if url == release_stores.ALTERNATIVETO_URL:
                return listing_status, listing if listing_status == 200 else b""
            if url == release_stores.ALTERNATIVETO_LATTE_URL:
                return 200, latte
            raise AssertionError(f"unexpected fetch {url}")

        return mock.patch.object(release_stores, "http_bytes", side_effect=fetch)

    def ocs(self, version: str, filename: str | None = None, md5: str | None = None):
        record = {
            "id": release_stores.KDE_RECORD,
            "name": "Krema",
            "version": version,
            "downloadname1": filename or f"kdockw-{version}.tar.gz",
            "downloadmd5sum1": md5 or (self.md5 if version == "9.8.7" else "0" * 32),
        }
        return mock.patch.object(release_stores, "ocs_record", return_value=record)

    # AlternativeTo: do not assume listing identity after HTTP 403.

    def test_unverified_alternativeto_listing_is_blocked_without_requests_or_receipts(
        self,
    ) -> None:
        with mock.patch.object(release_stores, "http_bytes") as request:
            self.assertEqual(self.status("alternativeto")["status"], "blocked")
        request.assert_not_called()
        with self.assertRaisesRegex(ReleaseError, "identity and owner are unverified"):
            self.record("alternativeto", "start")
        self.assertFalse((self.receipts / "alternativeto.lock").exists())
        self.assertFalse((self.receipts / "alternativeto.json").exists())

    # Pending recovery and abort

    def test_pending_receipt_recovers_without_a_second_upload_session(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "belongs to Krema"):
            self.record("kde-store", "start")
        self.assertFalse((self.receipts / "kde-store.lock").exists())
        self.assertFalse((self.receipts / "kde-store.json").exists())

    def test_abort_releases_lock_without_a_readable_packet(self) -> None:
        self.receipts.mkdir(parents=True, exist_ok=True)
        (self.receipts / "kde-store.lock").write_text(
            json.dumps({"store": "kde-store", "tag": self.ctx.tag,
                        "commit": self.ctx.commit, "source_sha256": self.ctx.sha256}),
            encoding="utf-8",
        )
        if self.packet.exists():
            shutil.rmtree(self.packet)
        release_stores.record(self.ctx, None, "kde-store", "abort", None)
        self.assertFalse((self.receipts / "kde-store.lock").exists())
        with self.assertRaises(ReleaseError):
            release_stores.record(self.ctx, None, "kde-store", "abort", None)

    def test_abort_refuses_a_lock_owned_by_another_release(self) -> None:
        self.receipts.mkdir(parents=True)
        lock = self.receipts / "kde-store.lock"
        lock.write_text(
            json.dumps(
                {
                    "store": "kde-store",
                    "tag": "v0.0.1",
                    "commit": COMMIT,
                    "source_sha256": self.ctx.sha256,
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaises(ReleaseError):
            release_stores.record(self.ctx, None, "kde-store", "abort", None)
        self.assertTrue(lock.exists())

    def test_kde_store_record_is_blocked_and_cannot_claim_krema_listing(self) -> None:
        self.assertEqual(self.status("kde-store")["status"], "blocked")
        with self.assertRaisesRegex(ReleaseError, "belongs to Krema"):
            self.record("kde-store", "published")

    # Packet corruption

    def test_corrupted_packet_is_refused_before_a_lock(self) -> None:
        def edit_description(packet: Path) -> None:
            (packet / "kit" / "kde-store" / "description.txt").write_text(
                "changed\n", encoding="utf-8"
            )

        def add_unlisted_file(packet: Path) -> None:
            (packet / "kit" / "kde-store" / "media" / "extra.png").write_bytes(
                b"\x89PNG\r\n\x1a\n"
            )

        def drop_zip(packet: Path) -> None:
            (packet / "kit.zip").unlink()

        def symlink_description(packet: Path) -> None:
            target = packet / "kit" / "kde-store" / "description.txt"
            copy = packet / "description-copy.txt"
            shutil.copyfile(target, copy)
            target.unlink()
            target.symlink_to(copy)

        def forge_task_hash(packet: Path) -> None:
            stores = json.loads((packet / "stores.json").read_text(encoding="utf-8"))
            stores["browser_tasks"][0]["content_sha256"] = "0" * 64
            (packet / "stores.json").write_text(json.dumps(stores), encoding="utf-8")

        def consistent_rewrite(packet: Path) -> None:
            # Every checksum is rewritten to agree, but the task still names the prepared content.
            edit_description(packet)
            sums = packet / "kit" / "SHA256SUMS"
            lines = []
            for line in sums.read_text(encoding="utf-8").splitlines():
                name = line.split("  ", 1)[1]
                lines.append(
                    f"{hashlib.sha256((packet / 'kit' / name).read_bytes()).hexdigest()}  {name}"
                )
            sums.write_text("\n".join(lines) + "\n", encoding="utf-8")
            stores = json.loads((packet / "stores.json").read_text(encoding="utf-8"))
            stores["kit"]["sha256sums_sha256"] = hashlib.sha256(
                sums.read_bytes()
            ).hexdigest()
            (packet / "stores.json").write_text(json.dumps(stores), encoding="utf-8")

        def hide_review_flag(packet: Path) -> None:
            stores = json.loads((packet / "stores.json").read_text(encoding="utf-8"))
            stores["browser_tasks"][1]["claims_review_required"] = not stores[
                "browser_tasks"
            ][1]["claims_review_required"]
            (packet / "stores.json").write_text(json.dumps(stores), encoding="utf-8")

        def truncate_manifest(packet: Path) -> None:
            (packet / "stores.json").write_text(
                '{"schema_version": 1, "release": ', encoding="utf-8"
            )

        for mutate in (
            edit_description,
            add_unlisted_file,
            drop_zip,
            symlink_description,
            forge_task_hash,
            consistent_rewrite,
            hide_review_flag,
            truncate_manifest,
        ):
            with self.subTest(mutate.__name__):
                packet = self.tmp / f"packet-{mutate.__name__}"
                shutil.copytree(self.packet, packet, symlinks=True)
                mutate(packet)
                with self.assertRaises(ReleaseError):
                    self.record("kde-store", "start", packet=packet)
                self.assertFalse((self.receipts / "kde-store.lock").exists())

    # GitHub GraphQL error payloads

    def test_github_graphql_error_payloads_are_blocked(self) -> None:
        repo = {
            "homepage": release_stores.EXPECTED_HOMEPAGE,
            "description": "Dock",
            "topics": [],
        }
        for payload in (
            '{"errors": [], "data": null}',
            '{"errors": [{"message": "Bad credentials"}]}',
            "[]",
            '{"data": {"repository": null}}',
        ):
            with (
                self.subTest(payload),
                mock.patch.object(release_stores, "http_json", return_value=repo),
                mock.patch.object(release_stores, "command", return_value=payload),
            ):
                self.assertEqual(self.status("github")["status"], "blocked")


if __name__ == "__main__":
    unittest.main()
