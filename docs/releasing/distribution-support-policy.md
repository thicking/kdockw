# Distribution Support Policy

This policy governs which distribution releases KDockW packages and the
conditions for retiring a packaging target.

- A distribution release reaching end of life (EOL) is **never** by itself a
  reason to remove a packaging target. Keep building and uploading it.
- A target is retired only when its build breaks and cannot reasonably be fixed,
  or when a product dependency requirement blocks work and the release cannot
  provide that dependency.
- Platform-forced removal is per channel. If a build service stops offering a
  release, that channel stops serving it; other channels that still offer the
  release keep building it. Record the platform action and do not remove the
  release elsewhere.
- Add new distribution releases promptly to every channel that offers them,
  including OBS, COPR, Launchpad, and the README installation table.
- The scheduled distro-release watcher opens one tracking issue per channel
  when that channel offers a release KDockW does not build. Releases a channel
  does not offer yet are logged but do not produce issues.

## Maintainer reporting and retirement records

- Never remove a target, OBS repository, COPR chroot, or PPA series because it
  is EOL.
- When retiring a target, cite the concrete build failure or blocking
  dependency requirement and update the package metadata, README installation
  table, and CHANGELOG (`### Removed`).
- Report EOL as information, not as a recommendation to drop support.
