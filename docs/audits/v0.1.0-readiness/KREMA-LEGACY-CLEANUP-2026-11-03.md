# KDockW publishing and legacy asset audit — 2026-11-03

This record documents the post-v0.1.0 audit. No external project, package, or
account was created or modified. The signed `v0.1.0` tag remains on commit
`37b04406e8c8ae008f86d8fe037482812a9fecbf`.

## Publishing destinations

Public API checks on 2026-11-03 found:

- COPR `thicking/kdockw`: HTTP 404; the COPR project is not configured.
- Launchpad project `/1.0/kdockw`: HTTP 404.
- Launchpad PPA `~thicking/+archive/ubuntu/kdockw`: HTTP 404.
- AUR RPC v5 for `kdockw`: HTTP 200 with zero results.
- KDE Store record `2376676`: HTTP 200, title `Krema`, author `isac322`.

The release adapters now report missing destinations as blocked prerequisites
and do not attempt project creation or package upload. The existing Krema
COPR, Launchpad resources, and KDE Store record are not KDockW destinations.
AlternativeTo returned HTTP 403, so its listing identity remains unverified.
OBS public checks were inconclusive; the local OBS account configuration was
not present, so no write was attempted.

The public source archive checksum used by Arch metadata was independently
calculated from the GitHub `v0.1.0` tag archive and matches `PKGBUILD` and
`.SRCINFO`. `makepkg` was unavailable on this host, so a package build was not
verified here.

## Removed obsolete assets

The cleanup removes the inactive Krema-era logo and social-card generation
assets, reference screenshots, clip-recording prototype, wallpaper prototype,
unused website media/style bundle, and stale Flatpak manifest/research packet.
The currently deployed website does not reference those media paths. The
release banner now uses the current KDockW website Open Graph artwork.

The old Flathub investigation is preserved under `docs/history/` and is
explicitly identified as Krema-era research. Required license and third-party
media provenance is retained in the source notices and
`LICENSES/THIRD-PARTY-WEBSITE-MEDIA.md`.

Several deleted raster assets were Git LFS pointers whose remote objects were
unavailable during this audit. Their image pixels therefore could not be
reviewed directly. Removal was based on the associated SVG/source provenance,
notes, and confirmation that active website/build files do not reference them;
this is not a claim that each unavailable bitmap was visually inspected.

## Preserved identity and release safety

The original Krema attribution to Byeonghoon Yoo, GPL notices, Git history,
and user-facing migration guidance remain. References to `isac322` that remain
in active files identify the original project or explicitly protect its
resources; they are not KDockW publishing targets.

The release signing fingerprint remains
`90798370719E91DDE1D5028AAA660B7C5AB258E7`. The published tag signature was
verified before this audit and the tag was not changed.

## Verification limits

Release-tooling unit tests and static metadata checks were run locally. A
release configure/build completed. Full CTest could not be run from a fresh
test-enabled configuration because Catch2 3 is not installed on the host. An
older generated CTest tree reported stale `0.1.0-dev` version expectations,
two known selected-output geometry assertions, and a QML preview test that
attempts to assign read-only `state`; those failures were not changed as part
of this infrastructure/asset audit.
