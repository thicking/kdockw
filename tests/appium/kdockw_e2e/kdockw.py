# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""The kdockw process under test: isolated start/stop/restart, AT-SPI lookup
through selenium-webdriver-at-spi, surface-local -> screen coordinates, and
input sugar for dock items."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import time
import urllib.request
from pathlib import Path
from typing import Any, Mapping, NamedTuple, Sequence

from appium import webdriver
from appium.options.common.base import AppiumOptions
from appium.webdriver.common.appiumby import AppiumBy
from appium.webdriver.webelement import WebElement
from PIL import Image
from selenium.common.exceptions import WebDriverException

from . import config as kcfg
from . import dbus, env, kwin
from . import input as inp
from .waits import wait_stable, wait_until

#: XPath of the dock tool bar and its items (see tests/e2e/README.md).
TOOLBAR_XPATH = "//tool_bar[@name='KDockW Dock']"
ITEMS_XPATH = TOOLBAR_XPATH + "/button"
PREVIEW_XPATH = "//popup_menu"
# The header close control is also a direct button; only thumbnail buttons
# expose a direct title label.
THUMBNAILS_XPATH = PREVIEW_XPATH + "/button[label]"
#: The Settings window's frame (SettingsDialog.qml, title "Settings").
SETTINGS_XPATH = "/*/frame[@name='Settings']"
#: AT-SPI role of a Kirigami/QQC2 Page: QQuickPage::accessibleRole() is
#: PageTab before Qt 6.11 and Pane (AT-SPI "panel") since. Each settings
#: page is a FormCardPage named after its sidebar entry.
PAGE_ROLE = "panel" if env.QT_VERSION >= (6, 11) else "page_tab"
#: The Settings window's sidebar ListView (Accessible.List "Settings pages").
SETTINGS_SIDEBAR_XPATH = SETTINGS_XPATH + "//list[@name='Settings pages']"
#: The sidebar's page entries (checkable RoundedItemDelegates; the checked one
#: is the shown page). Matched by their description so the "About" section
#: header is never counted as a page.
SETTINGS_PAGES_XPATH = SETTINGS_SIDEBAR_XPATH + "//list_item[starts-with(@description, 'Settings page: ')]"

#: Default kdockwrc for tests: nothing pinned, so the dock shows only what the
#: test opens. Override per test via KDockW(config=...).
DEFAULT_CONFIG: dict[str, Any] = {"PinnedLaunchers": []}


class Rect(NamedTuple):
    x: int
    y: int
    width: int
    height: int

    @property
    def center(self) -> tuple[int, int]:
        return (self.x + self.width // 2, self.y + self.height // 2)

    def contains(self, px: int, py: int) -> bool:
        return self.x <= px < self.x + self.width and self.y <= py < self.y + self.height

    @staticmethod
    def of(element: WebElement) -> "Rect":
        r = element.rect
        return Rect(int(r["x"]), int(r["y"]), int(r["width"]), int(r["height"]))


#: Qt < 6.9 reports an item's AT-SPI extents as its transformed top-left
#: corner with its untransformed size (qtdeclarative itemScreenRect used
#: mapToScene(0, 0) + item size; 6.9 maps the whole rect with
#: mapRectToScene). Dock items zoom through a Scale transform, so there a
#: zoomed item keeps its base width and height and only its origin moves.
EXTENTS_IGNORE_SCALE: bool = env.QT_VERSION < (6, 9)


def painted_rect(rect: Rect, rest: Rect) -> Rect:
    """Where a bottom-edge dock item is drawn, from its AT-SPI ``rect`` and
    ``rest``, the same item's rect while unzoomed (both in the same
    coordinates, surface-local or screen).

    DockItem.qml scales the item about the centre of its bottom side, then
    translates it along the dock by its zoom offset (the Parabolic style
    pushes neighbours aside). With Qt >= 6.9 ``rect`` already is the
    transformed rect and is returned as is. With older Qt
    (:data:`EXTENTS_IGNORE_SCALE`) ``rect`` is the transformed top-left corner
    with the unscaled size: scale s moves the corner up by height * (s - 1),
    so the zoom factor comes from how far it rose above the resting one (the
    horizontal shift mixes scale and offset and is not used).
    """
    if not EXTENTS_IGNORE_SCALE:
        return rect
    assert (rect.width, rect.height) == (rest.width, rest.height), f"{rect} and rest rect {rest} differ in size"
    grow = (rest.y - rect.y) / rest.height  # s - 1
    return Rect(rect.x, rect.y, round(rest.width * (1 + grow)), round(rest.height * (1 + grow)))



class KDockW:
    """One kdockw instance with private XDG dirs under ``home``.

    ``config`` (see kdockw_e2e.config.write_kdockwrc for the format) is written
    to ``$XDG_CONFIG_HOME/kdockwrc`` before the first start; ``None`` writes
    DEFAULT_CONFIG, ``{}`` writes nothing (kdockw's built-in defaults).
    """

    def __init__(self, home: Path, config: Mapping[str, Any] | None = None, name: str = "kdockw") -> None:
        self.home = Path(home)
        self.name = name
        self.process: subprocess.Popen | None = None
        self.driver: webdriver.Remote | None = None
        self._starts = 0
        for d in ("config", "data", "cache", "state"):
            (self.home / d).mkdir(parents=True, exist_ok=True)
        cfg = DEFAULT_CONFIG if config is None else config
        if cfg:
            self.write_config(cfg)

    # ---------------------------------------------------------------- lifecycle
    @property
    def config_path(self) -> Path:
        return self.home / "config" / "kdockwrc"

    @property
    def pid(self) -> int:
        assert self.process is not None, "kdockw is not running"
        return self.process.pid

    @property
    def log_path(self) -> Path:
        return env.artifact_path(f"{self.name}/kdockw-{self._starts}.log")

    def environment(self) -> dict[str, str]:
        e = dict(os.environ)
        e.update(
            XDG_CONFIG_HOME=str(self.home / "config"),
            XDG_DATA_HOME=str(self.home / "data"),
            XDG_CACHE_HOME=str(self.home / "cache"),
            XDG_STATE_HOME=str(self.home / "state"),
            QT_ACCESSIBILITY="1",
            QT_LINUX_ACCESSIBILITY_ALWAYS_ON="1",
            QT_QPA_PLATFORM="wayland",
        )
        if os.environ.get("KDOCKW_CORE_DUMP_DIR"):
            # KCrash handles SIGSEGV and exits 255 when DrKonqi cannot start,
            # preventing the kernel core handler from writing a dump. In the
            # explicit E2E core-dump mode only, disable KCrash so the signal
            # and core are preserved for the artifact collector.
            e["KDE_DEBUG"] = "1"
            existing_rules = e.get("QT_LOGGING_RULES", "").strip()
            multidock_rule = "kdockw.shell.multidock.debug=true"
            if multidock_rule not in existing_rules.split(";"):
                e["QT_LOGGING_RULES"] = ";".join(filter(None, (existing_rules, multidock_rule)))
        return e

    def start(self, timeout: float = 30.0) -> None:
        """Launch kdockw, attach a webdriver session to its AT-SPI tree and
        wait until the dock tool bar exists and KWin has mapped the dock."""
        assert self.process is None, "already running"
        # KDBusService(Unique): a previous instance must be gone first.
        wait_until(lambda: not dbus.has_name("org.kde.kdockw"), timeout=timeout, message="previous kdockw to release org.kde.kdockw")
        self._starts += 1
        log = open(self.log_path, "wb")
        command = [env.KDOCKW_BINARY]
        process_cwd: str | None = None
        if os.environ.get("KDOCKW_CORE_DUMP_DIR"):
            # Keep the application PID stable across exec while opting only
            # KDockW into core dumps; unrelated fixtures keep the default
            # zero core limit.
            command = ["sh", "-c", 'ulimit -c unlimited || exit; exec "$@"', "kdockw-core", env.KDOCKW_BINARY]
            try:
                pattern = Path("/proc/sys/kernel/core_pattern").read_text(encoding="utf-8").strip()
            except OSError:
                pattern = ""
            if not pattern.startswith("/") and not pattern.startswith("|"):
                # Local containers commonly use a relative `core` pattern and
                # cannot change the host sysctl. Give this opt-in KDockW
                # process its own mounted working directory so its dump
                # survives container exit; normal tests keep the image cwd.
                process_cwd = str(
                    Path(os.environ["KDOCKW_CORE_DUMP_DIR"]) / f"kdockw-{self.name}-{self._starts}"
                )
                Path(process_cwd).mkdir(parents=True, exist_ok=True)
        self.process = subprocess.Popen(
            command, env=self.environment(), stdout=log, stderr=subprocess.STDOUT, cwd=process_cwd
        )
        log.close()
        self.log_path.with_suffix(".process.json").write_text(
            json.dumps(
                {
                    "pid": self.process.pid,
                    "executable": os.path.realpath(env.KDOCKW_BINARY),
                    "argv": [env.KDOCKW_BINARY],
                    "log": str(self.log_path),
                    "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        if process_cwd is not None:
            (Path(process_cwd) / "core-process.json").write_text(
                json.dumps(
                    {
                        "pid": self.process.pid,
                        "executable": os.path.realpath(env.KDOCKW_BINARY),
                        "log": str(self.log_path),
                        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
        options = AppiumOptions()
        options.set_capability("app", str(self.process.pid))
        # Also the window in which the webdriver looks for the pid on the bus.
        options.set_capability("timeouts", {"implicit": int(timeout * 500)})
        try:
            self.driver = webdriver.Remote(command_executor=env.WEBDRIVER_URL, options=options)
        except WebDriverException:
            self._dump_failure()
            raise
        # One lookup pass per request; helpers poll with wait_until instead.
        self._set_implicit_wait(50)
        # One poll for both conditions: the dock frame XPath in surface_rect
        # matches only a frame whose child is the dock tool bar, so a surface
        # rect means the tool bar is in the tree too. The budget is the two
        # former sequential waits' combined.
        wait_until(
            lambda: self.surface_rect("dock"),
            timeout=2 * timeout,
            message=lambda: "dock surface mapped by KWin" if self.find(TOOLBAR_XPATH) is not None else "dock tool bar in AT-SPI",
        )

    def stop(self, timeout: float = 10.0) -> None:
        """Quit the webdriver session and terminate kdockw (SIGTERM, then SIGKILL)."""
        if self.driver is not None:
            try:
                self.driver.quit()
            except Exception:  # noqa: BLE001 - teardown
                pass
            self.driver = None
        if self.process is not None:
            unexpected_exit = self.process.poll() is not None
            if not unexpected_exit:
                self.process.send_signal(signal.SIGTERM)
                try:
                    self.process.wait(timeout)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(5)
            if unexpected_exit and self.process.returncode not in (None, 0):
                self.log_path.with_suffix(".exit.json").write_text(
                    json.dumps(
                        {
                            "pid": self.process.pid,
                            "returncode": self.process.returncode,
                            "signal": -self.process.returncode if self.process.returncode < 0 else None,
                            "ended_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                            "log": str(self.log_path),
                        },
                        indent=2,
                    )
                    + "\n",
                    encoding="utf-8",
                )
            self.process = None

    def restart(self, timeout: float = 30.0) -> None:
        """stop() + start(); XDG dirs and kdockwrc are preserved."""
        self.stop()
        self.start(timeout)

    def is_running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def _set_implicit_wait(self, ms: int) -> None:
        assert self.driver is not None
        req = urllib.request.Request(
            f"{env.WEBDRIVER_URL}/session/{self.driver.session_id}/timeouts/implicit_wait",
            data=json.dumps({"ms": ms}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=10).read()

    def _dump_failure(self) -> None:
        if self.process is not None and self.process.poll() is not None:
            raise RuntimeError(f"kdockw exited with {self.process.returncode}; see {self.log_path}")

    # ------------------------------------------------------------------ config
    def write_config(self, settings: Mapping[str, Any]) -> None:
        """(Over)write kdockwrc. Takes effect on the next (re)start."""
        kcfg.write_kdockwrc(self.config_path, settings)

    def read_config(self) -> dict[str, dict[str, str]]:
        """Parse the current kdockwrc: ``{group: {key: raw value}}``."""
        return kcfg.read_kdockwrc(self.config_path)

    # ------------------------------------------------------------------ lookup
    def find(self, xpath: str) -> WebElement | None:
        """First element matching ``xpath`` in kdockw's AT-SPI tree, or None.
        Tag names are AT-SPI role names with '_' for ' ' (tool_bar, button,
        popup_menu, frame, label, ...); attributes: name, description,
        states, accessibility-id."""
        assert self.driver is not None
        found = self.driver.find_elements(AppiumBy.XPATH, xpath)
        return found[0] if found else None

    def find_all(self, xpath: str) -> list[WebElement]:
        assert self.driver is not None
        return self.driver.find_elements(AppiumBy.XPATH, xpath)

    def wait_for(self, xpath: str, timeout: float = 10.0) -> WebElement:
        return wait_until(lambda: self.find(xpath), timeout=timeout, message=f"{xpath} in kdockw's AT-SPI tree")

    def toolbar(self) -> WebElement:
        return self.wait_for(TOOLBAR_XPATH)

    def items(self) -> list[WebElement]:
        """Dock item buttons in visual order."""
        return self.find_all(ITEMS_XPATH)

    def item_names(self) -> list[str]:
        """Accessible names of the dock items in order. Resolved apps use the
        .desktop Name (``KDockW Test Window``); pinned launchers whose desktop
        file is missing show the desktop id (``org.kde.dolphin.desktop``)."""
        return [e.get_attribute("name") for e in self.items()]

    def item(self, name: str) -> WebElement | None:
        return self.find(f"{ITEMS_XPATH}[@name={_xpath_str(name)}]")

    def wait_for_item(self, name: str, timeout: float = 10.0) -> WebElement:
        return wait_until(lambda: self.item(name), timeout=timeout, message=lambda: f"dock item {name!r} (have {self.item_names()})")

    def item_accessible(self, name: str) -> Any | None:
        """Dock item ``name`` as an in-process pyatspi Accessible (the node
        :meth:`item` finds through the webdriver), or None.

        For tight sampling loops: once looked up, each read on it is one
        D-Bus call to kdockw (~1 ms) instead of a webdriver request that
        serializes kdockw's whole AT-SPI tree for the XPath. Call
        ``clear_cache()`` on it before reading states (libatspi may cache
        them)."""
        import pyatspi  # noqa: PLC0415 - only in-process readers need it

        app = next((a for a in pyatspi.Registry.getDesktop(0) if a is not None and a.get_process_id() == self.pid), None)
        if app is None:
            return None
        toolbar = pyatspi.findDescendant(app, lambda n: n.getRoleName() == "tool bar" and n.name == "KDockW Dock")
        if toolbar is None:
            return None
        return next((c for c in toolbar if c is not None and c.getRoleName() == "button" and c.name == name), None)

    def wait_for_no_item(self, name: str, timeout: float = 10.0) -> None:
        wait_until(lambda: self.item(name) is None, timeout=timeout, message=f"dock item {name!r} to disappear")

    def focused_item(self) -> str | None:
        """Name of the dock item with the AT-SPI ``focused`` state."""
        el = self.find(f"{ITEMS_XPATH}[contains(@states, 'focused')]")
        return el.get_attribute("name") if el is not None else None

    def wait_keyboard_focus(self, surface: str = "dock") -> None:
        """Wait until KWin gives kdockw's ``surface`` keyboard focus (its
        window is KWin's active window).

        Keyboard navigation marks a dock item focused in the AT-SPI tree as
        soon as kdockw's QML enters it, before KWin has applied the layer
        surface's exclusive keyboard interactivity (wl_keyboard.enter follows
        with the next commit). A key sent in between goes to the previously
        active window, so wait for this before the first key."""

        def has_focus() -> bool:
            w, r = kwin.active_window(), self.surface_rect(surface)
            return w is not None and r is not None and w.pid == self.pid and Rect(w.client_x, w.client_y, w.client_width, w.client_height) == r

        wait_until(has_focus, timeout=5, message=f"KWin keyboard focus on kdockw's {surface} surface")

    def preview_popup(self) -> WebElement | None:
        """The preview ``[popup menu]`` (exists while hidden, with 0x0 size)."""
        return self.find(PREVIEW_XPATH)

    def preview_visible(self) -> bool:
        el = self.preview_popup()
        # The popup role does not consistently expose AT-SPI Component on
        # every Qt/KF build. Its `showing` state is the visibility oracle;
        # requesting WebDriver `rect` here can raise NotImplementedError even
        # while the popup and its thumbnails are visibly on screen.
        return bool(el is not None and has_state(el, "showing"))

    def thumbnails(self) -> list[WebElement]:
        """Thumbnail buttons of the preview popup (name = window title)."""
        return self.find_all(THUMBNAILS_XPATH)

    def settings(self) -> WebElement | None:
        """The Settings window's AT-SPI frame (None until opened)."""
        return self.find(SETTINGS_XPATH)

    def page_source(self) -> str:
        """Whole AT-SPI tree of kdockw as XML (for debugging/diagnostics)."""
        assert self.driver is not None
        return self.driver.page_source

    # ---------------------------------------------------------------- geometry
    def windows(self) -> list[kwin.Window]:
        """KWin windows owned by this kdockw (dock, preview, settings, ...)."""
        return [w for w in kwin.windows() if w.pid == self.pid]

    def _frame_xpath(self, surface: str) -> str:
        return {
            "dock": f"/*/frame[{TOOLBAR_XPATH[2:]}]",
            "preview": f"/*/frame[.{PREVIEW_XPATH}]",
            "settings": SETTINGS_XPATH,
        }[surface]

    def surface_rect(self, surface: str = "dock", *, output_x: int | None = None) -> Rect | None:
        """Screen geometry of a kdockw surface ("dock", "preview" or
        "settings"): KWin's client geometry of the kdockw window whose size
        matches the surface's AT-SPI frame. KWin can report identical extents
        for the dock and preview surfaces on vertical layouts, so use the
        process and window-role flags to disambiguate those before comparing
        dimensions. When multiple outputs have same-size surfaces, ``output_x``
        selects one explicitly; otherwise the output containing the current
        pointer is selected. The pointer need not be over the dock surface.
        None while unmapped or when the result remains ambiguous."""
        frame = self.find(self._frame_xpath(surface))
        if frame is None:
            return None
        fr = Rect.of(frame)
        candidates = [w for w in self.windows() if w.pid == self.pid]
        if surface == "dock":
            candidates = [w for w in candidates if w.dock and w.special_window]
        elif surface == "preview":
            # KWin versions differ on specialWindow for non-dock LayerShell
            # surfaces; both identify the mapped preview as a taskbar-skipped,
            # non-normal, non-dock window owned by this process.
            candidates = [w for w in candidates if w.skip_taskbar and not w.dock and not w.normal_window]
        elif surface == "settings":
            candidates = [w for w in candidates if w.normal_window and not w.special_window and not w.skip_taskbar]
        else:
            return None
        matching = [w for w in candidates if (w.client_width, w.client_height) == (fr.width, fr.height)]
        if output_x is not None:
            matching = [w for w in matching if w.client_x == output_x]
        elif len(matching) > 1:
            output = kwin.output_at()
            if output is not None:
                matching = [w for w in matching if w.output == output]
        if len(matching) != 1:
            return None
        window = matching[0]
        return Rect(window.client_x, window.client_y, window.client_width, window.client_height)

    def to_screen(self, rect: Rect, surface: str = "dock", *, output_x: int | None = None) -> Rect:
        """Convert a surface-local AT-SPI rect (what ``element.rect`` returns
        on Wayland) to global screen coordinates."""
        origin = wait_until(
            lambda: self.surface_rect(surface, output_x=output_x),
            timeout=5,
            message=f"{surface} surface geometry",
        )
        return Rect(origin.x + rect.x, origin.y + rect.y, rect.width, rect.height)

    def screen_rect(self, element: WebElement, surface: str = "dock", *, output_x: int | None = None) -> Rect:
        return self.to_screen(Rect.of(element), surface, output_x=output_x)

    def item_center(self, name: str) -> tuple[int, int]:
        """Screen coordinates of the centre of dock item ``name``."""
        return self.screen_rect(self.wait_for_item(name)).center

    def settled_item_center(self, name: str) -> tuple[int, int]:
        """``item_center`` once it stops moving. Adding or removing an item
        animates the panel width (main.qml ``Behavior on width``) and shifts
        its neighbours; pointer input aimed at a moving centre lands on the
        wrong item."""
        return wait_stable(lambda: self.item_center(name))

    # ------------------------------------------------------------------- input
    def hover_item(self, name: str, steps: int = 5, step_ms: int = 40) -> None:
        """Glide the pointer onto item ``name`` from just above the dock
        (gradual, so enter/hover handlers run like with a real mouse)."""
        x, y = self.settled_item_center(name)
        dock = self.surface_rect("dock") or Rect(0, env.SCREEN_HEIGHT - 1, env.SCREEN_WIDTH, 1)
        start = (x, max(0, dock.y - 40))
        # Teleport to ``start`` and glide down in one inputsynth run.
        inp.move_path([start, *inp.line(start, (x, y), steps)], step_ms)

    def click_item(self, name: str, button: str = "left") -> None:
        """Real pointer click on the centre of dock item ``name``."""
        inp.click(*self.settled_item_center(name), button=button)

    def scroll_item(self, name: str, dy: int = 15) -> None:
        inp.scroll(*self.settled_item_center(name), dy=dy)

    def move_away(self, close_preview: bool = True) -> None:
        """Glide the pointer to the top centre, away from the dock.

        Hovering a task item opens its preview popup after ``PreviewHoverDelay``;
        while that popup is alive the item still counts as hovered and stays
        zoomed. When ``close_preview`` is set (the default) this waits for the
        preview to be dismissed, so the dock truly returns to its rest state.
        """
        inp.move_path(inp.line((env.SCREEN_WIDTH // 2, env.SCREEN_HEIGHT - 1), (env.SCREEN_WIDTH // 2, 20), 4), 20)
        if close_preview:
            wait_until(lambda: not self.preview_visible(), timeout=8, message="preview to close after moving away")


    # ------------------------------------------------------------ context menu
    def open_context_menu(self, name: str, timeout: float = 5.0) -> kwin.Window:
        """Right-click item ``name`` and wait for the QMenu popup. Qt keeps
        popup menus out of the AT-SPI tree, so the result is the KWin window
        (its geometry is the menu's screen rect)."""
        before = {w.internal_id for w in self.windows()}
        self.click_item(name, button="right")
        return wait_until(
            lambda: next((w for w in self.windows() if w.internal_id not in before and not w.normal_window), None),
            timeout=timeout,
            message=f"context menu of {name!r}",
        )

    def choose_context_menu_entry(self, label: str, entries: list[str]) -> None:
        """Activate ``label`` in the open context menu with the keyboard
        (Down x position, Return). ``entries`` are the enabled entries in
        order, see :func:`context_menu_entries`."""
        for _ in range(entries.index(label) + 1):
            inp.key("Down")
        inp.key("Return")

    def open_settings(self, via_item: str, entries: list[str] | None = None, timeout: float = 15.0) -> kwin.Window:
        """Open Settings through item ``via_item``'s context menu and wait for
        the "Settings — KDockW" window. Pass ``entries`` when the item is not
        an unpinned single window without notifications."""
        self.open_context_menu(via_item)
        self.choose_context_menu_entry("Settings...", entries or context_menu_entries(pinned=False, is_window=True))
        return wait_until(
            lambda: next((w for w in self.windows() if w.normal_window and not w.skip_taskbar and w.title.startswith("Settings")), None),
            timeout=timeout,
            message="Settings window",
        )

    def screenshot(self, name: str, area: tuple[int, int, int, int] | None = None) -> Image.Image:
        """Screen image (RGB, screen coordinates), also saved as PNG to
        ``artifacts/<kdockw name>/<name>.png``. With ``area`` only that part is
        captured and the rest is black; see :func:`kwin.screenshot`."""
        return kwin.screenshot(env.artifact_path(f"{self.name}/{name}.png"), area)


def has_state(element: WebElement, state: str) -> bool:
    """Whether an AT-SPI element currently has ``state`` (``focused``,
    ``showing``, ``visible``, ``focusable``, ``sensitive``, ``active``...).
    Appium returns boolean attributes as the strings "true"/"false"."""
    return str(element.get_attribute(state)).lower() == "true"


class DescriptionChanges:
    """Collects AT-SPI ``object:property-change:accessible-description``
    events in arrival order: every description an element takes on, including
    states too short for a page_source() poll to see (a dock item's
    "Starting" launch feedback). Pumped on the default GLib main context like
    :class:`kdockw_e2e.preview.Announcements`."""

    EVENT = "object:property-change:accessible-description"

    def __init__(self) -> None:
        import pyatspi  # noqa: PLC0415 - only this helper needs it

        self._registry = pyatspi.Registry
        self._events: list[tuple[str, str]] = []
        self._registry.registerEventListener(self._on_event, self.EVENT)

    def _on_event(self, event) -> None:  # noqa: ANN001 - pyatspi event
        app = event.host_application.name if event.host_application is not None else ""
        self._events.append((app, str(event.any_data)))

    def texts(self, app: str | None = None) -> list[str]:
        """Descriptions received so far (from application ``app``)."""
        from gi.repository import GLib  # noqa: PLC0415

        ctx = GLib.MainContext.default()
        while ctx.iteration(False):
            pass
        return [text for a, text in self._events if app is None or a == app]

    def close(self) -> None:
        self._registry.deregisterEventListener(self._on_event, self.EVENT)


def context_menu_entries(pinned: bool, is_window: bool, has_notifications: bool = False, desktop_actions: Sequence[str] = ()) -> list[str]:
    """Enabled entries of a dock item's context menu in order (the disabled
    app-name header and separators are skipped by keyboard navigation);
    mirrors src/models/dockcontextmenu.cpp. ``desktop_actions`` are the
    visible desktop-file actions of the app, in their Actions= order."""
    entries = [*desktop_actions, "Unpin from Dock" if pinned else "Pin to Dock", "New Instance"]
    if has_notifications:
        entries.append("Clear Notifications")
    if is_window:
        entries.append("Close")
    return entries + ["Settings...", "About KDockW", "Quit"]


def _xpath_str(s: str) -> str:
    if "'" not in s:
        return f"'{s}'"
    if '"' not in s:
        return f'"{s}"'
    return "concat(" + ", \"'\", ".join(f"'{p}'" for p in s.split("'")) + ")"
