# Phase 2: Real Plasma/Wayland findings

**Status:** saved CPU compatibility mode implemented. A user-reported real-session A/B confirms it works on one hybrid-GPU laptop; the internal DMA-BUF failure remains unlocalized. The UI toggle's live effect is covered by automated lifecycle tests, not independently observed in this audit.

This report supplements the Phase 1 audit. It does not replace or rewrite it.

## WAYLAND-001: black window previews

### Evidence

- The installed KDockW process logged `PipeWireSourceItem` reaching streaming
  state (`state=4`) and `ready=true` for window captures. It reported populated
  stream dimensions and `usingDmaBuf=true`, with an empty KPipeWire error string.
- The installed KPipeWire header documents `ready` as true after the first
  frame has been received. This confirms receipt of a first frame, not that the
  frame's pixels are non-black or that DMA-BUF import and Qt Quick presentation
  succeeded.
- In the same log sequences, `ready` later became false as the stream left
  streaming state. This is consistent with the preview being hidden and does
  not by itself indicate a capture failure.
- `PreviewThumbnail.qml` only retries without DMA-BUF when streaming has not
  produced its first frame after 1.5 seconds. A black image with `ready=true`
  does not enter that retry path.
- The existing distro E2E preview test checks actual red/blue fixture pixels
  and includes a narrowly scoped resize renegotiation for the known untyped
  buffer race. That test is useful for its CI environment but does not establish
  that the hybrid Intel/NVIDIA Wayland session imports and renders its buffers
  correctly.

### Conclusion and remaining evidence

The stream setup and first-frame receipt are observed. The black-pixel stage is
not localized: the available logs do not distinguish black pixels delivered by
KWin from a DMA-BUF import problem or a Qt Quick scene-graph presentation issue.
There is no confirmed root cause and no renderer/import fix is justified yet.
Do not treat the existing no-first-frame CPU retry as a fix for a black frame
that has already made `ready` true.

### User-reported A/B result (subsequent manual test)

The user later compared Auto and CPU-only on TUXEDO OS 24.04.5, Plasma 6.6.6,
Qt 6.10.2, Intel Iris Xe + NVIDIA RTX 4050 with driver 580.178.04. Qt Quick
used OpenGL on the NVIDIA renderer. The same Wayland-native and XWayland
windows were tested. Auto used DMA-BUF (`usingDmaBuf=true`), reached
`ready=true`/Streaming without KPipeWire errors, and appeared black. CPU-only
used no DMA-BUF (`usingDmaBuf=false`) and displayed correct thumbnails, also
ready/Streaming without KPipeWire errors. This is a user-reported visual A/B,
not an independently reproduced result in this checkout. It is evidence of a
capture-path-specific compatibility problem on this setup; it does not identify
the exact failing API/import operation or imply a general NVIDIA defect.

### User setting, diagnostic override, and tests

`PreviewController` uses the saved `CpuOnlyPreviewCapture` setting, with Auto
as the default. It also accepts `KDOCKW_PREVIEW_CAPTURE_MODE=auto|cpu-only` as
a process-only override without writing that value to the configuration.
Changing the UI setting recreates active capture items; CPU-only starts each
item with `allowDmaBuf=false`, while Auto alone retains the bounded
no-first-frame retry. The setting provides the reported workaround without a
systemd environment override. The underlying import/rendering defect is not
fixed or automatically detected.

The existing retry remains limited to Auto streams that reach Streaming but
produce no first frame for 1.5 seconds. It is not triggered by `ready=true`. The
project's controlled E2E test retains its red/blue pixel oracle and one-time
untyped-buffer renegotiation. There is no evidence yet to remove the retry, nor
to generalize that fixture-specific race to the hybrid-GPU black frame.

At the time of the original Phase 2 run, automated checks covered unset,
`auto`, `cpu-only`, and invalid values, and the QML test verified CPU-only
creation and Auto's bounded no-first-frame retry. That run did not perform a
real Wayland/GPU comparison because an installed KDockW process was already
active. The user's subsequent manual A/B is recorded above. Follow the A/B procedure in
[`../../architecture/window-previews.md`](../../architecture/window-previews.md).

To collect a bounded reproduction from the installed process, start this in a
terminal, reproduce one black preview, then stop the command with Ctrl+C:

```sh
pid=$(pgrep -n -x kdockw) || { echo 'KDockW process not found'; exit 1; }
journalctl --user -f _PID="$pid" -o short-iso-precise |
  grep --line-buffered -E '\[kdockw\.preview\]|QRhi|QSG|scene.?graph|OpenGL|EGL|PipeWire|buffer|dma.?buf|GL_INVALID'
```

Please provide the matching preview lines and a screenshot showing the black
thumbnail. Test one Wayland-native window and one XWayland window separately,
and note which is which. Do not include full process environments or unrelated
window titles. If the logs show `ready=true`, also note whether the thumbnail
remains black continuously or only before a resize/reopen.

## WAYLAND-002: auto-hide and dodge

### Evidence

- `DockVisibilityController::evaluateVisibility()` intentionally keeps the dock
  visible while `m_interactingCount > 0`, while keyboard navigation is active,
  or while the pointer is over the dock. In Auto-hide mode it hides when those
  guards are clear; in Dodge mode it uses the region-filtered TaskManager model
  to test overlap.
- The Settings window contributes an interaction lock. The available live
  journal shows the user changing to Auto-hide and Dodge while
  `interacting=1`. The user then changed back to Always-visible before the lock
  was released. In that state the dock is expected to remain visible.
- No captured log sequence establishes behavior after the Settings window
  closed with Auto-hide or Dodge still selected. The current `kdockwrc` snapshot
  has no explicit `VisibilityMode` override and the configured default is
  Always-visible; this is not evidence that a saved non-default value was lost.
- `tests/appium/test_07_visibility.py` already exercises Auto-hide pointer leave,
  Dodge overlap, inactive-window overlap, and Smart Hide against its test
  compositor. Those tests do not establish behavior in the user's live Plasma
  session.

### Conclusion and remaining evidence

The observed “dock stays visible” while Settings is open is explained by the
interaction lock, not by a demonstrated Auto-hide/Dodge defect. There is no
post-settings reproduction in the available logs, so no root cause or source
change is justified yet.

For a live Auto-hide reproduction, close Settings, move the pointer well away
from the dock, wait at least two seconds, and collect:

```sh
pid=$(pgrep -n -x kdockw) || { echo 'KDockW process not found'; exit 1; }
journalctl --user _PID="$pid" --since '3 minutes ago' -o short-iso-precise --no-pager |
  grep -E 'kdockw\.shell\.visibility|Visibility mode changed|evaluateVisibility|Dock visible|Interaction lock'
```

For Dodge, repeat with Settings closed, `DodgeActiveOnly` set as intended, and
one normal window visibly covering the dock's edge area. Record whether that
window is active. Provide the filtered log and note the selected mode, monitor,
edge, and whether the pointer is over the dock. These observations distinguish
pointer/interaction guards from window-overlap tracking without changing any
system settings.

## Test and repository state

- Release configure/build: passed.
- Dev build: passed.
- New capture-mode unit test and `qml_tst_preview_popup`: passed.
- Full CTest initially passed 78/81. The staging failure was corrected by
  making the test install use `DESTDIR` inside its build-tree staging folder;
  the test then passed in isolation. The two remaining unrelated failures were
  reproduced individually: `kdockw_integration_tests` measured a 2.07 px
  settings-preview edge shift against a 0.5 px threshold, and
  `kdockw_selected_output_tests` failed to find the expected launcher item in a
  selected-mode shortcut case.
- No real GPU thumbnail comparison, application installation, service change,
  or publication was performed.

The code changes are limited to the isolated capture diagnostic mode and its
tests; the staged-install script was separately corrected to keep its test
installation inside the build tree. Automated mocks/software rendering cannot
confirm cross-GPU DMA-BUF import or visible pixels in the user's Plasma session.
