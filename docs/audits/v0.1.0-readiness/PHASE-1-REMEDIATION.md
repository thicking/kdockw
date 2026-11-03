# Phase 1 remediation

This document records changes made after the readiness audit. The historical assessment in [FINDINGS.md](FINDINGS.md) is preserved as written and remains the audit baseline at `bcbd48a`.

The latest code and test changes were verified at `42fb1c99040c2191018d41000848b9f44737a79e` (`test(settings): include general page in sidebar assertion`). The documentation update is a separate commit and does not change that tested code tree.

## Findings

| Finding | Original cause and remediation | Status | Fix commits |
|---|---|---|---|
| REL-001 | Current workflows and release instructions used `master` although the repository's default branch is `main`. Updated workflow triggers, OBS SCM revision, release skill, policy links, and release gate. The full distro workflow accepts `expected_sha` and rejects a different checked-out commit. | **FIXED** — `Build & tests` and the complete 12-target `Distro E2E` matrix both passed on the same published SHA `42fb1c99040c2191018d41000848b9f44737a79e`. No release or publication workflow was executed. | `7bbca06`, `42fb1c9` |
| REL-003 | The metadata test encoded development-only package versions. Version checks now cover `0.1.0-dev` and a temporary stable `0.1.0` tree. Distro packaging had a separate source archive naming defect: distro versions such as `0.1.0~dev` or `0.1.0_pre` were incorrectly used as the CMake source root/archive version. The shared source-version helper now reads the canonical CMake project version. | **FIXED** — dev/stable metadata tests and the 12-target package build/install/E2E matrix passed. No stable package was published or tagged. | `1dbe5e8`, `803c5a6` |
| REL-004 | The AUR renderer treated a checksum declaration and trailing comment as one line, missing valid shell syntax. Replaced the narrow expression with a scanner that handles balanced arrays, comments, and quoted text; added rendering and `.SRCINFO` consistency checks. The Docker staging path now creates a readable snapshot for its private build stage. | **PARTIALLY_FIXED** — renderer and release-tool tests pass, and the Docker staging regression test passes. Neither `makepkg` nor Docker was available locally for a complete AUR package build. No AUR publication or checksum generation from a real release archive was attempted. | `ef3fd9c`, `9fc01c4` |
| REL-008 | Some Git LFS tests attempted to fetch media using a fictitious commit, while fixtures copied pointer text into tagged trees. Unit fixtures now use generated valid PNG data; HTTP boundaries are mocked with pointer, size, SHA-256, and PNG validation retained. Real-object downloads are a separate opt-in integration test. Test images also now provide the Russian locale and the system utilities required by migration tests. | **FIXED** — the five release Python suites ran locally on the tested tree: 157 passed, 2 skipped (159 tests total). The opt-in real LFS integration passed separately against the published tested commit and verified downloaded bytes against pointer size, SHA-256, and PNG dimensions. The two suite skips are the opt-in integration and the `makepkg`/Docker-dependent test. | `76be3cf`, `84b5abe`, `45fbb06`, `88e815f`, `9d2a1d8`, `8b7bef0`, `42fb1c9` |
| REL-013 | The release skill named the former repository owner and `master`. Updated it to `thicking/kdockw`, `main`, and the current authenticated GitHub account. | **FIXED** — the release skill and CLI defaults point to the independent repository and current default branch. | `7bbca06` |
| REL-012 / CLI-KWin hang investigation | Tests had unbounded D-Bus, second-instance `--version`, and cleanup operations. A nested D-Bus bus with an empty private service directory and bounded waits/termination now isolate the test. An earlier local run observed real user-systemd portal activation, including a document-portal FUSE mount attempt; this was not established as the original hang's cause. | **PARTIALLY_FIXED** — the isolated CLI test passed in the exact-SHA 80-test CTest run. The original hang trigger remains unproven; this work does not establish manual acceptance in a user's Wayland/XWayland session. | `93a28b6` |

## Additional follow-up fixes

- Distro packages now use the canonical source version/root instead of distro-specific package-version syntax (`803c5a6`).
- Catch2 build-time discovery initializes Qt with the offscreen platform when no display server is available (`00911f5`).
- Fedora test images install `glibc-langpack-ru`; an attempted application locale fallback was reverted because gettext does not honor `LANGUAGE` under the `C` locale (`84b5abe`).
- Migration tests run as an unprivileged user when the container itself runs as root (`45fbb06`).
- RPM package manifests include the compiled KI18n catalog (`c221740`).
- The test image installs system utilities needed by the migration fixture (`88e815f`, `9d2a1d8`, `8b7bef0`).
- `SET-001` had an obsolete expected sidebar list: the General page was added to the UI but not to the E2E expectation. In addition, AT-SPI reports virtualized list delegates by creation order rather than their visible screen order. The assertion now includes General and sorts entries by screen Y coordinate. The screenshot and AT-SPI snapshot from the failing run showed the complete sidebar; the application UI itself was present. (`42fb1c9`.)

## Verification

- GitHub [Build & tests](https://github.com/thicking/kdockw/actions/runs/41582090633) passed on `42fb1c99040c2191018d41000848b9f44737a79e`: Release build, release tooling tests, and CTest **80/80**. The CTest run included development and stable version metadata, distro source-version, configuration migration, CLI metadata, and bounded second-instance CLI checks.
- GitHub [Distro E2E](https://github.com/thicking/kdockw/actions/runs/41582094743) passed on the same SHA for all 12 targets: Arch, Debian 13, Fedora 42/43/44/rawhide, openSUSE Leap 16.0/Slowroll/Tumbleweed, and Ubuntu 25.04/25.10/26.04. The workflow built and installed each target package before its E2E scenarios.
- All five release Python suites: **157 passed, 2 skipped (159 tests total)**. The opt-in real Git LFS download integration: **1 passed** on the same published commit.
- `msgfmt --check --check-format src/po/ru/kdockw.po`: passed.
- `python3 -m py_compile tests/appium/test_06_settings.py`: passed.
- `git diff --check`: passed on the final tree after this documentation update.
- Workflow YAML parsing and `actionlint` 1.7.12 passed during remediation.
- Release CLI dry-run (`publish --channel github`, without `--execute`) returned a planned result against an isolated synthetic fixture. No release tag, GitHub Release, package publication, AUR write, or store upload was made.
- A prior local isolated-D-Bus CTest run reported 77/79, with two failures in unchanged application/test code: a parabolic zoom settings-preview geometry tolerance and selected-output surface/shortcut behavior. The exact-SHA GitHub CTest run passed 80/80. This local-versus-CI difference is recorded rather than treated as proof that the local issues were resolved.

## Remaining release gates

- REL-004 remains partial until a complete AUR package build is exercised with `makepkg` or an equivalent package environment and a release archive with a verified checksum.
- The two local-only CTest failures need a separate environment-aware investigation if they recur; their exact-SHA GitHub tests passed.
- Manual user-session Wayland and XWayland checks in [MANUAL-TESTS.ru.md](MANUAL-TESTS.ru.md) remain unrun. The container distro matrix is not a substitute for owner acceptance in the target desktop session.
- This Phase 1 remediation does **not** establish a GO decision for KDockW v0.1.0. The independent release readiness audit's other phases and manual acceptance criteria remain outstanding.
