# KDockW 0.1.0 release readiness audit

Audit date: 2026-11-03
Audited commit: `90b97f452db6da8892fbea68e019ad9e4699e55f` (`main`, same as `origin/main`)
Scope: source integrity, release metadata/tooling, automated checks, Wayland acceptance, security, migration, and supported packaging channels. This is an audit record; no product or packaging fixes were made.

## Verdict: NO-GO for v0.1.0 publication

The audited source archive configures and builds cleanly in an isolated Release build, and the product version is consistently `0.1.0-dev` in the application and the current development metadata. That does not yet establish a releasable v0.1.0 candidate.

The release gate is not currently evidenced on the default branch, the release instructions still target `master` although GitHub's default branch is `main`, there is no current green workflow run, real Plasma/Wayland acceptance has not been performed for this audit, and the version metadata regression test only accepts development-form values. In addition, the AUR release renderer tests fail against the current PKGBUILD. Debian/RPM/Arch publication has separate packaging blockers recorded below. Findings are split by scope: package-only issues do not invalidate the source archive, but source and release-gate evidence is not complete enough for a public v0.1.0 release.

## Headline findings

- **Source archive:** verified GitHub-generated archive for the audited commit builds successfully. It contains 73 Git LFS pointer files, all in branding/website media; build inputs and installable app icons are ordinary Git blobs. The archive is usable for building, but its promotional media are not hydrated.
- **Automated release tests:** 128 passed, 23 failed, 1 skipped across the five release Python suites. Two AUR renderer tests fail because the renderer only accepts an uncommented one-line `sha256sums=(...)`, while the committed recipe appends a comment. Twenty-one submission-kit failures all trace to test fixtures resolving LFS media at a synthetic commit URL that returns HTTP 404; this does not prove that every submission flow is broken, but the suite is not green.
- **CI:** GitHub reports default branch `main`; build/E2E and image push triggers still name `master`. CI is PR-triggered, while this repository has no recorded Actions runs on `main` at audit time.
- **Interactive QA:** no fresh real Plasma/Wayland run was performed for this audit. Historical manual reports are not substituted for acceptance of the audited commit.
- **Versioning:** current development metadata is `0.1.0-dev`; no local or remote `v0.1.0` tag was found. `tests/check_version_metadata.cmake` hard-codes development metadata expectations, so it will reject a stable release metadata set unless revised as part of release preparation.
- **Native packages:** Arch uses `sha256sums=('SKIP')`; Debian source metadata contains zero hash/size placeholders and an inherited maintainer identity; RPM's source-version macro is explicitly `0.1.0-dev`. The AUR renderer is currently test-failing. These are channel blockers, not evidence that the source archive itself cannot build.
- **Flatpak:** retained as a historical local validation artifact based on Krema v0.9.0, not current KDockW packaging or a Flathub-ready release. Its own report records official lint failures and an unresolved native host-launch path.

See [FINDINGS.md](FINDINGS.md), [TEST-MATRIX.md](TEST-MATRIX.md), [PACKAGING.md](PACKAGING.md), [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md), [RELEASE-PLAN.md](RELEASE-PLAN.md), and [manual tests in Russian](MANUAL-TESTS.ru.md).

## Audit method and limits

The review used source/history inspection, GitHub repository and Actions metadata, a downloaded GitHub source archive, isolated temporary build paths, selected local validation commands, and local release test suites. It did not alter installed KDockW, KDE/Wayland session state, package repositories, or release destinations. A release tag, GitHub Release, package upload, and distro matrix dispatch were not created.

The complete evidence and the boundary between verified, partial, unverified, and not-tested results are recorded in the linked reports. Findings are not fixes, and no finding should be treated as resolved until its stated verification method passes.
