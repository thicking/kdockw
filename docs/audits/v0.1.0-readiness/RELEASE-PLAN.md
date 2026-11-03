# Recommended release plan

Current state: development version `0.1.0-dev`; audit verdict is **NO-GO for v0.1.0 publication**. This sequence is a plan, not authorization to perform a release.

## Gate 1 — fix source/release readiness

1. Align GitHub workflows and `.agents/skills/release/SKILL.md` with default branch `main`; make sure required checks run on a release candidate.
2. Update version consistency tests to accept stable metadata and preserve dev tests.
3. Resolve AUR renderer compatibility and make submission-kit media tests deterministic with real/hydrated or mocked content-addressed assets.
4. Complete full unit, QML, integration, Appium and distro E2E suites on one candidate SHA.
5. Complete manual Plasma Wayland and XWayland acceptance; record exact versions and evidence.

## Gate 2 — channel readiness

1. Arch: compute source archive SHA-256; remove `SKIP` from generated release recipe; build package in Arch.
2. RPM: update source-version macro with the stable version; build on each advertised RPM target.
3. Debian: create real descriptor hashes and size; verify authorized maintainer details; build and validate Debian packages.
4. Decide explicitly whether Flatpak is excluded from v0.1.0. Do not use the historical Krema v0.9.0 manifest as KDockW release evidence.

## Gate 3 — source release

1. Prepare a stable-version commit with changelog and AppStream release metadata.
2. Run all checks again on the exact commit and inspect generated deterministic archive.
3. Dispatch the full distro matrix on `main` for that exact SHA and wait for all jobs to succeed.
4. Create a signed annotated `v0.1.0` tag only after the full gate is green.
5. Verify tag signature, default-branch ancestry, archive root/manifest, and source checksum.

## Gate 4 — authorized publication

1. Review release CLI plans and the exact target list.
2. Publish only channels explicitly included in the release authorization.
3. Verify artifacts/builds publicly. Record failed, pending and unavailable channels without describing them as published.
4. Keep store submissions that require a browser as explicit handoffs until their public listings are confirmed.

## Scope boundary

This audit did not create commits, release tags, packages or GitHub releases. Its own documentation commit is not a product release commit. It did not install or restart KDockW or alter Plasma, KWin, systemd, drivers or package configuration.
