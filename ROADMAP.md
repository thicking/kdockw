# KDockW roadmap

KDockW is an independent KDE Plasma 6 dock for Wayland and a spiritual
successor to Latte Dock. This roadmap describes KDockW work only; it does not
copy or extend Krema's archived plan. Items are priorities, not release dates
or version promises. See the [Russian roadmap](ROADMAP.ru.md), the
[KDockW changelog](CHANGELOG.md), and the [archived Krema roadmap](docs/history/krema-roadmap.md).

## P0 — Stability and release readiness ⬅️ Current priority

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
  metadata; the release remains unpublished until signing and package gates pass.
- [ ] Publish the first standalone KDockW release; the existing `v0.x` tags
  belong to Krema history.
- [ ] Complete release automation and package smoke checks before publishing
  KDockW-specific binary packages.

## P1 — Documentation and user experience

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

## P3 — Future exploration

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
