# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""tests/e2e/scenarios/01-keyboard-nav.md (KBD-001..KBD-009): dock and
preview keyboard navigation driven by real key presses, checked through the
AT-SPI ``focused``/``showing`` states and KWin's window list.

The preview-entry key points away from the dock edge (src/qml/main.qml,
``previewKey``): Down on a top dock, Up on a bottom dock. The scenario's
steps press Down, so the preview tests put the dock on the top edge.
"""

from __future__ import annotations

import time
from typing import Callable

import pytest
from PIL import Image

from kdockw_e2e import config, env, kwin
from kdockw_e2e import input as inp
from kdockw_e2e.kdockw import KDockW, Rect, has_state, painted_rect
from kdockw_e2e.shortcuts import META_ALT_D, invoke_shortcut, shortcut_keys
from kdockw_e2e.waits import wait_stable, wait_until
from kdockw_e2e.windows import TestWindows

# Three distinct app ids so every window is its own (ungrouped) dock item,
# named after the window title.
APP_IDS = (env.TEST_APP_ID, env.TEST_APP2_ID, "org.kde.kwrite")

TOP = {"Edge": config.EDGE_TOP}

#: Screen centre (the scenario's "mouse_move x=400 y=300" target area).
CENTRE = (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2)
#: Neutral pointer spot: right edge, mid-height. Off the dock, its edge
#: trigger strip and the preview popup.
PARK = (env.SCREEN_WIDTH - 10, env.SCREEN_HEIGHT // 2)


# --------------------------------------------------------------------- helpers
def park_pointer() -> None:
    """Put the pointer where no kdockw surface receives it before keyboard
    navigation starts."""
    inp.move(*PARK)


def open_items(kdockw: KDockW, apps: TestWindows, titles: list[str]) -> None:
    for title, app_id in zip(titles, APP_IDS):
        apps.open(title, app_id=app_id)
    for title in titles:
        kdockw.wait_for_item(title)
    wait_until(lambda: kdockw.item_names() == titles, message=lambda: f"dock items {titles} in order (have {kdockw.item_names()})")


def focused_items(kdockw: KDockW) -> list[str]:
    return [e.get_attribute("name") for e in kdockw.items() if has_state(e, "focused")]


def wait_focused(kdockw: KDockW, name: str) -> None:
    wait_until(lambda: focused_items(kdockw) == [name], message=f"only {name!r} to be focused (have {focused_items(kdockw)})")


def item_rects(kdockw: KDockW) -> dict[str, Rect]:
    """Settled surface-local rects of the dock items by name."""
    return wait_stable(lambda: {e.get_attribute("name"): Rect.of(e) for e in kdockw.items()})


def wait_widest(kdockw: KDockW, name: str, rest: dict[str, Rect]) -> dict[str, Rect]:
    """Wait for the zoom animation to settle and check ``name`` is the widest
    item and, with the default Parabolic zoom style, that the items on its
    sides moved aside (away from it). ``rest``: :func:`item_rects` before
    keyboard navigation zoomed any."""
    rects = {n: painted_rect(r, rest[n]) for n, r in item_rects(kdockw).items()}
    widest = max(rects.values(), key=lambda r: r.width)
    assert rects[name].width == widest.width, rects
    others = [r.width for n, r in rects.items() if n != name]
    assert all(rects[name].width > w for w in others), f"{name!r} not zoomed beyond its neighbours: {rects}"
    order = list(rects)
    focus = order.index(name)
    for i, n in enumerate(order):
        if i != focus:
            shift = rects[n].center[0] - rest[n].center[0]
            assert shift * (i - focus) > 2, f"{n!r} not moved aside from focused {name!r} (centre shift {shift}): {rects}"
    return rects


def focused_thumbnails(kdockw: KDockW) -> list[str]:
    return [e.get_attribute("name") for e in kdockw.thumbnails() if has_state(e, "focused")]


def thumbnail_title(name: str) -> str:
    """Window title of a thumbnail (its name is "<title>[, Active][, Minimized]")."""
    return name.split(", ")[0]


def assert_holds(predicate: Callable[[], bool], duration: float, message: str) -> None:
    """Poll ``predicate`` for ``duration`` seconds; fail as soon as it is false."""
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        assert predicate(), message
        time.sleep(0.2)
    assert predicate(), message


def item_is_shown(kdockw: KDockW, name: str) -> bool:
    el = kdockw.item(name)
    return el is not None and has_state(el, "showing") and has_state(el, "visible")


def enter_preview(kdockw: KDockW, target: str) -> None:
    """Keyboard mode -> focus ``target`` with Right -> Down opens its preview."""
    invoke_shortcut("focus-dock")

    def steps() -> int | None:
        names, focused = kdockw.item_names(), focused_items(kdockw)
        if target not in names or len(focused) != 1 or focused[0] not in names:
            return None
        return names.index(target) - names.index(focused[0]) + 1  # +1: truthy for 0 steps

    right = wait_until(steps, message=f"a focused dock button and item {target!r}") - 1
    kdockw.wait_keyboard_focus()
    for _ in range(right):
        inp.key("Right")
    wait_focused(kdockw, target)
    inp.key("Down")
    wait_until(kdockw.preview_visible, message="preview popup to open")
    wait_until(lambda: len(focused_thumbnails(kdockw)) == 1, message="a focused thumbnail")


def blueish_pixels(img: Image.Image, rect: Rect) -> int:
    """Pixels in ``rect`` whose blue channel clearly dominates (focus ring)."""
    crop = img.convert("RGB").crop((rect.x, rect.y, rect.x + rect.width, rect.y + rect.height))
    return sum(1 for r, g, b in crop.getdata() if b > 150 and b > r + 60 and b > g + 20)


# ---------------------------------------------------------------------- KBD-001
def _assert_dock_keyboard_entry(kdockw: KDockW, first: str, rest: dict[str, Rect]) -> None:
    wait_focused(kdockw, first)
    kdockw.wait_keyboard_focus()
    toolbar = kdockw.toolbar()
    assert has_state(toolbar, "focused"), "tool bar 'KDockW Dock' lacks the focused state"
    for el in kdockw.items():
        assert has_state(el, "focusable"), el.get_attribute("name")
        assert has_state(el, "showing") and has_state(el, "visible"), el.get_attribute("name")
    rects = wait_widest(kdockw, first, rest)

    if kwin.can_capture():
        # Focus ring: a highlight-coloured border drawn only while the item
        # has keyboard focus. Same screen region with and without focus.
        region = kdockw.to_screen(rects[first])
        ring = blueish_pixels(kdockw.screenshot("keyboard-focus", region), region)
        inp.key("Escape")
        wait_until(lambda: focused_items(kdockw) == [], message="Escape to end keyboard navigation")
        wait_stable(lambda: Rect.of(kdockw.item(first)))
        plain = blueish_pixels(kdockw.screenshot("no-keyboard-focus", region), region)
        assert ring > 200 and ring > 3 * plain, f"no focus ring on {first!r}: {ring} blue px focused vs {plain} unfocused"


def test_kbd001_meta_alt_d_focuses_first_dock_item(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["First", "Second"])
    park_pointer()
    rest = item_rects(kdockw)
    assert focused_items(kdockw) == []
    # The default key must survive registration: no stock Plasma component
    # claims it, so kglobalacceld (any version) keeps it for kdockw.
    wait_until(
        lambda: shortcut_keys("focus-dock") == [META_ALT_D],
        message=lambda: f"kdockw focus-dock bound to Meta+Alt+D (keys: {shortcut_keys('focus-dock')})",
    )

    inp.key("Meta", "Alt", "d")

    _assert_dock_keyboard_entry(kdockw, "First", rest)


def test_kbd001_focus_dock_shortcut_focuses_first_dock_item(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["First", "Second"])
    park_pointer()
    rest = item_rects(kdockw)
    assert focused_items(kdockw) == []

    invoke_shortcut("focus-dock")

    _assert_dock_keyboard_entry(kdockw, "First", rest)


# ---------------------------------------------------------------------- KBD-002
def test_kbd002_arrow_keys_move_focus_between_items(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["One", "Two", "Three"])
    park_pointer()
    rest = item_rects(kdockw)
    invoke_shortcut("focus-dock")
    wait_focused(kdockw, "One")
    kdockw.wait_keyboard_focus()

    inp.key("Right")
    wait_focused(kdockw, "Two")
    wait_widest(kdockw, "Two", rest)

    inp.key("Right")
    wait_focused(kdockw, "Three")
    wait_widest(kdockw, "Three", rest)

    inp.key("Left")
    wait_focused(kdockw, "Two")
    wait_widest(kdockw, "Two", rest)


# ---------------------------------------------------------------------- KBD-003
@pytest.mark.kdockwrc({**TOP, "PinnedLaunchers": []})
def test_kbd003_down_opens_preview_with_first_thumbnail_focused(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["Other", "Calc"])
    park_pointer()
    assert not kdockw.preview_visible()

    enter_preview(kdockw, "Calc")

    popup = kdockw.preview_popup()
    assert popup.get_attribute("name") == f"Preview for {env.TEST_APP2_NAME}"
    assert has_state(popup, "showing") and has_state(popup, "visible")
    assert kdockw.find(f"//popup_menu/label[@name='{env.TEST_APP2_NAME}']") is not None, "app name label"
    assert kdockw.find("//popup_menu/separator") is not None, "separator"
    thumbs = kdockw.thumbnails()
    assert len(thumbs) == 1
    assert thumbnail_title(thumbs[0].get_attribute("name")) == "Calc"
    assert has_state(thumbs[0], "focused")
    assert kdockw.find("//popup_menu/button/button[@name='Close Calc']") is not None, "close button"
    assert kdockw.find("//popup_menu/button/label[@name='Calc']") is not None, "title label"

    if kwin.can_capture():
        # Live thumbnail: the popup area must contain rendered, varied content.
        img = kdockw.screenshot("preview-open")
        r = kdockw.screen_rect(thumbs[0], surface="preview")
        colors = img.crop((r.x, r.y, r.x + r.width, r.y + r.height)).getcolors(maxcolors=1 << 16)
        assert colors is None or len(colors) > 16, f"thumbnail region looks blank: {colors}"


# ---------------------------------------------------------------------- KBD-004
@pytest.mark.kdockwrc({**TOP, "PinnedLaunchers": [], "VisibilityMode": config.AUTO_HIDE})
def test_kbd004_enter_activates_focused_thumbnail_window(kdockw: KDockW, apps: TestWindows) -> None:
    a = apps.open("Window A", app_id=env.TEST_APP_ID)
    b = apps.open("Window B", app_id=env.TEST_APP_ID)
    park_pointer()
    app = env.TEST_APP_NAME
    kdockw.wait_for_item(app)
    wait_until(lambda: b.is_active(), message="last opened window to be active")

    enter_preview(kdockw, app)
    names = wait_until(
        lambda: (t := [thumbnail_title(e.get_attribute("name")) for e in kdockw.thumbnails()]) and sorted(t) == ["Window A", "Window B"] and t,
        message="thumbnails of both windows",
    )
    # Move focus to the inactive window so activation is observable.
    target = "Window A"
    if thumbnail_title(focused_thumbnails(kdockw)[0]) != target:
        inp.key("Right" if names.index(target) > 0 else "Left")
    wait_until(lambda: [thumbnail_title(n) for n in focused_thumbnails(kdockw)] == [target], message=f"{target!r} thumbnail focused")

    inp.key("Return")

    wait_until(lambda: a.is_active(), message=f"{target!r} to become the active KWin window")
    active = kwin.active_window()
    assert active is not None and active.title == target
    wait_until(lambda: focused_items(kdockw) == [], message="keyboard mode to end")
    wait_until(lambda: not kdockw.preview_visible(), message="preview to close")
    popup = kdockw.preview_popup()
    assert popup is not None and not has_state(popup, "showing")
    wait_until(lambda: not item_is_shown(kdockw, app), message="dock to slide out")


# ---------------------------------------------------------------------- KBD-005
def test_kbd005_escape_exits_keyboard_navigation(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["Esc One", "Esc Two"])
    park_pointer()
    invoke_shortcut("focus-dock")
    wait_focused(kdockw, "Esc One")
    kdockw.wait_keyboard_focus()

    inp.key("Escape")

    wait_until(lambda: focused_items(kdockw) == [], message="no focused dock button after Escape")
    # Keyboard mode is over: arrows no longer move a focus.
    inp.key("Right")
    assert_holds(lambda: focused_items(kdockw) == [], 1.0, "Right after Escape re-focused a button")


# ---------------------------------------------------------------------- KBD-006
@pytest.mark.kdockwrc({**TOP, "PinnedLaunchers": []})
def test_kbd006_left_right_move_between_thumbnails(kdockw: KDockW, apps: TestWindows) -> None:
    apps.open("Thumb A", app_id=env.TEST_APP_ID)
    apps.open("Thumb B", app_id=env.TEST_APP_ID)
    park_pointer()
    app = env.TEST_APP_NAME
    kdockw.wait_for_item(app)

    enter_preview(kdockw, app)
    wait_until(lambda: len(kdockw.thumbnails()) == 2, message="two thumbnails")
    first, second = (thumbnail_title(e.get_attribute("name")) for e in kdockw.thumbnails())
    assert [thumbnail_title(n) for n in focused_thumbnails(kdockw)] == [first]

    inp.key("Right")
    wait_until(lambda: [thumbnail_title(n) for n in focused_thumbnails(kdockw)] == [second], message="second thumbnail focused")

    if kwin.can_capture():
        thumbs = {thumbnail_title(e.get_attribute("name")): e for e in kdockw.thumbnails()}
        ring_rect = kdockw.screen_rect(thumbs[second], surface="preview")
        plain_rect = kdockw.screen_rect(thumbs[first], surface="preview")
        area = kwin.bounds(ring_rect, plain_rect)
        counts: list[tuple[int, int]] = []

        def ring_moved() -> bool:
            # AT-SPI focus changes as soon as kdockw's GUI thread handles the
            # key; the ring reaches KWin's output only with kdockw's next
            # frame, so wait for a screenshot that shows the new focus.
            img = kdockw.screenshot("thumbnail-focus", area)
            ring, plain = blueish_pixels(img, ring_rect), blueish_pixels(img, plain_rect)
            counts.append((ring, plain))
            return ring > 40 and ring > 4 * plain

        try:
            wait_until(ring_moved, timeout=5, interval=0.2, message=lambda: f"focus ring on {second!r} (ring vs plain blue px per screenshot: {counts})")
        finally:
            env.artifact_path(f"{kdockw.name}/thumbnail-focus.txt").write_text("".join(f"{r} {p}\n" for r, p in counts))

    inp.key("Left")
    wait_until(lambda: [thumbnail_title(n) for n in focused_thumbnails(kdockw)] == [first], message="first thumbnail focused again")


# ---------------------------------------------------------------------- KBD-007
@pytest.mark.kdockwrc({**TOP, "PinnedLaunchers": []})
@pytest.mark.parametrize(
    "pointer",
    [
        pytest.param(PARK, id="pointer-parked"),
        pytest.param(CENTRE, id="pointer-at-centre"),
    ],
)
def test_kbd007_delete_closes_focused_thumbnail_window(kdockw: KDockW, apps: TestWindows, pointer: tuple[int, int]) -> None:
    other = apps.open("Neighbour", app_id=env.TEST_APP2_ID)
    del_a = apps.open("Delete A", app_id=env.TEST_APP_ID)
    del_b = apps.open("Delete B", app_id=env.TEST_APP_ID)
    inp.move(*pointer)
    app = env.TEST_APP_NAME
    kdockw.wait_for_item("Neighbour")
    kdockw.wait_for_item(app)

    enter_preview(kdockw, app)
    wait_until(lambda: len(kdockw.thumbnails()) == 2, message="two thumbnails")
    doomed = thumbnail_title(focused_thumbnails(kdockw)[0])
    survivor = {"Delete A": del_b, "Delete B": del_a}[doomed]
    doomed_win = {"Delete A": del_a, "Delete B": del_b}[doomed]

    inp.key("Delete")

    wait_until(lambda: doomed_win.refresh() is None, message=f"{doomed!r} to leave KWin's window list")
    assert all(w.title != doomed for w in kwin.windows())
    wait_until(
        lambda: [thumbnail_title(e.get_attribute("name")) for e in kdockw.thumbnails()] == [survivor.title],
        message="thumbnail of the closed window to be removed",
    )
    wait_until(lambda: [thumbnail_title(n) for n in focused_thumbnails(kdockw)] == [survivor.title], message="focus on the remaining thumbnail")

    # Last window: the popup closes and the keyboard returns to the dock buttons.
    inp.key("Delete")

    wait_until(lambda: survivor.refresh() is None, message=f"{survivor.title!r} to close")
    wait_until(lambda: kdockw.item(app) is None, message="app item to disappear")
    wait_until(lambda: not kdockw.preview_visible(), message="preview to close")
    assert not has_state(kdockw.preview_popup(), "showing")
    assert other.refresh() is not None
    inp.key("Left")
    wait_focused(kdockw, "Neighbour")


# ---------------------------------------------------------------------- KBD-008
def test_kbd008_mouse_movement_cancels_keyboard_mode(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["Mouse One", "Mouse Two"])
    inp.move(40, 40)
    invoke_shortcut("focus-dock")
    wait_focused(kdockw, "Mouse One")

    inp.move(400, 300, duration_ms=300)

    wait_until(lambda: focused_items(kdockw) == [], timeout=3, message="pointer motion to cancel keyboard mode")
    # Cancelled for good: arrow keys no longer navigate.
    inp.key("Right")
    assert_holds(lambda: focused_items(kdockw) == [], 1.0, "Right re-focused a button after the mouse moved")


def test_kbd008_mouse_movement_over_dock_cancels_keyboard_mode(kdockw: KDockW, apps: TestWindows) -> None:
    open_items(kdockw, apps, ["Mouse One", "Mouse Two"])
    park_pointer()
    invoke_shortcut("focus-dock")
    wait_focused(kdockw, "Mouse One")

    # Glide along the item row onto the dock, then away again.
    (x1, y), (x2, _) = kdockw.item_center("Mouse One"), kdockw.item_center("Mouse Two")
    inp.move(x1 - 80, y)
    inp.move_path(inp.line((x1 - 80, y), (x2, y), 8))
    inp.move(*PARK, duration_ms=200)

    wait_until(lambda: focused_items(kdockw) == [], message="pointer motion over the dock to cancel keyboard mode")
    inp.key("Right")
    assert_holds(lambda: focused_items(kdockw) == [], 1.0, "Right re-focused a button after the mouse moved")


# ---------------------------------------------------------------------- KBD-009
AUTOHIDE = {"VisibilityMode": config.AUTO_HIDE}
DODGE = {"VisibilityMode": config.DODGE_WINDOWS}
#: SmartHide = DodgeWindows restricted to the active window.
SMARTHIDE = {"VisibilityMode": config.DODGE_WINDOWS, "DodgeActiveOnly": True}


def _keyboard_mode_keeps_dock_shown(kdockw: KDockW, apps: TestWindows, visibility: dict) -> str:
    """Hidden dock + overlapping active window -> focus-dock shows it and it
    stays shown and focused past the hide delay. Returns the focused item."""
    kdockw.stop()
    kdockw.write_config({"PinnedLaunchers": [], **visibility})
    apps.open("Side", app_id=env.TEST_APP2_ID)
    # Full-screen window overlapping the dock area, opened last so it is the
    # active window (the Dodge/SmartHide trigger).
    cover = apps.open("Cover", app_id=env.TEST_APP_ID, width=env.SCREEN_WIDTH, height=env.SCREEN_HEIGHT)
    wait_until(cover.is_active, message="covering window to be active")
    park_pointer()
    kdockw.start()
    kdockw.wait_for_item("Cover")
    kdockw.wait_for_item("Side")
    first = kdockw.item_names()[0]
    wait_until(lambda: not item_is_shown(kdockw, first), message="dock to start hidden")

    invoke_shortcut("focus-dock")

    wait_until(lambda: item_is_shown(kdockw, first), message="keyboard mode to slide the dock in")
    wait_focused(kdockw, first)
    kdockw.wait_keyboard_focus()
    if kwin.can_capture():
        wait_stable(lambda: Rect.of(kdockw.item(first)))  # slide-in finished
        img = kdockw.screenshot("keyboard-shown", kdockw.surface_rect("dock"))
        r = kdockw.screen_rect(kdockw.item(first))
        assert 0 <= r.y and r.y + r.height <= env.SCREEN_HEIGHT, f"item off screen: {r}"
        colors = img.crop((r.x, r.y, r.x + r.width, r.y + r.height)).getcolors(maxcolors=1 << 16)
        assert colors is None or len(colors) > 16, "dock item region looks blank"
    # Longer than HideDelay (400 ms) plus the slide-out: the dock stays.
    assert_holds(
        lambda: item_is_shown(kdockw, first) and focused_items(kdockw) == [first],
        3.5,
        "dock hid (or lost focus) while in keyboard mode",
    )
    return first


def _escape_resumes_auto_hide(kdockw: KDockW, first: str) -> None:
    inp.key("Escape")
    inp.move(CENTRE[0] + 50, CENTRE[1] + 50, duration_ms=200)

    wait_until(lambda: not item_is_shown(kdockw, first), message="dock to auto-hide again after Escape")


@pytest.mark.parametrize(
    "visibility",
    [pytest.param(AUTOHIDE, id="autohide"), pytest.param(DODGE, id="dodge"), pytest.param(SMARTHIDE, id="smarthide")],
)
def test_kbd009_keyboard_mode_keeps_hidden_dock_visible(kdockw: KDockW, apps: TestWindows, visibility: dict) -> None:
    _keyboard_mode_keeps_dock_shown(kdockw, apps, visibility)


@pytest.mark.parametrize(
    "visibility",
    [pytest.param(AUTOHIDE, id="autohide"), pytest.param(DODGE, id="dodge"), pytest.param(SMARTHIDE, id="smarthide")],
)
def test_kbd009_dock_auto_hides_again_after_escape(kdockw: KDockW, apps: TestWindows, visibility: dict) -> None:
    first = _keyboard_mode_keeps_dock_shown(kdockw, apps, visibility)
    _escape_resumes_auto_hide(kdockw, first)
