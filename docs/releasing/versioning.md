# KDockW versioning

KDockW has not published its first standalone release. The current development
version is `0.1.0-dev`; existing Krema tags and release notes remain historical
Krema records and are not renamed or reused.

## Source of truth

`KDOCKW_VERSION` in the top-level `CMakeLists.txt` is the single product-version
source. It is compiled into `KAboutData` and the `kdockw --version` output. The
numeric `project(kdockw VERSION ...)` value is derived from its `x.y.z` core only
because CMake requires a numeric project version. AppStream uses the full
development version and marks it as a development build.

When preparing the first release, change the canonical value to its release
version (for example, `0.1.0`) and keep the numeric CMake project version in
sync. Release tooling reads the canonical variable and checks generated release
metadata against the release tag. No `v0.1.0` tag or GitHub Release has been
created as part of setting this development version.

## Package version forms

Package formats use their own spelling for this prerelease:

| Format | Development version | Rule |
| --- | --- | --- |
| AppStream | `0.1.0-dev` | Keep the product version and mark `type="development"`. |
| Arch | `0.1.0_pre` | Arch rejects hyphens in `pkgver`; `_pre` is a recognized prerelease suffix and sorts before the stable version. The source tag keeps `-dev`. |
| RPM | `0.1.0~dev` | RPM accepts `~` in `Version` and sorts the prerelease before the stable version. |
| Debian | `0.1.0~dev-1` | `~dev` sorts before the eventual `0.1.0` release; `-1` is the Debian revision. |

These mappings follow the [Arch PKGBUILD manual](https://man.archlinux.org/man/PKGBUILD.5),
[RPM version rules](https://rpm.org/docs/4.20.x/manual/spec.html), and
[Debian Policy](https://www.debian.org/doc/debian-policy/policy.pdf). AppStream's
`development` release type and required date follow its
[release metadata specification](https://www.freedesktop.org/software/appstream/docs/sect-Metadata-Releases.html).

These are metadata mappings, not evidence of published or validated binary
packages. The development recipes point at the future `v0.1.0-dev` source tag;
no such tag/archive exists yet. In particular, the Arch recipe has a temporary
`SKIP` checksum until an immutable source archive can be fetched and its digest
verified. Do not publish a package from these recipes until the release source
and each target distro's package build have been validated.

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
