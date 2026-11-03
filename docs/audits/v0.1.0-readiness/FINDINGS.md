# Findings

Audited commit: `90b97f452db6da8892fbea68e019ad9e4699e55f` (2026-11-03). Severity is scoped to the named release channel. `VERIFIED` means the condition is directly established; `PARTIAL` means evidence covers only part of the claim; `UNVERIFIED` and `NOT_TESTED` identify missing evidence rather than an assumed defect.

## REL-001 — Default branch and release instructions disagree

- **Severity/status:** BLOCKER / VERIFIED
- **Scope:** source release and release gate
- **Evidence:** GitHub API reports `default_branch=main`; local `main` tracks `origin/main`. `.github/workflows/e2e.yml` and `ci-images.yml` push triggers target `master`. `.agents/skills/release/SKILL.md` requires `master`/`origin/master` and dispatches `distro-e2e.yml --ref master`. GitHub Actions API reported zero runs for `main` at audit time.
- **Impact:** the documented release sequence does not target the authoritative branch, and a release commit on `main` has no current push-triggered build/E2E evidence. The release gate could be run manually, but the present procedure does not provide evidence that it was run on the release commit.
- **Required action:** align release instructions and workflow triggers with the real default branch, then run the complete build and distro gate on the exact candidate SHA.
- **Verification:** inspect workflow run records and `scripts/release.py gate` context to prove every required job passed on the candidate commit.

## REL-002 — No real Plasma/Wayland acceptance for audited revision

- **Severity/status:** HIGH / NOT_TESTED
- **Scope:** source release
- **Evidence:** this audit performed no interactive session test. Historical documentation mentions a manual Dolphin multi-file drag check on Plasma 6.6.6, but it predates the audited commit and does not cover the complete current release matrix.
- **Impact:** visual behavior, KWin permissions, PipeWire previews, task discovery, auto-hide, and session integration are not accepted for this candidate.
- **Required action:** complete [MANUAL-TESTS.ru.md](MANUAL-TESTS.ru.md) on a real supported Plasma Wayland session and attach evidence to the release review.
- **Verification:** record OS, Plasma/Qt/KF versions, GPU/session details, exact commit, observed results, and media for dynamic interactions.

## REL-003 — Version metadata check only accepts development form

- **Severity/status:** HIGH / VERIFIED
- **Scope:** source release
- **Evidence:** `tests/check_version_metadata.cmake` unconditionally expects an AppStream development release, `0.1.0_pre`, RPM `~dev`, and Debian `~dev-1`. `CMakeLists.txt` currently declares `KDOCKW_VERSION=0.1.0-dev`. The current development check passes, but no stable-form mode is represented.
- **Impact:** changing the canonical version to `0.1.0` for release makes the existing consistency test fail, or requires disabling it; either path weakens release metadata verification.
- **Required action:** make the test validate both valid development and stable metadata according to the canonical version, then run it against both forms in isolated fixtures.
- **Verification:** run CTest/current metadata check for `0.1.0-dev` and a disposable stable candidate and confirm matching AppStream, Arch, RPM, Debian, catalog, CLI and About values.

## REL-004 — AUR release renderer cannot process committed checksum line

- **Severity/status:** HIGH / VERIFIED
- **Scope:** AUR channel only
- **Evidence:** `scripts/release_aur.py::render_pkgbuild` matches only `^sha256sums=\(.*\)$`. `packaging/arch/PKGBUILD` has `sha256sums=('SKIP') # No independent KDockW release archive exists yet.` Running `tests/release/test_release_aur.py` produced two failures: renderer found zero checksum definitions.
- **Impact:** the release adapter cannot render a correctly hashed candidate PKGBUILD from the committed template; AUR publication is blocked.
- **Required action:** accept the actual recipe form or stage a release template with a machine-parseable checksum declaration; do not publish while checksum remains `SKIP`.
- **Verification:** AUR renderer suite passes and rendered `PKGBUILD`/`.SRCINFO` contain the exact tag URL, verified archive SHA-256 and package version.

## REL-005 — Debian source descriptor has placeholder integrity data

- **Severity/status:** HIGH / VERIFIED
- **Scope:** Debian/OBS/PPA package channels
- **Evidence:** `packaging/obs/kdockw.dsc` contains `Files: 00000000000000000000000000000000 0 kdockw-0.1.0-dev.tar.gz`. The OBS adapter copies and validates version/name metadata, but its `build_obs_inputs` path does not replace this placeholder with digest and size of the release tarball.
- **Impact:** Debian source integrity metadata is not ready to describe a real source archive; downstream source-package validation/build may reject it.
- **Required action:** generate and verify actual source hashes and size from the exact signed-tag archive before any Debian-family submission.
- **Verification:** run `dpkg-source --check`/source package build from the prepared release context and compare descriptor hash/size to the archive bytes.

## REL-006 — Debian Maintainer field is inherited and not confirmed for KDockW

- **Severity/status:** HIGH / VERIFIED
- **Scope:** Debian/OBS/PPA package channels
- **Evidence:** both `packaging/obs/kdockw.dsc` and `packaging/obs/debian.control` declare `Byeonghoon Yoo <bhyoo@bhyoo.com>` as Maintainer; no current authorization or KDockW maintainer contact was established by this audit. Historical Krema authorship remains valid attribution, but it does not establish current package maintenance.
- **Impact:** package upload would attribute current package maintenance to an inherited identity without verified authorization.
- **Required action:** obtain the authorized KDockW package maintainer identity/contact and update Debian metadata with that identity while preserving source copyright/license notices.
- **Verification:** review generated source package control metadata and confirm the named maintainer has explicitly accepted maintenance.

## REL-007 — RPM source macro is pinned to the prerelease string

- **Severity/status:** MEDIUM / VERIFIED
- **Scope:** RPM/OBS/COPR package channels
- **Evidence:** `packaging/obs/kdockw.spec` has `Version: 0.1.0~dev` and `%global upstream_version 0.1.0-dev`; `Source0` and `%autosetup` both use this macro. Release adapter validates `Version` but does not rewrite the macro. The release skill requires version metadata to be synchronized manually.
- **Impact:** updating only the package `Version` for stable `0.1.0` leaves the source URL and extracted directory at the development version.
- **Required action:** synchronize the macro and validate generated source URL/extraction root as part of stable candidate preparation.
- **Verification:** build the RPM from the candidate tag and verify Source0 downloads that exact tag and `%prep` extracts the matching tree.

## REL-008 — Release test suite is not green; failures are partly fixture/environment related

- **Severity/status:** HIGH / VERIFIED
- **Scope:** release tooling confidence
- **Evidence:** `python3 -m pytest -q tests/release/test_release_core.py tests/release/test_release_aur.py tests/release/test_release_ppa.py tests/release/test_release_rpm.py tests/release/test_submission_kit.py`: 128 passed, 23 failed, 1 skipped. Two AUR failures are the verified renderer mismatch in REL-004. Twenty-one submission-kit failures resolve media against a synthetic all-zero-like commit URL returning HTTP 404; this checkout has LFS pointers rather than hydrated media and `git-lfs` is unavailable. These 21 failures do not establish a production submission defect, but they show this test invocation cannot validate that path in the current fixture.
- **Impact:** release tooling is not fully validated and the suite cannot be used as a green release signal.
- **Required action:** repair the AUR compatibility defect and provide deterministic/hydrated media fixtures or mock the immutable media fetch for submission tests; rerun all release tests.
- **Verification:** all five suites pass in an environment with explicit fixture provenance; separate any remaining network/service tests from deterministic unit tests.

## REL-009 — GitHub source archive contains LFS pointers for non-build media

- **Severity/status:** LOW / VERIFIED
- **Scope:** source archive and submission media
- **Evidence:** downloaded GitHub archive at the audited SHA contains 540 files, including 73 Git LFS pointer files under branding/website media. The actual CMake build inputs and installed icon assets are normal Git blobs, and the source archive built successfully. `git-lfs` is not installed in the audit environment; `.git/lfs/objects` is empty.
- **Impact:** compiling from the source archive is unaffected, but screenshots/banners in the archive are not usable as images without fetching the corresponding LFS objects. Submission tooling must receive the exact verified LFS assets separately.
- **Required action:** make the release archive/media-generation instructions explicitly LFS-aware and validate every redistributed or upload media byte against its declared digest.
- **Verification:** inspect the final candidate archive and confirm required source files are regular blobs; for media, verify fetched object SHA-256/size.

## REL-010 — Flatpak artifact is a historical Krema-based experiment, not a KDockW release

- **Severity/status:** HIGH / VERIFIED
- **Scope:** Flatpak channel only
- **Evidence:** `packaging/flatpak/README.md` documents unchanged v0.9.0 app code and a manifest source at Krema v0.9.0. It records official lint failures, a host-application launch failure, and preview capture blocked by the test compositor; no Flathub acceptance is claimed. `packaging/submissions/flathub-research.md` says no manifest contribution is prepared.
- **Impact:** a Flatpak package or Flathub release must not be advertised as KDockW 0.1.0 or as a supported, validated channel.
- **Required action:** keep this artifact clearly marked historical/local; before Flatpak distribution, create a KDockW-source manifest and complete official lint plus installed-host Wayland tests.
- **Verification:** manifest source points to the signed KDockW tag, official lint passes or has documented upstream-approved exceptions, and runtime checks pass on supported hosts.

## REL-011 — Stable release tag and publication do not yet exist

- **Severity/status:** LOW / VERIFIED
- **Scope:** source release
- **Evidence:** local tags contain Krema tags through `v0.12.0` and no `v0.1.0`; `git ls-remote --tags origin refs/tags/v0.1.0*` returned no match. The repository version is still `0.1.0-dev`.
- **Impact:** expected for a development candidate, but there is no published stable source release to audit as an existing artifact.
- **Required action:** after all release blockers pass, prepare the stable versioned commit, rerun checks, run full distro gate on that SHA, then create the signed tag and publish only under an explicitly authorized release request.
- **Verification:** signed annotated `v0.1.0` tag resolves to the reviewed commit; GitHub release/source archive matches deterministic manifest and SHA-256.

## REL-012 — No release-candidate Wayland/XWayland test evidence

- **Severity/status:** HIGH / NOT_TESTED
- **Scope:** source release
- **Evidence:** this audit did not run Appium E2E, distro E2E, a live KWin session, Wayland-native or XWayland application coverage. Local container tooling lacks Docker; the host release CTest attempt was interrupted after `kdockw_cli_unknown_option` hit its 120-second timeout. See [TEST-MATRIX.md](TEST-MATRIX.md).
- **Impact:** task discovery, drag/drop, activation, preview, settings lifecycle and visual behavior have not been accepted on the audited revision.
- **Required action:** run automated suites in the supported CI images and complete the manual matrix on a real Wayland desktop.
- **Verification:** green CI on the candidate SHA plus recorded manual observations for native Wayland and XWayland windows.

## REL-013 — Release skill default repository is stale

- **Severity/status:** MEDIUM / VERIFIED
- **Scope:** release operations
- **Evidence:** `scripts/release.py` sets `DEFAULT_REPOSITORY = "thicking/kdockw"`; `.agents/skills/release/SKILL.md` says `--repository` defaults to `isac322/kdockw` and the procedure still uses `master`.
- **Impact:** operators following the skill may inspect or dispatch against the wrong repository/branch even though the CLI default is correct.
- **Required action:** synchronize release documentation with the executable's repository and GitHub default branch before relying on it.
- **Verification:** dry-run release CLI and documented commands resolve to `thicking/kdockw` and `main`.

## REL-014 — No supported package build was confirmed in this audit

- **Severity/status:** HIGH / NOT_TESTED
- **Scope:** Arch, RPM, Debian, OBS and PPA channels
- **Evidence:** `makepkg`, `rpmspec`, Docker and Flatpak Builder are unavailable. `dpkg-buildpackage` exists but no production package was built; the Debian metadata blockers above remain. No OBS/COPR/PPA upload or remote build was dispatched.
- **Impact:** binary package dependencies, install manifests and runtime metadata have no fresh candidate-build evidence.
- **Required action:** build each supported package in its target environment after fixing channel blockers; do not infer package readiness from the clean source build.
- **Verification:** successful package build and install/test jobs for each advertised channel using the exact candidate tag.

## REL-015 — Current development source and AppStream metadata are coherent

- **Severity/status:** LOW / VERIFIED
- **Scope:** positive control
- **Evidence:** `KDOCKW_VERSION` is `0.1.0-dev`; executable from clean archive reports `kdockw 0.1.0-dev`; AppStream validates; `tests/check_version_metadata.cmake` passes for the current development value. No v0.1.0 tag exists.
- **Impact:** confirms current development identity, not stable-release readiness.
- **Required action:** retain this as baseline; run the updated metadata test again for both development and stable candidate versions.
- **Verification:** compare CLI, KAboutData, AppStream, translation catalog and package forms after candidate preparation.

## REL-016 — Migration and rollback scripts preserve existing settings in isolation

- **Severity/status:** LOW / VERIFIED
- **Scope:** user migration safety
- **Evidence:** `bash tests/migration-scripts.sh "$PWD"` passed using temporary XDG paths. The test confirmed an existing KDockW config is not overwritten, original Krema settings remain, and rollback does not remove KDockW service/desktop/autostart files.
- **Impact:** the tested migration path is isolated and does not require release-blocking changes; this does not verify every user's real config.
- **Required action:** retain isolated migration regression coverage and include backup/rollback directions in user-facing upgrade notes.
- **Verification:** rerun the isolated test and inspect its temporary fixture assertions on each migration change.
