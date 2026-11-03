# GitHub Pages deployment

KDockW's static website is deployed by
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml) from the
`main` branch. The workflow assembles a small allowlist of files from
`website/` into `_site/`; it does not publish the repository or its `branding/`
and documentation directories.

The repository must have GitHub Pages configured with **Source: GitHub
Actions**. `actions/configure-pages` runs with `enablement: false`: its
`GITHUB_TOKEN` reads an existing Pages configuration but cannot create the
site. If Pages is disabled or removed, the Pages workflow will fail at
`Configure Pages` with HTTP 404. An administrator must enable Pages once in
the repository settings; no personal token is stored in this repository or
workflow.

The configured site URL is <https://thicking.github.io/kdockw/>. The workflow
is intentionally a deployment workflow, so successful runs publish the
assembled site. Its `pages: write` and `id-token: write` permissions are
limited to that workflow.
