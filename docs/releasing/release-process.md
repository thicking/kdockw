# KDockW release process

## Publication scope

GitHub Releases is KDockW's only publication channel. Beginning with v0.3.2,
each release contains the source archive, SHA-256 manifest, and the three
packages built and tested by the required Distro E2E matrix: current Debian
stable, current Ubuntu LTS, and current stable Fedora. The required target IDs
are listed in `tests/distro/release-targets.txt`; update them when those
upstream representatives change. Older compatibility targets remain available
for explicit manual runs but are not release gates or release assets.

AUR, OBS, COPR, and Launchpad/PPA are inactive. Optional adapter scripts may
remain in the repository, but the release CLI's `all` selection means GitHub
only. No release preflight or gate may require credentials, accounts, projects,
or publication in those services.

## Source release

1. Start from a clean, current `main` checkout. Audit and test the accepted
   source changes before making the release commit.
2. Bump `KDOCKW_VERSION` and synchronize AppStream, package metadata for the
   required targets, documentation, and package version metadata. Move the new
   user-facing entries from `[Unreleased]` into a dated version section in
   `CHANGELOG.md`.
3. Build Release and run the complete Release CTest suite, localization,
   desktop-entry, documentation, release-tooling, and packaging checks.
4. Commit and push the release source to `main` without rewriting history.
5. Dispatch the required Distro E2E matrix with `targets=all` for the exact
   candidate commit. Every target in `release-targets.txt` must pass; the
   matrix builds and installs each package in its corresponding test image.
6. Create `kdockw-vX.Y.Z` as an annotated tag signed by the pinned project key.
   Verify the tag signature locally, then push the tag.

## GitHub Release

Run `scripts/release.py prepare` for the signed tag. The generated context binds
the source archive, commit, hash, and release notes to the tag. The existing
KDockW release banner is embedded using this stable GitHub Attachments URL:

`https://github.com/user-attachments/assets/47fe4b06-8469-4b48-8fed-cb9d5872ec4e`

Check the generated GitHub publication plan, then run `scripts/release.py
publish --channel github --execute`. Publication is blocked until the exact
tagged commit has a fully green Distro E2E matrix. The publisher verifies and
attaches the source archive, every expected required-target package, and
`SHA256SUMS` before making the Release public.

After publication, verify the public release state, tag-to-commit identity,
asset set, package versions, and every checksum. Never report a queued or
partial upload as complete.

## Inactive adapters

The AUR, OBS, COPR, and Launchpad/PPA adapters are retained for reference but
are not selectable through the main release CLI and are never invoked by the
KDockW release process. Their missing credentials or projects do not block a
release. Do not create external projects or upload there under this process.
