# Optional catalog and browser publication boundaries

GitHub Releases is the only active publication channel for KDockW packages.
Catalog submissions are separate, inactive work and are not part of the release
gate. This document records boundaries only; it does not authorize external
publication or project setup.

## Current destination state

- KDE Store record `2376676` belongs to Krema, originally created by Byeonghoon Yoo. Do not edit it for KDockW. The release adapter reports `blocked` and refuses KDockW receipts for this record.
- AlternativeTo returned HTTP 403 during the last public audit. The identity, owner, and relationship are unverified. A 403 is not evidence that the listing exists or is absent.
- Launchpad/PPA is not used for KDockW releases. The original
  `isac322/krema` resources are unrelated and must remain unchanged.

A future catalog project would require a separate owner decision and verified
destination. It must not be treated as a package publication channel or as a
prerequisite for releasing packages on GitHub. Never infer ownership from a
similar name, repository login, or historical Krema records.

Do not create a project or listing, upload a package, approve OAuth access, or
publish a change under this playbook. See
[`packaging/submissions/README.md`](../../packaging/submissions/README.md) for
the retained submission metadata and [`initial-channel-setup.md`](initial-channel-setup.md)
for the inactive adapter policy.
