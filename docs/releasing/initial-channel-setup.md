# Inactive external package adapters

GitHub Releases is the only active publication channel for KDockW. The release
matrix builds and tests packages for the supported Debian, Ubuntu, Fedora,
openSUSE, and Arch targets; the verified packages are attached to the GitHub
Release.

AUR, OBS, COPR, and Launchpad/PPA are not used for KDockW releases. Do not
create projects, configure credentials, or publish packages there as part of a
release. The corresponding scripts and metadata are retained as inactive
adapters for possible future work, but they are excluded from the release CLI,
publication plan, and release gate.

This policy does not remove any distribution from the GitHub package matrix.
Targets remain governed by the [Distribution Support Policy](distribution-support-policy.md)
and are retired only for a documented build failure or blocking dependency.
