# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""TZONE-001..TZONE-007: real pinned/running task-zone behavior.

These scenarios exercise KWin-mapped fixture windows and the dock's AT-SPI
surface. The image-free geometry checks use actual accessible bounds; there is
no screenshot or DRM dependency here.
"""

from __future__ import annotations

import json
from typing import Iterable

import pytest

from kdockw_e2e import config, env, kwin
from kdockw_e2e import input as inp
from kdockw_e2e.kdockw import KDockW, context_menu_entries, has_state
from kdockw_e2e.preview import Announcements
from kdockw_e2e.waits import wait_stable, wait_until
from kdockw_e2e.windows import TestWindows

# Reuse the established settings-page navigation rather than adding a second
# scrolling convention to the Appium suite.
from test_06_settings import close_settings, open_page, scroll_into_view
from test_05_drag import drag
from test_04_context_menu import description


KWRITE_ID, KFIND_ID = "org.kde.kwrite", "org.kde.kfind"
PINNED_A, PINNED_B = "Pinned A", "Pinned B"
UNPINNED_A, UNPINNED_B = "Unpinned A", "Unpinned B"
PINNED_IDS = (env.TEST_APP_ID, env.TEST_APP2_ID)
ALL_NAMES = (PINNED_A, PINNED_B, UNPINNED_A, UNPINNED_B)
REST_ICON_SIZE = 48
REST_ICON_SPACING = 4
SEPARATE_SWITCH = "//frame[@name='Settings']//check_box[@name='Separate pinned and running apps']"
SEPARATOR = "//separator[@name='Pinned and running apps separator']"


@pytest.fixture
def task_zone_names() -> tuple[str, ...]:
    """Stable names exposed by the real fixture window titles."""
    return ALL_NAMES


def _launcher_ids(kdockw: KDockW) -> list[str]:
    return config.as_list(kdockw.read_config().get("General", {}).get("PinnedLaunchers", ""))


def _separate_launchers(kdockw: KDockW) -> bool:
    """KConfigXT omits values equal to the true factory default on disk."""
    value = kdockw.read_config().get("General", {}).get("SeparateLaunchers")
    return True if value is None else config.as_bool(value)


def _configure(kdockw: KDockW, *, edge: int, separate: bool, pinned: Iterable[str] = PINNED_IDS) -> None:
    kdockw.write_config(
        {
            "PinnedLaunchers": [config.launcher(app_id) for app_id in pinned],
            "SeparateLaunchers": separate,
            "IconSize": REST_ICON_SIZE,
            "IconSpacing": REST_ICON_SPACING,
            "Edge": edge,
            "VisibilityMode": config.ALWAYS_VISIBLE,
            "PreviewHoverDelay": 60000,
        }
    )
    kdockw.restart()


def _open_matrix(apps: TestWindows, kdockw: KDockW) -> None:
    apps.open("Pinned A", app_id=env.TEST_APP_ID)
    apps.open("Pinned B", app_id=env.TEST_APP2_ID)
    apps.open("Unpinned A", app_id=KWRITE_ID)
    apps.open("Unpinned B", app_id=KFIND_ID)
    for name in ALL_NAMES:
        kdockw.wait_for_item(name)
    wait_until(lambda: len(kdockw.item_names()) == len(ALL_NAMES), message="one visible task per fixture app")
    kdockw.move_away()


def _assert_partition(kdockw: KDockW, expected: Iterable[str] = ALL_NAMES) -> None:
    names = kdockw.item_names()
    fixture_names = [name for name in names if name in ALL_NAMES]
    assert names[:2] == [PINNED_A, PINNED_B], f"pinned zone order: {names}"
    assert fixture_names == list(expected), f"fixture task order/duplicates: {names}"

def _separator(kdockw: KDockW):
    return kdockw.find(SEPARATOR)


def _wait_separator(kdockw: KDockW):
    return wait_until(lambda: _separator(kdockw), message="pinned/running accessible separator")


def _wait_no_separator(kdockw: KDockW) -> None:
    wait_until(lambda: _separator(kdockw) is None, message="separator to be absent")


def _open_behavior_switch(kdockw: KDockW, *, pinned: bool = True):
    # Use the real button currently exposed by the dock. Running fixture
    # tasks are named by their window titles in the source-built QA image,
    # while launcher-only items may use the desktop Name.
    anchor = wait_until(
        lambda: next((name for name in kdockw.item_names() if ("Pinned" in description(kdockw, name)) is pinned), None),
        message="a real dock item matching the Settings context-menu membership",
    )
    kdockw.open_settings(anchor, entries=context_menu_entries(pinned=pinned, is_window=True))
    # The keyboard-chosen entry leaves the pointer on the anchor, whose hover
    # preview reopens after the menu closes; on a side dock it can cover the
    # Settings sidebar. Leave the dock first, as test_06's open_settings does.
    kdockw.move_away()
    open_page(kdockw, "Behavior")
    return scroll_into_view(kdockw, SEPARATE_SWITCH)


def _toggle_separation(kdockw: KDockW, expected: bool) -> None:
    switch = _open_behavior_switch(kdockw)
    assert has_state(switch, "checked") is not expected
    inp.click(*kdockw.screen_rect(switch, "settings").center)
    wait_until(
        lambda: has_state(kdockw.wait_for(SEPARATE_SWITCH), "checked") == expected,
        message=f"separation switch to become {expected}",
    )
    wait_until(
        lambda: _separate_launchers(kdockw) == expected,
        message=f"SeparateLaunchers autosaved as {expected}",
    )


@pytest.mark.parametrize(
    "edge",
    [config.EDGE_TOP, config.EDGE_BOTTOM, config.EDGE_LEFT, config.EDGE_RIGHT],
    ids=["top", "bottom", "left", "right"],
)
def test_tzone001_live_toggle_orders_visible_tasks_and_persists(
    kdockw: KDockW, apps: TestWindows, edge: int, task_zone_names: tuple[str, ...]
) -> None:
    """The live switch partitions real tasks and survives full restarts."""
    _configure(kdockw, edge=edge, separate=False)
    _open_matrix(apps, kdockw)
    assert kdockw.item_names() == list(task_zone_names)
    original_membership = _launcher_ids(kdockw)
    _wait_no_separator(kdockw)

    # Prove ON-mode migration from a genuinely cross-zone OFF-mode order. The
    # relative order within each resulting zone must remain stable.
    active = kwin.active_window()
    assert active is not None
    _drag_from_rest(kdockw, UNPINNED_B, PINNED_A, "off-mode-cross-zone-before-toggle")
    off_order = [UNPINNED_B, PINNED_A, PINNED_B, UNPINNED_A]
    wait_until(lambda: kdockw.item_names() == off_order, message="OFF mode permits cross-zone order before enabling separation")
    assert _launcher_ids(kdockw) == original_membership
    # Match the established post-drag focus contract before opening a fresh
    # menu. This observes KWin state without activating or repairing a client.
    wait_until(
        lambda: (current := kwin.active_window()) is not None and current.internal_id == active.internal_id,
        message="pre-drag window active again after the drop",
    )
    park = (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2)
    dock = kdockw.surface_rect("dock")
    assert dock is not None and not dock.contains(*park)
    inp.move(*park)

    _toggle_separation(kdockw, True)
    separated_order = [PINNED_A, PINNED_B, UNPINNED_B, UNPINNED_A]
    # Settings is itself an unpinned native task while its window is open.
    wait_until(
        lambda: [name for name in kdockw.item_names() if name in ALL_NAMES] == separated_order,
        message="ON mode preserves fixture relative order while partitioning zones",
    )
    _assert_partition(kdockw, separated_order)
    _wait_separator(kdockw)
    assert _launcher_ids(kdockw) == original_membership
    close_settings(kdockw)
    wait_until(lambda: kdockw.item_names() == separated_order, message="exact separated order once Settings closes")

    kdockw.restart()
    for name in task_zone_names:
        kdockw.wait_for_item(name)
    # Only launcher order is persisted. Running-task enumeration may change
    # after a process restart, but ON mode must restore the pinned section.
    wait_until(
        lambda: len(names := kdockw.item_names()) == 4 and names[:2] == [PINNED_A, PINNED_B] and set(names[2:]) == {UNPINNED_A, UNPINNED_B},
        message="ON restart restores pinned order and exactly one of each running fixture",
    )
    restarted_order = wait_stable(kdockw.item_names)
    assert len(restarted_order) == 4
    assert restarted_order[:2] == [PINNED_A, PINNED_B]
    assert set(restarted_order[2:]) == {UNPINNED_A, UNPINNED_B}
    _wait_separator(kdockw)
    assert _launcher_ids(kdockw) == original_membership
    assert _separate_launchers(kdockw)

    _toggle_separation(kdockw, False)
    close_settings(kdockw)
    _wait_no_separator(kdockw)
    wait_until(lambda: kdockw.item_names() == restarted_order, message="live OFF mode retains the settled pre-toggle order")
    _assert_partition(kdockw, restarted_order)
    assert _launcher_ids(kdockw) == original_membership
    assert config.as_bool(kdockw.read_config().get("General", {}).get("SeparateLaunchers", "false")) is False

    kdockw.restart()
    for name in task_zone_names:
        kdockw.wait_for_item(name)
    wait_until(
        lambda: len(names := kdockw.item_names()) == 4 and set(names) == set(ALL_NAMES),
        message="OFF restart restores exactly one of each fixture without imposing task ranks",
    )
    off_restart_order = wait_stable(kdockw.item_names)
    assert len(off_restart_order) == 4 and set(off_restart_order) == set(ALL_NAMES)
    switch = _open_behavior_switch(kdockw)
    wait_until(
        lambda: [name for name in kdockw.item_names() if name in ALL_NAMES] == off_restart_order,
        message="opening Settings preserves existing OFF-mode fixture order",
    )
    _wait_no_separator(kdockw)
    assert _launcher_ids(kdockw) == original_membership
    assert not has_state(switch, "checked"), "OFF separation preference must persist across restart"
    assert not config.as_bool(kdockw.read_config().get("General", {}).get("SeparateLaunchers", "false"))
    close_settings(kdockw)
    wait_until(lambda: kdockw.item_names() == off_restart_order, message="closing Settings preserves exact OFF-mode fixture order")


@pytest.mark.parametrize(
    "edge",
    [config.EDGE_TOP, config.EDGE_BOTTOM, config.EDGE_LEFT, config.EDGE_RIGHT],
    ids=["top", "bottom", "left", "right"],
)
def test_tzone002_separator_accessibility_geometry_and_single_zone_visibility(
    kdockw: KDockW, apps: TestWindows, edge: int
) -> None:
    """The separator is an accessible, allocated slot, not a task."""
    _configure(kdockw, edge=edge, separate=True)
    _open_matrix(apps, kdockw)
    # The stock helper parks at (screenWidth/2, 20), which is still inside a
    # top-edge dock. Establish actual rest bounds before checking its gap.
    park = (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2)
    dock = kdockw.surface_rect("dock")
    assert dock is not None and not dock.contains(*park)
    inp.move(*park)
    vertical = edge in (config.EDGE_LEFT, config.EDGE_RIGHT)
    wait_until(
        lambda: all(
            (kdockw.screen_rect(item).height if vertical else kdockw.screen_rect(item).width) == REST_ICON_SIZE
            for item in kdockw.items()
        ),
        message="all dock items to return to their unzoomed primary extent",
    )
    wait_stable(
        lambda: tuple(kdockw.screen_rect(item) for item in kdockw.items()),
        duration=0.6,
    )

    separator = _wait_separator(kdockw)
    assert has_state(separator, "showing")
    assert has_state(separator, "visible")
    rect = kdockw.screen_rect(separator)
    assert rect.width > 0 and rect.height > 0, f"separator must have positive extents: {rect}"
    before = kdockw.screen_rect(kdockw.wait_for_item(PINNED_B))
    after = kdockw.screen_rect(kdockw.wait_for_item(UNPINNED_A))
    if edge in (config.EDGE_TOP, config.EDGE_BOTTOM):
        assert rect.height > rect.width
        left_gap = rect.x - (before.x + before.width)
        right_gap = after.x - (rect.x + rect.width)
        assert abs(left_gap - REST_ICON_SPACING) <= 1, f"pinned/separator gap was {left_gap}px: {before} {rect}"
        assert abs(right_gap - REST_ICON_SPACING) <= 1, f"separator/running gap was {right_gap}px: {rect} {after}"
        assert before.x + before.width <= rect.center[0] <= after.x
    else:
        assert rect.width > rect.height
        top_gap = rect.y - (before.y + before.height)
        bottom_gap = after.y - (rect.y + rect.height)
        assert abs(top_gap - REST_ICON_SPACING) <= 1, f"pinned/separator gap was {top_gap}px: {before} {rect}"
        assert abs(bottom_gap - REST_ICON_SPACING) <= 1, f"separator/running gap was {bottom_gap}px: {rect} {after}"
        assert before.y + before.height <= rect.center[1] <= after.y

    # At maximum zoom the two adjacent delegates remain real hit targets; the
    # allocated separator slot must not steal pointer input or disappear while
    # either is hovered.
    for name in (PINNED_B, UNPINNED_A):
        kdockw.hover_item(name)
        wait_until(lambda: kdockw.screen_rect(kdockw.wait_for_item(name)).width >= REST_ICON_SIZE, message=f"{name} hover target")
        assert _separator(kdockw) is not None
        # Re-resolve the target's transformed centre after hover. The pointer
        # path can itself reflow neighbouring icons, so the endpoint computed
        # before the path is not guaranteed to remain over this delegate.
        target = next(window for window in apps.open_windows if window.title == name)
        active = kwin.active_window()
        assert active is not None and (active.pid, active.internal_id) != (target.pid, target.internal_id), (
            f"{name!r} must differ from the active client before the boundary hit: {active}"
        )
        kdockw.click_item(name)
        wait_until(
            lambda: (active := kwin.active_window()) is not None
            and (active.pid, active.internal_id) == (target.pid, target.internal_id),
            message=f"same-pointer boundary click activates exact {name!r} native client",
        )
    kdockw.move_away()

    # Removing the unpinned zone leaves no boundary; removing every task does
    # the same. Both observations are from AT-SPI, not QML/source inspection.
    for window in list(apps.open_windows):
        if window.app_id in (KWRITE_ID, KFIND_ID):
            apps.close(window)
    wait_until(
        lambda: kdockw.item(UNPINNED_A) is None and kdockw.item(UNPINNED_B) is None,
        message="all unpinned tasks to close",
    )
    _wait_no_separator(kdockw)
    apps.close_all()
    _configure(kdockw, edge=edge, separate=True, pinned=())
    wait_until(lambda: kdockw.item_names() == [], message="empty task model to have no dock items")
    _wait_no_separator(kdockw)


def test_tzone003_grouped_instances_keep_one_pinned_slot_and_close_differently(
    kdockw: KDockW, apps: TestWindows
) -> None:
    """A pinned app stays in its slot; an unpinned task vanishes on close."""
    _configure(kdockw, edge=config.EDGE_BOTTOM, separate=True, pinned=(env.TEST_APP_ID,))
    wait_until(lambda: kdockw.item_names() == [env.TEST_APP_NAME], message="cold pinned launcher slot")

    first = apps.open("Pinned first", app_id=env.TEST_APP_ID)
    wait_until(lambda: kdockw.item_names() == [first.title], message="single pinned window title in its slot")
    second = apps.open("Pinned second", app_id=env.TEST_APP_ID)
    wait_until(
        lambda: kdockw.item_names() == [env.TEST_APP_NAME]
        and "2 windows" in description(kdockw, env.TEST_APP_NAME),
        message="two same-app windows grouped as one pinned desktop-name task",
    )
    assert {w.pid for w in apps.open_windows if w.refresh()} == {first.pid, second.pid}

    apps.close(second)
    wait_until(lambda: kdockw.item_names() == [first.title], message="group collapses to the remaining pinned window title")
    apps.close(first)
    wait_until(lambda: kdockw.item_names() == [env.TEST_APP_NAME], message="cold pinned launcher slot survives all instances closing")

    apps.open(UNPINNED_A, app_id=KWRITE_ID)
    kdockw.wait_for_item(UNPINNED_A)
    menu = kdockw.open_context_menu(UNPINNED_A)
    assert menu.pid == kdockw.pid
    kdockw.choose_context_menu_entry("Close Window", context_menu_entries(pinned=False, is_window=True))
    wait_until(lambda: not [w for w in apps.open_windows if w.refresh()], message="unpinned fixture window to close")
    kdockw.wait_for_no_item(UNPINNED_A)
    assert kdockw.item_names() == [env.TEST_APP_NAME]


def test_tzone004_pin_and_unpin_use_real_context_menu_and_preserve_membership(
    kdockw: KDockW, apps: TestWindows
) -> None:
    _configure(kdockw, edge=config.EDGE_BOTTOM, separate=True, pinned=(env.TEST_APP_ID,))
    apps.open(PINNED_A, app_id=env.TEST_APP_ID)
    apps.open(UNPINNED_A, app_id=KWRITE_ID)
    kdockw.wait_for_item(PINNED_A)
    kdockw.wait_for_item(UNPINNED_A)
    original = _launcher_ids(kdockw)

    kdockw.open_context_menu(UNPINNED_A)
    kdockw.choose_context_menu_entry("Pin to Dock", context_menu_entries(pinned=False, is_window=True))
    wait_until(lambda: config.launcher(KWRITE_ID) in _launcher_ids(kdockw), message="real Pin to Dock action")
    wait_until(lambda: kdockw.item_names()[:2] == [PINNED_A, UNPINNED_A], message="pinned item to move into pinned zone")

    kdockw.open_context_menu(UNPINNED_A)
    kdockw.choose_context_menu_entry("Unpin from Dock", context_menu_entries(pinned=True, is_window=True))
    wait_until(lambda: config.launcher(KWRITE_ID) not in _launcher_ids(kdockw), message="real Unpin from Dock action")
    assert config.launcher(env.TEST_APP_ID) in _launcher_ids(kdockw)
    assert original == [config.launcher(env.TEST_APP_ID)]
    wait_until(lambda: kdockw.item_names() == [PINNED_A, UNPINNED_A], message="unpinned running task to remain visible after unpin")


def _drag_from_rest(
    kdockw: KDockW, source: str, target: str, tag: str, announcements: Announcements | None = None
) -> None:
    """Compute both physical drag endpoints from one settled rest layout."""
    park = (env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT // 2)
    dock = kdockw.surface_rect("dock")
    assert dock is not None and not dock.contains(*park)
    inp.move(*park)
    settings = kdockw.read_config().get("General", {})
    icon_size = int(settings.get("IconSize", "40"))
    edge = int(settings.get("Edge", config.EDGE_BOTTOM))
    vertical = edge in (config.EDGE_LEFT, config.EDGE_RIGHT)
    wait_until(
        lambda: all(
            (kdockw.screen_rect(item).height if vertical else kdockw.screen_rect(item).width) == icon_size
            for item in kdockw.items()
        ),
        message="dock to return to unzoomed drag geometry",
    )
    bounds = wait_stable(
        lambda: {name: kdockw.screen_rect(kdockw.wait_for_item(name)) for name in (source, target)},
        duration=0.6,
    )
    dock = kdockw.surface_rect("dock")
    assert dock is not None
    assert all(dock.contains(*rect.center) for rect in bounds.values()), f"drag endpoints outside dock: {bounds}, {dock}"
    artifact = env.artifact_path(f"{kdockw.name}/drag-{tag}.json")
    metadata = {"source": source, "target": target, "bounds": {name: list(rect) for name, rect in bounds.items()}, "dock": list(dock)}
    if announcements is not None:
        metadata["announcements_before"] = announcements.messages("kdockw")
    artifact.write_text(json.dumps(metadata), encoding="utf-8")
    try:
        drag(bounds[source].center, [bounds[target].center])
    finally:
        if announcements is not None:
            metadata["announcements_after"] = announcements.messages("kdockw")
            artifact.write_text(json.dumps(metadata), encoding="utf-8")



def test_tzone005_on_reorders_inside_both_zones_and_clamps_cross_boundary(
    kdockw: KDockW, apps: TestWindows
) -> None:
    _configure(kdockw, edge=config.EDGE_BOTTOM, separate=True)
    _open_matrix(apps, kdockw)
    original_membership = set(_launcher_ids(kdockw))

    # Real pointer drags inside each zone retain the zone's independent order.
    _drag_from_rest(kdockw, PINNED_B, PINNED_A, "pinned-reorder")
    wait_until(lambda: kdockw.item_names()[:2] == [PINNED_B, PINNED_A], message="pinned-zone reorder")
    _drag_from_rest(kdockw, UNPINNED_B, UNPINNED_A, "running-reorder")
    wait_until(lambda: kdockw.item_names()[2:] == [UNPINNED_B, UNPINNED_A], message="running-zone reorder")

    announcements = Announcements()
    try:
        # Drop the first pinned app past the running zone: it must move to the
        # nearest valid position (last pinned), not merely stay in its zone.
        _drag_from_rest(kdockw, PINNED_B, UNPINNED_A, "pinned-to-running-clamped", announcements)
        wait_until(
            lambda: kdockw.item_names() == [PINNED_A, PINNED_B, UNPINNED_B, UNPINNED_A],
            message="pinned-to-running drop clamped to the last pinned position",
        )
        assert set(_launcher_ids(kdockw)) == original_membership

        # The last running app dropped before the pinned zone must move to the
        # first running position, without becoming pinned.
        _drag_from_rest(kdockw, UNPINNED_A, PINNED_A, "running-to-pinned-clamped", announcements)
        wait_until(
            lambda: kdockw.item_names() == [PINNED_A, PINNED_B, UNPINNED_A, UNPINNED_B],
            message="running-to-pinned drop clamped to the first running position",
        )
        assert set(_launcher_ids(kdockw)) == original_membership
        stable_order = wait_stable(kdockw.item_names, duration=0.6)
        assert stable_order == [PINNED_A, PINNED_B, UNPINNED_A, UNPINNED_B], "queued partition must not roll back the clamped order"
        env.artifact_path(f"{kdockw.name}/native-clamp-announcements.json").write_text(
            json.dumps({"order": kdockw.item_names(), "messages": announcements.messages("kdockw")}),
            encoding="utf-8",
        )
    finally:
        announcements.close()


def test_tzone006_off_allows_real_cross_zone_reorder_without_auto_pin(
    kdockw: KDockW, apps: TestWindows
) -> None:
    _configure(kdockw, edge=config.EDGE_BOTTOM, separate=False)
    _open_matrix(apps, kdockw)
    original_membership = set(_launcher_ids(kdockw))

    _drag_from_rest(kdockw, UNPINNED_B, PINNED_A, "running-to-pinned-free")
    wait_until(
        lambda: kdockw.item_names().index(UNPINNED_B) < kdockw.item_names().index(PINNED_A),
        message="OFF mode cross-zone drag to reorder freely",
    )
    assert set(_launcher_ids(kdockw)) == original_membership
    _drag_from_rest(kdockw, PINNED_A, UNPINNED_B, "pinned-to-running-free")
    wait_until(
        lambda: kdockw.item_names().index(PINNED_A) < kdockw.item_names().index(UNPINNED_B),
        message="OFF mode reverse cross-zone drag",
    )
    assert set(_launcher_ids(kdockw)) == original_membership


def test_tzone007_fresh_default_separation_is_on(kdockw: KDockW, apps: TestWindows) -> None:
    """A fresh config uses the configured pinned/running separation default."""
    apps.open("Default", app_id=env.TEST_APP_ID)
    kdockw.wait_for_item("Default")
    switch = _open_behavior_switch(kdockw, pinned=False)
    assert has_state(switch, "checked")
    assert config.as_bool(kdockw.read_config().get("General", {}).get("SeparateLaunchers", "true"))
    close_settings(kdockw)
