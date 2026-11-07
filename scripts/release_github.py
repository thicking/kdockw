#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""GitHub release channel: the release for the tag plus immutable source assets.

The release carries ``kdockw-X.Y.Z.tar.gz`` (the context archive) and
``SHA256SUMS``. Existing assets are never replaced: an asset with the same
name and the same bytes counts as published, different bytes fail the
channel. An existing public release's title and notes are left untouched.

A new release is created as a private draft bound to the context commit,
with the notes re-verified against the tagged source immediately before.
The remote annotated tag object is read before the draft is created and
again right before the draft is published; any change, or a peeled commit
other than the context commit, leaves the draft unpublished and fails the
channel. GitHub has no compare-and-swap on a tag object, so a tag moved in
the short window between that final check and publication cannot be
excluded here; it is detected by the post-publication check and reported.
A draft this tooling did not create (different notes or target) blocks the
channel and is never edited or deleted.

Uses the authenticated ``gh`` CLI already configured on the machine. The
tag's automatic source archive, used only by ``release.py prepare`` for a
published release lacking ``kdockw-X.Y.Z.tar.gz``, is a public anonymous
HTTPS download confined to GitHub's archive hosts and size-capped.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from release_common import (
    USER_AGENT,
    ReleaseContext,
    ReleaseError,
    asset_name,
    command,
    expected_notes,
    redact,
    remote_tag_oids,
    result,
    sha256_bytes,
    sha256_file,
)

CHANNEL = "github"
SUMS_NAME = "SHA256SUMS"
API_TIMEOUT = 60
UPLOAD_TIMEOUT = 900
# GitHub's automatic source archive for a tag: streamed with a hard size cap.
ARCHIVE_TIMEOUT = 120
MAX_ARCHIVE_BYTES = 50 * 1024 * 1024
# Redirects may only stay on GitHub's own archive hosts; anything else fails.
_ARCHIVE_HOSTS = frozenset({"github.com", "codeload.github.com"})
PACKAGE_ARTIFACT_PREFIX = "kdockw-package-"


def _target_formats(context: ReleaseContext) -> dict[str, str]:
    path = context.source_dir / "tests/distro/targets.tsv"
    if path.is_symlink() or not path.is_file():
        raise ReleaseError("tagged source lacks tests/distro/targets.tsv")
    targets: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        extension = fields[-1]
        package_format = {"*.deb": "deb", "*.rpm": "rpm", "*.pkg.tar.zst": "arch"}.get(extension)
        if not package_format:
            raise ReleaseError(f"unsupported package format in target matrix: {extension}")
        if fields[0] in targets:
            raise ReleaseError(f"duplicate package target in matrix: {fields[0]}")
        targets[fields[0]] = package_format
    targets["arch"] = "arch"
    gate_path = context.source_dir / "tests/distro/release-targets.txt"
    if gate_path.is_symlink():
        raise ReleaseError("release target list must not be a symlink")
    if not gate_path.exists():
        # Immutable pre-v0.3.2 tags use the full historical matrix.
        return targets
    selected = [
        line.strip()
        for line in gate_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not selected or len(selected) != len(set(selected)):
        raise ReleaseError("release target list is empty or contains duplicates")
    unknown = sorted(set(selected) - targets.keys())
    if unknown:
        raise ReleaseError("release target list selects targets without package metadata: " + ", ".join(unknown))
    return {target: targets[target] for target in selected}


def _gh_json(args: list[str], *, timeout: int = API_TIMEOUT) -> Any:
    out = command(["gh", *args], timeout=timeout)
    try:
        return json.loads(out) if out.strip() else None
    except ValueError:
        raise ReleaseError("gh returned invalid JSON") from None


def find_releases(repository: str, tag: str) -> list[dict]:
    """All releases (drafts included) whose tag is ``tag``."""
    out = command(
        [
            "gh",
            "api",
            "--paginate",
            "-H",
            "Accept: application/vnd.github+json",
            f"repos/{repository}/releases?per_page=100",
            "--jq",
            f'.[] | select(.tag_name == "{tag}")',
        ],
        timeout=API_TIMEOUT,
    )
    releases = []
    for line in out.splitlines():
        if line.strip():
            try:
                releases.append(json.loads(line))
            except ValueError:
                raise ReleaseError("gh returned invalid release JSON") from None
    return releases


def download_asset(repository: str, tag: str, name: str) -> bytes:
    """Bytes of a release asset, downloaded to a private temporary directory."""
    with tempfile.TemporaryDirectory(prefix="kdockw-asset-") as tmp:
        command(
            [
                "gh",
                "release",
                "download",
                tag,
                "--repo",
                repository,
                "--pattern",
                name,
                "--dir",
                tmp,
            ],
            timeout=UPLOAD_TIMEOUT,
        )
        path = Path(tmp) / name
        if path.is_symlink() or not path.is_file():
            raise ReleaseError(f"downloaded asset {name} is missing")
        return path.read_bytes()


def tag_archive_url(repository: str, tag: str) -> str:
    """GitHub's automatic source archive for ``tag`` (root ``<repo>-<version>/``).

    Deliberately not the API ``tarball_url``: that endpoint serves other
    bytes rooted at ``<owner>-<repo>-<short sha>/``, which is neither the
    release layout nor what packagers already hold for a published tag.
    """
    return f"https://github.com/{repository}/archive/refs/tags/{tag}.tar.gz"


class _ArchiveRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        parts = urllib.parse.urlsplit(newurl)
        if parts.scheme != "https" or parts.hostname not in _ARCHIVE_HOSTS:
            raise ReleaseError(
                f"source archive redirect to {parts.scheme}://{parts.hostname or ''} refused"
            )
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_tag_archive(repository: str, tag: str) -> bytes:
    """Bytes of GitHub's automatic source archive for ``tag``.

    HTTPS only, redirects confined to GitHub's archive hosts, at most
    ``MAX_ARCHIVE_BYTES``. The bytes are not trusted here: the caller must
    bind their recorded commit and file manifest to the signed tag.
    """
    url = tag_archive_url(repository, tag)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    opener = urllib.request.build_opener(_ArchiveRedirect())
    chunks: list[bytes] = []
    total = 0
    try:
        with opener.open(request, timeout=ARCHIVE_TIMEOUT) as response:
            while chunk := response.read(1 << 20):
                total += len(chunk)
                if total > MAX_ARCHIVE_BYTES:
                    raise ReleaseError(
                        f"source archive for {tag} exceeds {MAX_ARCHIVE_BYTES} bytes"
                    )
                chunks.append(chunk)
    except urllib.error.HTTPError as exc:
        raise ReleaseError(f"GET {url} failed: HTTP {exc.code}") from None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        reason = getattr(exc, "reason", exc)
        raise ReleaseError(f"GET {url} failed: {redact(str(reason))}") from None
    return b"".join(chunks)


def remote_asset_sha256(repository: str, tag: str, asset: dict) -> str:
    """SHA-256 of an uploaded asset: GitHub's digest, else the downloaded bytes."""
    digest = asset.get("digest")
    if isinstance(digest, str) and digest.startswith("sha256:"):
        return digest.removeprefix("sha256:").lower()
    return sha256_bytes(download_asset(repository, tag, asset["name"]))


def classify_asset(
    expected_sha256: str, remote: dict | None, remote_sha256: str | None
) -> str:
    """``missing``, ``match``, ``mismatch`` or ``incomplete`` for one asset.

    ``remote`` is the GitHub asset object (None when absent) and
    ``remote_sha256`` its content hash. A partially uploaded asset
    (``state`` other than ``uploaded``) is ``incomplete``; it is never
    overwritten automatically.
    """
    if remote is None:
        return "missing"
    if remote.get("state", "uploaded") != "uploaded":
        return "incomplete"
    return "match" if remote_sha256 == expected_sha256 else "mismatch"


def _package_manifest(context: ReleaseContext) -> tuple[Path, list[dict]] | None:
    directory = context.work_dir / "github-packages" / "verified"
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        return None
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ReleaseError("package manifest is not a regular file")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise ReleaseError("package manifest is invalid") from None
    if (
        not isinstance(manifest, dict)
        or manifest.get("commit") != context.commit
        or manifest.get("version") != context.version
        or not isinstance(manifest.get("packages"), list)
    ):
        raise ReleaseError("package manifest does not match the release context")
    packages = manifest["packages"]
    targets = _target_formats(context)
    if sorted(item.get("target", "") for item in packages) != sorted(targets):
        raise ReleaseError("package manifest does not contain exactly the release target matrix")
    names: set[str] = set()
    for item in packages:
        if not isinstance(item, dict):
            raise ReleaseError("package manifest entry is invalid")
        target = item.get("target", "")
        package_format = item.get("format")
        suffix = {"deb": ".deb", "rpm": ".rpm", "arch": ".pkg.tar.zst"}.get(package_format)
        if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", target) or not suffix or targets[target] != package_format:
            raise ReleaseError("package manifest contains an invalid target or format")
        name = item.get("asset_filename")
        if name != f"kdockw-{context.version}-{target}{suffix}" or name in names:
            raise ReleaseError("package manifest contains an invalid or duplicate asset filename")
        names.add(name)
        path = directory / name
        if path.is_symlink() or not path.is_file() or sha256_file(path) != item.get("sha256"):
            raise ReleaseError(f"verified package bytes are missing or changed for {target}")
    return directory, packages


def expected_assets(context: ReleaseContext) -> dict[str, str]:
    assets = {asset_name(context.version): context.sha256}
    package_data = _package_manifest(context)
    if package_data:
        directory, packages = package_data
        for item in packages:
            assets[item["asset_filename"]] = item["sha256"]
    sums_text = "".join(f"{digest}  {name}\n" for name, digest in sorted(assets.items()))
    assets[SUMS_NAME] = sha256_bytes(sums_text.encode())
    return assets


def download_verified_packages(context: ReleaseContext) -> dict:
    """Download and validate all package artifacts from the exact green matrix run."""
    existing = _package_manifest(context)
    if existing:
        return {"targets": len(existing[1]), "source": "cached"}

    # Import at call time to avoid a module cycle: release.py owns the gate
    # decision and this function runs only after its context is established.
    import release

    decision = release.evaluate_gate(context)
    if decision.get("status") != "ready" or not decision.get("run_id"):
        raise ReleaseError("verified package artifacts require a full green Distro E2E run")
    run_id = str(decision["run_id"])
    targets = _target_formats(context)
    parent = context.work_dir / "github-packages"
    if parent.is_symlink():
        raise ReleaseError("package output directory is a symlink")
    parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    stage_root = Path(tempfile.mkdtemp(prefix=".packages-", dir=parent))
    packages: list[dict] = []
    try:
        for target in targets:
            if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", target):
                raise ReleaseError(f"invalid package target id {target!r}")
            artifact = f"{PACKAGE_ARTIFACT_PREFIX}{target}"
            target_dir = stage_root / target
            target_dir.mkdir()
            command(
                ["gh", "run", "download", run_id, "--repo", context.repository,
                 "--name", artifact, "--dir", str(target_dir)],
                timeout=UPLOAD_TIMEOUT,
            )
            manifest_path = target_dir / "manifest.json"
            if manifest_path.is_symlink() or not manifest_path.is_file():
                raise ReleaseError(f"package artifact {artifact} has no regular manifest")
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                raise ReleaseError(f"package artifact {artifact} has no valid manifest") from None
            package_files = [
                path for path in target_dir.iterdir()
                if path.name != "manifest.json" and path.is_file() and not path.is_symlink()
            ]
            if len(package_files) != 1 or any(
                path.is_symlink() or path.is_dir()
                for path in target_dir.iterdir()
            ):
                raise ReleaseError(f"package artifact {artifact} has an unexpected file layout")
            package = package_files[0]
            actual_hash = sha256_file(package)
            if (
                not isinstance(manifest, dict)
                or manifest.get("target") != target
                or manifest.get("commit") != context.commit
                or manifest.get("version") != context.version
                or manifest.get("filename") != package.name
                or manifest.get("sha256") != actual_hash
            ):
                raise ReleaseError(f"package artifact {artifact} does not match the release commit")
            package_format = manifest.get("format")
            extension = {"deb": ".deb", "rpm": ".rpm", "arch": ".pkg.tar.zst"}.get(package_format)
            if not extension or targets[target] != package_format or not package.name.endswith(extension):
                raise ReleaseError(f"package artifact {artifact} has an unsupported package format")
            asset_filename = f"kdockw-{context.version}-{target}{extension}"
            shutil.copyfile(package, stage_root / asset_filename)
            packages.append({
                "target": target,
                "format": package_format,
                "source_filename": package.name,
                "asset_filename": asset_filename,
                "sha256": actual_hash,
            })
        aggregate = {
            "run_id": run_id,
            "commit": context.commit,
            "version": context.version,
            "packages": packages,
        }
        (stage_root / "manifest.json").write_text(
            json.dumps(aggregate, sort_keys=True, indent=2) + "\n", encoding="utf-8"
        )
        # Publish the complete directory atomically and refuse replacing any
        # pre-existing result, even if a previous attempt was interrupted.
        final = parent / "verified"
        if os.path.lexists(final):
            raise ReleaseError("verified package directory already exists without a matching manifest")
        os.replace(stage_root, final)
        return {"targets": len(packages), "run_id": run_id, "source": "distro-e2e"}
    except BaseException:
        if stage_root.exists():
            shutil.rmtree(stage_root, ignore_errors=True)
        raise


def remote_tag_object(context: ReleaseContext) -> str:
    """The remote annotated tag object id, after checking it peels to the context commit."""
    refs = remote_tag_oids(context.repository, context.tag)
    obj = refs.get(f"refs/tags/{context.tag}")
    peeled = refs.get(f"refs/tags/{context.tag}^{{}}")
    if obj is None:
        raise ReleaseError(f"tag {context.tag} is not on {context.repository}")
    if peeled != context.commit:
        raise ReleaseError(
            f"remote tag {context.tag} resolves to {peeled or obj}, context has {context.commit}"
        )
    return obj


def inspect(context: ReleaseContext) -> dict:
    """Read-only comparison of GitHub with the context.

    Returns {"state": "missing"|"draft"|"ambiguous"|"present", "id": <id>,
    "release": <url or None>, "assets": {name: classification}} and, for a
    draft, "ours": whether its notes and target are exactly what this
    context would create.
    """
    releases = find_releases(context.repository, context.tag)
    if not releases:
        return {"state": "missing", "id": None, "release": None, "assets": {}}
    if len(releases) > 1:
        return {"state": "ambiguous", "id": None, "release": None, "assets": {}}
    release = releases[0]
    remote = {asset.get("name"): asset for asset in release.get("assets", [])}
    assets: dict[str, str] = {}
    for name, wanted in expected_assets(context).items():
        asset = remote.get(name)
        remote_sha = None
        if asset is not None and asset.get("state", "uploaded") == "uploaded":
            remote_sha = remote_asset_sha256(context.repository, context.tag, asset)
        assets[name] = classify_asset(wanted, asset, remote_sha)
    out = {
        "state": "draft" if release.get("draft") else "present",
        "id": release.get("id"),
        "release": release.get("html_url"),
        "assets": assets,
    }
    if release.get("draft"):
        out["ours"] = (
            release.get("target_commitish") == context.commit
            and release.get("body") == expected_notes(context).decode()
        )
    return out


def _report(context: ReleaseContext, found: dict, *, planning: bool) -> dict:
    state, assets, url = found["state"], found["assets"], found["release"]
    extra = {"release_url": url, "assets": assets, "version": context.version}
    if state == "ambiguous":
        return result(
            CHANNEL, "failed", f"more than one release uses tag {context.tag}", **extra
        )
    if state == "draft" and not found["ours"]:
        return result(
            CHANNEL,
            "blocked",
            f"a draft release for {context.tag} with other notes or target exists; publish or delete it by hand",
            **extra,
        )
    if state == "missing":
        verb = "would create" if planning else "not created:"
        return result(
            CHANNEL,
            "planned",
            f"{verb} release {context.tag} with {', '.join(expected_assets(context))}",
            **extra,
        )
    bad = sorted(
        name for name, kind in assets.items() if kind in ("mismatch", "incomplete")
    )
    if bad:
        return result(
            CHANNEL,
            "failed",
            f"existing assets differ from the context and are never overwritten: {', '.join(bad)}",
            **extra,
        )
    missing = sorted(name for name, kind in assets.items() if kind == "missing")
    if state == "draft":
        todo = f"upload {', '.join(missing)} and " if missing else ""
        verb = "would resume" if planning else "unpublished:"
        return result(
            CHANNEL,
            "planned",
            f"{verb} draft release {context.tag}: {todo}publish",
            **extra,
        )
    if missing:
        verb = "would upload" if planning else "missing assets:"
        return result(CHANNEL, "planned", f"{verb} {', '.join(missing)}", **extra)
    return result(
        CHANNEL, "already_published", "release and assets match the context", **extra
    )


def status(context: ReleaseContext) -> dict:
    return _report(context, inspect(context), planning=False)


def _sums_file(context: ReleaseContext) -> Path:
    """Create ``github-upload/SHA256SUMS`` atomically, never clobbering.

    The bytes are written to a private temporary file and hard-linked into
    place, so an interruption never leaves a truncated file and an existing
    file (or a dangling symlink) is never followed or replaced.
    """
    upload_dir = context.work_dir / "github-upload"
    if upload_dir.is_symlink():
        raise ReleaseError(f"{upload_dir} is a symlink")
    upload_dir.mkdir(mode=0o755, exist_ok=True)
    path = upload_dir / SUMS_NAME
    sums = expected_assets(context)
    sums.pop(SUMS_NAME, None)
    content = "".join(
        f"{digest}  {name}\n" for name, digest in sorted(sums.items())
    ).encode()
    if not os.path.lexists(path):
        fd, tmp = tempfile.mkstemp(prefix=f".{SUMS_NAME}.", dir=upload_dir)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp, 0o644)
            try:
                os.link(tmp, path)
            except FileExistsError:
                pass
        finally:
            os.unlink(tmp)
    if path.is_symlink() or not path.is_file():
        raise ReleaseError(f"{path} is not a regular file")
    if path.read_bytes() != content:
        raise ReleaseError(f"{path} exists with different content")
    return path


def _require_tag(context: ReleaseContext, expected: str) -> None:
    if remote_tag_object(context) != expected:
        raise ReleaseError(f"remote tag {context.tag} moved during publication")


def publish(context: ReleaseContext, *, execute: bool = False) -> dict:
    found = inspect(context)
    report = _report(context, found, planning=True)
    if not execute or report["status"] != "planned":
        return report

    draft_left = found["state"] == "draft"
    try:
        tag_object = remote_tag_object(context)
        if context.notes_path.read_bytes() != expected_notes(context):
            return result(CHANNEL, "failed", "notes changed after context validation")
        if sha256_file(context.archive) != context.sha256:
            return result(CHANNEL, "failed", "archive changed after context validation")
        files = {
            asset_name(context.version): context.archive,
            SUMS_NAME: _sums_file(context),
        }
        package_data = _package_manifest(context)
        if package_data:
            package_dir, packages = package_data
            for item in packages:
                files[item["asset_filename"]] = package_dir / item["asset_filename"]

        if found["state"] == "present":
            todo = [
                str(files[name])
                for name, kind in found["assets"].items()
                if kind == "missing"
            ]
            command(
                [
                    "gh",
                    "release",
                    "upload",
                    context.tag,
                    *todo,
                    "--repo",
                    context.repository,
                ],
                timeout=UPLOAD_TIMEOUT,
            )
        else:
            if found["state"] == "missing":
                command(
                    [
                        "gh",
                        "release",
                        "create",
                        context.tag,
                        "--repo",
                        context.repository,
                        "--draft",
                        "--verify-tag",
                        "--target",
                        context.commit,
                        "--title",
                        context.tag,
                        "--notes-file",
                        str(context.notes_path),
                    ],
                    timeout=UPLOAD_TIMEOUT,
                )
                draft_left = True
                found = inspect(context)
                if found["state"] != "draft" or not found.get("ours"):
                    raise ReleaseError(
                        f"the created draft for {context.tag} could not be verified as the only matching draft"
                    )
            todo = [
                str(files[name])
                for name, kind in found["assets"].items()
                if kind == "missing"
            ]
            if todo:
                command(
                    [
                        "gh",
                        "release",
                        "upload",
                        context.tag,
                        *todo,
                        "--repo",
                        context.repository,
                    ],
                    timeout=UPLOAD_TIMEOUT,
                )
            found = inspect(context)
            if (
                found["state"] != "draft"
                or not found.get("ours")
                or set(found["assets"].values()) != {"match"}
            ):
                raise ReleaseError("draft assets or notes do not match the context")
            _require_tag(context, tag_object)
            command(
                [
                    "gh",
                    "api",
                    "--method",
                    "PATCH",
                    f"repos/{context.repository}/releases/{found['id']}",
                    "-F",
                    "draft=false",
                ],
                timeout=API_TIMEOUT,
            )
            draft_left = False
        _require_tag(context, tag_object)
    except ReleaseError as exc:
        detail = f"GitHub publication failed: {exc}"
        if draft_left:
            detail += "; the release remains an unpublished draft"
        return result(CHANNEL, "failed", detail, version=context.version)

    after = inspect(context)
    verified = _report(context, after, planning=False)
    if verified["status"] != "already_published":
        return result(
            CHANNEL,
            "failed",
            f"post-upload verification failed: {verified['detail']}",
            release_url=after["release"],
            assets=after["assets"],
            version=context.version,
        )
    return result(
        CHANNEL,
        "published",
        f"release {context.tag} carries verified {', '.join(files)}",
        release_url=after["release"],
        assets=after["assets"],
        version=context.version,
    )
