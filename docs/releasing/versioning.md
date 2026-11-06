# KDockW versioning

KDockW's first standalone stable version is `0.1.0`. This release is prepared
from the independent KDockW history; existing Krema tags and release notes
remain historical Krema records and are not renamed or reused.

The working tree is being prepared as local version `0.1.2`; it is not
published. No tag or GitHub Release is being created as part of this work.
Package source checksums must match the exact immutable archive fetched by each
recipe. A source checksum for a future GitHub tag archive cannot be verified
until that archive exists; do not carry forward a checksum from an older
version or use a placeholder. Package publication therefore remains blocked
until the final source archive is produced and its recipe checksums are
verified against that exact file.

## Source of truth

`KDOCKW_VERSION` in the top-level `CMakeLists.txt` is the single product-version
source. It is compiled into `KAboutData` and the `kdockw --version` output. The
numeric `project(kdockw VERSION ...)` value is derived from its `x.y.z` core only
because CMake requires a numeric project version. AppStream records stable
releases without the `development` type.

Release tooling checks the canonical value and generated metadata against the
signed release tag. A stable release is not considered published until its
tagged source passes the full Distro E2E gate and the GitHub assets are verified.

## Package version forms

Package formats use their own spelling for this prerelease:

| Format | Stable version | Development equivalent | Rule |
| --- | --- | --- | --- |
| AppStream | `0.1.2` | `0.1.2-dev` | Stable releases omit `type="development"`; development builds include it. |
| Arch | `0.1.2` | `0.1.2_pre` | Arch `pkgver` uses `_pre` for a development build; the source tag still uses `-dev`. |
| RPM | `0.1.2` | `0.1.2~dev` | RPM accepts `~` in `Version` and sorts the prerelease before stable. |
| Debian | `0.1.2-1` | `0.1.2~dev-1` | Debian `~dev` sorts before stable; `-1` is the Debian revision. |

These mappings follow the [Arch PKGBUILD manual](https://man.archlinux.org/man/PKGBUILD.5),
[RPM version rules](https://rpm.org/docs/4.20.x/manual/spec.html), and
[Debian Policy](https://www.debian.org/doc/debian-policy/policy.pdf). AppStream's
`development` release type and required date follow its
[release metadata specification](https://www.freedesktop.org/software/appstream/docs/sect-Metadata-Releases.html).

These are metadata mappings, not by themselves proof that a binary package has
been published. The Arch release adapter renders a tag-specific PKGBUILD and
replaces its template checksum with the verified immutable source archive hash.
The CI Distro E2E matrix builds and installs one package for each listed target;
only artifacts from the full successful matrix for the exact release commit
are eligible for GitHub Release uploads.

The JSON and research files under `packaging/submissions/` and the local
Flatpak validation package are retained historical receipts for earlier Krema
or pre-release source snapshots. Their recorded versions are evidence of those
past checks, not the current KDockW application version or package source.

## Attribution and licenses

The About copyright statement names Krema and KDockW contributors and says that
KDockW is based on Krema, originally created by Byeonghoon Yoo. Existing
file-level SPDX notices and the GPL-3.0-or-later and MIT-CMU license texts are
preserved; this project does not claim that all inherited code is owned by the
current KDockW maintainer. Historical Krema release notes remain in
[`docs/history/krema-changelog.md`](../history/krema-changelog.md).
