# KDockW roadmap

KDockW is an independent KDE Plasma 6 dock for Wayland and a spiritual
successor to Latte Dock. This roadmap describes KDockW work only; it does not
copy or extend Krema's archived plan. Items are priorities, not release dates
or version promises. See the [Russian roadmap](ROADMAP.ru.md), the
[KDockW changelog](CHANGELOG.md), and the [archived Krema roadmap](docs/history/krema-roadmap.md).

## P0 — Stability and release readiness

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

## v0.3.0 — Window Appearance & Interactions (planned) ⬅️ Next feature-development priority

### P0 — Window Preview for Minimized Windows (accepted by owner)

- [ ] Keep showing the last available authorized thumbnail frame after minimize;
  prefer current frames when KWin continues to provide them.
- [ ] Resume live capture on restore, keep frames tied to their window UUID, and
  release resources when a window closes. Never persist window content to disk.
- [ ] Verify grouped windows, rapid minimize/restore, CPU-only and DMA-BUF paths,
  Wayland behavior, memory use, and multiple monitors.

Owner manual acceptance on KDE Plasma 6 / Wayland confirmed open and minimized
previews in CPU-only mode. DMA-BUF/auto, RAM/VRAM profiling, and exhaustive
multi-monitor checks remain technical debt.

### P0 — Window Preview Redesign (accepted)

- [x] Follow the approved [`концепт.png`](концепт.png): compact card without an
  arrow, minimal padding, rounded corners, a thin border, and a soft shadow.
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

### P0 — Application Name Tooltip

- [ ] Show a compact application-name tooltip when no preview card is visible.
- [ ] Put the application name in the preview-card header while the card is
  visible; suppress the separate tooltip.
- [ ] Transition smoothly between tooltip and card without overlap or flicker,
  including grouped windows.

### P0 — Toggle Minimize on Click

- [ ] Provide **Activate only** and **Minimize on second click** settings.
- [ ] First click activates or restores a window; a second click on the active
  window minimizes it.
- [ ] Support grouped windows without changing existing window-switching
  behavior; verify KDE Plasma 6 / Wayland / KWin behavior.

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

- [ ] Add pinned folder stacks with a Grid view, file opening and drag-and-drop,
  animation, and usable handling of long lists. Consider Fan only if technically
  justified.
- [ ] Improve drag-and-drop to new and running applications, including Dolphin;
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

## P3 — Future exploration

- **Badge Appearance:** use `#FF3B30` red with `#FFFFFF` text by default and
  provide independent settings for both colors.
- **Badge Startup Synchronization:** investigate why a Telegram counter can be
  absent when Telegram starts before KDockW, while restarting Telegram restores
  it and restarting KDockW does not.
- **Preview Close Button:** use a KDE-themed close button that remains readable
  without hover.
- **GitHub Release Update Checker:** check for stable GitHub Releases in the
  background, send KDE notifications, offer manual checks and settings, and
  never install updates automatically.

- [ ] Define and evaluate a small built-in dock-widget model before committing
  to a public extension API; then consider left, center, and right slots plus
  separator and spacer widgets.
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
