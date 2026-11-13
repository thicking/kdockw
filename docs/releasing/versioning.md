# KDockW versioning

KDockW's first standalone stable version was `0.1.0`. Starting with `0.3.0`,
KDockW release tags use the permanent `kdockw-vX.Y.Z` form (for example,
`kdockw-v0.4.3`). Historical Krema `v0.x.x` tags and release notes remain
unchanged and are not renamed or reused. The release tools continue to
recognize legacy `vX.Y.Z` tags so existing records remain verifiable.

The application version is read from `KDOCKW_VERSION`; the release tooling
binds checksums to the exact immutable source archive and package artifacts
verified for the GitHub Release. Checksums from older versions are never reused
for published artifacts.

## Source of truth

`KDOCKW_VERSION` in the top-level `CMakeLists.txt` is the single product-version
source. It is compiled into `KAboutData` and the `kdockw --version` output. The
numeric `project(kdockw VERSION ...)` value is derived from its `x.y.z` core
because CMake requires a numeric project version. AppStream records stable
releases without the `development` type.

Release tooling checks the canonical value and generated metadata against the
signed release tag. A stable release is not considered published until its
tagged source passes the full Distro E2E gate and all GitHub assets are
verified. GitHub Releases is the only publication channel. From v0.3.2,
packages are built for the required targets in
`tests/distro/release-targets.txt`. Fedora 45 was excluded from the published
v0.5.0 gate. It passed the full Qt 6.11.2 Distro E2E for the v0.5.1 candidate
and is included in that candidate's required matrix. Manual compatibility rows
are not required gates or release assets.

## Package version forms

Package formats use their own spelling for development builds:

| Format | Stable example | Development equivalent | Rule |
| --- | --- | --- | --- |
| AppStream | `0.4.3` | `0.4.3-dev` | Stable releases omit `type="development"`; development builds include it. |
| RPM | `0.4.3` | `0.4.3~dev` | RPM accepts `~` in `Version` and sorts the prerelease before stable. |
| Debian | `0.4.3-1` | `0.4.3~dev-1` | Debian `~dev` sorts before stable; `-1` is the Debian revision. |

These mappings follow [RPM version rules](https://rpm.org/docs/4.20.x/manual/spec.html) and
[Debian Policy](https://www.debian.org/doc/debian-policy/policy.pdf). AppStream's
`development` release type and required date follow its
[release metadata specification](https://www.freedesktop.org/software/appstream/docs/sect-Metadata-Releases.html).

These metadata mappings do not prove a binary package has been published. From
v0.3.2, the CI Distro E2E matrix builds and installs one package for each
required target in `release-targets.txt`; only artifacts from the full
successful matrix for the exact release commit are eligible for GitHub Release
uploads. `SHA256SUMS` covers the source archive and every package asset.

KDockW v0.5.0 release packages target Debian 13 and Ubuntu 26.04 LTS. Fedora
45 was not included in those release assets; its full Qt 6.11.2 E2E has passed
for the v0.5.1 candidate and it is now a required candidate target. Arch Linux
packaging was removed. Existing signed tags and historical release assets
remain unchanged.

The JSON and research files under `packaging/submissions/` and the local
Flatpak validation package are historical receipts for earlier Krema or
pre-release source snapshots. Their versions are evidence of those past checks,
not the current KDockW application version or package source.

## Attribution and licenses

The About copyright statement names Krema and KDockW contributors and says that
KDockW is based on Krema, originally created by Byeonghoon Yoo. Existing
file-level SPDX notices and the GPL-3.0-or-later and MIT-CMU license texts are
preserved; this project does not claim that all inherited code is owned by the
current KDockW maintainer. Historical Krema release notes remain in
[`docs/history/krema-changelog.md`](../history/krema-changelog.md).
