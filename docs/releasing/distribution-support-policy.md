# Distribution Support Policy

This policy governs which distribution releases KDockW packages and the
conditions for retiring a packaging target.

- A distribution release reaching end of life (EOL) is **never** by itself a
  reason to remove a packaging target. Keep building and uploading it.
- A target is retired only when its build breaks and cannot reasonably be fixed,
  or when a product dependency requirement blocks work and the release cannot
  provide that dependency.
- Distribution packages are built and tested by the GitHub Actions Distro E2E
  matrix, then attached to the GitHub Release. A distro is supported when its
  target is present in `tests/distro/targets.tsv` and passes the package/E2E
  gate; support does not depend on an external package-hosting account.
- Add new distribution releases to the package matrix and README after the
  package build and Distro E2E target have been validated. The scheduled distro
  watcher tracks gaps in that GitHub package matrix; it does not query or
  require AUR, OBS, COPR, or Launchpad/PPA.
- External package repositories are inactive and are not part of the release
  gate. Optional adapters may remain in the source tree for future use, but
  they must not block a GitHub Release.

## Maintainer reporting and retirement records

- Never remove a supported target because it is EOL.
- When retiring a target, cite the concrete build failure or blocking
  dependency requirement and update `tests/distro/targets.tsv`, the README
  installation table, and CHANGELOG (`### Removed`).
- Report EOL as information, not as a recommendation to drop support.
