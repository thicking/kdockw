# Initial KDockW publishing channel setup

This is a preparation guide. It makes no account or project changes. Create external projects only when the maintainer separately authorizes that work.

## COPR

1. Confirm the Fedora Account System login that the maintainer controls. A GitHub username does not prove the FAS identity.
2. Sign in to COPR and create a new project named `kdockw` under the confirmed account. Choose the intended Fedora chroots and review build settings in COPR.
3. Add a package named `kdockw` using the SCM source `https://github.com/thicking/kdockw.git`, the OBS spec at `packaging/obs/kdockw.spec`, and a release tag as the committish.
4. Configure the local `copr-cli` account for that same owner. Verify `copr-cli whoami` and the public project API before using `scripts/release.py status --channel copr`.
5. Do not use or modify `isac322/krema`; it is the original Krema channel.

## Launchpad

1. Sign in to the maintainer's `~thicking` account and create a separate Launchpad project named `kdockw` if desired.
2. Create and activate a separate PPA named `kdockw` under `~thicking`.
3. Add the approved public GPG signing key to `~thicking`. Verify the fingerprint through Launchpad's public API. Never upload or export the private key.
4. Confirm the source package name is `kdockw`, the maintainer is `thicking <thicking@gmail.com>`, and the PPA accepts uploads for the supported Ubuntu series.
5. Run release status again. The adapter must report the new project and owner correctly before any upload is authorized.
6. Leave `~isac322`, `isac322/krema`, and `ppa:thicking/krema` unchanged.

## OBS and AUR

OBS currently targets `home:thicking/kdockw`, but public unauthenticated verification was inconclusive. Verify it using the maintainer's authorized `osc` identity before attempting a write. The AUR RPC did not return a `kdockw` package. Create one only if explicitly authorized, calculate source checksums from the verified release archive, and submit through the maintainer's AUR account. Never publish `SKIP` checksums.

## Verify without publishing

From a clean checkout with a verified signed release context, use read-only status commands:

```sh
python3 scripts/release.py status --context /path/to/context.json --channel copr
python3 scripts/release.py status --context /path/to/context.json --channel ppa
python3 scripts/release.py status --context /path/to/context.json --channel obs
python3 scripts/release.py status --context /path/to/context.json --channel aur
```

A missing project should be reported as `blocked` with its setup prerequisite. Do not run `publish --execute` until the maintainer has separately authorized publication and the destination identity, package inputs, signing key, and release gate have all been verified.
