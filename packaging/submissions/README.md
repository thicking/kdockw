# Distribution and catalog submission state

This directory contains local metadata for release tooling. It does not establish that a remote project or listing exists and does not authorize publication.

## Verified state as of 2026-11-03

- **GitHub Releases:** KDockW's signed `v0.1.0` release is published in `thicking/kdockw`.
- **COPR:** `thicking/kdockw` does not exist. Create it in the maintainer's COPR account and confirm the FAS login before using the release adapter.
- **Launchpad:** no KDockW project or `ppa:thicking/kdockw` exists. The `isac322/krema` project and `ppa:thicking/krema` are not KDockW destinations.
- **OBS:** the configured target is `home:thicking/kdockw`; unauthenticated public checks did not establish whether it exists. The local `osc` account must be verified before any write.
- **AUR:** the `kdockw` package was absent from the public AUR RPC response. A package must be created by the authorized maintainer before publication can proceed.
- **KDE Store:** record 2376676 is Krema. KDockW has no configured listing, and the tooling refuses to use that record.
- **AlternativeTo:** public inspection returned HTTP 403. Listing identity, ownership, and any Latte Dock relationship remain unverified; this is not evidence of absence or existence.

The release tools report missing prerequisites as `blocked` and do not create projects. Initial setup guidance is in [`docs/releasing/initial-channel-setup.md`](../../docs/releasing/initial-channel-setup.md). Public project creation, package upload, and account changes require separate maintainer authorization.

## Local submission packet

`prepare_submission_kit.py` can render candidate metadata and existing KDockW brand assets into a local packet. It does not authenticate, create a listing, submit a package, or modify external state. Do not use a packet to update a similarly named Krema resource. The KDE Store record guard, Launchpad target state, and AlternativeTo read limitation are represented in the schemas and release adapter.

For an authorized future browser handoff, inspect the generated packet and every destination in a normal browser session. Never claim a listing is published based only on local metadata.
