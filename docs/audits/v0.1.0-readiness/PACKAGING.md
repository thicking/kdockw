# Packaging audit

This report evaluates current packaging readiness for the prospective standalone `0.1.0` release. It does not publish or build packages.

## Source archive

The GitHub-generated archive for commit `90b97f452db6da8892fbea68e019ad9e4699e55f` was extracted and clean-built in an isolated Release directory. Build inputs and app icons are not LFS pointers. The archive includes 73 LFS pointer files for branding and website media; those files are not hydrated images. The source build is therefore verified, while marketing media must be fetched and integrity-checked separately.

## Native package channels

| Channel | Current state | Blocking evidence | Release gate |
| --- | --- | --- | --- |
| Arch / AUR | **BLOCKED** | `PKGBUILD` uses `sha256sums=('SKIP')`; no standalone tag archive exists yet. AUR renderer tests fail because an inline comment prevents the release adapter's anchored checksum regex from matching. `makepkg` unavailable here. | Create immutable source archive, verify SHA-256, render `PKGBUILD` and `.SRCINFO`, then build/install in Arch target image. |
| RPM / OBS / COPR | **NOT VALIDATED** | Spec version/macro are dev values. `upstream_version` controls source URL and prep directory and is not rewritten by the OBS adapter. `rpmspec`/Docker unavailable; no remote build evidence. | Synchronize stable version macro, run RPM build and target E2E; verify OBS/COPR exact tag source revision. |
| Debian / OBS / Launchpad PPA | **BLOCKED** | `.dsc` has all-zero hash and size zero; `Maintainer` is inherited as `Byeonghoon Yoo <bhyoo@bhyoo.com>` without current package-maintainer authorization. No Debian source build. | Generate true checksum/size from candidate archive, confirm maintainer identity, build source and binary packages, validate PPA/OBS metadata. |
| Flatpak / Flathub | **NOT A CURRENT KDOCKW RELEASE CHANNEL** | Local manifest uses Krema v0.9.0 source and docs identify it as a historical validation artifact. Docs record lint failures and unresolved host application launch; no Flathub manifest submission. | Do not advertise as v0.1.0. A separate KDockW source port and lint/installed Wayland acceptance are prerequisites. |
| GitHub source | **BUILD VERIFIED; RELEASE NOT CUT** | Current `0.1.0-dev` archive builds. No `v0.1.0` tag or release. | Complete source/QA gates, make versioned release commit, sign tag and verify archive manifest. |

## Dependency and target coverage

Top-level CMake requires Qt 6.8, KDE Frameworks 6.0, LayerShellQt 6.0, and conditionally exact Qt Gui private headers for Qt 6.9 or newer. Arch/Debian metadata requires GCC 14, while RPM requires GCC 13 and the host build used GCC 13.3.0. A successful TUXEDO build with updated Qt/KDE is not evidence that every minimum or rolling target resolves the correct package names and runtime dependencies.

The distro matrix is defined in `tests/distro/targets.tsv`; it was not executed during this audit. Current workspace lacks Docker, `makepkg`, `rpmspec`, Flatpak Builder, and `git-lfs`. Keep target-level support decisions based on actual build logs; do not remove targets because they are EOL.

## Version conversion

The documented development forms are AppStream `0.1.0-dev`, Arch `0.1.0_pre`, RPM `0.1.0~dev`, Debian `0.1.0~dev-1`; current release recipes point to a future `v0.1.0-dev` tag. No such tag exists. For stable release, forms must be generated from the canonical version rather than carried forward as dev strings. The current metadata test encodes only development forms, so this transition needs explicit regression coverage.

## Historical and submission artifacts

Files in `packaging/submissions/` are handoff/research material, not proof of a package upload. `packaging/flatpak/` is a separate local artifact. Audit report distinguishes these from active package recipes and the source release.
