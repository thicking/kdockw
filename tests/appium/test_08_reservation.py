# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""VIS-009: actual KWin work areas and already-maximized consumer frames.

No screenshot/DRM prerequisite. Observations pair KWin's MaximizeArea and
FullScreenArea with real fixture frameGeometry and unzoomed AT-SPI dock item
bounds, rather than echoing a KDockW exclusive-zone property or pixel constant.
"""

from __future__ import annotations

import json

import pytest

from kdockw_e2e import config, env, kwin
from kdockw_e2e import input as inp
from kdockw_e2e import preview as pv
from kdockw_e2e.kdockw import KDockW, Rect, has_state
from kdockw_e2e.waits import WaitTimeout, wait_stable, wait_until
from kdockw_e2e.windows import TestWindow, TestWindows
from test_06_settings import (
    ICON_SIZE_SLIDER,
    RESERVE_SWITCH,
    SETTINGS,
    click_el,
    close_settings,
    config_value,
    focus_slider,
    open_page,
    open_settings,
    pick,
    reveal_dock,
    scroll_into_view,
    slider_value,
)
from test_07_visibility import maximize

EDGES = (
    ("top", config.EDGE_TOP),
    ("bottom", config.EDGE_BOTTOM),
    ("left", config.EDGE_LEFT),
    ("right", config.EDGE_RIGHT),
)


def _edge_cases(reserved: bool):
    return [
        pytest.param(
            edge,
            marks=pytest.mark.kdockwrc(
                {
                    "PinnedLaunchers": [],
                    "VisibilityMode": config.ALWAYS_VISIBLE,
                    "ReserveScreenSpace": reserved,
                    "Edge": edge,
                    "Floating": False,
                }
            ),
            id=name,
        )
        for name, edge in EDGES
    ]


def _park() -> None:
    inp.move(env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2)


def _observe(kdockw: KDockW, win: TestWindow, with_icon: bool) -> dict:
    observation = kwin.evaluate(
        f"const w = workspace.windowList().find(w => w.pid === {win.pid} && w.normalWindow && !w.skipTaskbar);"
        "if (!w) throw new Error('reservation fixture window not found');"
        "function rect(r) { return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]; }"
        "report({window: String(w.internalId), frame: rect(w.frameGeometry),"
        " workarea: rect(workspace.clientArea(KWin.MaximizeArea, w)),"
        " screen: rect(workspace.clientArea(KWin.FullScreenArea, w)),"
        " output: w.output.name});"
    )
    if with_icon:
        icon = wait_stable(lambda: kdockw.screen_rect(kdockw.wait_for_item(win.title)), duration=0.3)
        observation["icon"] = list(icon)
        observation["icon_center"] = list(icon.center)
        observation["surface"] = list(kdockw.surface_rect("dock"))
    return observation


def _matches(observation: dict, edge: int, reserved: bool) -> bool:
    frame = Rect(*observation["frame"])
    work = Rect(*observation["workarea"])
    screen = Rect(*observation["screen"])
    if frame != work:
        return False
    if not reserved:
        return work == screen
    # Exactly one screen edge is removed from the consumer work area. Its
    # amount is measured by KWin, never computed from KDockW's source defaults.
    if edge == config.EDGE_TOP:
        return work.x == screen.x and work.width == screen.width and work.y > screen.y and work.y + work.height == screen.y + screen.height
    if edge == config.EDGE_BOTTOM:
        return work.x == screen.x and work.width == screen.width and work.y == screen.y and work.y + work.height < screen.y + screen.height
    if edge == config.EDGE_LEFT:
        return work.y == screen.y and work.height == screen.height and work.x > screen.x and work.x + work.width == screen.x + screen.width
    return work.y == screen.y and work.height == screen.height and work.x == screen.x and work.x + work.width < screen.x + screen.width


def _record(kdockw: KDockW, stage: str, observation: dict) -> None:
    with env.artifact_path(f"{kdockw.name}/reservation-geometry.jsonl").open("a", encoding="utf-8") as artifact:
        artifact.write(json.dumps({"stage": stage, **observation}) + "\n")


def _geometry(kdockw: KDockW, win: TestWindow, edge: int, reserved: bool, stage: str) -> dict:
    last = {}

    def ready():
        nonlocal last
        last = _observe(kdockw, win, with_icon=False)
        return last if _matches(last, edge, reserved) else None

    try:
        wait_until(ready, timeout=8, message=lambda: f"{stage}: consumer frame/workarea reservation={reserved}, last={last}")
        observation = wait_stable(lambda: _observe(kdockw, win, with_icon=False), duration=0.3)
    except WaitTimeout:
        _record(kdockw, stage + "-failed", last)
        raise
    assert _matches(observation, edge, reserved), f"{stage}: geometry changed before settling: {observation}"
    # Only ON needs an item comparison. In particular the OFF baseline fails
    # on actual consumer geometry, not because old code lacks the new UI row.
    if reserved:
        observation = _observe(kdockw, win, with_icon=True)
        _record(kdockw, stage, observation)
        assert _matches(observation, edge, True), observation
        frame, icon = Rect(*observation["frame"]), Rect(*observation["icon"])
        if edge == config.EDGE_TOP:
            assert frame.y >= icon.y + icon.height, observation
        elif edge == config.EDGE_BOTTOM:
            assert frame.y + frame.height <= icon.y, observation
        elif edge == config.EDGE_LEFT:
            assert frame.x >= icon.x + icon.width, observation
        else:
            assert frame.x + frame.width <= icon.x, observation
    else:
        _record(kdockw, stage, observation)
    return observation


def _behavior(kdockw: KDockW, name: str = "Alpha", edge: int = config.EDGE_BOTTOM) -> None:
    if edge != config.EDGE_BOTTOM:
        from kdockw_e2e.kdockw import context_menu_entries

        # Leave any existing preview before revealing off-centre. The shared
        # settings helper's bottom-specific park lies inside a top dock.
        _park()
        wait_until(lambda: not kdockw.preview_visible(), timeout=8, message="preview closed before approaching the edge dock")
        trigger = {
            config.EDGE_TOP: (60, 0),
            config.EDGE_LEFT: (0, 60),
            config.EDGE_RIGHT: (env.SCREEN_WIDTH - 1, 60),
        }[edge]
        inp.move(*trigger)
        _wait_shown_at_edge(kdockw, name)
        surface, rest = wait_stable(
            lambda: (kdockw.surface_rect("dock"), kdockw.screen_rect(kdockw.wait_for_item(name)))
        )
        assert surface is not None and surface.contains(*rest.center)
        wait_until(lambda: not kdockw.preview_visible(), timeout=8, message="preview closed at the off-centre reveal point")
        near = (rest.center[0], trigger[1]) if edge == config.EDGE_TOP else (trigger[0], rest.center[1])
        inp.move_path([trigger, near, *inp.line(near, rest.center, 5)], 40)

        # Hovering a running task may legitimately show its preview. Prove the
        # Settings frontdoor through the native menu at the existing pointer.
        wait_until(
            lambda: has_state(kdockw.wait_for_item(name), "showing"),
            timeout=5,
            message=f"{name!r} showing before the native context menu",
        )
        assert kdockw.item_names() == [name], "the native Settings frontdoor must target the sole fixture task"
        before = {w.internal_id for w in kdockw.windows()}
        pointer = kwin.cursor_pos()
        inp.click(*pointer, button="right")
        menu = wait_until(
            lambda: next((w for w in kdockw.windows() if w.internal_id not in before and not w.normal_window), None),
            timeout=5,
            message=f"real context menu of {name!r} on selected edge",
        )
        _record(kdockw, "edge-settings-frontdoor", {
            "edge": edge, "surface": list(surface), "rest_icon": list(rest),
            "pointer": list(pointer), "menu": list(menu.client_geometry),
        })
        kdockw.choose_context_menu_entry("Settings...", context_menu_entries(pinned=False, is_window=True))
        wait_until(
            lambda: next((w for w in kdockw.windows() if w.normal_window and not w.skip_taskbar and w.title.startswith("Settings")), None),
            timeout=15,
            message="Settings window opened through the real edge dock context menu",
        )
        _park()
        wait_until(lambda: not kdockw.preview_visible(), timeout=8, message="preview closed before driving Settings")
    else:
        if not has_state(kdockw.wait_for_item(name), "showing"):
            reveal_dock(kdockw, name)
        open_settings(kdockw, name)
    open_page(kdockw, "Behavior")


def _wait_shown_at_edge(kdockw: KDockW, name: str) -> None:
    def shown():
        item = kdockw.wait_for_item(name)
        if not has_state(item, "showing"):
            return None
        icon = kdockw.screen_rect(item)
        surface = kdockw.surface_rect("dock")
        if surface is None:
            return None
        inside = (
            surface.x <= icon.x and icon.x + icon.width <= surface.x + surface.width
            and surface.y <= icon.y and icon.y + icon.height <= surface.y + surface.height
        )
        return (icon, surface) if inside else None

    wait_until(shown, timeout=8, message="shown dock item inside its actual KWin surface")


def _wait_hidden_at_edge(kdockw: KDockW, name: str, edge: int, why: str) -> None:
    def hidden():
        item = kdockw.wait_for_item(name)
        if has_state(item, "showing"):
            return None
        icon = kdockw.screen_rect(item)
        surface = kdockw.surface_rect("dock")
        if surface is None:
            return None
        outside = {
            config.EDGE_TOP: icon.y + icon.height <= surface.y,
            config.EDGE_BOTTOM: icon.y >= surface.y + surface.height,
            config.EDGE_LEFT: icon.x + icon.width <= surface.x,
            config.EDGE_RIGHT: icon.x >= surface.x + surface.width,
        }[edge]
        return (icon, surface) if outside else None

    icon, surface = wait_until(hidden, timeout=8, message=f"dock hidden beyond selected edge {why}")
    _record(kdockw, f"hidden-{why}", {"edge": edge, "icon": list(icon), "surface": list(surface)})


def _reserve(kdockw: KDockW, reserved: bool) -> None:
    switch = scroll_into_view(kdockw, RESERVE_SWITCH)
    if has_state(switch, "checked") != reserved:
        click_el(kdockw, switch)
    wait_until(lambda: has_state(kdockw.wait_for(RESERVE_SWITCH), "checked") == reserved, message=f"reservation switch={reserved}")
    wait_until(
        lambda: config.as_bool(config_value(kdockw, "ReserveScreenSpace") or "true") == reserved,
        message=f"reservation autosaved={reserved}",
    )
    _park()


@pytest.mark.parametrize("edge", _edge_cases(False))
def test_vis009_reservation_off_maximized_window_uses_full_output(kdockw: KDockW, apps: TestWindows, edge: int) -> None:
    """Negative control: pre-feature AlwaysVisible reserves despite OFF."""
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)
    _geometry(kdockw, win, edge, False, "startup-off")


@pytest.mark.parametrize("edge", _edge_cases(True))
def test_vis009_already_maximized_window_reflows_on_live_reservation_toggle(
    kdockw: KDockW, apps: TestWindows, edge: int
) -> None:
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)  # The only maximize request in the entire test.
    initial = _geometry(kdockw, win, edge, True, "startup-on")
    pid = kdockw.pid
    _behavior(kdockw, edge=edge)
    _reserve(kdockw, False)
    off = _geometry(kdockw, win, edge, False, "live-off-settings-open")
    assert off["window"] == initial["window"] and off["frame"] != initial["frame"]
    _reserve(kdockw, True)
    on = _geometry(kdockw, win, edge, True, "live-on-settings-open")
    assert on["window"] == initial["window"] and on["workarea"] == initial["workarea"]
    assert kdockw.pid == pid, "live reservation must not restart the dock"
    close_settings(kdockw)
    _park()
    _geometry(kdockw, win, edge, True, "live-on-settings-closed")


@pytest.mark.kdockwrc({"PinnedLaunchers": [], "VisibilityMode": config.ALWAYS_VISIBLE, "ReserveScreenSpace": True, "Floating": False})
def test_vis009_reservation_off_and_on_persist_and_reflow_existing_window_after_restart(
    kdockw: KDockW, apps: TestWindows
) -> None:
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)  # Remains maximized across both dock restarts.
    initial = _geometry(kdockw, win, config.EDGE_BOTTOM, True, "before-restarts")
    for reserved in (False, True):
        _behavior(kdockw)
        _reserve(kdockw, reserved)
        close_settings(kdockw)
        _park()
        _geometry(kdockw, win, config.EDGE_BOTTOM, reserved, f"saved-{reserved}")
        pid = kdockw.pid
        kdockw.restart()
        assert kdockw.pid != pid
        kdockw.wait_for_item("Alpha")
        _park()
        restored = _geometry(kdockw, win, config.EDGE_BOTTOM, reserved, f"restarted-{reserved}")
        assert restored["window"] == initial["window"], "consumer window must survive dock restart unchanged"
        _behavior(kdockw)
        assert has_state(scroll_into_view(kdockw, RESERVE_SWITCH), "checked") == reserved
        assert config.as_bool(config_value(kdockw, "ReserveScreenSpace") or "true") == reserved
        close_settings(kdockw)
        _park()


@pytest.mark.parametrize("edge", _edge_cases(True))
def test_vis009_live_icon_size_and_floating_update_maximized_consumer(kdockw: KDockW, apps: TestWindows, edge: int) -> None:
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)
    initial = _geometry(kdockw, win, edge, True, "initial-size-flat")
    pid = kdockw.pid
    _behavior(kdockw, edge=edge)
    open_page(kdockw, "Icons")
    slider = focus_slider(kdockw, ICON_SIZE_SLIDER, 24, 96)
    before_size = slider_value(slider)
    inp.key("right")
    wait_until(lambda: slider_value(slider) > before_size, message="icon size increased through native control")
    _park()
    resized = _geometry(kdockw, win, edge, True, "larger-icons")
    assert resized["workarea"][2] * resized["workarea"][3] < initial["workarea"][2] * initial["workarea"][3], (initial, resized)
    assert resized["icon"][2] > initial["icon"][2], (initial, resized)
    open_page(kdockw, "Layout & Position")
    floating_xpath = f"{SETTINGS}//check_box[@name='Floating']"
    for floating in (True, False):
        switch = scroll_into_view(kdockw, floating_xpath)
        if has_state(switch, "checked") != floating:
            click_el(kdockw, switch)
        wait_until(lambda: has_state(kdockw.wait_for(floating_xpath), "checked") == floating, message=f"floating={floating}")
        _park()
        changed = _geometry(kdockw, win, edge, True, f"floating-{floating}")
        if floating:
            assert changed["workarea"][2] * changed["workarea"][3] < resized["workarea"][2] * resized["workarea"][3], (resized, changed)
        else:
            assert changed["workarea"] == resized["workarea"], (resized, changed)
        assert changed["window"] == initial["window"]
    open_page(kdockw, "Behavior")
    _reserve(kdockw, False)
    _geometry(kdockw, win, edge, False, "resized-off")
    assert kdockw.pid == pid, "size, floating and reservation changes must all apply live"


FLOATING_SWITCH = f"{SETTINGS}//check_box[@name='Floating']"
FLOATING_MARGIN_SLIDER = f"{SETTINGS}//slider[@name='Floating margin']"


def _floating_margin_cases():
    # No FloatingMargin key: the slider must start from the 3 px default.
    return [
        pytest.param(
            edge,
            marks=pytest.mark.kdockwrc(
                {
                    "PinnedLaunchers": [],
                    "VisibilityMode": config.ALWAYS_VISIBLE,
                    "ReserveScreenSpace": True,
                    "Edge": edge,
                    "Floating": True,
                }
            ),
            id=name,
        )
        for name, edge in EDGES
    ]


def _reserved_depth(observation: dict, edge: int) -> int:
    """Thickness KWin removed from the consumer work area at the dock edge."""
    work, screen = Rect(*observation["workarea"]), Rect(*observation["screen"])
    if edge in (config.EDGE_TOP, config.EDGE_BOTTOM):
        return screen.height - work.height
    return screen.width - work.width


def _set_floating(kdockw: KDockW, floating: bool) -> None:
    switch = scroll_into_view(kdockw, FLOATING_SWITCH)
    if has_state(switch, "checked") != floating:
        click_el(kdockw, switch)
    wait_until(lambda: has_state(kdockw.wait_for(FLOATING_SWITCH), "checked") == floating, message=f"floating={floating}")
    _park()


@pytest.mark.parametrize("edge", _floating_margin_cases())
def test_vis009_live_floating_margin_update_maximized_consumer(kdockw: KDockW, apps: TestWindows, edge: int) -> None:
    """The Floating margin slider moves an already-maximized consumer by
    exactly the margin delta, live, only while Floating is on, and persists."""
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)
    default = _geometry(kdockw, win, edge, True, "margin-default")
    pid = kdockw.pid
    _behavior(kdockw, edge=edge)
    open_page(kdockw, "Layout & Position")
    slider = focus_slider(kdockw, FLOATING_MARGIN_SLIDER, 1, 32)
    assert slider_value(slider) == 3, "a fresh configuration uses the 3 px default margin"
    assert has_state(slider, "enabled"), "the margin is adjustable while the dock floats"
    inp.key("pageup")  # ten 1 px steps, as a user would press it
    wait_until(lambda: slider_value(kdockw.wait_for(FLOATING_MARGIN_SLIDER)) == 13, message="floating margin raised to 13 px")
    wait_until(lambda: config_value(kdockw, "FloatingMargin") == "13", message="floating margin autosaved")
    _park()
    wider = _geometry(kdockw, win, edge, True, "margin-13")
    assert _reserved_depth(wider, edge) - _reserved_depth(default, edge) == 10, (default, wider)
    assert wider["window"] == default["window"]

    # Floating off removes the gap entirely, whatever the saved margin.
    _set_floating(kdockw, False)
    wait_until(
        lambda: not has_state(kdockw.wait_for(FLOATING_MARGIN_SLIDER), "enabled"),
        message="floating margin disabled while the dock is not floating",
    )
    flat = _geometry(kdockw, win, edge, True, "margin-13-floating-off")
    assert _reserved_depth(default, edge) - _reserved_depth(flat, edge) == 3, (default, flat)
    assert config_value(kdockw, "FloatingMargin") == "13", "turning Floating off keeps the saved margin"

    _set_floating(kdockw, True)
    restored = _geometry(kdockw, win, edge, True, "margin-13-floating-on")
    assert _reserved_depth(restored, edge) == _reserved_depth(wider, edge), (wider, restored)
    assert restored["window"] == default["window"]
    assert kdockw.pid == pid, "floating margin changes must apply live"

    close_settings(kdockw)
    _park()
    kdockw.restart()
    assert kdockw.pid != pid
    kdockw.wait_for_item("Alpha")
    _park()
    restarted = _geometry(kdockw, win, edge, True, "margin-13-restarted")
    assert _reserved_depth(restarted, edge) == _reserved_depth(wider, edge), (wider, restarted)
    assert restarted["window"] == default["window"], "consumer window must survive dock restart unchanged"


@pytest.mark.parametrize(
    "edge,reserved",
    [
        pytest.param(
            edge,
            reserved,
            marks=pytest.mark.kdockwrc(
                {
                    "PinnedLaunchers": [],
                    "VisibilityMode": config.ALWAYS_VISIBLE,
                    "ReserveScreenSpace": reserved,
                    "Edge": edge,
                }
            ),
            id=f"{name}-{str(reserved).lower()}",
        )
        for name, edge in EDGES
        for reserved in (False, True)
    ],
)
def test_vis009_visibility_policy_ignores_and_retains_reservation_preference(
    kdockw: KDockW, apps: TestWindows, edge: int, reserved: bool
) -> None:
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)
    _geometry(kdockw, win, edge, reserved, "always-before-modes")
    pid = kdockw.pid
    for label, mode in (("Auto hide", config.AUTO_HIDE), ("Dodge windows", config.DODGE_WINDOWS)):
        _behavior(kdockw, edge=edge)
        pick(kdockw, "Visibility mode", label)
        wait_until(lambda: config_value(kdockw, "VisibilityMode") == str(mode), message=f"visibility policy {label} saved")
        _geometry(kdockw, win, edge, False, f"{label}-settings-open")
        close_settings(kdockw)
        kwin.activate(win.internal_id)
        _park()
        _wait_hidden_at_edge(kdockw, "Alpha", edge, why=f"{label}-maximized-consumer")
        _geometry(kdockw, win, edge, False, f"{label}-hidden")
        assert config.as_bool(config_value(kdockw, "ReserveScreenSpace") or "true") == reserved
    _behavior(kdockw, edge=edge)
    pick(kdockw, "Visibility mode", "Always visible")
    assert has_state(scroll_into_view(kdockw, RESERVE_SWITCH), "checked") == reserved
    close_settings(kdockw)
    _park()
    _wait_shown_at_edge(kdockw, "Alpha")
    _geometry(kdockw, win, edge, reserved, "always-restored")
    assert kdockw.pid == pid


@pytest.mark.parametrize(
    "edge,reserved",
    [
        pytest.param(
            edge,
            reserved,
            marks=pytest.mark.kdockwrc(
                {
                    "PinnedLaunchers": [],
                    "VisibilityMode": config.ALWAYS_VISIBLE,
                    "ReserveScreenSpace": reserved,
                    "Edge": edge,
                    "Floating": True,
                    "PreviewEnabled": True,
                }
            ),
            id=f"{name}-{'on' if reserved else 'off'}",
        )
        for name, edge in EDGES
        for reserved in (False, True)
    ],
)
def test_prev_reservation_hover_popup_stays_inward_of_resting_dock_item(
    kdockw: KDockW, apps: TestWindows, edge: int, reserved: bool
) -> None:
    """A real hover popup never uses a reserved origin when reservation is OFF."""
    win = apps.open("Alpha", width=400, height=300)
    kdockw.wait_for_item("Alpha")
    _park()
    rest = _observe(kdockw, win, with_icon=True)
    icon = Rect(*rest["icon"])
    popup = pv.open_by_hover(kdockw, "Alpha")
    wait_until(
        lambda: pv.thumb_titles(kdockw) == ["Alpha"],
        message="real fixture window represented by its preview thumbnail",
    )

    def visible_geometry():
        current = kdockw.preview_popup()
        if current is None or not has_state(current, "showing") or not has_state(current, "visible"):
            return None
        return pv._popup_geometry(kdockw, current)

    wait_until(visible_geometry, timeout=8, message="visible hover popup within its real KWin preview surface")
    geometry = wait_stable(visible_geometry, duration=pv.GEOMETRY_SETTLE)
    assert geometry is not None, "hover preview disappeared instead of presenting valid geometry"
    surface, popup_rect = geometry
    assert has_state(popup, "showing") and has_state(popup, "visible")
    observation = {
        **rest,
        "reserved": reserved,
        "edge": edge,
        "preview_surface": list(surface),
        "popup": list(popup_rect),
        "thumbnail_titles": pv.thumb_titles(kdockw),
        "pixel_oracle": "not exercised; popup geometry does not require DRM or screencast pixels",
    }
    _record(kdockw, "hover-preview", observation)
    screen = Rect(*rest["screen"])
    assert screen.x <= popup_rect.x and popup_rect.x + popup_rect.width <= screen.x + screen.width, observation
    assert screen.y <= popup_rect.y and popup_rect.y + popup_rect.height <= screen.y + screen.height, observation
    # The visible popup must sit on the content side of the unzoomed icon
    # measured before hover. The full-screen LayerShell surface intentionally
    # includes transparent anchor/headroom around that popup; its containment
    # of the popup is checked by _popup_geometry, but its outer bounds are not
    # a visible overlap contract.
    if edge == config.EDGE_TOP:
        assert popup_rect.y >= icon.y + icon.height, observation
        assert popup_rect.x <= icon.center[0] <= popup_rect.x + popup_rect.width, observation
    elif edge == config.EDGE_BOTTOM:
        assert popup_rect.y + popup_rect.height <= icon.y, observation
        assert popup_rect.x <= icon.center[0] <= popup_rect.x + popup_rect.width, observation
    elif edge == config.EDGE_LEFT:
        assert popup_rect.x >= icon.x + icon.width, observation
        assert popup_rect.y <= icon.center[1] <= popup_rect.y + popup_rect.height, observation
    else:
        assert popup_rect.x + popup_rect.width <= icon.x, observation
        assert popup_rect.y <= icon.center[1] <= popup_rect.y + popup_rect.height, observation


@pytest.mark.no_kdockw_autostart
@pytest.mark.kdockwrc({"PinnedLaunchers": [], "VisibilityMode": config.ALWAYS_VISIBLE, "Edge": config.EDGE_BOTTOM})
def test_vis009_fresh_config_default_reserves_screen_space_for_maximized_consumer(
    kdockw: KDockW, apps: TestWindows
) -> None:
    """An absent reservation key must produce the actual reserving behavior."""
    # The normal fixture creates a private fresh XDG home. Delayed autostart
    # lets this consumer case prove the key was absent before KDockW read it.
    assert config_value(kdockw, "ReserveScreenSpace") is None
    env.artifact_path(f"{kdockw.name}/fresh-default-before-start.kdockwrc").write_text(
        kdockw.config_path.read_text(), encoding="utf-8"
    )
    win = apps.open("Alpha", width=400, height=300)
    kdockw.start()
    kdockw.wait_for_item("Alpha")
    _park()
    maximize(win)
    _geometry(kdockw, win, config.EDGE_BOTTOM, True, "fresh-default-maximized")

    _behavior(kdockw)
    switch = scroll_into_view(kdockw, RESERVE_SWITCH)
    assert has_state(switch, "showing") and has_state(switch, "checked"), (
        "fresh AlwaysVisible configuration must expose an enabled reservation preference"
    )
    # Capture native semantic-help exposure for manual inspection, rather
    # than asserting incidental wording or claiming that text was painted.
    from xml.etree import ElementTree

    settings_xml = kdockw.page_source()
    control_name = switch.get_attribute("name")
    native_control = next(
        (
            node.attrib
            for node in ElementTree.fromstring(settings_xml).iter("check_box")
            if node.attrib.get("name") == control_name
        ),
        None,
    )
    env.artifact_path(f"{kdockw.name}/fresh-default-settings-atspi.xml").write_text(
        settings_xml, encoding="utf-8"
    )
    env.artifact_path(f"{kdockw.name}/fresh-default-reservation-control.json").write_text(
        json.dumps(
            {
                "name": control_name,
                "description": native_control.get("description") if native_control is not None else None,
                "states": native_control.get("states") if native_control is not None else None,
                "native_control": native_control,
                "description_transport": "native AT-SPI page_source XML; WebDriver description getter unsupported",
                "collector_match_found": native_control is not None,
                "stored_reservation_key": config_value(kdockw, "ReserveScreenSpace"),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    for mode in ("Auto hide", "Dodge windows"):
        pick(kdockw, "Visibility mode", mode)
        assert not any(has_state(row, "showing") for row in kdockw.find_all(RESERVE_SWITCH)), (
            f"reservation preference must not be available in {mode}"
        )
    pick(kdockw, "Visibility mode", "Always visible")
    restored = scroll_into_view(kdockw, RESERVE_SWITCH)
    assert has_state(restored, "showing") and has_state(restored, "checked")
    _park()
    _geometry(kdockw, win, config.EDGE_BOTTOM, True, "fresh-default-restored")
