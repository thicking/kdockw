# v0.1.0 release checklist

Do not mark a box complete based only on this audit. The checklist is a release handoff for a future explicitly authorized candidate.

## Source identity and version

- [ ] Confirm `main` is the GitHub default branch and release docs/workflows use it.
- [ ] Keep current `0.1.0-dev` work separate from a stable release commit.
- [ ] Synchronize CMake canonical version, About/CLI, AppStream, catalog header, changelog, desktop metadata and native package versions.
- [ ] Update version-metadata test to cover dev and stable values.
- [ ] Confirm local and remote `v0.1.0` tag namespace is free immediately before tagging.
- [ ] Verify signed annotated tag with the configured pinned release signer.
- [ ] Verify tag commit is reachable from default branch and exact archive manifest matches the tagged tree.

## Build and quality gates

- [ ] Clean Release configure/build from the exact source archive.
- [ ] Run complete CTest unit, integration, KWin, QML and CLI suites.
- [ ] Run release tooling tests; AUR renderer and submission media fixture failures are resolved and all suites pass.
- [ ] Run `msgfmt --check --check-format`, AppStream, desktop-file, license/SPDX and `git diff --check` validations.
- [ ] Run Appium E2E and the full distro E2E matrix on the exact candidate SHA.
- [ ] Verify CI run records reflect GitHub `main`, not a stale `master` branch.

## Manual acceptance

- [ ] Complete [MANUAL-TESTS.ru.md](MANUAL-TESTS.ru.md) on real Plasma Wayland.
- [ ] Test both Wayland-native and XWayland windows and app launchers.
- [ ] Confirm previews, task list, focus, drag/drop, settings persistence, autohide and zoom animation.
- [ ] Capture dynamic behavior from the candidate build and retain evidence suitable for release review.
- [ ] Test migration and rollback with isolated user configuration; do not overwrite a real user's files during QA.

## Package-specific gates

- [ ] Arch/AUR: verified source SHA-256; generated `.SRCINFO`; successful clean Arch package build/install.
- [ ] RPM/OBS/COPR: stable `Version` and `upstream_version`; exact source tag and prep directory; target RPM builds and E2E.
- [ ] Debian/OBS/PPA: actual `.dsc` checksums/sizes; authorized Maintainer identity; successful source/binary build and target tests.
- [ ] Flatpak: advertise only if a KDockW-source manifest is prepared, official lint is addressed, and installed host Wayland tests pass.
- [ ] Label historical submission kits and local Flatpak artifacts separately from published release channels.

## Publication controls

- [ ] Prepare and inspect release plan/context; verify no credentials enter files, logs, URLs or process arguments.
- [ ] Reconfirm destination repository and branch; never force-push.
- [ ] Publish only destinations authorized by the specific release request.
- [ ] Verify each channel's public artifact and build result; `submitted` is not `published`.
- [ ] Update changelog/release docs only after the released version is actually established.
