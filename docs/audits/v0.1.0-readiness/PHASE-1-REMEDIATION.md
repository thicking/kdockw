# Phase 1 remediation

This document records changes made after the readiness audit. The historical assessment in [FINDINGS.md](FINDINGS.md) is preserved as written and remains the audit baseline at `bcbd48a`.

## Findings

| Finding | Cause and remediation | Status | Commit |
|---|---|---|---|
| REL-001 | Workflow triggers and release instructions named `master` although GitHub's default branch is `main`. Updated the workflows, OBS SCM revision, release skill, and policy links. Added an `expected_sha` input to the full distro workflow; the workflow rejects a dispatch whose checked-out commit differs from that SHA. The release gate sends the context commit as the expected SHA. | PARTIALLY_FIXED — branch alignment and local workflow validation are complete; exact-SHA GitHub CI evidence is pending a workflow run on the published remediation commit. | `7bbca06` |
| REL-003 | The CMake metadata test encoded development-only package forms. It now derives development or stable package forms from the canonical version and checks CMake, CLI/About sources, AppStream, translation header, Arch and `.SRCINFO`, RPM, and Debian metadata. A separate CTest transforms a temporary copy to stable `0.1.0`; the checkout remains `0.1.0-dev`. | FIXED — development and temporary stable metadata checks pass. A stable package itself has not been built or published. | `1dbe5e8` |
| REL-004 | The AUR renderer matched the entire checksum assignment as one line, so a valid trailing comment made it miss the declaration. Replaced the narrow expression with a balanced-array scanner that skips comments and quoted text, then rewrites source and checksum arrays. Tests cover comments, multiline arrays, ambiguous definitions, malformed checksums, and `.SRCINFO` agreement. | PARTIALLY_FIXED — renderer and recipe consistency tests pass; no `makepkg` or container build was available for a complete AUR package build. Publication remains unattempted. | `ef3fd9c` |
| REL-008 | Unit fixtures copied Git LFS pointer text into fake tagged trees and some tests then fetched media at a fictitious commit. The fixtures now use locally generated valid PNGs and update fixture-only receipt hashes. Pointer download tests mock the HTTP boundary while retaining pointer, byte count, SHA-256, and PNG validation. A separate opt-in integration test downloads objects referenced by the current commit and verifies them against their LFS pointers. | FIXED — all five Python suites pass (158 tests, 2 skipped). The opt-in real LFS integration passed against the published audit baseline (1 test). Before push, GitHub returned 404 for the unpublished local remediation SHA; rerun after push. The two default-suite skips are the opt-in integration and a `makepkg`/Docker-dependent test. | `76be3cf` |
| REL-013 | The release skill still named the former repository owner and `master`. Updated it to `thicking/kdockw`, `main`, and the current authenticated GitHub account. | FIXED — release skill and CLI defaults agree. | `7bbca06` |
| REL-012 / CLI-KWin hang investigation | The shell test had unbounded `busctl` and second-instance `--version` calls and unbounded cleanup. The KWin wrapper's default `dbus-run-session` configuration exposed service entries using `SystemdService`; during an earlier local test it activated portal services through the real user systemd manager, including a document-portal FUSE mount attempt. This side effect is confirmed; it is **not proven to be the original cause of the CLI hang**. Added bounded waits and termination, plus a nested D-Bus bus with only a private empty service directory. The isolated `kdockw_cli_version_while_running` test now passes. | PARTIALLY_FIXED — the test no longer depends on the host session and has bounded cleanup. The original hang's precise trigger remains unproven, and real Wayland/XWayland acceptance is still open. | `93a28b6` |

## Verification

- Fresh Release build with `BUILD_TESTING=OFF`: passed (48/48 build steps).
- Fresh test-enabled Release build: passed (118/118 build steps).
- Development metadata CTest and the temporary stable metadata fixture: passed.
- Five release Python suites: 158 tests passed, 2 skipped.
- Opt-in real Git LFS download integration on the published audit baseline: 1 passed; real LFS bytes matched pointer size, SHA-256, and PNG dimensions. An attempt against the unpublished local remediation SHA returned HTTP 404 because GitHub has no ref for that commit yet.
- Workflow YAML parsing and `actionlint` 1.7.12: passed.
- Full local CTest in an isolated D-Bus session: 77/79 passed. Two tests in unchanged application code remain failing and are not attributed to these release-tooling changes:
  - `kdockw_integration_tests`: `Parabolic zoom in a settings preview keeps the panel still under a moving pointer` measured a 29.72 px edge movement against a 0.5 px limit.
  - `kdockw_selected_output_tests`: two selected-output surface-geometry checks failed, and the selected-mode shortcut case did not find its expected dock shell after virtual output topology changes.
- The five QML suites were rerun separately under an isolated D-Bus session: all passed.
- `git diff --check`: passed before the remediation report was added; it will be rerun on the final tree.
- The release CLI was run in dry-run mode (`publish --channel github`, without `--execute`) using an isolated synthetic fixture context. It returned a `planned` result and correctly reported that the fixture tag/signature were absent. No release tag was created and no external write was requested.

## Remaining release gates

The full GitHub build and distro matrix has not yet been verified on the final remediation commit. The two local CTest failures above need triage in a separate product/test investigation. The real Plasma Wayland and XWayland manual matrix in `MANUAL-TESTS.ru.md` remains unrun. This Phase 1 work does not establish a GO decision for KDockW v0.1.0.
