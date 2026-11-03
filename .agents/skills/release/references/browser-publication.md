# Browser publication boundaries

KDockW's store/catalog release tooling does not create external projects. It can prepare offline metadata and verify public status, but no account, project, package, or listing is created by this document.

## Current destination state

- KDE Store record `2376676` belongs to Krema, originally created by Byeonghoon Yoo. Do not edit it for KDockW. The release adapter reports `blocked` and refuses KDockW receipts for this record.
- AlternativeTo returned HTTP 403 during the last public audit. The identity, owner, and relationship are unverified. A 403 is not evidence that the listing exists or is absent.
- Launchpad has no KDockW project or `ppa:thicking/kdockw`; the original `isac322/krema` resources are unrelated and must remain unchanged.

A future separately authorized publication task must first verify the exact KDockW destination and account in a normal browser. Update the KDockW schema and public-read verification in the same change before preparing an update packet. Never infer ownership from a similar name, repository login, or historical Krema records.

Only use the existing authorized maintainer account. Do not create a project or listing, upload a package, approve OAuth access, or publish a change under this playbook alone. See [`packaging/submissions/README.md`](../../../packaging/submissions/README.md) and [`docs/releasing/initial-channel-setup.md`](../../../docs/releasing/initial-channel-setup.md) for current channel state.
