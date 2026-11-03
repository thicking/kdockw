# v0.1.0 release readiness follow-up — 2026-11-03

This follow-up records work after the audit in `README.md`. The audited commit
and its findings remain an immutable historical snapshot. The release
candidate changes in the current working tree are not yet committed or
published, so this is not a release approval.

## Verified locally

| Area | Evidence | State |
| --- | --- | --- |
| Stable version metadata | Release and development fixture checks passed with CTest; CMake, CLI, AppStream, Russian catalog, Arch, RPM and Debian metadata were checked. | PASS |
| Release build | `cmake --preset release && cmake --build --preset release -j 4`. | PASS |
| Full CTest | `ctest --test-dir build/dev --output-on-failure`: 86/86 passed. | PASS |
| Release tooling | `python3 -m unittest discover -s tests/release -p 'test_*.py' -v`: 161 passed, 2 skipped because this host has neither `makepkg` nor Docker. | PASS WITH SKIPS |
| Russian catalog | `msgfmt --check --check-format`. | PASS |
| AppStream | `appstreamcli validate src/com.thicking.kdockw.metainfo.xml`. | PASS |
| Desktop entries | Generated application and XDG autostart entries passed `desktop-file-validate`. | PASS |
| GPG signer | The local key has fingerprint `90798370719E91DDE1D5028AAA660B7C5AB258E7`, RSA 4096, created 2026-11-03 and expiring 2031-11-02. A disposable repository tag passed `git tag -s`, `git tag -v`, and `release.py verify_signature`. | PASS |
| Debian Maintainer | The project owner confirmed `thicking <thicking@gmail.com>`; active `.dsc`, `debian.control`, and the new changelog entry use that identity. Historical Krema author/copyright records remain intact. | PASS |

The release build preset has `BUILD_TESTING=OFF`. An initial `ctest` against
`build/release` saw stale generated test registration files from an older
development configuration and failed version assertions expecting
`0.1.0-dev`. Those registrations were not a valid release test run. The
complete current run used the freshly configured `build/dev` tree and passed.

## Packaging and workflow changes in the candidate

- The Distro E2E matrix stages a package and a manifest only after the target's
  primary package-install/E2E test passes. The manifest records target,
  version, commit, format, filename, and SHA-256.
- The GitHub publisher requires a complete green matrix for the exact tagged
  commit, downloads every per-target artifact, validates the manifest and
  bytes, then attaches the target-labelled packages. `SHA256SUMS` covers the
  source archive and every package.
- The candidate target list is in `tests/distro/targets.tsv`: Debian 13;
  Ubuntu 25.04, 25.10, 26.04; Fedora 42, 43, 44, Rawhide; openSUSE
  Tumbleweed, Slowroll, Leap 16.0; and Arch Linux x86_64. No target has yet
  passed the matrix on the release candidate commit.
- `packaging/obs/kdockw.dsc` is an OBS `debtransform` input template rather
  than the final Debian source descriptor. The transform creates the final
  descriptor and its file checksums from the source archive; the checked-in
  zero-valued `Files` line alone is not evidence of a valid built source
  package. An actual OBS build remains unverified. See the
  [debtransform implementation](https://sources.debian.org/src/obs-build/20210120-4/debtransform/).
- `Source0` and `%autosetup` in the RPM spec now use the stable `0.1.0`
  version. The stable AppStream, Arch, RPM, and Debian forms are covered by the
  metadata checks.

## Still required before publication

1. Commit and push the candidate to `main`; record its exact SHA.
2. Wait for CI and run the complete `targets=all` Distro E2E matrix against
   that exact SHA. This also exercises package build/install and the Arch
   `makepkg` package path.
3. Review the generated English release notes and obtain approval before
   creating or pushing `v0.1.0`.
4. Prepare and verify the signed annotated tag and release context. Do not
   publish the release if any target artifact or hash is missing.
5. Complete manual real-Plasma Wayland acceptance of the installed release
   candidate. This work deliberately has not installed KDockW or altered the
   current Plasma session.
6. Assess AUR, OBS, COPR, and Launchpad separately. No extra-channel package
   has been submitted or published by this follow-up. Flatpak remains outside
   v0.1.0 because its current manifest is not a validated KDockW package.
