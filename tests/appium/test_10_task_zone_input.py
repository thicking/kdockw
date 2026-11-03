# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""KBD-010, PREV-010 and MOUSE-018: real task-zone input consumers."""

from __future__ import annotations

import json
from dataclasses import asdict

import pyatspi
import pytest

from kdockw_e2e import config, env, kwin
from kdockw_e2e import input as inp
from kdockw_e2e import preview as pv
from kdockw_e2e.kdockw import EXTENTS_IGNORE_SCALE, KDockW, Rect, context_menu_entries, has_state
from kdockw_e2e.shortcuts import invoke_shortcut
from kdockw_e2e.waits import wait_stable, wait_until
from kdockw_e2e.windows import TestWindow, TestWindows
from test_09_task_zones import ALL_NAMES, KFIND_ID, KWRITE_ID, PINNED_A, PINNED_B, PINNED_IDS, SEPARATOR, UNPINNED_A, UNPINNED_B

pytestmark = pytest.mark.no_kdockw_autostart

EDGES = [
    pytest.param(config.EDGE_BOTTOM, id="bottom"),
    pytest.param(config.EDGE_TOP, id="top"),
    pytest.param(config.EDGE_LEFT, id="left"),
    pytest.param(config.EDGE_RIGHT, id="right"),
]
ORIENTATIONS = [pytest.param(config.EDGE_BOTTOM, id="horizontal"), pytest.param(config.EDGE_LEFT, id="vertical")]
SEPARATION = [pytest.param(True, id="on"), pytest.param(False, id="off")]
APP_IDS = (*PINNED_IDS, KWRITE_ID, KFIND_ID)
EXTRA_APP_ID = "org.kde.kdockw.taskzoneextra"
EXTRA_COLD_NAME = "KDockW Extra Test Window"
EXTRA_NAME = "Newly launched"
ICON_SIZE = 48
GROUP_TITLES = ("Group 1", "Group 2", "Group 3")
F12 = 0x0100003B


def _record(kdockw: KDockW, stage: str, **values) -> None:
    with env.artifact_path(f"{kdockw.name}/consumer-proof.jsonl").open("a") as stream:
        stream.write(json.dumps({"stage": stage, **values}, sort_keys=True) + "\n")


def _vertical(edge: int) -> bool:
    return edge in (config.EDGE_LEFT, config.EDGE_RIGHT)


def _extent(rect: Rect, edge: int) -> int:
    return rect.height if _vertical(edge) else rect.width


def _primary_center(rect: Rect, edge: int) -> int:
    return rect.center[1] if _vertical(edge) else rect.center[0]


def _rects(kdockw: KDockW, names: tuple[str, ...]) -> dict[str, Rect]:
    return {name: kdockw.screen_rect(kdockw.wait_for_item(name)) for name in names}


def _json_rects(rects: dict[str, Rect]) -> dict[str, dict]:
    return {name: rect._asdict() for name, rect in rects.items()}


def _start(kdockw: KDockW, edge: int, *, separate: bool = True, zoom: float = 1.0, previews: bool = False, pinned: tuple[str, ...] = PINNED_IDS) -> None:
    settings = {
        "PinnedLaunchers": [config.launcher(app_id) for app_id in pinned],
        "SeparateLaunchers": separate,
        "Edge": edge,
        "VisibilityMode": config.ALWAYS_VISIBLE,
        "IconSize": ICON_SIZE,
        "MaxZoomFactor": zoom,
        "ZoomStyle": 0,
        "PreviewEnabled": previews,
        "PreviewHoverDelay": 500,
    }
    if previews:
        # Keep the popup open while its 500 ms hover retarget is pending.
        settings["PreviewHideDelay"] = 1500
    kdockw.write_config(settings)
    kdockw.start()
    _record(kdockw, "configuration", requested=settings, actual=kdockw.read_config()["General"])


def _expect_order(kdockw: KDockW, names: tuple[str, ...]) -> None:
    wait_until(lambda: kdockw.item_names() == list(names), message=f"native dock task order {names}")


def _park(kdockw: KDockW) -> tuple[int, int]:
    dock = kdockw.surface_rect("dock")
    preview = kdockw.surface_rect("preview")
    popup = pv.screen_rect(kdockw, kdockw.preview_popup()) if kdockw.preview_visible() else None
    assert dock is not None
    occupied = [rect for rect in (dock, preview, popup) if rect is not None]
    candidates = [
        (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2),
        (env.SCREEN_WIDTH - 20, env.SCREEN_HEIGHT // 2),
        (20, env.SCREEN_HEIGHT // 2),
        (env.SCREEN_WIDTH // 2, 20),
        (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT - 20),
        (20, 20),
        (env.SCREEN_WIDTH - 20, 20),
        (20, env.SCREEN_HEIGHT - 20),
        (env.SCREEN_WIDTH - 20, env.SCREEN_HEIGHT - 20),
    ]
    # KWin can report the preview surface's previous width briefly while a
    # grouped popup is being hidden or resized. Avoid parking just beyond that
    # stale edge: the popup may already have grown into that point, in which
    # case the move re-enters it and its hover hold keeps it open. Keep a
    # generous logical-pixel margin around both surfaces and the current popup.
    margin = 64
    point = next(
        (
            p
            for p in candidates
            if not any(
                rect.x - margin <= p[0] < rect.x + rect.width + margin
                and rect.y - margin <= p[1] < rect.y + rect.height + margin
                for rect in occupied
            )
        ),
        None,
    )
    assert point is not None, (
        f"no neutral pointer position outside surfaces (with {margin}px margin): {occupied}"
    )
    inp.move(*point)
    wait_until(lambda: kwin.cursor_pos() == point, message="native pointer parked outside dock/preview")
    wait_until(lambda: not kdockw.preview_visible(), message="preview hidden before measuring rest")
    _record(
        kdockw,
        "pointer-park",
        native_cursor=kwin.cursor_pos(),
        occupied=[rect._asdict() for rect in occupied],
        safety_margin=margin,
    )
    return point


def _rest(kdockw: KDockW, names: tuple[str, ...], edge: int) -> dict[str, Rect]:
    _park(kdockw)
    wait_until(lambda: all(_extent(rect, edge) == ICON_SIZE for rect in _rects(kdockw, names).values()), message="all task primary extents at rest")
    return wait_stable(lambda: _rects(kdockw, names))


def _divider(kdockw: KDockW, present: bool) -> None:
    if not present:
        wait_until(lambda: kdockw.find(SEPARATOR) is None, message="accessible divider removed after repartition")
        return
    separator = kdockw.wait_for(SEPARATOR)
    states = {state: has_state(separator, state) for state in ("focusable", "focused", "selectable", "selected")}
    assert not any(states.values()), states


def _matrix(apps: TestWindows, kdockw: KDockW, order: tuple[str, ...] = ALL_NAMES) -> dict[str, TestWindow]:
    windows = {name: apps.open(name, app_id=app_id, accessible=True) for name, app_id in zip(ALL_NAMES, APP_IDS, strict=True)}
    _expect_order(kdockw, order)
    return windows


def _active(kdockw: KDockW, window: TestWindow, stage: str) -> None:
    current = wait_until(
        lambda: (w if (w := kwin.active_window()) is not None and w.pid == window.pid and w.internal_id == window.internal_id else None),
        message=f"exact native active window {window.title}, PID {window.pid}",
    )
    assert current.title == window.title
    _record(kdockw, stage, expected_pid=window.pid, expected_internal_id=window.internal_id, active=asdict(current))


def _focused_names(kdockw: KDockW, names: tuple[str, ...]) -> list[str]:
    focused = []
    for name in names:
        node = kdockw.item_accessible(name)
        if node is not None:
            node.clear_cache()
            if node.getState().contains(pyatspi.STATE_FOCUSED):
                focused.append(node.name)
    return focused


def _focus(kdockw: KDockW, names: tuple[str, ...], expected: str, stage: str) -> None:
    wait_until(lambda: _focused_names(kdockw, names) == [expected], message=f"only native task {expected!r} focused")
    _divider(kdockw, True)
    _record(kdockw, stage, expected=expected, native_focused=_focused_names(kdockw, names), accessible_process_pid=kdockw.pid)


def _client_states(window: TestWindow) -> dict | None:
    app = next((a for a in pyatspi.Registry.getDesktop(0) if a is not None and a.get_process_id() == window.pid), None)
    if app is None:
        return None
    frame = pyatspi.findDescendant(app, lambda n: n.getRoleName() == "frame" and n.name == window.title)
    if frame is None:
        return None
    frame.clear_cache()
    focusable, focused = [], []
    for node in pyatspi.findAllDescendants(frame, lambda n: True):
        node.clear_cache()
        state = node.getState()
        identity = {"name": node.name, "role": node.getRoleName()}
        if state.contains(pyatspi.STATE_FOCUSABLE):
            focusable.append(identity)
        if state.contains(pyatspi.STATE_FOCUSED):
            focused.append(identity)
    return {"pid": app.get_process_id(), "title": frame.name, "active": frame.getState().contains(pyatspi.STATE_ACTIVE), "focusable_children": focusable, "focused_children": focused}


def _client_activation(kdockw: KDockW, expected: TestWindow, windows: list[TestWindow], stage: str) -> None:
    def observed():
        states = [_client_states(window) for window in windows]
        if any(state is None for state in states):
            return None
        target = next(state for state in states if state["pid"] == expected.pid)
        if not target["active"] or any(state["active"] for state in states if state["pid"] != expected.pid):
            return None
        if target["focusable_children"] and not target["focused_children"]:
            return None
        return states

    states = wait_until(observed, message=f"own native client PID {expected.pid} active with focused child")
    assert next(state for state in states if state["pid"] == expected.pid)["title"] == expected.title
    _record(kdockw, stage, expected_pid=expected.pid, own_native_frames=states)


def _traverse(kdockw: KDockW, apps: TestWindows, windows: dict[str, TestWindow], names: tuple[str, ...], edge: int, stage: str) -> None:
    _expect_order(kdockw, names)
    _park(kdockw)
    kdockw.click_item(names[-1])
    _active(kdockw, windows[names[-1]], f"{stage}-before-navigation")
    _park(kdockw)
    invoke_shortcut("focus-dock")
    initial = wait_until(lambda: (f if len(f := _focused_names(kdockw, names)) == 1 else None), message="one native focused controlled task")[0]
    _focus(kdockw, names, initial, f"{stage}-initial")
    kdockw.wait_keyboard_focus()
    previous, following = ("Up", "Down") if _vertical(edge) else ("Left", "Right")
    for index in range(names.index(initial) - 1, -1, -1):
        inp.key(previous)
        _focus(kdockw, names, names[index], f"{stage}-canonicalize")
    _focus(kdockw, names, names[0], f"{stage}-first")
    visits = [names[0]]
    for name in names[1:]:
        inp.key(following)
        _focus(kdockw, names, name, f"{stage}-forward")
        visits.append(name)
    for name in reversed(names[:-1]):
        inp.key(previous)
        _focus(kdockw, names, name, f"{stage}-reverse")
        visits.append(name)
    assert visits == [*names, *reversed(names[:-1])]
    _record(kdockw, stage, visits=visits, forward=following, backward=previous)
    inp.key("Return")
    target = windows[names[0]]
    _client_activation(kdockw, target, list(windows.values()), f"{stage}-return")
    before = len(apps.key_presses())
    inp.key("F12")
    wait_until(lambda: (target.title, F12, 0) in apps.key_presses()[before:], message="new F12 delivered to the exact native client")
    delivered = apps.key_presses()[before:]
    assert all(title == target.title for title, key, _ in delivered if key == F12)
    _client_activation(kdockw, target, list(windows.values()), f"{stage}-probe-active")
    _record(kdockw, f"{stage}-delivered", expected_pid=target.pid, delivered=delivered)


def _install_extra_launcher(kdockw: KDockW) -> None:
    # Use the fixture's private XDG_DATA_HOME, as the native mouse tests do.
    applications = kdockw.home / "data" / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    (applications / f"{EXTRA_APP_ID}.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={EXTRA_COLD_NAME}\n"
        f"Exec={env.TEST_WINDOW_BINARY} --app-id {EXTRA_APP_ID}\n"
        "Icon=utilities-terminal\n"
        f"StartupWMClass={EXTRA_APP_ID}\n",
        encoding="utf-8",
    )


@pytest.mark.parametrize("edge", EDGES)
def test_kbd010_task_navigation_survives_native_launch_and_close(kdockw: KDockW, apps: TestWindows, edge: int) -> None:
    _install_extra_launcher(kdockw)
    _start(kdockw, edge, pinned=(*PINNED_IDS, EXTRA_APP_ID))
    cold_names = wait_until(
        lambda: (names if len(names := kdockw.item_names()) == 3 else None),
        message="three actual cold pinned launchers",
    )
    cold_name = cold_names[2]
    # The existing harness documents desktop-id names as unresolved launchers.
    assert cold_name not in (EXTRA_APP_ID, f"{EXTRA_APP_ID}.desktop", config.launcher(EXTRA_APP_ID)), f"extra desktop fixture did not resolve: {cold_names}"
    assert cold_name == EXTRA_COLD_NAME, f"cold launcher name must resolve from the private fixture entry: {cold_names}"
    _record(kdockw, "cold-pinned-fixture", app_id=EXTRA_APP_ID, native_cold_names=cold_names, extra_cold_name=cold_name)
    initial = (PINNED_A, PINNED_B, cold_name, UNPINNED_A, UNPINNED_B)
    windows = _matrix(apps, kdockw, initial)
    _traverse(kdockw, apps, windows, initial, edge, "initial-cold-pinned")
    extra = apps.open(EXTRA_NAME, app_id=EXTRA_APP_ID, accessible=True)
    windows[EXTRA_NAME] = extra
    launched = (PINNED_A, PINNED_B, EXTRA_NAME, UNPINNED_A, UNPINNED_B)
    _traverse(kdockw, apps, windows, launched, edge, "after-pinned-launch")
    apps.close(windows.pop(UNPINNED_B))
    kdockw.wait_for_no_item(UNPINNED_B)
    closed = (PINNED_A, PINNED_B, EXTRA_NAME, UNPINNED_A)
    _traverse(kdockw, apps, windows, closed, edge, "after-unpinned-close")


def _entry(kdockw: KDockW, edge: int, target: Rect) -> list[tuple[int, int]]:
    dock = kdockw.surface_rect("dock")
    assert dock is not None
    x, y = target.center
    if edge == config.EDGE_LEFT:
        start, near = (env.SCREEN_WIDTH - 20, y - 4), (x, y - 4)
    elif edge == config.EDGE_RIGHT:
        start, near = (20, y - 4), (x, y - 4)
    elif edge == config.EDGE_BOTTOM:
        start, near = (x - 4, 20), (x - 4, y)
    else:
        start, near = (x - 4, env.SCREEN_HEIGHT - 20), (x - 4, y)
    assert not dock.contains(*start)
    preview = kdockw.surface_rect("preview")
    assert preview is None or not preview.contains(*start)
    assert target.contains(*near)
    return [start, *inp.line(start, near, 5), *inp.line(near, target.center, 2)]


def _physical(kdockw: KDockW, names: tuple[str, ...], name: str, stage: str, path: list[tuple[int, int]]) -> dict[str, Rect]:
    bounds = wait_stable(lambda: _rects(kdockw, names))
    cursor = kwin.cursor_pos()
    dock = kdockw.surface_rect("dock")
    preview = kdockw.surface_rect("preview")
    popup = pv.screen_rect(kdockw, kdockw.preview_popup()) if kdockw.preview_visible() else None
    _record(kdockw, stage, target=name, native_cursor=cursor, planned_path=path, all_task_bounds=_json_rects(bounds), native_dock=dock._asdict() if dock else None, native_preview=preview._asdict() if preview else None, interactive_popup=popup._asdict() if popup else None)
    assert [item for item, rect in bounds.items() if rect.contains(*cursor)] == [name]
    assert popup is None or not popup.contains(*cursor)
    return bounds


def _vertical_preview_hover(kdockw: KDockW, names: tuple[str, ...], item: str, initial: bool) -> None:
    before = _rest(kdockw, names, config.EDGE_LEFT) if initial else wait_stable(lambda: _rects(kdockw, names))
    assert all(rect.height == ICON_SIZE for rect in before.values())
    target = before[item]
    cursor = kwin.cursor_pos()
    if initial:
        path = _entry(kdockw, config.EDGE_LEFT, target)
        inp.move_path(path, step_ms=40)
    else:
        assert kdockw.preview_visible(), "retarget must begin with the real popup open"
        assert cursor[0] == target.center[0]
        path = inp.line(cursor, target.center, 5)
        for point in path:
            inp.move_path([point], step_ms=40)
            assert kdockw.preview_visible(), "popup must stay open throughout primary-axis retarget"
    after = _physical(kdockw, names, item, "vertical-after-single-action", path)
    assert kwin.cursor_pos() == target.center
    assert after == before
    wait_until(kdockw.preview_visible, message=f"popup after single measured vertical hover on {item}")
    assert _physical(kdockw, names, item, "vertical-popup-physical-target", path) == before


def _group_identity(kdockw: KDockW, group: list[TestWindow] | tuple[TestWindow, ...], stage: str) -> None:
    expected = {(w.pid, w.internal_id, w.title) for w in group}
    assert len(expected) == len(group), "fixture windows must have unique native identities"
    native = [w for w in kwin.app_windows() if w.pid in {window.pid for window in group}]
    actual = {(w.pid, w.internal_id, w.title) for w in native}
    _record(kdockw, stage, expected_count=len(group), native_count=len(native), native_windows=[asdict(window) for window in native])
    assert len(native) == len(group) and len(actual) == len(native)
    assert actual == expected


def _preview(kdockw: KDockW, edge: int, names: tuple[str, ...], item: str, header: str, windows: list[TestWindow] | tuple[TestWindow, ...], stage: str, *, initial: bool = False, expected_order: tuple[TestWindow, ...] | None = None) -> tuple[TestWindow, ...]:
    if edge == config.EDGE_LEFT:
        _vertical_preview_hover(kdockw, names, item, initial)
    else:
        pv.open_by_hover(kdockw, item)
    popup = kdockw.preview_popup()
    assert popup is not None and has_state(popup, "showing") and has_state(popup, "visible")
    wait_until(lambda: kdockw.find(pv.HEADER_XPATH).get_attribute("name") == header, message=f"application header {header!r}")
    by_title = {window.title: window for window in windows}
    assert len(by_title) == len(windows), "thumbnail titles must identify fixture windows uniquely"
    wait_until(
        lambda: len(titles := pv.thumb_titles(kdockw)) == len(windows) and set(titles) == set(by_title),
        message=f"exact thumbnail title set/count {tuple(by_title)}",
    )
    if expected_order is not None:
        wait_until(
            lambda: pv.thumb_titles(kdockw) == [window.title for window in expected_order],
            message=f"unchanged thumbnail order {[window.title for window in expected_order]}",
        )
    titles = tuple(pv.thumb_titles(kdockw))
    assert len(titles) == len(windows) and len(set(titles)) == len(titles) and set(titles) == set(by_title)
    assert len(kdockw.thumbnails()) == len(windows)
    _group_identity(kdockw, windows, stage)
    displayed = tuple(by_title[title] for title in titles)
    identities = tuple((window.pid, window.internal_id, window.title) for window in displayed)
    _record(kdockw, stage, popup_name=popup.get_attribute("name"), expected_header=header, thumbnail_count=len(titles), thumbnail_titles=titles, displayed_window_identities=identities, baseline_window_identities=tuple((window.pid, window.internal_id, window.title) for window in expected_order) if expected_order is not None else identities)
    if expected_order is not None:
        assert identities == tuple((window.pid, window.internal_id, window.title) for window in expected_order)
    return displayed


def _select_thumbnail(kdockw: KDockW, baseline: tuple[TestWindow, ...], index: int, other: TestWindow, stage: str) -> None:
    expected = baseline[index]
    assert pv.thumb_titles(kdockw) == [window.title for window in baseline]
    surface, popup, thumbnail = wait_stable(
        lambda: (kdockw.surface_rect("preview"), pv.screen_rect(kdockw, kdockw.preview_popup()), pv.screen_rect(kdockw, kdockw.wait_for(pv.thumb_xpath(expected.title))))
    )
    point = thumbnail.center
    _record(kdockw, f"{stage}-target", displayed_slot=index, expected_title=expected.title, expected_pid=expected.pid, expected_internal_id=expected.internal_id, native_preview=surface._asdict() if surface else None, popup=popup._asdict(), thumbnail=thumbnail._asdict(), point=point)
    assert surface is not None and surface.contains(*point), f"thumbnail slot {index} is outside native input surface: {surface}, {thumbnail}"
    assert popup.contains(*point)
    before = kwin.active_window()
    assert before is not None and (before.pid, before.internal_id, before.title) == (other.pid, other.internal_id, other.title), "thumbnail selection must start with the other app active"
    assert before is not None and before.pid != expected.pid, "thumbnail selection must activate a different native client"
    pv.glide_into(kdockw, point)
    wait_until(lambda: kwin.cursor_pos() == point, message=f"native pointer on thumbnail slot {index}")
    assert pv.thumb_titles(kdockw) == [window.title for window in baseline]
    inp.click(*point)
    _active(kdockw, expected, stage)
    wait_until(lambda: not kdockw.preview_visible(), message=f"thumbnail slot {index} activation closes preview")


def _toggle_pin(kdockw: KDockW, name: str, app_id: str, *, pinned: bool, order: tuple[str, ...]) -> None:
    _park(kdockw)
    before_names = kdockw.item_names()
    before_launchers = config.as_list(kdockw.read_config()["General"]["PinnedLaunchers"])
    kdockw.open_context_menu(name)
    action = "Unpin from Dock" if pinned else "Pin to Dock"
    kdockw.choose_context_menu_entry(action, context_menu_entries(pinned=pinned, is_window=True))
    launcher = config.launcher(app_id)
    wait_until(lambda: (launcher in config.as_list(kdockw.read_config()["General"].get("PinnedLaunchers", ""))) is not pinned, message=f"real {action} membership change")
    _expect_order(kdockw, order)
    _park(kdockw)
    _record(kdockw, "native-pin-transition", action=action, task=name, before_names=before_names, before_launcher_urls=before_launchers, after_names=kdockw.item_names(), after_launcher_urls=config.as_list(kdockw.read_config()["General"]["PinnedLaunchers"]))


@pytest.mark.parametrize("edge", ORIENTATIONS)
def test_prev010_last_thumbnail_and_other_app_pin_transitions(kdockw: KDockW, apps: TestWindows, edge: int) -> None:
    _start(kdockw, edge, previews=True)
    # The two-thumbnail vertical fixture exercises both vertical slots.
    # PREV-011 in test_11_preview_surface.py checks whole-popup rectangles:
    # test_prev011_grouped_preview_surface_tracks_two_three_and_single_layouts.
    group_titles = GROUP_TITLES if edge == config.EDGE_BOTTOM else GROUP_TITLES[:2]
    group = [apps.open(title, app_id=env.TEST_APP_ID, accessible=True) for title in group_titles]
    apps.open(PINNED_B, app_id=env.TEST_APP2_ID, accessible=True)
    unpinned = apps.open(UNPINNED_A, app_id=KWRITE_ID, accessible=True)
    name = env.TEST_APP_NAME
    original = (name, PINNED_B, UNPINNED_A)
    reordered = (PINNED_B, name, UNPINNED_A)
    _expect_order(kdockw, original)
    _toggle_pin(kdockw, name, env.TEST_APP_ID, pinned=True, order=reordered)
    _toggle_pin(kdockw, name, env.TEST_APP_ID, pinned=False, order=reordered)
    assert config.as_list(kdockw.read_config()["General"]["PinnedLaunchers"]) == [config.launcher(env.TEST_APP2_ID), config.launcher(env.TEST_APP_ID)]
    _divider(kdockw, True)
    baseline = _preview(kdockw, edge, reordered, name, name, group, "initial-group", initial=True)
    _preview(kdockw, edge, reordered, UNPINNED_A, "KWrite", [unpinned], "initial-across-division", expected_order=(unpinned,))
    _preview(kdockw, edge, reordered, name, name, group, "initial-return-group", expected_order=baseline)

    shifted = (name, PINNED_B, UNPINNED_A)
    for currently_pinned, label in ((None, "initial-selection"), (True, "other-app-unpinned"), (False, "other-app-repinned")):
        names = reordered if currently_pinned is None else shifted
        if currently_pinned is not None:
            before_names = kdockw.item_names()
            _toggle_pin(kdockw, PINNED_B, env.TEST_APP2_ID, pinned=currently_pinned, order=shifted)
            after_names = kdockw.item_names()
            assert after_names.index(name) == 0
            if currently_pinned:
                assert before_names.index(name) == 1
                assert after_names.index(name) != before_names.index(name)
            _record(kdockw, f"{label}-group-slot", before_names=before_names, after_names=after_names, before_slot=before_names.index(name), after_slot=after_names.index(name))
            _group_identity(kdockw, group, f"{label}-group-preserved")
            _divider(kdockw, True)
        for index in range(len(baseline)):
            stage = f"{label}-thumbnail-{index}"
            anchor = kwin.active_window()
            if anchor is None or (anchor.pid, anchor.internal_id) != (unpinned.pid, unpinned.internal_id):
                kdockw.click_item(UNPINNED_A)
            _active(kdockw, unpinned, f"{stage}-before-selection")
            _preview(kdockw, edge, names, name, name, group, f"{stage}-group", initial=True, expected_order=baseline)
            _preview(kdockw, edge, names, UNPINNED_A, "KWrite", [unpinned], f"{stage}-other-app", expected_order=(unpinned,))
            _preview(kdockw, edge, names, name, name, group, f"{stage}-return-group", expected_order=baseline)
            _select_thumbnail(kdockw, baseline, index, unpinned, stage)


def _expanded_point(base: Rect, drawn: Rect, edge: int) -> tuple[int, int]:
    x, y = drawn.center
    if edge == config.EDGE_BOTTOM:
        point = (x, base.y - 4)
    elif edge == config.EDGE_TOP:
        point = (x, base.y + base.height + 4)
    elif edge == config.EDGE_LEFT:
        point = (base.x + base.width + 4, y)
    else:
        point = (base.x - 4, y)
    assert drawn.contains(*point) and not base.contains(*point), f"no expanded-only hit at {point}: baseline={base}, magnified={drawn}"
    return point


def _magnified_click(kdockw: KDockW, names: tuple[str, ...], windows: dict[str, TestWindow], target: str, edge: int, separate: bool) -> None:
    baseline = _rest(kdockw, names, edge)
    path = _entry(kdockw, edge, baseline[target])
    inp.move_path(path, step_ms=40)
    wait_until(lambda: _extent(_rects(kdockw, names)[target], edge) >= ICON_SIZE * 1.5, message=f"{target} actually magnifies near configured 1.6x")
    drawn = wait_stable(lambda: _rects(kdockw, names))
    index = names.index(target)
    for neighbor in (index - 1, index + 1):
        name = names[neighbor]
        shift = _primary_center(drawn[name], edge) - _primary_center(baseline[name], edge)
        assert shift * (neighbor - index) > 2, f"{name} did not reflow outward: {baseline}, {drawn}"
    point = _expanded_point(baseline[target], drawn[target], edge)
    assert [name for name, rect in drawn.items() if rect.contains(*point)] == [target]
    inp.move_path(inp.line(kwin.cursor_pos(), point, 3), step_ms=40)
    final = wait_stable(lambda: _rects(kdockw, names))
    cursor = kwin.cursor_pos()
    _record(kdockw, "magnified-expanded-hit", target=target, edge=edge, separate=separate, baseline=_json_rects(baseline), magnified=_json_rects(final), point=point, native_cursor=cursor)
    assert cursor == point
    assert final[target].contains(*point) and not baseline[target].contains(*point)
    assert [name for name, rect in final.items() if rect.contains(*point)] == [target]
    assert _extent(final[target], edge) >= ICON_SIZE * 1.5
    surface = kdockw.surface_rect("dock")
    assert surface is not None and surface.contains(*point)
    _divider(kdockw, separate)
    inp.click(*point)
    _active(kdockw, windows[target], f"magnified-click-{target}")


@pytest.mark.skipif(EXTENTS_IGNORE_SCALE, reason="expanded native AT-SPI hit rectangles require Qt >= 6.9")
@pytest.mark.parametrize("edge", EDGES)
@pytest.mark.parametrize("separate", SEPARATION)
def test_mouse018_separation_modes_and_magnified_boundary_hits(kdockw: KDockW, apps: TestWindows, edge: int, separate: bool) -> None:
    _start(kdockw, edge, separate=separate, zoom=1.6)
    windows = _matrix(apps, kdockw)
    _divider(kdockw, separate)
    for name in (PINNED_B, UNPINNED_A):
        rest = _rest(kdockw, ALL_NAMES, edge)
        point = rest[name].center
        inp.click(*point)
        assert kwin.cursor_pos() == point
        _active(kdockw, windows[name], f"rest-boundary-click-{name}")
    for name in (PINNED_B, UNPINNED_A):
        _magnified_click(kdockw, ALL_NAMES, windows, name, edge, separate)
