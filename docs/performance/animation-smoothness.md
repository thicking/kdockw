# Classic Zoom Smoothness Investigation

## Current baseline and limits

The November 5, 2026 source inspection found the existing Classic zoom path in
`src/qml/main.qml` and `src/shell/dockview.cpp`. Cursor position and the eased
zoom amount feed `DockView.zoomLayout()`; its scale and offset values are bound
to each `DockItem`. Hover reevaluation is coalesced with `Qt.callLater()`, and
panel-rectangle reporting is also deferred/coalesced. These are code-path facts,
not evidence that bindings or geometry calculations are a performance problem.
The zoom algorithm and QML bindings were not changed.

No frame-time, GPU, QML-binding, or pointer-motion measurements are part of
this source review. QML tests are regression checks, not a replacement for
those measurements.

## Manual profiling procedure

Run this only in a maintenance window chosen by the owner. Do not run a second
dock alongside the installed one. Close the running dock normally, then launch
the candidate binary and keep its output for each scenario:

```sh
repo_root="$(git rev-parse --show-toplevel)"
mkdir -p "$HOME/kdockw-smoothness"
QSG_RENDER_TIMING=1 \
QT_LOGGING_RULES='qt.scenegraph.general=true;qt.scenegraph.time.renderloop=true;qt.scenegraph.time.renderer=true;qt.scenegraph.time.texture=true' \
  "$repo_root/build/release/bin/kdockw" \
  2> "$HOME/kdockw-smoothness/144hz-rest.log"
```

For each refresh rate, use the same display, scale, theme, icon size, pinned
items, running windows, and application set for the before/after comparison.
Use a display mode that the monitor actually advertises; the current machine
offers 60 and 144 Hz, but not 120 Hz. Repeat each case three times:

1. Leave the pointer outside the dock for 20 seconds (idle baseline).
2. Enter the dock and hold over the center icon for 20 seconds.
3. Sweep slowly from one end of the dock to the other for 20 seconds.
4. Sweep quickly across and back for 20 seconds.
5. Repeat the moving cases with a small and a large mix of pinned and running
   applications, recording the item counts.

Record refresh rate and item counts alongside each log. Compare frame timing
distributions and missed/late frames against the frame budgets (16.67 ms at
60 Hz, 8.33 ms at 120 Hz, 6.94 ms at 144 Hz). Use Qt Creator's QML Profiler on
the same candidate and cases to inspect binding evaluation, signal handlers,
JavaScript, animation frames, and Scene Graph events. Inspect texture timing and
icon source changes during motion; texture upload logs alone do not prove that
no texture was recreated. Do not force a different Qt render loop for the
acceptance run.

Only optimize after a repeatable profile identifies a cause. Keep the same
machine, monitor mode, settings, application counts, and pointer path for a
before/after comparison, then rerun geometry, icon, badge, preview, and animation
regression tests.
