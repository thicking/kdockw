# Inactive external package adapters

GitHub Releases is the only publication channel for KDockW. The required
release matrix is recorded in `tests/distro/release-targets.txt`. Fedora 45
was excluded from the v0.5.0 release assets; it passed full Qt 6.11.2 Distro
E2E for the v0.5.1 candidate and is now included in its release matrix. See the
[Distribution Support Policy](distribution-support-policy.md) and
`tests/distro/release-targets.txt` for current representatives.

AUR, OBS, COPR, and Launchpad/PPA are not used for KDockW releases. Do not
create projects, configure credentials, or publish packages there as part of a
release. The corresponding scripts and metadata are retained as inactive
adapters for possible future work, but they are excluded from the release CLI,
publication plan, and release gate.

The broader manual compatibility list and packaging recipes may remain in
`tests/distro/targets.tsv`; they are not automatically built or published.
