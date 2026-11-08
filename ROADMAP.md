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

## v0.4.0 — macOS-like Spring Physics (planned)

- [ ] Add a separate Spring magnification mode with damping and configurable
  stiffness, speed, and decay; preserve Classic unchanged. Verify cursor
  tracking, spacing, all four dock edges, and 60/120/144 Hz behavior.
- [ ] Add configurable dock show/hide animation. Keep KWin/window interaction
  correct and ensure an invisible surface does not capture the pointer.
- [ ] Refine launch bounce and separate launch and attention states; verify
  overlapping events do not leave an item in a stale animation state.

**Dependencies:** Spring Magnification follows v0.2.0 geometry and the separate
Classic zoom performance-profile technical debt. Dock show/hide follows accepted
surface/input-region geometry. Launch and attention animation remains independent.

## v0.5.0 — Dock Interactions (planned)

- [ ] **13.1 Folder Stacks:** add pinned folder stacks with a Grid view, file opening and drag-and-drop,
  animation, and usable handling of long lists. Plan Downloads Stack and real
  download progress as a linked extension; do not infer percentages from file
  presence. Consider Fan only if technically justified.
- [ ] **13.2 Advanced Drag & Drop:** improve drag-and-drop to new and running applications, including Dolphin;
  handle cancellation and unsupported data safely.

## v0.6.0 — Visual Effects & KWin Integration (planned)

- [ ] Research supported KWin/Wayland interfaces for window animations and
  evaluate Scale/Genie and dock-icon association. Document Plasma compatibility
  and public/private API boundaries; build no prototype without a separate
  decision.
- [ ] Improve glass materials, highlights, lighting, and shadows for light and
  dark wallpapers; measure GPU/frame cost on Intel, AMD, and NVIDIA hardware and
  provide controls for effects.

## Technical debt — Classic Zoom Performance Profile

- [ ] Capture real frame pacing, Qt Quick/QML binding, texture-update, pointer
  response, and CPU/GPU measurements at 60/120/144 Hz with different dock item
  counts. Compare idle, slow pointer movement, and fast movement.
- [ ] Optimize only after a repeatable profile confirms a bottleneck; preserve
  Classic zoom mathematics, geometry, input regions, and Wayland behavior.

## P3 — Unversioned future exploration and accepted work

### Built-in Dock Widgets (planned; no release assignment)

- [ ] Define a small built-in widget model with left, center, and right slots,
  separators, and spacers. Keep it internal; a public plugin API is out of scope.
- [ ] **Application Launcher Widget:** provide compact macOS-style Launchpad,
  Windows-style Start, and KDE-menu-based hierarchical Launchpad views. All
  styles share search, keyboard control, localization, and Wayland-aware
  positioning; use the real KService/XDG Menu hierarchy for KDE categories.
- [ ] **Media Player Controls Widget:** use MPRIS2 over D-Bus, with player
  selection, track and artist metadata, artwork, transport controls, and
  seeking only when supported by the active player.
- [ ] **Downloads Stack & Progress Indicator:** extend 13.1 Folder Stacks with
  a navigable Downloads grid, automatic refresh, file opening and Dolphin
  navigation. Investigate KDE JobViewServer/KIO for actual progress; show an
  indeterminate or neutral state when no progress is available.

The shared built-in widget model is a prerequisite for the Launcher, Media
Player Controls, and Downloads Stack. This planning does not assign a release
version or date.

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
