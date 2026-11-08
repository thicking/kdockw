# KDockW Agent Guidelines

Rules that apply to every agent working on this repository, regardless of harness. Situational rules (Wayland surfaces, QML UI, KDE APIs, performance, docs/SEO, E2E scenarios) live in `.agents/rules/`; read the matching rule before working in its area.

## Project Scope

- KDockW is a dock for KDE Plasma 6 on Wayland only. Do not design for other desktop environments.
- When both a Qt API and a KDE API exist, use the KDE API. Follow the KDE HIG; prefer Kirigami / Kirigami Addons over plain QQC2.
- Never guess KDE APIs. Verify them against `docs/kde/` and the installed headers before implementing (see `.agents/rules/kde-api-verification.md`).
- KDockW is a dock: visual smoothness and responsiveness are non-negotiable (see `.agents/rules/performance.md`).

## Code Rules

- C++23, Qt 6, KDE Frameworks 6.
- Code is formatted with clang-format (enforced by the pre-commit hook).
- Commit messages are English and follow Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, …).
- Documentation, manifests, and PR communication are in English.
- When adding or removing a dependency (`find_package()` / `target_link_libraries()` in CMake), update `packaging/arch/PKGBUILD` (`depends` / `makedepends`) and the OBS packaging (`packaging/obs/kdockw.spec`, `packaging/obs/debian.control`) in the same change.

## Testing Strategy & Efficiency

- Match test scope to the changed code and regression risk. Prefer targeted checks;
  do not run the full CTest suite after every small edit.
- For small QML, UI, or settings changes, build affected targets when needed, then
  run the directly related QML/unit tests and relevant regression tests. UI
  changes still require visual acceptance by the owner in a real Plasma/Wayland
  session; automated tests do not replace it.
- For C++ or KDE/KWin integration changes, run the relevant unit/integration
  tests and nearby regression tests when risk warrants them. Run one full
  production CTest before completing a substantial change when its scope
  justifies the broader check.
- For documentation, ROADMAP, or SEO-only changes, check the affected documents,
  links, and formatting. Do not run CTest when application sources and test
  infrastructure are unchanged.
- For release preparation, run full production and diagnostic CTest, plus Distro
  E2E and release gates required by the current release policy. Do not weaken or
  omit required release checks to save time. The current policy and target list
  in `docs/releasing/` are authoritative if older instructions in this file or
  retained tooling mention inactive publication channels.
- Reuse prior test results only when the relevant code and test configuration have
  not changed since those results were obtained. Do not rebuild both production
  and diagnostic configurations without a concrete need.
- When a test fails, inspect its log and reproduce the specific test separately
  before deciding what to do next. Determine whether the failure is caused by
  the change, the environment, or known test instability. Do not automatically
  rerun the full suite after an isolated failure.
- Report a failed full run as failed even if an isolated retry passes. Record
  isolated retries separately. If instability is confirmed, preserve it as
  technical debt rather than hiding the failure.
- Do not run a third or later full suite for the same configuration unless a
  concrete technical reason justifies it, such as a code fix prompted by a
  failure or a required release gate. Do not repeat full runs merely to obtain a
  clean-looking percentage.
- Finish once the change is implemented, related tests pass, remaining checks
  are recorded honestly, and any needed manual-acceptance instructions are
  ready. Do not extend testing indefinitely for secondary diagnostic doubts.
- In the final report, list the tests run and their results, tests not run with
  the reason, and any remaining release or manual-acceptance checks.

## Pull Request Completion

- A PR is ready for review or merge only when every CI check on its head is green, the change has been QA'd in a running KDockW session, and review feedback is resolved.
- QA means exercising the changed behavior in a real KWin Wayland session (for example, maximize a window to check space reservation) and observing the result. Use `kwin-mcp` when the check needs automation. Passing unit tests or reading the code is not QA; never report a feature as working without having observed it.
- Fix E2E and CI failures the PR causes or exposes in that same PR. Do not merge with known E2E breakage or defer it to a follow-up.
- Reproduce and iterate on E2E failures locally with `tests/appium/run-e2e.sh` (Docker) until they pass; do not use repeated CI pushes as the debug loop.

## Visual Evidence for Pull Requests

- Every agent MUST upload media evidence to the PR body or a PR comment for every visual change before requesting or conducting PR review (including internal agent review), marking the PR ready for review, or merging it.
- Dynamic changes (animations, movement, interactive transitions, and live or real-time updates) MUST include a video of the changed behavior. Screenshots cannot replace that video. Use video whenever a change is not clearly static.
- Purely static visual changes may use screenshots instead of video.
- Capture the actual running implementation from the PR revision under review. The media MUST visibly demonstrate each changed appearance or behavior; logs, passing tests, mockups, and unrelated footage are not substitutes.
- For dynamic changes, show the trigger or setup and the resulting motion or live update, not just the final state.
- Use any suitable capture method within existing authorization and safety rules. If one method fails, try another available route (local, containerized, or remote); capture difficulty does not waive this requirement.
- Open the uploaded media and confirm reviewers can view it and the change is clearly visible. Refresh evidence when subsequent commits alter the demonstrated appearance or behavior.
- If no authorized capture route works, report the concrete blocker and required access; keep the visual work incomplete and the PR not ready for review until evidence is attached.

## Branding and Media Assets

- `branding/README.md` is the brand kit and the single home of promotional assets. Read it before creating or editing logos, social cards, screenshots, clips, or any promotional or website media, and follow its palette, wallpaper, and regeneration rules. Never reuse the old brand palette.

## Roadmap

- Obsidian `KDockW/_Roadmap.md` is the planning source for agreed scope and priorities; repository `ROADMAP.md` is its public view of approved milestones and progress. Draft Obsidian versions or ideas are not release commitments.
- Work only on an approved current milestone. Preserve the existing `⬅️` marker process, but do not move it or alter roadmap scope until the corresponding plan is agreed and reflected consistently in both documents.
- After finishing a feature, check the applicable approved ROADMAP items. When an approved milestone is complete, mark it ✅ and move ⬅️ to the next approved milestone in both documents as appropriate.
- Keep the tech stack table current when dependencies change.

## CHANGELOG

- Every user-visible change (feature, bug fix, behavior change) adds an entry under `## [Unreleased]` in `CHANGELOG.md`.
- Categories: `### Added`, `### Changed`, `### Fixed`, `### Removed`.
- Write in English, past tense, from the user's point of view (user benefit, not the commit message).
- Do not record changes invisible to users (internal refactors, CI, agent configuration).

## Obsidian Project Documentation

- After completing each KDockW task, update the corresponding existing Obsidian project note with the work actually completed, relevant commit SHAs, verified test results, and discovered limitations.
- Keep approved roadmap scope synchronized with PM Compass in the Obsidian vault (`Projects/AGENTS.md` and `KDockW/AGENTS.md`): an approved stage is a parent task with independently verifiable results as subtasks. Check for an existing matching card before creating one.
- Keep implemented, investigated, planned, and externally blocked work clearly distinguished. Do not record a task as complete unless its result is supported by evidence.
- Reuse the existing KDockW notes and their structure; do not create a duplicate note when an existing history, status, verification, distribution, or research note is the right place.
- The Obsidian project guide (`KDockW/AGENTS.md`) owns documentation and PM Compass workflow. This file and `.agents/rules/` own repository implementation and release requirements; keep the scopes aligned without duplicating their detailed technical procedures.
- Obsidian is the planning source for agreed scope; this repository’s `ROADMAP.md` is a public view of approved items. Do not promote draft stages into release promises or change roadmap scope without owner agreement.

## Releases

- Releases follow the `release` skill (`.agents/skills/release/SKILL.md`) end to end (version choice, document sync, tag, GitHub release, AUR, OBS, COPR, PPA).
- On release, move every `[Unreleased]` entry into a `## [x.y.z] - YYYY-MM-DD` section and leave `[Unreleased]` empty.

## Distribution Support Policy

- A distro release reaching end of life (EOL) is **never** a reason to remove a packaging target. Keep building and uploading it.
- A target is retired only when:
  1. its build breaks and cannot reasonably be fixed, or
  2. the product needs a newer dependency (Qt, KDE Frameworks, LayerShellQt, etc.) that the release cannot provide and this blocks product work.
- Platform-forced removal is per channel: when a build service stops offering a release (COPR deletes EOL Fedora chroots, Launchpad rejects uploads to Obsolete Ubuntu series, OBS removes a distro project), that channel simply stops serving the release. Other channels that still offer it keep building it — record the platform action, do not remove the release elsewhere.
- Add new distro releases promptly to every channel that offers them (OBS `packaging/obs/project.meta.xml`, COPR chroots, Launchpad PPA series, README Installation table).
- The scheduled workflow `.github/workflows/distro-release-watch.yml` opens one tracking issue per channel, labeled `distro-release`, once that channel offers a distro release (including pre-releases) that KDockW does not build there yet; those issues drive the additions. Releases a channel does not offer yet are only logged, never filed.

### Agent Rules

- Never propose or perform removal of a target, OBS repository, COPR chroot, or PPA series because it is EOL.
- When retiring a target, cite the concrete build log or the blocking dependency requirement in the PR/issue, and update `packaging/obs/project.meta.xml`, the README Installation table, and CHANGELOG (`### Removed`) accordingly.
- When reporting distro status, report EOL as information only, not as a recommendation to drop support.
