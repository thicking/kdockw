# Test matrix

Audited source: `90b97f452db6da8892fbea68e019ad9e4699e55f`. A passing build or test is not a substitute for live Wayland acceptance.

## Executed in this audit

| Check | Result | Evidence / limits |
| --- | --- | --- |
| GitHub source archive download and inventory | PASS | Archive SHA-256 `381480ca964d66d6c70505318497c9f8f700d2f4780f6c766b1fd4e1dd0d6cb3`; 540 files, 73 LFS pointer files. |
| Clean Release configure/build from extracted GitHub archive | PASS | Isolated `/tmp` source/build/prefix, `BUILD_TESTING=OFF`; `kdockw` reports `0.1.0-dev`. Configure emits non-fatal “not a git repository” notices and a missing generated include-dir warning. No install was run. |
| AppStream validation | PASS | `appstreamcli validate --no-net src/com.thicking.kdockw.metainfo.xml` |
| Current version metadata consistency | PASS | `cmake -DSOURCE_DIR="$PWD" -DKDOCKW_VERSION=0.1.0-dev -P tests/check_version_metadata.cmake`; this validates only current dev form. |
| Migration/rollback regression | PASS | `bash tests/migration-scripts.sh "$PWD"`; temporary XDG directory only. |
| Release Python suites | FAIL | `128 passed, 23 failed, 1 skipped`. 2 AUR renderer tests fail on the current commented checksum line; 21 submission-kit tests fail fetching LFS media from a synthetic fake commit URL (HTTP 404). See REL-004 and REL-008. |
| GitHub Actions status | NO RUNS | GitHub repository API reports default `main`; Actions run API for `main` returned `total_count=0` at audit time. |

## Attempted, interrupted, or unavailable

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Host CTest private-KWin case `kdockw_cli_unknown_option` | TIMEOUT / INCOMPLETE | During a prior local attempt it printed the expected unknown-option message, then CTest reached its 120-second timeout. Logs also showed portal/FUSE permission warnings. The cause was not isolated. Later test cases were not run. |
| Full CTest/QML/KWin suite for this audit | NOT RUN | The clean source-archive build used `BUILD_TESTING=OFF`; no claim that unit or QML suites passed on this audit run. |
| Appium/distro E2E | NOT RUN | Docker unavailable in the audit environment; workflows also target `master` on push while default branch is `main`. |
| Native Plasma/Wayland and XWayland manual checks | NOT RUN | This audit did not exercise or modify the active desktop session. |
| Arch/RPM/Flatpak package builds | NOT RUN | `makepkg`, `rpmspec`, and Flatpak Builder unavailable; Docker unavailable. |
| Debian package build | NOT RUN | `dpkg-buildpackage` is present, but source descriptor has zero hash/size placeholders and maintainer identity is unresolved. |
| clang-format / clang build | NOT AVAILABLE | `clang` and `clang++` executables unavailable. |

## Release validation required on a candidate

1. Clean Release build from the exact signed-tag archive.
2. Full CTest suite including Catch2, integration/KWin, QML and CLI tests.
3. Appium E2E and full target distro E2E, with all jobs green on the same candidate SHA.
4. Both development and stable version metadata checks; `msgfmt --check --check-format`; AppStream and desktop metadata validation.
5. Package build/install tests for each channel actually advertised.
6. Manual native Wayland and XWayland checks in [MANUAL-TESTS.ru.md](MANUAL-TESTS.ru.md).
7. Deterministic archive manifest and checksums verified against the signed tag; confirm media LFS objects separately.

## Toolchain observed

Ubuntu/TUXEDO environment: CMake 4.2.3, Ninja 1.11.1, C++ compiler reporting GCC 13.3.0, Qt 6.10.2, KDE Frameworks 6.24.0, Plasma 6.6.6, KPipeWire/LayerShellQt 6.6.4, Kirigami Addons 1.11.0. Package target metadata requires newer versions for some components (notably GCC 14 in Arch/Debian), so host build success does not validate all distro targets.
