# KDockW roadmap

KDockW is an independent KDE Plasma 6 dock for Wayland and a spiritual
successor to Latte Dock. This roadmap describes KDockW work only; it does not
copy or extend Krema's archived plan. Items are priorities, not release dates
or version promises. See the [Russian roadmap](ROADMAP.ru.md), the
[KDockW changelog](CHANGELOG.md), and the [archived Krema roadmap](docs/history/krema-roadmap.md).

## P0 — Stability and release readiness

Starting with v0.3.2, required GitHub Release builds and Distro E2E gates cover
current Debian stable, current Ubuntu LTS, and stable Fedora only. The v0.3.1
release remains unchanged; see `docs/releasing/distribution-support-policy.md`.

- [ ] Reproduce and resolve black or missing window previews on real Wayland
  sessions, including hybrid-GPU systems. Keep the experimental CPU-buffer
  retry labelled as experimental until hardware testing confirms its scope.
- [ ] Run the installed application through the KWin Wayland scenarios for
  previews, launch feedback, task-manager drops, file-drag activation,
  background effects, and language switching.
- [ ] Stabilize the KWin integration and Appium E2E suites across the supported
  CI images; distinguish container limitations from application failures.
- [ ] Verify the opt-in Krema settings migration and rollback with representative
  existing configurations using the XDG-only startup path.
- [ ] Manually verify one XDG autostart launch after login and upgrade for both
  `/usr` and `/usr/local` installations in a real Plasma session.
- [x] Establish KDockW's independent versioning policy and stable `0.1.0`
  metadata; the signed stable release was published on 2026-11-03 after the
  signing and package gates passed.
- [x] Publish the first standalone KDockW release; the existing `v0.x` tags
  belong to Krema history. [v0.1.0 release](https://github.com/thicking/kdockw/releases/tag/v0.1.0)
- [x] Publish KDockW 0.3.0 with the signed tag, source archive, checksums, and
  packages for all 12 distro targets. [v0.3.0 release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.0)
- [x] Publish KDockW 0.3.1 with the signed tag, source archive, checksums, and
  packages for all 12 distro targets. [v0.3.1 release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.1)
- [x] Complete release automation and package smoke checks for the initial
  standalone release. The release contains 12 distro package assets, and the
  tagged release gate passed for all 12 supported distro targets.

## P1 — Documentation and user experience

### v0.2.0 — Rendering Quality & Animation Foundation (completed by user acceptance)

- [x] Deliver the accepted icon and badge rendering improvements, adaptive
  contrast, icon opacity control, and badge typography defaults. The owner
  accepted the Full HD result on 2026-11-05; badge font defaults are Medium
  (500), 100%, and Number, with explicit user settings preserved.
- [x] Complete the v0.2.0 work by the owner's acceptance decision. This records
  acceptance of the delivered behavior, not completion of every possible
  display configuration or instrumentation run.
- [x] Accept the current animation geometry changes for this stage. Automated
  geometry/input tests and the user's Full HD acceptance are evidence; exhaustive
  four-edge and multi-monitor measurement is not claimed.

The unperformed Classic zoom frame-time, QML, texture, and GPU measurements are
tracked separately as technical debt. No measurements are marked complete; see
[`animation-smoothness.md`](docs/performance/animation-smoothness.md).

### Ongoing documentation and user experience

- [x] Maintain English and Russian READMEs, a Russian Krema-to-KDockW migration
  guide, and language-switch links between both versions.
- [x] Keep the current project identity, repository links, original Krema
  attribution, copyright notices, and license references explicit.
- [x] Provide KI18n Russian translations, English source-string fallback, and
  a saved System default / Русский / English preference.
- [x] Document source build, installation, removal, and the limits of the
  NVIDIA PRIME and PipeWire preview workarounds.
- [ ] Complete a manual language and translation review in a real Wayland
  session, including menus, tooltips, notifications, settings, and restart.
- [ ] Check icon clarity and dock sizing at common fractional and integer
  display scales, then fix any confirmed HiDPI defects.
- [ ] Visually verify all four background styles during parabolic zoom and fix
  any remaining artifacts without disabling blur.

## P2 — Multi-monitor improvements

- [x] Provide Primary Only, All Screens, Follow Active, and Selected Screens
  modes, with debounced hot-plug handling and a temporary primary fallback.
- [x] Provide a KConfig-backed per-screen override layer for the settings
  currently supported by `ScreenSettings`.
- [ ] Add a settings page for per-screen overrides, including a clear action to
  return individual values to global defaults.
- [ ] Verify dock and preview geometry, saved screen choices, and shortcut
  targeting across monitor removal, reconnection, reordering, mixed scaling,
  and primary-screen changes in a real Wayland session.

## v0.3.0 — Window Appearance & Interactions (in progress) ⬅️ Current feature-development priority

### P0 — Window Preview for Minimized Windows (accepted by owner)

- [x] Keep showing the last available authorized thumbnail frame after minimize;
  prefer current frames when KWin continues to provide them.
- [x] Resume live capture on restore, keep frames tied to their window UUID, and
  release resources when a window closes. Never persist window content to disk.
- [x] Verify open and minimized previews in the accepted CPU-only Plasma 6 /
  Wayland session.
- [ ] Validate DMA-BUF/auto capture, memory use, rapid lifecycle changes, and
  exhaustive multi-monitor configurations; these remain unverified technical
  debt.

Owner manual acceptance on KDE Plasma 6 / Wayland confirmed open and minimized
previews in CPU-only mode. DMA-BUF/auto, RAM/VRAM profiling, and exhaustive
multi-monitor checks remain technical debt.

### P0 — Window Preview Redesign (accepted)

- [x] Follow the approved
  [window preview concept](docs/design/window-preview-concept.png): compact card
  without an arrow, minimal padding, rounded corners, a thin border, and a soft
  shadow.
- [x] Provide configurable thumbnail width, maximum height with aspect
  preservation, card padding, and dock gap.
- [x] Show the application name in the compact card header; retain per-window
  titles, grouping, activation, and close actions.
- [x] Keep the current KWin/KPipeWire capture path and CPU-only compatibility.
  Owner acceptance covers frames, rounded clipping, viewport bounds, and open
  and minimized windows in CPU-only mode. DMA-BUF, RAM/VRAM, and exhaustive
  multi-monitor checks remain unverified.

Card: [[11.2-Window-Preview-Improvements]] (done). The owner confirmed in a
real Plasma 6 / Wayland session that frames, rounded clipping, viewport bounds,
and open and minimized CPU-only previews work. DMA-BUF/auto, RAM/VRAM profiling,
and exhaustive multi-monitor validation are not claimed. It depends on accepted
v0.2.0 geometry.

Follow-up refinement ([[11.7-Window-Preview-Spacing-And-Sharpness]], `review`):
the owner accepted the fixed maximum-Classic-Zoom anchor and the latest preview
position. The earlier Wayland coordinate mix was fixed by keeping icon anchors
local to the dock surface and deriving output-edge margins from that surface
plus its floating margin. Invalid pre-frame PipeWire dimensions cannot expand
Cover geometry. A 1581×904 CPU frame at DPR 1 was downsampled to a 196×121
viewport; the sampling filter has not been compared, so the remaining softness
is not isolated. Further filtering experiments are deferred by the owner; this
follow-up remains open. KWin 6.6.6 fixes the window
stream size to the source texture size and advertises an exact SPA rectangle;
client-selected smaller stream resolutions are unsupported. Diagnostic
Baseline/Linear comparison is deferred. Source review found that
KPipeWire 6.6.4 does not set the QSGImageNode filter; Qt 6.10.2 defaults to
Nearest and disables mipmap filtering for that node. A diagnostic Linear A/B is
available, but its visual quality and resource/performance effects remain
unmeasured.

### P0 — Window Preview Size Presets (review)

- [x] Add Compact 180×113, Standard 220×138, Enlarged 260×163, and Large
  320×200 logical-pixel presets on top of the existing width/height settings.
- [x] Keep custom values and existing defaults unchanged until the user selects
  a preset; preserve live updates and saved values.
- [ ] Complete owner visual verification for DPR, grouped windows, screen
  bounds, and all four dock edges.

Card: [[11.8-Window-Preview-Size-Presets]] (`review`). Existing saved values
remain as-is; visual acceptance is pending.

### P0 — Application Name Tooltip (implemented and accepted)

- [x] Show a compact application-name tooltip when no preview card is visible.
- [x] Put the application name in the preview-card header while the card is
  visible; suppress the separate tooltip.
- [x] Verify transitions do not overlap or flicker, including grouped windows;
  implementation tests passed and the owner accepted the functionality.

Card: [[11.5-Application-Name-Tooltip]] (`done`). The source and QML tests cover
the implementation and tooltip bounds; the owner previously accepted the
functionality. No release publication is implied.

### P0 — Toggle Minimize on Click (accepted by owner)

- [x] Provide the single-window and grouped-window activate/minimize settings.
- [x] Activate or restore a window unless it is already active, in which case
  it is minimized.
- [x] Handle grouped windows in the action implementation and automated tests.
- [x] Owner marked the feature done on 2026-11-07.

The implementation is in `DockActions::activateOrMinimize`; QML and KWin
integration tests cover settings dispatch and grouped-window behavior. The
owner marked the task done; the v0.3.0 milestone remains in progress.

**Priority order:** Window Preview for Minimized Windows → Window Preview Redesign
→ Application Name Tooltip → Toggle Minimize on Click. This is an implementation
priority sequence; it creates no dependency by itself. Window Preview Redesign
depends on accepted v0.2.0 geometry. Application Name Tooltip depends on the
preview card's visibility/header state. Toggle Minimize on Click is independent.

## v0.4.0 — macOS-like Spring Physics (released)

KDockW v0.4.0 was published on 2026-11-09 from the verified `main` commit.
The signed tag, packages, and SHA-256 manifest are available on the
[GitHub Release page](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.0).
The required Distro E2E gate passed on Debian 13, Ubuntu 26.04 LTS, and Fedora
45 in [workflow run 42609893460](https://github.com/thicking/kdockw/actions/runs/42609893460).

- [x] **Spring Magnification (`done`):** added time-based spring motion with
  adjustable stiffness, damping, and reaction speed. New configurations use
  Spring (170 / 0.60 / 1.0, 1.9×); saved user values are preserved and Classic
  remains available. Owner accepted the animation in a real Plasma/Wayland
  session; bounded-step tests simulate 60/120/144 Hz.
- [x] **Dock Show/Hide Animation (`done`):** added configurable slide/fade
  animation (enabled, 220 ms by default) for existing hide-capable modes only;
  hiding delay remains independently configurable (500 ms by default). Input
  remains restricted to the edge activation strip while hidden. Owner accepted
  both animation and interaction on real KDE Plasma/Wayland on 2026-11-08.
- [x] **Window Preview Hide Delay (`done`):** added an independent 0–1500 ms
  delay (400 ms default) that can be cancelled when the pointer returns. Owner
  accepted the behavior on KDE Plasma/Wayland on 2026-11-08.
- [x] **Launch & Attention Animation (`done`):** added launch bounce with
  decreasing amplitude, adjustable intensity and speed, and separate attention
  motion driven only by explicit urgency signals. Attention motion is
  time-limited with a persistent calm marker; launch motion takes priority
  during overlapping events. Added a short Click Bounce for activating,
  restoring, or minimizing an already-running app; it is separate from Launch
  Bounce and does not run on hover. Launch height is configurable as a
  percentage of icon size. Owner accepted Launch Bounce, Click Bounce, and
  Attention Animation on Plasma 6.6.6 / Wayland; the new Attention duration
  default is 3 seconds, while saved values remain unchanged.

**Dependencies:** Spring Magnification follows v0.2.0 geometry and the separate
Classic zoom performance-profile technical debt. Dock show/hide follows accepted
surface/input-region geometry. Launch and attention animation remains independent.

## v0.4.2 — Stabilization (completed; published 2026-11-11)

- [x] **Spring re-entry and accepted defaults:** retain the owner-accepted re-entry behavior, 90% Spring Speed, and 70% Launch Bounce Speed; saved values remain unchanged.
- [x] **Minimized preview lifecycle:** prefetch one frame for the foreground window before its popup is opened, preserve each captured frame for its exact window across minimize, popup close, and reopen, refresh TaskManager state after an external titlebar minimize, release capture resources when windows close, and keep storage bounded. PREV-012 was checked in the full required distro matrix.
- [x] **Follow Active:** handle batched TaskManager active-state changes and grouped child geometry; targeted two-output and full required distro checks passed without weakening the scenarios.
- [x] **Immediate preview dismissal:** close the preview after a dispatched activation, restore, or minimize action and suppress reopening until the pointer leaves the source task.
- [x] **Russian settings localization:** complete the settings, help text, dialogs, and accessibility labels; automated localization and release checks passed.

The owner accepted v0.4.2 on real Plasma/Wayland. The signed tag `kdockw-v0.4.2` points to `54aeb6d7c09cbea86bd47175338a855902cfbb12`; the full three-target Distro E2E passed in [run 42833056363](https://github.com/thicking/kdockw/actions/runs/42833056363). See the [published release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.2). The release includes the accepted v0.4.1 changes; no v0.4.1 tag or release was created. Arch Linux package support was retired after v0.4.2 and is not a supported target.

## v0.4.3 — Localization & Preview Cache Reliability (completed, published 2026-11-11)

- [x] **Installed settings localization:** resolve the current KI18n catalog
  from the application's install prefix and verify its compiled contents in
  the installable package.
- [x] **Minimized preview cache reliability:** retain minimized-window frames
  under bounded cache pressure, prioritize them over restored-window frames,
  and preserve UUID isolation and close cleanup.
- [x] Include the completed retirement of unsupported Arch Linux packaging;
  do not alter historical releases or tags.

The owner accepted the diagnostic candidate on real Plasma/Wayland. Commit
`17347884f98e35cb4f9919edb265ebad3529f84c` passed Build & Tests, CI images,
release tooling, and the full required Distro E2E matrix: Debian 13, Ubuntu
26.04 LTS, and Fedora 45 ([run 42970493484](https://github.com/thicking/kdockw/actions/runs/42970493484)).
Signed tag `kdockw-v0.4.3` points to that commit. The stable
[GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.3)
is public with verified packages, source archive, and `SHA256SUMS`. Work has now
started on the approved v0.5.0 feature stage.

## v0.5.0 — Dock Interactions (done, published 2026-11-12)

Folder Stacks and Advanced Drag & Drop were accepted on KDE Plasma 6.6.6 / Wayland in three consecutive 24/24 cycles. The release added mixed stable ordering for pinned tasks and Folder Stacks; folder browsing, file opening, customization, accessibility and popup improvements; safer drag-and-drop; and TaskManager identity/stability fixes.

Production Release CTest passed 176/176; Diagnostic Release CTest passed 177/177. Release tooling passed 154 tests with 1 optional LFS test skipped. Full required Distro E2E passed on Debian 13 and Ubuntu 26.04 for all configured scenarios on exact commit `ebb0527aaa26f7c7f3886d88c0b03811bf099719` ([run 43194552508](https://github.com/thicking/kdockw/actions/runs/43194552508)). The signed tag `kdockw-v0.5.0` and [public GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.5.0) were verified with source archive, both DEB packages, and `SHA256SUMS`.

Fedora 45 was experimental for v0.5.0. The v0.5.1 candidate fixed the stale TaskManager display role on structural row replacement, passed the full Fedora 45 / Qt 6.11.2 Distro E2E (214 passed, 13 skipped, 0 failed), and added Fedora to the candidate release matrix. The published v0.5.0 matrix remains historical. The maximized-window overlap after Plasma lock/unlock is tracked separately for v0.5.1 and is not included in v0.5.0. Stable v0.4.3 was not replaced automatically.

- [x] **13.1 Folder Stacks:** add pinned folder stacks with a Grid view, file opening and drag-and-drop, animation, and usable handling of long lists.
- [x] **13.2 Advanced Drag & Drop:** improve drag-and-drop to new and running applications, including Dolphin; handle cancellation and unsupported data safely.

## v0.5.1 — Wayland Geometry & Fedora Compatibility (in progress)

- [ ] **92e4ea553c084196 Maximized Window Geometry After Unlock:** capture real
  Wayland evidence for lock/unlock changes to the LayerShell exclusive zone,
  surface commit, and KWin available geometry; preserve the Layer Shell surface
  when unlock parameters are unchanged. The owner confirmed the real Plasma
  6.6.6 / Wayland maximized-browser scenario after unlock: frameGeometry and
  MaximizeArea both measured 1920×989 with no 59 px overlap. Broader recovery
  modes and release gates remain to be verified.
- [ ] **f87e3fa5d8554eb7 Dock-to-Window Gap:** add an independent persistent
  0–20 px window gap through the Layer Shell exclusive zone, with live updates,
  all four dock edges, no permanent reservation in Auto Hide/Dodge, and geometry
  regression coverage. Default is 0 px.
- [x] **6b3b5084bd3c479f Fedora 45 / Qt 6.11 Compatibility:** fixed the
  stale TaskManager display role on structural replacement; Debian 13,
  Ubuntu 26.04, and Fedora 45 packages built, and the full Fedora 45 suite
  passed on Qt 6.11.2 (214 passed, 13 skipped, 0 failed). Fedora 45 is included
  in the v0.5.1 candidate matrix.

The first Ubuntu 26.04 full run had one preview fast-pointer timing failure;
the isolated retry passed. Inspection showed the 190 ms assertion combined
AT-SPI geometry lookup with input dispatch. The test now records lookup time
separately, keeps the 190 ms limit on actual input dispatch, verifies the
KWin-reported cursor position, and checks that the popup stays open. The
instrumented isolated retry and the complete rerun passed.

Candidate verification: Production Release CTest **180/180**, Diagnostic
Release CTest **181/181**; Debian 13 **210 passed / 21 skipped / 0 failed**;
Ubuntu 26.04 **218 / 13 / 0**; Fedora 45 / Qt 6.11.2 **218 / 13 / 0**. The
original failed Ubuntu full-run result remains preserved as historical evidence.
The owner accepted the reported maximized-browser unlock case; a candidate
lock/unlock check and manual Plasma checks for fullscreen, Auto Hide, Dodge,
all edges, scaling, and TaskManager/previews remain open. v0.5.1 stays in
progress pending that live acceptance; no release or tag has been created.

## v0.6.0 — Visual Effects & KWin Integration (planned)

- [ ] **Context Menu UX Cleanup:** group KDockW settings/about/quit actions in a
  `KDockW` submenu; rename the selected application's `Quit` action to
  `Close application` without terminating the dock; preserve remaining system
  and application actions for pinned apps, unpinned tasks, and window groups.
  Add regression tests and manual Wayland verification.
- [ ] Research supported KWin/Wayland interfaces for window animations and
  evaluate Scale/Genie and dock-icon association. Document Plasma compatibility
  and public/private API boundaries; build no prototype without a separate
  decision.
- [ ] Improve glass materials, highlights, lighting, and shadows for light and
  dark wallpapers; measure GPU/frame cost on Intel, AMD, and NVIDIA hardware and
  provide controls for effects.

## v0.7.0 — Built-in Dock Widgets & Application Launcher (planned)

- [ ] **Built-in Dock Widget Model:** define the internal architecture for
  built-in widgets, including dock slots, separators, and spacers; a public
  plugin API is out of scope.
- [ ] **Application Launcher Widget:** provide three switchable menu styles:
  compact macOS Launchpad app/folder grid; Windows Start with pinned apps,
  search, and full list; and KDE hierarchical Launchpad preserving the
  KService/XDG Menu hierarchy.

## Technical debt — Classic Zoom Performance Profile

- [ ] Capture real frame pacing, Qt Quick/QML binding, texture-update, pointer
  response, and CPU/GPU measurements at 60/120/144 Hz with different dock item
  counts. Compare idle, slow pointer movement, and fast movement.
- [ ] Optimize only after a repeatable profile confirms a bottleneck; preserve
  Classic zoom mathematics, geometry, input regions, and Wayland behavior.

## P3 — Unversioned future exploration and accepted work

### Backlog — no release assignment

- [ ] **Media Player Controls Widget:** use MPRIS2 over D-Bus, with player
  selection, track and artist metadata, artwork, transport controls, and
  seeking only when supported by the active player.
- [ ] **Downloads Stack & Progress Indicator:** extend 13.1 Folder Stacks with
  a navigable Downloads grid, automatic refresh, file opening and Dolphin
  navigation. Investigate KDE JobViewServer/KIO for actual progress; show an
  indeterminate or neutral state when no progress is available.

Media Player Controls and Downloads Stack remain unversioned backlog items.
The v0.7.0 widget model is a prerequisite for both. This planning assigns no
release date.

- **Badge Appearance (implemented and owner accepted):** default badge colors
  are `#FF3B30` and `#FFFFFF`; independent saved colors, reset, preview, and
  contrast feedback are available. This work is not assigned to a published
  release.
- **Badge Startup Synchronization (`research`):** investigate why a Telegram counter can be
  absent when Telegram starts before KDockW, while restarting Telegram restores
  it and restarting KDockW does not.
- **Classic Zoom Performance Profiling (`research`):** capture frame pacing and
  QML/CPU/GPU behavior; instrumented measurements have not been run.
- **Window Preview Spacing and Sharpness (`review`):** accepted positioning is
  preserved; further filtering experiments are deferred because the remaining
  softness has not been isolated.
- **Preview Close Button (placement review):** the accepted idle/hover/pressed
  appearance remains; the button is in the top-right of the card header,
  opposite the app icon, and awaits visual verification. This work is not
  assigned to a published release.
- **GitHub Release Update Checker (`done`):** stable-release checks, KDE
  notifications, manual checks, and settings are implemented and accepted.
  Settings live under About; updates are never downloaded or installed
  automatically.
- **Grouped Window Preview Close Controls (`done`):** each grouped thumbnail
  has a close button tied to that child's current window UUID; the existing
  header button remains for a single window. The owner accepted the production
  behavior.
- **Settings Preview Consistency (`done`):** the settings mini-dock uses the
  live badge colors and typography, edge-aware parabolic zoom geometry, and an
  interactive “Pointer hover zoom” switch. The owner accepted the behavior in a
  real Plasma 6 / Wayland session; no release assignment is implied.
- **Adaptive Inactive Preview Border (`review`):** add a subtle one-pixel
  outline that adapts to the configured preview-card surface while preserving
  the active KDE accent. No release assignment is implied; visual acceptance
  remains pending.

- [ ] Evaluate StatusNotifierItem system-tray support, including item lifecycle
  and native menus, before planning implementation.
- [ ] Study whether hosting Plasma widgets (Plasmoids) fits KDockW's Wayland and
  lifecycle architecture.
- [ ] Consider additional visual effects only after an implementation design
  has a clear performance budget and accessibility review.

## Project scope

KDockW targets KDE Plasma 6 on Wayland and uses Qt 6 and KDE Frameworks 6.
The project is developed independently from [Krema](https://github.com/isac322/krema),
originally created by Byeonghoon Yoo. Historical Krema releases and planning
documents are retained under [`docs/history/`](docs/history/); they are not
KDockW release records or commitments.
