# Distribution Support Policy

## Latest published release: KDockW v0.4.2

Published on 2026-11-11 from commit `54aeb6d7c09cbea86bd47175338a855902cfbb12`
with signed tag `kdockw-v0.4.2`. The full required Distro E2E run passed all
three targets on that exact commit: [run 42833056363](https://github.com/thicking/kdockw/actions/runs/42833056363).
The public [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.2)
contains the source archive, Debian 13 and Ubuntu 26.04 LTS DEBs, Fedora 45 RPM,
and `SHA256SUMS`. All four payload assets and the manifest were downloaded and
verified against the published SHA-256 values. The retained Arch recipes are
archival manual-compatibility files; their stale version fields do not enter
the required package matrix or release gate.

## Required release targets from v0.3.2

GitHub Releases is the only publication channel. Starting with KDockW v0.3.2,
the required package-build and Distro E2E gates cover one current release from
each supported family:

| Family | Required representative | Selection rule |
| --- | --- | --- |
| Debian | Current Debian stable | Update when Debian stable changes. |
| Ubuntu | Current Ubuntu LTS | Follow LTS releases only; skip interim YY.10 releases. |
| Fedora | Current stable Fedora | Update when Fedora stable changes; Rawhide is not required. |

The versioned list is `tests/distro/release-targets.txt`; the selected package
metadata and pinned base image live in `tests/distro/targets.tsv`. At the time
this policy was adopted, the representatives are Debian 13, Ubuntu 26.04 LTS,
and Fedora 45. Update the list at release preparation when upstream stable/LTS
versions change. Do not add separate mandatory packages for older point or
distribution releases.

`targets.tsv` may retain additional legacy compatibility rows and packaging
recipes for explicit manual investigation. Those rows are not selected by
`targets=all`, scheduled image builds, the release gate, or GitHub Release
assets. Keeping a manual row does not make it a required release target.

## Publication channels and maintenance

- Build and install the three required package targets in the GitHub Actions
  Distro E2E workflow, then attach only those verified packages, the source
  archive, and `SHA256SUMS` to the GitHub Release.
- AUR, OBS, COPR, and Launchpad/PPA are inactive. Do not create accounts,
  projects, credentials, keys, or publication steps for them. Optional adapters
  may remain in the repository but must not enter the release gate.
- An upstream EOL event alone does not delete a packaging recipe or manual
  compatibility target. It also does not add that target to future release
  packages. Required representatives are governed by the current stable/LTS
  selection above.
- The scheduled distro watcher reports only newly released current-family
  representatives eligible for the required matrix: Debian stable, Ubuntu
  LTS, and Fedora stable.

## Maintainer reporting and retirement records

- Do not remove a packaging recipe solely because its distribution release is
  EOL. A release-gate change is not, by itself, a claim that the underlying
  package recipe was retired.
- When removing a recipe, cite the concrete unfixable build failure or blocking
  dependency requirement, and update `tests/distro/targets.tsv`, the README,
  and CHANGELOG (`### Removed`).
- Report EOL as lifecycle information, not as the sole rationale for removing
  packaging code.
