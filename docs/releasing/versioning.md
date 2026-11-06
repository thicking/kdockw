# KDockW versioning

KDockW's first standalone stable version was `0.1.0`. Starting with the
`0.3.0` release, KDockW release tags use the permanent `kdockw-vX.Y.Z` form
(for example, `kdockw-v0.3.0`). Historical Krema `v0.x.x` tags and release
notes remain unchanged and are not renamed or reused. The release tools also
continue to recognize legacy `vX.Y.Z` tags so existing release records remain
verifiable.

The application version is read from `KDOCKW_VERSION`; package source
checksums must match the exact immutable archive fetched by each recipe. Do
not carry forward checksums from an older version or use placeholders.

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
| AppStream | `0.3.0` | `0.3.0-dev` | Stable releases omit `type="development"`; development builds include it. |
| Arch | `0.3.0` | `0.3.0_pre` | Arch `pkgver` uses `_pre` for a development build; the source tag is `kdockw-vX.Y.Z`. |
| RPM | `0.3.0` | `0.3.0~dev` | RPM accepts `~` in `Version` and sorts the prerelease before stable. |
| Debian | `0.3.0-1` | `0.3.0~dev-1` | Debian `~dev` sorts before stable; `-1` is the Debian revision. |

These mappings follow the [Arch PKGBUILD manual](https://man.archlinux.org/man/PKGBUILD.5),
[RPM version rules](https://rpm.org/docs/4.20.x/manual/spec.html), and
[Debian Policy](https://www.debian.org/doc/debian-policy/policy.pdf). AppStream's
`development` release type and required date follow its
[release metadata specification](https://www.freedesktop.org/software/appstream/docs/sect-Metadata-Releases.html).

These are metadata mappings, not by themselves proof that a binary package has
been published. The Arch release adapter renders a tag-specific PKGBUILD and
replaces its template checksum with the verified immutable source archive hash.
The checked-in Arch recipe is a source template; publication uses only the
rendered, hash-verified recipe and generated `.SRCINFO` from the release
context.
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
