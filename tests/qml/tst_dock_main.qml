// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// The real dock root (src/qml/main.qml) with mocked backends: layout from
// settings, pointer-driven zoom, hover/tooltip/preview, clicks, wheel,
// keyboard navigation and drag reorder.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "TestUtils.js" as T
import "../../src/qml/BadgeTextColor.js" as BadgeTextColor

// TestCase is an invisible Item: visual fixtures live under `stage`, a visible
// sibling, so effective visibility, layout and pointer delivery are real.
Item {
    id: root
    width: 800
    height: 240

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "DockMain"
        when: windowShown

        function init() {
            KDockWMocks.resetAll()
            // Most DockMain cases exercise legacy Classic behavior; Spring
            // defaults are covered explicitly in the settings and MiniDock
            // tests, while Spring dock coverage opts in per test.
            DockSettings.magnificationMode = 0
            IconDiagnostics.debugEnabled = false
            IconDiagnostics.testBadgeOverlay = false
            IconDiagnostics.testBadgeMetrics = false
            IconDiagnostics.testBadgeTextQt = false
            IconDiagnostics.testBadgeTextNative = false
            // Keep hover timers short so condition waits finish quickly.
            DockSettings.previewHoverDelay = 50
        }

        function cleanup() {
            // Park the pointer outside the stage so the next test starts un-hovered.
            mouseMove(stage, -1, -1)
        }

        function addTasks(names, extra) {
            for (let n of names)
                DockModel.tasksModel.addTask(Object.assign({ display: n, AppId: n.toLowerCase(), IsWindow: true }, extra || {}))
        }

        function addGroupTask(name = "Grouped") {
            let row = DockModel.tasksModel.addTask({
                display: name,
                AppId: name.toLowerCase(),
                IsWindow: true,
                IsGroupParent: true,
            })
            DockModel.tasksModel.addChildTask(row, {
                display: name + " child 1",
                AppId: (name + " child 1").toLowerCase(),
                IsWindow: true,
                IsActive: true,
            })
            DockModel.tasksModel.addChildTask(row, {
                display: name + " child 2",
                AppId: (name + " child 2").toLowerCase(),
                IsWindow: true,
                IsActive: false,
            })
            return row
        }

        function addMixedPinnedRows() {
            DockSettings.separateLaunchers = true
            DockModel.pinnedTaskCount = 3
            DockModel.tasksModel.addTask({
                display: "OpenCode",
                AppId: "opencode",
                LauncherUrlWithoutIcon: "applications:opencode.desktop",
                entryType: "task",
                entryId: "task:opencode",
                IsLauncher: true,
                isPinned: true,
                IsWindow: true,
            })
            DockModel.tasksModel.addTask({
                display: "Projects",
                AppId: "folder-stack",
                entryType: "folderStack",
                entryId: "folder:/tmp/projects",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                IsLauncher: true,
                isPinned: true,
            })
            DockModel.tasksModel.addTask({
                display: "Kate",
                AppId: "kate",
                LauncherUrlWithoutIcon: "applications:org.kde.kate.desktop",
                entryType: "task",
                entryId: "task:kate",
                IsLauncher: true,
                isPinned: true,
                IsWindow: true,
            })
            DockModel.tasksModel.addTask({
                display: "Terminal window",
                AppId: "terminal",
                entryType: "task",
                entryId: "running:terminal",
                IsLauncher: false,
                isPinned: false,
                IsWindow: true,
            })
        }

        function entryOrder() {
            let order = []
            for (let i = 0; i < DockModel.tasksModel.count; ++i)
                order.push(DockModel.tasksModel.get(i, "entryId"))
            return order
        }

        function dockTooltip(dock) {
            return T.findFirst(dock, o => o.objectName === "dockTooltip")
        }

        function badgeOverlayLabel(dock) {
            return T.findFirst(dock, o => o.objectName === "badgeOverlayLabel")
        }

        function items(dock) {
            return T.findAll(dock, T.isDockItem).sort((a, b) => a.index - b.index)
        }

        property int settledTurns: 0

        // Lets deferred (Qt.callLater) post-layout delegate setup run.
        function settleDeferredCallbacks() {
            let next = settledTurns + 1
            Qt.callLater(function() {
                Qt.callLater(function() { tc.settledTurns = next })
            })
            tryCompare(tc, "settledTurns", next)
        }

        function makeDock(count) {
            let comp = Qt.createComponent(Qt.resolvedUrl("../../src/qml/main.qml"))
            compare(comp.status, Component.Ready, comp.errorString())
            let dock = createTemporaryObject(comp, stage)
            verify(dock)
            tryVerify(() => items(dock).length === count, 2000, "expected " + count + " dock items")
            for (let it of items(dock))
                tryVerify(() => it._delegateGeometryReady, 2000)
            settleDeferredCallbacks()
            tryVerify(() => DockVisibility.panelRect.width > 0)
            return dock
        }

        function test_badgeOverlayTextRendererAndGeometry_data() {
            return [
                { tag: "default-qt", forceQt: false, forceNative: false, expected: Text.QtRendering },
                { tag: "qt", forceQt: true, forceNative: false, expected: Text.QtRendering },
                { tag: "native", forceQt: false, forceNative: true, expected: Text.NativeRendering },
            ]
        }

        function test_badgeOverlayTextRendererAndGeometry(data) {
            DockSettings.iconSize = 40
            DockSettings.maxZoomFactor = 1.7
            DockSettings.badgeDisplayMode = 0
            IconDiagnostics.debugEnabled = true
            IconDiagnostics.testBadgeOverlay = true
            IconDiagnostics.testBadgeMetrics = true
            IconDiagnostics.testBadgeTextQt = data.forceQt
            IconDiagnostics.testBadgeTextNative = data.forceNative

            DockModel.tasksModel.addTask({
                display: "Badge render test",
                AppId: "org.kde.dolphin",
                IsWindow: true,
            })
            NotificationTracker.setUnread("org.kde.dolphin", 8)
            const dock = makeDock(1)
            const item = items(dock)[0]
            tryVerify(() => item.badgeOverlayVisible, 2000,
                      "source badge did not become eligible for overlay")
            const label = badgeOverlayLabel(dock)
            tryVerify(() => label && label.visible, 2000,
                      "diagnostic overlay text did not become visible")

            compare(label.renderType, data.expected)
            const overlay = label.parent
            verify(overlay)
            verify(!label.layer.enabled, "text must not be baked into its own layer texture")
            verify(!overlay.layer.enabled, "overlay delegate must not be baked into a layer texture")
            compare(label.scale, 1)
            compare(overlay.scale, 1)
            compare(overlay.transform.length, 0)
            compare(overlay.parent, dock)
            verify(Math.abs(label.x + label.width / 2 - overlay.width / 2) < 0.01)
            verify(Math.abs(label.y + label.height / 2 - overlay.height / 2) < 0.01)

            const restFontSize = label.font.pixelSize
            const restBaseline = label.baselineOffset
            mouseMove(stage, -1, -1)
            tryCompare(item, "currentScale", 1.0)
            hoverItem(item)
            tryCompare(dock, "hoveredIndex", item.index)
            tryCompare(item, "currentScale", DockSettings.maxZoomFactor)
            wait(100)
            const mappedBadge = item.badgeOverlayRectIn(dock)
            verify(Math.abs(overlay.width - mappedBadge.width) < 0.5)
            verify(Math.abs(overlay.height - mappedBadge.height) < 0.5)
            verify(Math.abs(label.x + label.width / 2 - overlay.width / 2) < 0.01)
            verify(Math.abs(label.y + label.height / 2 - overlay.height / 2) < 0.01)
            verify(label.font.pixelSize >= restFontSize)
            verify(label.baselineOffset > 0)
            verify(label.baselineOffset >= restBaseline)
            verify(Math.round(label.font.pixelSize) === label.font.pixelSize)
        }

        function test_badgeColorsUseSavedValuesAndKeepQtTextRendering() {
            compare(DockSettings.badgeBackgroundColor.toString(), "#ff3b30")
            compare(DockSettings.badgeTextColor.toString(), "#ffffff")
            DockSettings.iconSize = 40
            DockSettings.badgeDisplayMode = 0
            DockModel.tasksModel.addTask({
                display: "Badge color test",
                AppId: "org.telegram.desktop",
                IsWindow: true,
            })
            NotificationTracker.setUnread("org.telegram.desktop", 12)

            const dock = makeDock(1)
            const item = items(dock)[0]
            const badge = T.findFirst(item, o => o.objectName === "badge")
            const label = T.findFirst(badge, o => o.objectName === "badgeLabel")
            verify(badge && label)
            tryVerify(() => badge.visible)
            compare(badge.color.toString(), "#ff3b30")
            compare(label.color.toString(), "#ffffff")
            compare(label.renderType, Text.QtRendering)

            DockSettings.badgeBackgroundColor = "#ff000000"
            DockSettings.badgeTextColor = "#ffffff00"
            tryVerify(() => badge.color.toString() === "#000000")
            tryVerify(() => label.color.toString() === "#ffff00")
            compare(DockSettings.badgeDisplayMode, 0)
            compare(item._badgeCount, 12)
            compare(label.renderType, Text.QtRendering)
        }

        // Item center in stage coordinates (valid while the item is at rest scale 1).
        function centerOf(item) {
            return item.mapToItem(stage, item.width / 2, item.height / 2)
        }

        function hoverItem(item) {
            let c = centerOf(item)
            mouseMove(stage, c.x, c.y)
            return c
        }
        function dockEdges() {
            return [
                { tag: "top", edge: 0 },
                { tag: "bottom", edge: 1 },
                { tag: "left", edge: 2 },
                { tag: "right", edge: 3 },
            ]
        }

        // Painted delegate bounds include Scale/Translate, unlike Flow x/y.
        function drawnBounds(item, target = stage) {
            let near = item.mapToItem(target, 0, 0)
            let far = item.mapToItem(target, item.width, item.height)
            return { x: near.x, y: near.y, width: far.x - near.x, height: far.y - near.y }
        }

        function primaryNear(rect) {
            return DockView.isVertical ? rect.y : rect.x
        }

        function primaryExtent(rect) {
            return DockView.isVertical ? rect.height : rect.width
        }

        function secondaryCenter(rect) {
            return DockView.isVertical ? rect.x + rect.width / 2 : rect.y + rect.height / 2
        }

        function addSeparatedTasks() {
            addTasks(["Pinned A", "Pinned B"], { IsLauncher: true })
            addTasks(["Running A", "Running B"])
            DockModel.pinnedTaskCount = 2
        }

        function separatorOf(dock) {
            return T.findFirst(dock, o => o.objectName === "taskZonesSeparator")
        }

        function verifyRestProxies(dock, its, restBounds) {
            for (let i = 0; i < its.length; ++i) {
                let proxy = drawnBounds(its[i].delegateGeometryTarget, dock)
                fuzzyCompare(proxy.x, restBounds[i].x, 1e-6)
                fuzzyCompare(proxy.y, restBounds[i].y, 1e-6)
                fuzzyCompare(proxy.width, restBounds[i].width, 1e-6)
                fuzzyCompare(proxy.height, restBounds[i].height, 1e-6)
            }
            // A minimize/restore consumer receives the painted REST slot,
            // including separation, never the transient hover translation.
            tryVerify(() => {
                return its.every((it, index) => {
                    let requests = DockModel.delegateGeometryRequests.filter(r => r.index === index)
                    if (requests.length === 0) return false
                    let actual = requests[requests.length - 1].geometry
                    let expected = restBounds[index]
                    return Math.abs(actual.x - expected.x) < 1e-6
                        && Math.abs(actual.y - expected.y) < 1e-6
                        && Math.abs(actual.width - expected.width) < 1e-6
                        && Math.abs(actual.height - expected.height) < 1e-6
                })
            }, 3000, "published window targets did not match the allocated rest slots")
        }

        function verifySeparatorClearance(dock, its) {
            let before = drawnBounds(its[1])
            let after = drawnBounds(its[2])
            let separator = drawnBounds(separatorOf(dock))
            fuzzyCompare(primaryExtent(separator), 1, 1e-6)
            fuzzyCompare(primaryNear(separator) - primaryNear(before) - primaryExtent(before),
                         DockSettings.iconSpacing, 0.51)
            fuzzyCompare(primaryNear(after) - primaryNear(separator) - primaryExtent(separator),
                         DockSettings.iconSpacing, 0.51)
        }


        // --- Layout from settings ---

        function test_oneDelegatePerTask() {
            addTasks(["Dolphin", "Konsole", "Kate"])
            let dock = makeDock(3)
            let its = items(dock)
            compare(its.map(i => i.displayName), ["Dolphin", "Konsole", "Kate"])
            DockModel.tasksModel.addTask({ display: "Okular", IsWindow: true })
            tryVerify(() => items(dock).length === 4)
            DockModel.tasksModel.removeTask(0)
            tryVerify(() => items(dock).length === 3)
            compare(items(dock)[0].displayName, "Konsole")
        }

        function test_unpinnedRunningWindowAddsAndRemovesDelegate() {
            let dock = makeDock(0)
            DockModel.tasksModel.addTask({
                display: "Unpinned test app",
                AppId: "org.example.unpinned",
                IsWindow: true,
                IsLauncher: false,
                ChildCount: 1,
            })
            tryVerify(() => items(dock).length === 1)
            compare(items(dock)[0].displayName, "Unpinned test app")
            compare(DockModel.isPinned(0), false)

            DockModel.tasksModel.removeTask(0)
            tryVerify(() => items(dock).length === 0)
        }

        function test_folderStackDelegateOpensGridPopup() {
            const entry = {
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                isPinned: true,
            }
            DockModel.dockEntriesModel.append(entry)
            DockModel.tasksModel.addTask(entry)
            let dock = makeDock(1)
            let stack = T.findFirst(dock, o => o.objectName === "folderStackItem" && o.visible)
            verify(stack)
            compare(stack.displayName, "tmp")
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            compare(stack.popupItemCount, 2)
        }

        function test_folderStackPopupClosesOnEscapeSelectionAndWindowDeactivation() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            let dock = makeDock(1)
            let stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            verify(stack)

            stack.openStack()
            tryVerify(() => stack.popupVisible)
            verify(stack.popupControl.usesSeparateWindow,
                   "Folder Stack popup must use a native window, not the masked dock scene")
            let popupContent = stack.popupControl.contentItem
            verify(popupContent)
            verify(popupContent.Window.window !== stack.Window.window,
                   "Popup.Window must own a separate input surface")
            verify(stack.popupControl.closeOnOutsideEnabled,
                   "native outside dismissal must be enabled")
            popupContent.forceActiveFocus()
            keyClick(popupContent, Qt.Key_Escape)
            tryVerify(() => !stack.popupVisible)

            stack.openStack()
            tryVerify(() => stack.popupVisible)
            stack.activateGridItem(0, true)
            verify(stack.popupVisible, "navigating into a directory keeps the grid open")
            stack.activateGridItem(0, false)
            tryVerify(() => !stack.popupVisible, 2000, "choosing a file closes the popup")

            stack.openStack()
            tryVerify(() => stack.popupVisible)
            stack.closeForWindowDeactivation(false)
            tryVerify(() => !stack.popupVisible, 2000,
                      "loss of popup-window activity closes the popup")
        }

        function test_folderStackContextMenuUsesDismissibleWindowAndDefersThemeChooser() {
            const entryId = "folder:/tmp/theme-test"
            DockModel.dockEntriesModel.append({
                entryType: "folderStack",
                entryId: entryId,
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "theme-test",
                taskIndex: -1,
                isPinned: true,
            })
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: entryId,
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "theme-test",
                IsLauncher: true,
                isPinned: true,
            })

            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            verify(stack)
            const menu = stack.contextMenuControl
            compare(menu.popupType, QQC2.Popup.Window)
            verify((menu.closePolicy & QQC2.Popup.CloseOnPressOutside) !== 0,
                   "folder menu outside clicks must be handled by its own Wayland popup surface")
            verify((menu.closePolicy & QQC2.Popup.CloseOnEscape) !== 0,
                   "Escape must close the folder menu")

            stack.openContextMenu()
            tryVerify(() => menu.visible)
            stack.closeContextMenuForWindowDeactivation(false)
            tryVerify(() => !menu.visible, 2000,
                      "switching away from the native folder menu must dismiss it")

            stack.openContextMenu()
            tryVerify(() => menu.visible)
            stack.chooseThemeIconFromMenu()
            tryVerify(() => !menu.visible)
            tryVerify(() => DockModel.folderThemeIconRequests.length === 1)
            compare(DockModel.folderThemeIconRequests[0].entryId, entryId,
                   "the deferred chooser must retain the selected stack stable ID")
            verify(DockModel.folderThemeIconRequests[0].hasTransientParent,
                   "the chooser must receive the dock's native window as transient parent")
        }

        function test_folderStackPopupFitsAllDockEdges_data() {
            return dockEdges()
        }

        function test_folderStackPopupFitsAllDockEdges(data) {
            DockView.edge = data.edge
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            let dock = makeDock(1)
            let stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            verify(stack.popupScreenX >= DockView.screenGeometry.x - 0.5
                   && stack.popupScreenY >= DockView.screenGeometry.y - 0.5)
            verify(stack.popupScreenX + stack.popupWidth
                   <= DockView.screenGeometry.x + DockView.screenGeometry.width + 0.5,
                   "popup window must remain inside the selected output width")
            verify(stack.popupScreenY + stack.popupHeight
                   <= DockView.screenGeometry.y + DockView.screenGeometry.height + 0.5,
                   "popup window must remain inside the selected output height")
            verify(stack.popupGridHeight > 0, "GridView must receive the popup's remaining layout height")
            const expectedSurface = DockView.backgroundColor.a > 0
                ? BadgeTextColor.composite(DockView.backgroundColor, Kirigami.Theme.backgroundColor)
                : BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.backgroundColor,
                                                      DockSettings.backgroundOpacity),
                                            Kirigami.Theme.backgroundColor)
            compare(stack.popupCardColor, expectedSurface,
                    "Folder Stack must use the same resolved surface color as Window Preview")
            const customSurface = DockView.backgroundColor
            DockView.backgroundColor = "transparent"
            compare(stack.popupCardColor,
                    BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.backgroundColor,
                                                        DockSettings.backgroundOpacity),
                                              Kirigami.Theme.backgroundColor),
                    "a transparent dock must use the current theme background")
            DockView.backgroundColor = customSurface
            compare(stack.popupCardPadding, DockSettings.previewCardPadding,
                    "Folder Stack must use the Window Preview card padding setting")
            fuzzyCompare(stack.popupShadowMargin, Kirigami.Units.smallSpacing * 2, 0.1)
            const pathHeader = T.findFirst(stack.popupControl.contentItem,
                                           o => o.objectName === "folderStackPath")
            const scrollBar = T.findFirst(stack.popupControl.contentItem,
                                          o => o.objectName === "folderStackScrollBar")
            verify(pathHeader && pathHeader.elide === Text.ElideMiddle,
                   "long paths must remain inside the card header")
            verify(scrollBar, "the grid must retain its card-styled vertical scrollbar")
            const previewClearance = DockSettings.previewDockGap
                + DockSettings.iconSize * (DockSettings.maxZoomFactor - 1)
            const cardLeft = stack.popupScreenX + stack.popupShadowMargin
            const cardRight = stack.popupScreenX + stack.popupWidth - stack.popupShadowMargin
            const cardTop = stack.popupScreenY + stack.popupShadowMargin
            const cardBottom = stack.popupScreenY + stack.popupHeight - stack.popupShadowMargin
            switch (DockView.edge) {
            case 0:
                fuzzyCompare(cardTop, stack.popupAnchorScreenRect.y
                             + stack.popupAnchorScreenRect.height + previewClearance, 1.0)
                break
            case 1:
                fuzzyCompare(cardBottom, stack.popupAnchorScreenRect.y - previewClearance, 1.0)
                break
            case 2:
                fuzzyCompare(cardLeft, stack.popupAnchorScreenRect.x
                             + stack.popupAnchorScreenRect.width + previewClearance, 1.0)
                break
            case 3:
                fuzzyCompare(cardRight, stack.popupAnchorScreenRect.x - previewClearance, 1.0)
                break
            }
            if (!DockView.isVertical)
                compare(stack.popupWidth, Math.min(560, stage.width - Kirigami.Units.largeSpacing * 2))
        }

        function test_folderStackPopupWindowGridReceivesClicksAndListsFiles() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "icons",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            let dock = makeDock(1)
            let stack = T.findFirst(dock, o => o.objectName === "folderStackItem" && o.visible)
            verify(stack)
            stack.openStack()
            verify(stack.popupPendingOpen,
                   "the first native popup surface must wait for the asynchronous folder listing")
            verify(!stack.popupVisible,
                   "the xdg_popup must not be committed with its empty pre-listing geometry")
            tryVerify(() => stack.popupVisible)
            verify(stack.popupControl.usesSeparateWindow)
            compare(stack.popupItemCount, 2,
                    "the popup must bind the model rows into its grid")
            compare(stack.popupModelCount, 2,
                    "the FolderStackModel rows must reach the popup")
            verify(stack.popupContentVisible,
                   "the native popup content item must be visible")
            verify(stack.popupContentWidth > 100 && stack.popupContentHeight > 100,
                   "the popup content item must receive its bounded window geometry")
            const grid = T.findFirst(stack.popupControl.contentItem,
                                     o => o.objectName === "folderStackGrid")
            verify(grid)
            verify(stack.popupGridVisible && stack.popupGridWidth > 100
                   && stack.popupGridHeight >= 80,
                   "the visible GridView must have usable width and height")
            tryVerify(() => grid.itemAtIndex(0) !== null)
            tryVerify(() => stack.popupFirstDelegateVisible)
            const firstDirectory = grid.itemAtIndex(0)
            verify(firstDirectory)
            verify(firstDirectory.width > 80 && firstDirectory.height >= grid.cellHeight,
                   "the first delegate must have visible cell geometry")
            const filenameLabel = T.findFirst(firstDirectory,
                                               o => o.objectName === "folderStackFilename")
            verify(filenameLabel && filenameLabel.wrapMode === Text.NoWrap
                   && filenameLabel.elide === Text.ElideRight,
                   "long filenames must stay on one neatly elided line")
            mouseClick(firstDirectory, firstDirectory.width / 2, firstDirectory.height / 2)
            tryVerify(() => stack.popupCurrentUrl !== "file:///tmp", 3000,
                      "a click on the popup grid must reach its directory delegate")
            verify(stack.popupVisible, "folder navigation must keep the popup open")
            const goUp = T.findFirst(stack.popupControl.contentItem,
                                     o => o.objectName === "folderStackGoUpButton")
            verify(goUp && goUp.enabled)
            mouseClick(goUp)
            tryVerify(() => stack.popupCurrentUrl === "file:///tmp",
                      3000, "the popup header must navigate to the parent folder")
            const firstFile = grid.itemAtIndex(1)
            verify(firstFile)
            mouseClick(firstFile, firstFile.width / 2, firstFile.height / 2)
            tryVerify(() => !stack.popupVisible,
                      3000, "selecting a file from the GridView must close the popup")
            stack.openStack()
            tryVerify(() => stack.popupVisible, 2000,
                      "the popup must be reusable after a completed content interaction")
            compare(stack.popupModelCount, 2,
                    "a repeated open must reload the same Folder Stack contents")
            stack.popupControl.close()
        }

        function test_folderStackGridHoverKeyboardHandoffAndPointerExit() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack-selection",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            verify(stack)
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            const grid = T.findFirst(stack.popupControl.contentItem,
                                     o => o.objectName === "folderStackGrid")
            verify(grid)
            grid.forceActiveFocus()
            verify(grid.activeFocus, "keyboard navigation must have a stable focus target")

            keyClick(Qt.Key_Right)
            tryCompare(grid, "currentIndex", 1)
            verify(grid.keyboardSelectionActive)
            compare(grid.hoveredIndex, -1)
            let secondHighlight = T.findFirst(grid.itemAtIndex(1),
                                              o => o.objectName === "folderStackCellHighlight")
            verify(secondHighlight && secondHighlight.keyboardActive)

            const firstCell = grid.itemAtIndex(0)
            mouseMove(grid, firstCell.x + firstCell.width / 2,
                      firstCell.y + firstCell.height / 2)
            tryCompare(grid, "hoveredIndex", 0)
            tryCompare(grid, "currentIndex", 0)
            verify(!grid.keyboardSelectionActive,
                   "mouse movement must become the active visual selection")
            verify(grid.activeFocus, "mouse hover must not steal keyboard focus")
            const firstHighlight = T.findFirst(firstCell,
                                               o => o.objectName === "folderStackCellHighlight")
            verify(firstHighlight && firstHighlight.visible && firstHighlight.hoverActive)

            mouseMove(grid, grid.width / 2, grid.cellHeight + 12)
            tryCompare(grid, "hoveredIndex", -1)
            verify(!firstHighlight.visible,
                   "leaving a cell must remove its hover highlight")
            verify(grid.activeFocus, "pointer exit must not clear grid keyboard focus")

            keyClick(Qt.Key_Right)
            tryCompare(grid, "currentIndex", 1)
            verify(grid.keyboardSelectionActive,
                   "keyboard input after pointer exit must restore keyboard selection styling")
            verify(secondHighlight.visible && secondHighlight.keyboardActive)
            stack.popupControl.close()
        }

        function test_folderStackGridThemeSelectionColorsKeepTextContrast() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack-contrast",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            verify(stack)
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            const popup = stack.popupControl
            verify(popup.gridHoverTintOpacity > 0 && popup.gridHoverTintOpacity < 0.15)
            verify(popup.gridSelectionTintOpacity > popup.gridHoverTintOpacity
                   && popup.gridSelectionTintOpacity < 0.3)
            verify(popup.gridCellInset >= 6 && popup.gridCellRadius >= 10
                   && popup.gridCellRadius <= 12)
            verify(BadgeTextColor.contrastRatio(popup.gridHoverForegroundColor,
                                                popup.gridHoverSurfaceColor) >= 4.5,
                   "hover text must keep WCAG normal-text contrast against its themed fill")
            verify(BadgeTextColor.contrastRatio(popup.gridSelectionForegroundColor,
                                                popup.gridSelectionSurfaceColor) >= 4.5,
                   "keyboard-selection text must keep WCAG normal-text contrast against its themed fill")
            compare(popup.gridHoverSurfaceColor,
                    BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.highlightColor,
                                                       popup.gridHoverTintOpacity),
                                             popup.surfaceColor),
                    "the hover tint must derive from the active KDE theme color")
            stack.popupControl.close()
        }

        function test_folderStackGridKeyboardEnterNavigatesAndOpensFiles() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack-keyboard",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem")
            verify(stack)
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            const grid = T.findFirst(stack.popupControl.contentItem,
                                     o => o.objectName === "folderStackGrid")
            verify(grid)
            grid.forceActiveFocus()
            keyClick(Qt.Key_Right)
            tryCompare(grid, "currentIndex", 1)
            keyClick(Qt.Key_Left)
            tryCompare(grid, "currentIndex", 0)
            keyClick(Qt.Key_Return)
            tryVerify(() => stack.popupCurrentUrl === "file:///tmp/Nested", 2000,
                      "Enter on a directory must navigate into it")
            verify(stack.popupVisible, "Enter on a directory must navigate without closing the grid")

            keyClick(Qt.Key_Return)
            tryVerify(() => !stack.popupVisible,
                      2000, "Enter on a file must open it and close the popup")
        }

        function test_folderStackPopupAnchorsToMagnifiedItemGeometry() {
            DockView.edge = 1
            DockSettings.magnificationMode = 1
            DockSettings.maxZoomFactor = 1.7
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const delegate = items(dock)[0]
            const stack = T.findFirst(delegate, o => o.objectName === "folderStackItem")
            verify(stack)
            hoverItem(delegate)
            tryVerify(() => delegate.currentScale > 1.05,
                      2000, "Spring Magnification must transform the Folder Stack anchor")

            const restGeometry = delegate.delegateGeometryTarget
            verify(restGeometry)
            const restOrigin = restGeometry.mapToItem(dock, 0, 0)
            const expectedRestCenter = Qt.point(
                restOrigin.x + (restGeometry.width - stack.iconSize) / 2 + stack.iconSize / 2,
                restOrigin.y + (restGeometry.height - stack.iconSize) / 2 + stack.iconSize / 2)
            const mappedCenter = stack.mapToItem(dock, stack.width / 2, stack.height / 2)
            stack.openStack()
            tryVerify(() => stack.popupPendingOpen || stack.popupVisible)
            tryVerify(() => stack.popupVisible)
            fuzzyCompare(stack.popupAnchorCenter.x, expectedRestCenter.x, 0.5)
            fuzzyCompare(stack.popupAnchorCenter.y, expectedRestCenter.y, 0.5)
            verify(stack.popupTransformedAnchorRect.width > stack.popupAnchorRect.width,
                   "diagnostics must preserve the live Spring-transformed anchor separately")
            verify(Math.abs(stack.popupAnchorCenter.x - mappedCenter.x) > 0.5
                   || Math.abs(stack.popupAnchorCenter.y - mappedCenter.y) > 0.5,
                   "the native popup must use the stable rest slot while Spring is active")
            fuzzyCompare(stack.popupWidth, stack.popupControl.requestedPopupWidth, 0.5)
            fuzzyCompare(stack.popupHeight, stack.popupControl.requestedPopupHeight, 0.5)
            fuzzyCompare(stack.popupScreenX + stack.popupWidth / 2,
                         stack.popupAnchorScreenRect.x + stack.popupAnchorScreenRect.width / 2,
                         0.5)
            const springOverflow = DockSettings.iconSize * (DockSettings.maxZoomFactor - 1)
            const previewClearance = DockSettings.previewDockGap + springOverflow
            fuzzyCompare(stack.popupScreenY + stack.popupHeight - stack.popupShadowMargin,
                         stack.popupAnchorScreenRect.y - previewClearance,
                         1.0)
            stack.popupControl.close()
        }

        function test_folderStackPopupRestoresSpringOnlyWhenWaylandPointerReturns() {
            DockView.edge = 1
            DockSettings.magnificationMode = 1
            DockSettings.maxZoomFactor = 1.7
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const delegate = items(dock)[0]
            const stack = T.findFirst(delegate, o => o.objectName === "folderStackItem")
            verify(stack)
            hoverItem(delegate)
            tryVerify(() => delegate.currentScale > 1.05)
            DockView.pointerInside = true
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            stack.popupControl.close()
            tryVerify(() => dock.hoveredIndex === 0,
                      2000, "closing over a dock focused by Wayland must re-hit-test the saved pointer")
            tryVerify(() => delegate.currentScale > 1.05,
                      2000, "Spring Magnification must resume at the saved in-dock pointer")

            stack.openStack()
            tryVerify(() => stack.popupVisible)
            DockView.pointerInside = false
            stack.popupControl.close()
            tryVerify(() => dock.hoveredIndex === -1,
                      2000, "closing after focus moved outside must not restore stale hover")
            verify(!dock._zoomActive,
                   "the dock must not stay magnified when Wayland focus is outside")
        }

        function test_folderStackIconUsesMaximumZoomSourceSize() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem" && o.visible)
            verify(stack)
            compare(stack.folderIconSourceSize.width,
                    Math.ceil(stack.iconSize * stack.maxZoomFactor * Screen.devicePixelRatio))
            compare(stack.folderIconSourceSize.height,
                    Math.ceil(stack.iconSize * stack.maxZoomFactor * Screen.devicePixelRatio))
            compare(stack.popupCardColor.a, 1,
                    "the folder popup surface is opaque so text contrast is independent of the window behind it")
            verify(BadgeTextColor.contrastRatio(stack.popupControl.foregroundColor,
                                                stack.popupCardColor) >= 4.5)
        }

        function test_folderStackUsesDockTooltipAndHidesItForPopup() {
            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-named-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "Project archive",
                taskIndex: -1,
                IsLauncher: true,
                isPinned: true,
            })
            const dock = makeDock(1)
            const stack = T.findFirst(dock, o => o.objectName === "folderStackItem" && o.visible)
            const tooltip = T.findFirst(dock, o => o.objectName === "dockTooltip")
            verify(stack)
            verify(tooltip)
            compare(stack.displayName, "Project archive")
            hoverItem(stack)
            tryVerify(() => tooltip.visible)
            stack.openStack()
            tryVerify(() => stack.popupVisible)
            verify(!tooltip.visible, "the shared dock tooltip must not cover an open folder popup")
        }

        function test_mixedPinnedReorderUsesStableEntryIds() {
            addMixedPinnedRows()
            let dock = makeDock(4)
            compare(entryOrder().join(","),
                    "task:opencode,folder:/tmp/projects,task:kate,running:terminal")

            verify(dock.reorderDockItems(0, 2), "the selected pinned app should move by stable ID")
            compare(entryOrder().join(","),
                    "folder:/tmp/projects,task:kate,task:opencode,running:terminal")

            verify(dock.reorderDockItems(0, 2), "the folder stack should move across pinned apps")
            compare(entryOrder().join(","),
                    "task:kate,task:opencode,folder:/tmp/projects,running:terminal")
            compare(entryOrder()[3], "running:terminal",
                    "moving pinned entries must not reorder an unpinned running task")

            const repeatedMoves = [[2, 0], [0, 1], [1, 2], [2, 0], [1, 0], [0, 2],
                                   [2, 1], [0, 2], [1, 0], [0, 1], [1, 2], [2, 0]]
            for (const move of repeatedMoves) {
                const sourceId = DockModel.dockPresentationModel.entryIdForDockIndex(move[0])
                const targetId = DockModel.dockPresentationModel.entryIdForDockIndex(move[1])
                verify(sourceId && targetId && sourceId !== targetId)
                verify(dock.reorderDockEntries(sourceId, targetId),
                       "repeated mixed reorder must resolve both endpoints by stable ID")
                const ids = []
                for (let i = 0; i < DockModel.dockPresentationModel.rowCount(); ++i)
                    ids.push(DockModel.dockPresentationModel.entryIdForDockIndex(i))
                compare(new Set(ids).size, ids.length,
                        "repeated moves must not duplicate presentation IDs")
                compare(ids[3], "running:terminal",
                        "the unpinned TaskManager row must stay after the pinned zone")

            }
        }

        function test_combinedTaskZonesAllowCrossZoneTaskReorder() {
            addMixedPinnedRows()
            DockSettings.separateLaunchers = false
            let dock = makeDock(4)
            const sourceId = DockModel.dockPresentationModel.entryIdForDockIndex(3)
            const targetId = DockModel.dockPresentationModel.entryIdForDockIndex(0)

            verify(dock.reorderDockEntries(sourceId, targetId),
                   "combined pinned/running mode should delegate cross-zone task moves to TaskManager")
            const moves = DockActions.callsTo("moveTask")
            compare(moves.length, 1)
            compare(moves[0].args[0], 3)
            compare(moves[0].args[1], 0)
        }

        function test_folderStackMouseStartsInternalDragAndDoesNotOpenPopup() {
            addMixedPinnedRows()
            let dock = makeDock(4)
            let rows = items(dock)
            let stack = T.findFirst(dock, o => o.objectName === "folderStackItem" && o.visible)
            verify(stack)
            const start = stack.mapToItem(stage, stack.width / 2, stack.height / 2)
            const target = rows[0].mapToItem(stage, rows[0].width / 2, rows[0].height / 2)

            mousePress(stage, start.x, start.y, Qt.LeftButton)
            tryVerify(() => dock._dragPending, 1500, "Folder Stack press must reach the dock drag handler")
            compare(dock._dragSourceIndex, 1, "the stack must remain the source row throughout the press")
            wait(350)
            verify(dock._dragPending)
            verify(!stack.popupVisible, "holding to drag must not open the folder popup")
            mouseMove(stage, start.x + (DockView.isVertical ? 0 : 12),
                      start.y + (DockView.isVertical ? 12 : 0), -1, Qt.LeftButton)
            tryVerify(() => dock._dragActive)
            mouseMove(stage, target.x, target.y, -1, Qt.LeftButton)
            compare(dock._dragTargetIndex, 0, "the first app must remain the selected drop target")
            mouseRelease(stage, target.x, target.y, Qt.LeftButton)
            tryVerify(() => entryOrder()[0] === "folder:/tmp/projects", 2000,
                      "dragging the Folder Stack before the first app should persist that order")
            compare(entryOrder()[3], "running:terminal")

        }

        function test_iconSizeAndSpacingDriveLayout_data() {
            return [
                { tag: "defaults", size: 40, spacing: 13 },
                { tag: "small-tight", size: 32, spacing: 0 },
                { tag: "large-wide", size: 72, spacing: 16 },
            ]
        }

        function test_iconSizeAndSpacingDriveLayout(data) {
            DockSettings.iconSize = data.size
            DockSettings.iconSpacing = data.spacing
            addTasks(["A", "B", "C"])
            let its = items(makeDock(3))
            for (let i = 0; i < 3; i++) compare(its[i].width, data.size)
            tryCompare(its[1], "x", its[0].x + data.size + data.spacing)
            tryCompare(its[2], "x", its[1].x + data.size + data.spacing)
            compare(its[0].y, its[1].y)
        }

        function test_contentPaddingAndAlignment_data() {
            const alignments = [0, 1, 2]
            const rows = []
            for (const edge of dockEdges()) {
                for (const alignment of alignments) {
                    rows.push({ tag: edge.tag + "-alignment-" + alignment, edge: edge.edge, alignment: alignment })
                }
            }
            return rows
        }

        function test_contentPaddingAndAlignment(data) {
            DockView.edge = data.edge
            DockSettings.iconSize = 32
            DockSettings.iconSpacing = 5
            DockSettings.contentPaddingLeft = 11
            DockSettings.contentPaddingRight = 19
            DockSettings.contentPaddingTop = 7
            DockSettings.contentPaddingBottom = 23
            DockSettings.contentAlignment = data.alignment
            DockSettings.maxZoomFactor = 1.6
            addTasks(["A", "B", "C"])

            const dock = makeDock(3)
            const its = items(dock)
            const row = its[0].parent
            const panel = row.parent
            const vertical = data.edge >= 2
            const primaryExtent = vertical ? row.animatedContentHeight : row.animatedContentWidth
            const primaryAvailable = vertical ? panel.height : panel.width
            const primaryLeading = vertical ? DockSettings.contentPaddingTop : DockSettings.contentPaddingLeft
            const primaryTrailing = vertical ? DockSettings.contentPaddingBottom : DockSettings.contentPaddingRight
            const freeSpace = Math.max(0, primaryAvailable - primaryLeading - primaryTrailing - primaryExtent)
            const alignmentFactor = data.alignment === 0 ? 0 : data.alignment === 2 ? 1 : 0.5
            const expectedPrimaryStart = primaryLeading + freeSpace * alignmentFactor
            fuzzyCompare(vertical ? row.y : row.x, expectedPrimaryStart, 0.5)

            const crossLeading = vertical ? DockSettings.contentPaddingLeft : DockSettings.contentPaddingTop
            const crossTrailing = vertical ? DockSettings.contentPaddingRight : DockSettings.contentPaddingBottom
            const crossAvailable = vertical ? panel.width : panel.height
            const crossExtent = vertical ? row.implicitWidth : row.implicitHeight
            const expectedCrossStart = crossLeading + Math.max(0, crossAvailable - crossLeading - crossTrailing - crossExtent) / 2
            fuzzyCompare(vertical ? row.x : row.y, expectedCrossStart, 0.5)

            const visible = drawnBounds(its[1])
            const panelRect = DockVisibility.panelRect
            verify(visible.width > 0 && visible.height > 0)
            verify(panelRect.width > 0 && panelRect.height > 0)
            hoverItem(its[1])
            tryVerify(() => its[1].zoomScale > 1.0, 1000, "padding disabled parabolic zoom")
        }

        function test_transparentPaddingDoesNotExpandInteractionRegion_data() {
            let rows = []
            const edges = dockEdges()
            for (let i = 0; i < edges.length; ++i) {
                rows.push({ tag: `edge-${edges[i].edge}-screen`, edge: edges[i].edge, position: 0 })
                rows.push({ tag: `edge-${edges[i].edge}-interior`, edge: edges[i].edge, position: 1 })
            }
            return rows
        }

        function test_transparentPaddingDoesNotExpandInteractionRegion(data) {
            DockView.edge = data.edge
            DockSettings.runningIndicatorPosition = data.position
            DockView.backgroundStyleType = 1
            DockSettings.contentPaddingLeft = 32
            DockSettings.contentPaddingRight = 32
            DockSettings.contentPaddingTop = 32
            DockSettings.contentPaddingBottom = 32
            DockSettings.iconSize = 24
            addTasks(["A"])
            const dock = makeDock(1)
            settleDeferredCallbacks()
            const background = DockVisibility.panelRect
            const interactive = DockVisibility.interactionRect
            verify(background.width > 0 && background.height > 0)
            verify(interactive.width > 0 && interactive.height > 0)
            if (data.edge < 2)
                verify(interactive.width < background.width, "transparent horizontal padding intercepted input")
            else
                verify(interactive.height < background.height, "transparent vertical padding intercepted input")
            if (data.edge < 2)
                compare(interactive.height, DockSettings.iconSize, "indicator reserve expanded the input region")
            else
                compare(interactive.width, DockSettings.iconSize, "indicator reserve expanded the input region")

            const row = items(dock)[0].parent
            DockSettings.contentAlignment = 0
            tryVerify(() => {
                const updated = DockVisibility.interactionRect
                const screenSideAfter = data.edge === 1 || data.edge === 3
                const indicatorBeforeIcon = !(data.position === 0 ? screenSideAfter : !screenSideAfter)
                const reserve = DockSettings.runningIndicatorSize * 2
                const expectedX = row.parent.x + row.x + (data.edge >= 2 && indicatorBeforeIcon ? reserve : 0)
                const expectedY = row.parent.y + row.y + (data.edge < 2 && indicatorBeforeIcon ? reserve : 0)
                return Math.abs(updated.x - expectedX) <= 1 && Math.abs(updated.y - expectedY) <= 1
            }, 1000, "transparent interaction region did not follow the aligned icon row")
        }

        function test_spacingChangeRelayoutsLive() {
            addTasks(["A", "B"])
            let its = items(makeDock(2))
            tryCompare(its[1], "x", its[0].x + DockSettings.iconSize + DockSettings.iconSpacing)
            DockSettings.iconSpacing = 12
            tryCompare(its[1], "x", its[0].x + DockSettings.iconSize + 12)
            DockSettings.iconSize = 64
            tryCompare(its[1], "x", its[0].x + 64 + 12)
        }

        function test_panelHugsContent() {
            addTasks(["A", "B", "C", "D", "E"])
            makeDock(5)
            // Panel = content + the independently configured side insets.
            let expected = Math.max(5 * DockSettings.iconSize + 4 * DockSettings.iconSpacing
                                    + DockSettings.contentPaddingLeft + DockSettings.contentPaddingRight,
                                    Kirigami.Units.gridUnit * 6)
            tryVerify(() => DockVisibility.panelRect.width === expected, 3000,
                      "panel width " + DockVisibility.panelRect.width + " != " + expected)
            let before = DockVisibility.panelRect.width
            DockSettings.iconSize = 64
            tryVerify(() => DockVisibility.panelRect.width > before, 3000, "panel did not grow with icon size")
        }

        function test_panelIsCenteredOnBottomEdge() {
            addTasks(["A", "B", "C"])
            makeDock(3)
            tryVerify(() => Math.abs(DockVisibility.panelRect.x + DockVisibility.panelRect.width / 2 - stage.width / 2) < 1)
            verify(DockVisibility.panelRect.y + DockVisibility.panelRect.height <= stage.height)
            verify(DockVisibility.panelRect.y > stage.height / 2, "bottom dock panel must sit in the lower half")
        }

        function test_verticalDockStacksItems() {
            DockView.edge = 2
            addTasks(["A", "B", "C"])
            let its = items(makeDock(3))
            compare(its[0].height, DockSettings.iconSize)
            compare(its[0].x, its[1].x)
            tryCompare(its[1], "y", its[0].y + DockSettings.iconSize + DockSettings.iconSpacing)
            tryCompare(DockVisibility.panelRect, "width", DockSettings.iconSize
                       + DockSettings.runningIndicatorSize * 2
                       + DockSettings.contentPaddingLeft + DockSettings.contentPaddingRight)
            verify(DockVisibility.panelRect.x < stage.width / 2, "left dock panel must sit on the left")
        }
        function test_separatedLayoutToggleKeepsSpacingAndSecondaryCenter_data() {
            return dockEdges()
        }

        function test_separatedLayoutToggleKeepsSpacingAndSecondaryCenter(data) {
            DockView.edge = data.edge
            DockSettings.iconSize = 32
            DockSettings.iconSpacing = 7
            DockSettings.maxZoomFactor = 1
            DockSettings.previewEnabled = false
            DockSettings.separateLaunchers = false
            addSeparatedTasks()
            let dock = makeDock(4)
            let its = items(dock)
            let ordinary = its.map(it => drawnBounds(it))
            let ordinarySpan = primaryNear(ordinary[3]) + primaryExtent(ordinary[3]) - primaryNear(ordinary[0])
            compare(ordinarySpan, 4 * 32 + 3 * 7)
            verify(!separatorOf(dock).visible)

            DockSettings.separateLaunchers = true
            tryVerify(() => {
                let before = drawnBounds(its[1])
                let after = drawnBounds(its[2])
                let first = drawnBounds(its[0])
                let last = drawnBounds(its[3])
                let leadingPadding = DockView.isVertical
                    ? DockSettings.contentPaddingTop : DockSettings.contentPaddingLeft
                let trailingPadding = DockView.isVertical
                    ? DockSettings.contentPaddingBottom : DockSettings.contentPaddingRight
                // Center alignment centers within the asymmetric padded area.
                let contentCenter = (DockView.isVertical ? stage.height : stage.width) / 2
                    + (leadingPadding - trailingPadding) / 2
                return Math.abs(primaryNear(after) - primaryNear(before) - primaryExtent(before) - 15) < 1e-6
                    && Math.abs((primaryNear(first) + primaryNear(last) + primaryExtent(last)) / 2
                        - contentCenter) < 1e-6
            }, 3000, "separated row did not settle into its centered stroke slot")
            verify(separatorOf(dock).visible)
            verifySeparatorClearance(dock, its)
            let resting = its.map(it => drawnBounds(it, dock))
            verifyRestProxies(dock, its, resting)
            for (let i = 0; i < its.length; ++i)
                fuzzyCompare(secondaryCenter(drawnBounds(its[i])), secondaryCenter(ordinary[i]), 1e-6)

            // The nearest-drop midpoint and trailing hit edge both move with
            // the running zone. Raw Flow coordinates select the wrong task.
            dock._dragSourceIndex = 2
            let a = drawnBounds(its[2], dock)
            let b = drawnBounds(its[3], dock)
            let midpoint = (primaryNear(a) + primaryExtent(a) / 2
                + primaryNear(b) + primaryExtent(b) / 2) / 2
            compare(dock.computeDropIndex(midpoint - 1), 2)
            compare(dock.computeDropIndex(midpoint + 1), 3)
            if (!DockView.isVertical) {
                let panelBounds = drawnBounds(its[2], its[2].parent.parent)
                compare(dock.computeExternalDropIndex(panelBounds.x + panelBounds.width - 1), 2)
                compare(dock.computeExternalDropIndex(panelBounds.x - 1), -1)
            }
            let drawn = drawnBounds(its[2])
            let point = DockView.isVertical
                ? Qt.point(drawn.x + drawn.width / 2, drawn.y + drawn.height - 1)
                : Qt.point(drawn.x + drawn.width - 1, drawn.y + drawn.height / 2)
            mouseMove(stage, point.x, point.y)
            tryCompare(dock, "hoveredIndex", 2)
            mouseMove(stage, -1, -1)

            DockSettings.separateLaunchers = false
            tryVerify(() => {
                let first = drawnBounds(its[0])
                let last = drawnBounds(its[3])
                return Math.abs(primaryNear(last) + primaryExtent(last) - primaryNear(first) - ordinarySpan) < 1e-6
                    && Math.abs(primaryNear(first) - primaryNear(ordinary[0])) < 1e-6
            }, 3000, "ordinary row did not return after disabling separation")
            verify(!separatorOf(dock).visible)
            for (let i = 0; i < its.length; ++i)
                fuzzyCompare(secondaryCenter(drawnBounds(its[i])), secondaryCenter(ordinary[i]), 1e-6)
        }

        function test_singleZoneAndEmptyModelHaveNoSeparatorSlot_data() {
            return [
                { tag: "no-pinned", edge: 1, count: 4, pinned: 0 },
                { tag: "only-pinned-vertical", edge: 2, count: 4, pinned: 4 },
                { tag: "empty-model", edge: 1, count: 0, pinned: 0 },
            ]
        }

        function test_singleZoneAndEmptyModelHaveNoSeparatorSlot(data) {
            DockView.edge = data.edge
            DockSettings.iconSize = 32
            DockSettings.iconSpacing = 7
            DockSettings.maxZoomFactor = 1
            for (let i = 0; i < data.count; ++i)
                addTasks(["Task " + i], { IsLauncher: i < data.pinned })
            DockModel.pinnedTaskCount = data.pinned
            let dock = makeDock(data.count)
            let its = items(dock)
            let ordinary = its.map(it => drawnBounds(it))
            DockSettings.separateLaunchers = true
            wait(Kirigami.Units.longDuration + 50)
            verify(!separatorOf(dock).visible)
            for (let i = 0; i < its.length; ++i) {
                let actual = drawnBounds(its[i])
                fuzzyCompare(primaryNear(actual), primaryNear(ordinary[i]), 1e-6)
                fuzzyCompare(secondaryCenter(actual), secondaryCenter(ordinary[i]), 1e-6)
            }
            let primaryPadding = DockView.isVertical
                ? DockSettings.contentPaddingTop + DockSettings.contentPaddingBottom
                : DockSettings.contentPaddingLeft + DockSettings.contentPaddingRight
            let expected = Math.max(data.count === 0 ? 0 : data.count * 32 + (data.count - 1) * 7,
                                    0) + primaryPadding
            expected = Math.max(expected, Kirigami.Units.gridUnit * 6)
            tryVerify(() => Math.abs(primaryExtent(DockVisibility.panelRect) - expected) <= 1)
        }

        function test_separatedParabolicHoverPreservesGapAndRestProxy_data() {
            return dockEdges()
        }

        function test_separatedParabolicHoverPreservesGapAndRestProxy(data) {
            DockSettings.singleWindowClickAction = 0
            DockView.edge = data.edge
            DockSettings.iconSize = 32
            DockSettings.iconSpacing = 7
            DockSettings.separateLaunchers = true
            DockSettings.previewEnabled = false
            addSeparatedTasks()
            let dock = makeDock(4)
            let its = items(dock)
            let resting = its.map(it => drawnBounds(it, dock))
            verifyRestProxies(dock, its, resting)
            // Qt's synthetic pointer uses integer coordinates, while the
            // centered odd-width row has half-pixel rest centres. A rounded
            // cursor must follow the Gaussian, not be treated as its peak.
            let restCenter = centerOf(its[2])
            let cursor = Qt.point(Math.round(restCenter.x), Math.round(restCenter.y))
            mouseMove(stage, cursor.x, cursor.y)
            tryCompare(dock, "hoveredIndex", 2)
            let panel = its[2].parent.parent
            let distance = panel.zoomCursor - its[2].itemCenterX
            verify(Math.abs(distance) <= 0.5, "actual cursor left the rounded rest-centre pixel")
            let sigma = DockSettings.iconSize * 1.2
            let expectedScale = 1 + (DockSettings.maxZoomFactor - 1)
                * Math.exp(-distance * distance / (sigma * sigma))
            tryVerify(() => Math.abs(its[2].currentScale - expectedScale) < 1e-9,
                      2000, "rounded pointer did not reach its expected Gaussian scale")
            verifySeparatorClearance(dock, its)
            verifyRestProxies(dock, its, resting)
            let drawn = drawnBounds(its[2])
            let point = Qt.point(drawn.x + drawn.width / 2, drawn.y + drawn.height / 2)
            mouseClick(stage, point.x, point.y, Qt.LeftButton)
            let activations = DockActions.callsTo("activate")
            compare(activations[activations.length - 1].args[0], 2)
            mouseMove(stage, -1, -1)
            for (let it of its)
                tryCompare(it, "currentOffset", 0)
            verifyRestProxies(dock, its, resting)
        }


        // --- Pointer-driven zoom through main.qml's hit testing ---

        function test_hoverZoomsItemUnderPointer() {
            addTasks(["A", "B", "C", "D", "E"])
            let dock = makeDock(5)
            let its = items(dock)
            hoverItem(its[2])
            tryCompare(dock, "hoveredIndex", 2)
            compare(dock.hoveredName, "C")
            tryCompare(its[2], "currentScale", DockSettings.maxZoomFactor)
            fuzzyCompare(its[1].zoomScale, its[3].zoomScale, 1e-6)
            verify(its[1].zoomScale > its[0].zoomScale && its[0].zoomScale > 1.0)
            compare(its[2].z, 1)
            compare(its[1].z, 0)
        }

        function test_springZoomVisualAndClickGeometryStayTogether() {
            DockSettings.magnificationMode = 1
            DockSettings.singleWindowClickAction = 0
            addTasks(["A", "B", "C", "D", "E"])
            let dock = makeDock(5)
            let its = items(dock)
            hoverItem(its[2])
            tryCompare(dock, "hoveredIndex", 2)
            tryVerify(() => its[2].currentScale > 1.05,
                      2000, "spring magnification did not move the hovered icon")

            // The pointer-driven hit test reads the same currentScale/currentOffset
            // that DockItem uses to draw, so a click at the visible icon center
            // must still activate that exact window while the spring is moving.
            const visible = drawnBounds(its[2], dock)
            mouseClick(stage, visible.x + visible.width / 2,
                       visible.y + visible.height / 2, Qt.LeftButton)
            const activations = DockActions.callsTo("activate")
            compare(activations[activations.length - 1].args[0], 2)
        }

        function test_springReentryFromOppositeSideUsesNewCursorImmediately() {
            DockSettings.previewEnabled = false
            DockSettings.magnificationMode = 1
            addTasks(["A", "B", "C", "D", "E", "F", "G"])
            const dock = makeDock(7)
            const its = items(dock)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            hoverItem(its[0])
            tryCompare(dock, "hoveredIndex", 0)
            tryVerify(() => panel.zoomAmount > 0.98)

            mouseMove(stage, -1, -1)
            tryCompare(dock, "hoveredIndex", -1)
            tryCompare(panel, "zoomAmount", 0.0, 3000)

            const target = centerOf(its[6])
            mouseMove(stage, target.x, target.y)
            compare(panel.layoutCursor, panel.zoomCursor,
                    "fresh entry must not interpolate the cursor across intermediate icons")
            verify(panel.mouseInside,
                   "the dock should resume its hover zone before the fade completes")
            tryVerify(() => panel.zoomAmount > 0.05)
        }

        function test_springFastReentryKeepsFadingAmplitudeAndSnapsCursor() {
            DockSettings.previewEnabled = false
            DockSettings.magnificationMode = 1
            addTasks(["A", "B", "C", "D", "E", "F", "G"])
            const dock = makeDock(7)
            const its = items(dock)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            hoverItem(its[0])
            tryCompare(dock, "hoveredIndex", 0)
            tryVerify(() => panel.zoomAmount > 0.98)

            mouseMove(stage, -1, -1)
            tryCompare(dock, "hoveredIndex", -1)
            tryVerify(() => panel.zoomAmount > 0.05 && panel.zoomAmount < 0.95,
                      1000, "exit should be fading when the pointer returns")
            const fadingAmount = panel.zoomAmount

            const target = centerOf(its[6])
            mouseMove(stage, target.x, target.y)
            tryVerify(() => panel.mouseInside,
                      1000, "the dock should resume its hover zone before the fade completes")
            compare(panel.layoutCursor, panel.zoomCursor,
                    "fast re-entry must re-anchor before showing the new zoom center")
            verify(panel.zoomAmount > 0.05,
                   "re-entry must preserve the visible amplitude instead of resetting it")
            verify(Math.abs(panel.zoomAmount - fadingAmount) < 0.15,
                   "re-entry must continue the amount spring without a scale jump")
        }

        function test_springReentryUsesMouseAreaEnterWhenPreviewKeepsOldZoomState() {
            DockSettings.previewEnabled = false
            DockSettings.magnificationMode = 1
            DockSettings.zoomStyle = 1
            addTasks(["A", "B", "C", "D", "E", "F", "G"])
            const dock = makeDock(7)
            const its = items(dock)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            hoverItem(its[0])
            tryCompare(dock, "hoveredIndex", 0)
            tryVerify(() => panel.zoomAmount > 0.98)

            // The real dock intentionally keeps its zoom anchor while moving
            // from the dock to a visible preview surface. A later physical
            // MouseArea enter must still re-anchor from that entry sample.
            PreviewController.visible = true
            const amountBeforeLeave = panel.zoomAmount
            mouseMove(stage, -1, -1)
            tryCompare(dock, "_pointerOnDock", false)
            compare(panel.mouseInside, true,
                    "a visible preview preserves the old zoom region during exit")

            const target = centerOf(its[6])
            const localTarget = Qt.point(panel.x + its[6].itemCenterX, target.y)
            // Drive the same QML handler used by MouseArea.onEntered. The
            // visible test popup may own native input, so QTest cannot deliver
            // a physical motion event through that second surface reliably.
            dock._handleDockPointerEntered(localTarget.x, localTarget.y)
            tryCompare(dock, "hoveredIndex", 6)
            compare(panel.layoutCursor, panel.zoomCursor,
                    "MouseArea entry must re-anchor before hit testing the distant icon")
            verify(Math.abs(panel.zoomAmount - amountBeforeLeave) < 0.15,
                   "entry must preserve the ongoing amplitude spring")
            PreviewController.visible = false
        }

        function test_springCursorStillInterpolatesDuringInDockMovement() {
            DockSettings.previewEnabled = false
            DockSettings.magnificationMode = 1
            addTasks(["A", "B", "C", "D", "E", "F", "G"])
            const dock = makeDock(7)
            const its = items(dock)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            hoverItem(its[0])
            tryCompare(dock, "hoveredIndex", 0)
            tryVerify(() => panel.zoomAmount > 0.98)
            const previousCursor = panel.layoutCursor

            const target = centerOf(its[6])
            mouseMove(stage, target.x, target.y)
            tryCompare(dock, "hoveredIndex", 6)
            const targetCursor = panel.zoomCursor
            const initialDistance = Math.abs(previousCursor - targetCursor)
            verify(initialDistance > 0.01,
                   "ordinary in-dock movement should keep spatial spring interpolation")
            wait(20)
            const currentDistance = Math.abs(panel.layoutCursor - targetCursor)
            verify(currentDistance > 0.01 && currentDistance < initialDistance,
                   "spatial spring should interpolate toward the new in-dock target")
        }

        function panelEdges() {
            let r = DockVisibility.panelRect
            return { left: r.x, right: r.x + r.width }
        }

        // Parabolic (default): the magnified row pushes neighbours aside and the
        // reported dock background grows by the row's growth, evenly on both
        // sides for a middle icon, then returns to its rest extent.
        function test_parabolicHoverGrowsBackgroundAndPushesNeighbours() {
            addTasks(["A", "B", "C", "D", "E"])
            let dock = makeDock(5)
            let its = items(dock)
            let rest = panelEdges()
            hoverItem(its[2])
            tryCompare(its[2], "currentScale", DockSettings.maxZoomFactor)
            let growth = 0
            for (let it of its) growth += DockSettings.iconSize * (it.zoomScale - 1)
            let zoomed = panelEdges()
            // Integer rect, rounded outward: at most 1 px per side.
            verify(Math.abs((rest.left - zoomed.left) - growth / 2) <= 1, "left edge grew by " + (rest.left - zoomed.left) + ", expected " + growth / 2)
            verify(Math.abs((zoomed.right - rest.right) - growth / 2) <= 1, "right edge grew by " + (zoomed.right - rest.right) + ", expected " + growth / 2)
            for (let i = 0; i + 1 < its.length; i++) {
                let a = its[i], b = its[i + 1]
                let aRight = a.itemCenterX + a.currentOffset + a.width * a.currentScale / 2
                let bLeft = b.itemCenterX + b.currentOffset - b.width * b.currentScale / 2
                verify(Math.abs((bLeft - aRight) - DockSettings.iconSpacing) < 1e-6, "gap " + i + " is " + (bLeft - aRight))
            }
            verify(its[0].currentOffset < 0 && its[4].currentOffset > 0, "outer icons not pushed aside")

            mouseMove(stage, stage.width / 2, 2)
            for (let it of its) tryCompare(it, "currentOffset", 0)
            tryVerify(() => panelEdges().left === rest.left && panelEdges().right === rest.right, 2000, "background did not return to rest")
        }

        // In place: icons magnify over their neighbours; nothing moves and the
        // background keeps its rest extent.
        function test_inPlaceHoverKeepsBackgroundAndPositions() {
            DockSettings.zoomStyle = 1
            addTasks(["A", "B", "C", "D", "E"])
            let dock = makeDock(5)
            let its = items(dock)
            let rest = panelEdges()
            hoverItem(its[2])
            tryCompare(its[2], "currentScale", DockSettings.maxZoomFactor)
            for (let it of its) compare(it.currentOffset, 0)
            compare(panelEdges().left, rest.left)
            compare(panelEdges().right, rest.right)
            // Leaving eases zoomAmount out: every icon settles back at rest.
            mouseMove(stage, stage.width / 2, 2)
            for (let it of its) tryCompare(it, "currentScale", 1.0)
            for (let it of its) compare(it.currentOffset, 0)
        }

        function test_zoomSettlesWhenPointerLeavesPanel() {
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            hoverItem(its[1])
            tryCompare(its[1], "currentScale", DockSettings.maxZoomFactor)
            // Far above the panel's zoom zone.
            mouseMove(stage, stage.width / 2, 2)
            tryCompare(dock, "hoveredIndex", -1)
            for (let it of its) tryCompare(it, "currentScale", 1.0)
        }

        function test_zoomDisabledByUnitFactor() {
            DockSettings.maxZoomFactor = 1.0
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            hoverItem(its[1])
            tryCompare(dock, "hoveredIndex", 1)
            for (let it of its) compare(it.currentScale, 1.0)
        }

        function test_showHideOffsetUsesEachDockEdge_data() {
            return [
                { tag: "top", edge: 0, axis: "y" },
                { tag: "bottom", edge: 1, axis: "y" },
                { tag: "left", edge: 2, axis: "x" },
                { tag: "right", edge: 3, axis: "x" },
            ]
        }

        function test_showHideOffsetUsesEachDockEdge(data) {
            addTasks(["A", "B"])
            DockSettings.dockShowHideAnimationDuration = 80
            DockSettings.dockShowHideAnimationEnabled = true
            DockView.edge = data.edge
            const dock = makeDock(2)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            tryCompare(panel, "visibilityOffset", 0)
            const expected = panel.hiddenEdgeOffset
            DockVisibility.dockVisible = false
            tryVerify(() => Math.abs(panel.visibilityOffset - expected) < 0.1,
                      1000, "hide offset did not reach the off-screen edge " + data.edge)
            if (data.axis === "y")
                compare(panel.y, panel.restY + panel.visibilityOffset)
            else
                compare(panel.x, panel.restX + panel.visibilityOffset)
        }

        function test_showHideAnimationCanBeDisabled() {
            addTasks(["A"])
            DockSettings.dockShowHideAnimationEnabled = false
            DockView.edge = 1
            const dock = makeDock(1)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)
            DockSettings.dockShowHideAnimationEnabled = false
            DockVisibility.dockVisible = true
            tryCompare(panel, "visibilityOffset", 0)
            DockVisibility.dockVisible = false
            compare(panel.visibilityOffset, panel.hiddenEdgeOffset)
        }

        function test_showHideAnimationReversesFromItsCurrentPosition() {
            addTasks(["A"])
            DockSettings.dockShowHideAnimationDuration = 220
            DockSettings.dockShowHideAnimationEnabled = true
            DockView.edge = 1
            DockVisibility.dockVisible = true
            const dock = makeDock(1)
            const panel = T.findFirst(dock, o => o.objectName === "dockPanel")
            verify(panel)

            DockVisibility.dockVisible = false
            wait(50)
            verify(panel.visibilityOffset > 0 && panel.visibilityOffset < panel.hiddenEdgeOffset,
                   "hide animation should be between its visible and hidden positions")
            DockVisibility.dockVisible = true
            tryCompare(panel, "visibilityOffset", 0, 1000)
        }

        function test_pointerReturnCancelsPendingPreviewHide() {
            addTasks(["Window"])
            const dock = makeDock(1)
            PreviewController.visible = true
            PreviewController.hidePreviewDelayed()
            const cancellations = PreviewController.callsTo("cancelHide").length

            DockView.pointerInside = true
            tryVerify(() => PreviewController.callsTo("cancelHide").length > cancellations)
            verify(PreviewController.visible,
                   "returning the pointer to the dock must not hide the preview")
        }

        // Easing curves of ZoomAnimationProfile's easing indices (Qt's formulas),
        // mirroring tst_dockitem_zoom.qml.
        function ease(index, t) {
            switch (index) {
            case 0: return t
            case 1: return t * t * t
            case 2: return 1.0 - Math.pow(1.0 - t, 3)
            case 4: return -(Math.cos(Math.PI * t) - 1.0) / 2.0
            default: return t < 0.5 ? 4.0 * t * t * t : 1.0 - Math.pow(-2.0 * t + 2.0, 3) / 2.0
            }
        }

        // Every intermediate zoomAmount sample must sit on the configured
        // curve and — where the two curves separate — closer to it than to the
        // other direction's easing.
        function verifyAmountTimeline(probe, from, to, easingIndex, otherEasingIndex) {
            verify(probe.samples.length >= 2,
                   "configured duration must produce intermediate zoomAmount frames")
            let discriminating = 0
            for (const sample of probe.samples) {
                let expected = from + (to - from) * ease(easingIndex, sample.progress)
                fuzzyCompare(sample.amount, expected, 1e-2,
                    "zoomAmount " + sample.amount + " off the configured curve (" + expected
                    + ") at timeline progress " + sample.progress)
                let wrong = from + (to - from) * ease(otherEasingIndex, sample.progress)
                if (Math.abs(wrong - expected) > 0.08) {
                    discriminating++
                    verify(Math.abs(sample.amount - wrong) > Math.abs(sample.amount - expected),
                           "zoomAmount " + sample.amount + " fits the wrong easing better at progress "
                           + sample.progress)
                }
            }
            verify(discriminating >= 1, "no sample landed where the two easing curves separate")
        }

        // The Custom preset must drive the PRODUCTION dockPanel Behavior
        // (src/qml/main.qml), not only the DockItemRow fixture: hover eases
        // zoomAmount in on the configured zoom-in duration/easing and back out
        // on the zoom-out ones.
        function test_customZoomTimingDrivesProductionDock() {
            // Keep the pointer exit a clean zoom-out: no preview popup.
            DockSettings.previewEnabled = false
            DockSettings.zoomAnimationPreset = 4
            DockSettings.zoomInDuration = 600
            DockSettings.zoomInEasing = 1   // Ease in (InCubic)
            DockSettings.zoomOutDuration = 400
            DockSettings.zoomOutEasing = 2  // Ease out (OutCubic)
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            // Delegates are dockRow (Flow) children; the Flow sits in
            // dockPanel — the same path
            // test_separatedParabolicHoverPreservesGapAndRestProxy uses for
            // zoomCursor.
            let panel = its[1].parent.parent
            verify(panel.zoomAmount !== undefined, "dockPanel not reachable through the delegate tree")
            compare(panel.zoomAmount, 0.0)

            // Effective durations honour Plasma's animation-speed scaling.
            let inMs = Math.round(DockSettings.zoomInDuration * Kirigami.Units.shortDuration / 100.0)
            let outMs = Math.round(DockSettings.zoomOutDuration * Kirigami.Units.shortDuration / 100.0)
            if (inMs === 0 && outMs === 0)
                skip("Plasma Instant animation speed: no zoom timeline to sample")

            // Zoom in: a linear probe started in the same turn reports the
            // timeline fraction; zoomAmount must trace InCubic, not OutCubic.
            let inProbe = createTemporaryObject(zoomProbeComponent, tc, { targetPanel: panel })
            let inStart = Date.now()
            hoverItem(its[1])
            inProbe.start(inMs)
            tryCompare(dock, "hoveredIndex", 1)
            tryCompare(inProbe, "finished", true, inMs + 3000)
            tryCompare(panel, "zoomAmount", 1.0)
            let inElapsed = Date.now() - inStart
            if (inMs > 0) {
                verifyAmountTimeline(inProbe, 0.0, 1.0, 1, 2)
                verify(inElapsed >= inMs * 0.8 && inElapsed <= inMs + 3000,
                       "zoom-in took " + inElapsed + " ms, expected ≈ " + inMs + " ms")
            } else {
                compare(panel.zoomAmount, 1.0, "0 ms zoom-in must snap synchronously")
            }

            // Zoom out: zoomAmount must trace the OutCubic decay, not InCubic.
            let outProbe = createTemporaryObject(zoomProbeComponent, tc, { targetPanel: panel })
            let outStart = Date.now()
            mouseMove(stage, stage.width / 2, 2)  // far above the panel's zoom zone
            outProbe.start(outMs)
            tryCompare(outProbe, "finished", true, outMs + 3000)
            tryCompare(panel, "zoomAmount", 0.0)
            let outElapsed = Date.now() - outStart
            if (outMs > 0) {
                verifyAmountTimeline(outProbe, 1.0, 0.0, 2, 1)
                verify(outElapsed >= outMs * 0.8 && outElapsed <= outMs + 3000,
                       "zoom-out took " + outElapsed + " ms, expected ≈ " + outMs + " ms")
            } else {
                compare(panel.zoomAmount, 0.0, "0 ms zoom-out must snap synchronously")
            }
            for (let it of its) tryCompare(it, "currentScale", 1.0)
        }

        function test_hoverReportsToVisibilityController() {
            addTasks(["A"])
            let dock = makeDock(1)
            hoverItem(items(dock)[0])
            tryCompare(DockVisibility, "hovered", true)
        }

        // --- Tooltip / preview trigger ---

        function test_launcherHoverShowsTooltipNotPreview() {
            DockModel.tasksModel.addTask({ display: "KDockW Launcher Fixture", IsWindow: false, IsLauncher: true })
            let dock = makeDock(1)
            hoverItem(items(dock)[0])
            tryVerify(() => T.findFirst(dock, o => o.text === "KDockW Launcher Fixture" && o.visible) !== null,
                      2000, "tooltip with the app name never appeared")
            verify(!PreviewController.visible)
        }

        function test_appNameTooltipClearsTheZoomedIcon_data() {
            const cases = []
            for (const edge of [0, 1, 2, 3]) {
                for (const state of ["launcher", "inactive-window", "active-window"]) {
                    cases.push({ tag: edge + "-" + state, edge, state })
                }
            }
            return cases
        }

        function test_appNameTooltipClearsTheZoomedIcon(data) {
            DockView.edge = data.edge
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 0
            if (data.state === "launcher") {
                DockModel.tasksModel.addTask({
                    display: "Tooltip launcher",
                    IsWindow: false,
                    IsLauncher: true,
                })
            } else {
                addTasks(["Tooltip window"], {
                    IsActive: data.state === "active-window",
                })
            }

            let dock = makeDock(1)
            let item = items(dock)[0]
            hoverItem(item)
            tryCompare(item, "currentScale", DockSettings.maxZoomFactor)
            let tooltip = dockTooltip(dock)
            tryCompare(tooltip, "visible", true)
            compare(PreviewController.visible, false)

            const bounds = drawnBounds(item, dock)
            const gap = tooltip.gapForItem(item)
            const panel = item.parent.parent
            verify(gap > Kirigami.Units.largeSpacing,
                   "the tooltip clearance should grow with the zoomed icon")
            if (data.edge === 0) {
                verify(tooltip.y >= bounds.y + bounds.height,
                       "top dock tooltip must clear the enlarged icon below the dock: tooltipY="
                       + tooltip.y + " iconBottom=" + (bounds.y + bounds.height)
                       + " scale=" + item.currentScale + " panelY=" + panel.y
                       + " panelHeight=" + panel.height + " gap=" + gap)
            } else if (data.edge === 1) {
                verify(tooltip.y + tooltip.height <= bounds.y,
                       "bottom dock tooltip must clear the enlarged icon above the dock")
            } else if (data.edge === 2) {
                verify(tooltip.x >= bounds.x + bounds.width,
                       "left dock tooltip must clear the enlarged icon")
            } else {
                verify(tooltip.x + tooltip.width <= bounds.x,
                       "right dock tooltip must clear the enlarged icon")
            }
            verify(tooltip.x >= 0 && tooltip.y >= 0
                   && tooltip.x + tooltip.width <= dock.width
                   && tooltip.y + tooltip.height <= dock.height,
                   "the complete tooltip rectangle must stay inside the dock surface")
            const expectedCrossExtent = data.edge === 2 || data.edge === 3
                ? tooltip.maxSideWidth
                : tooltip.height
            verify(DockView.tooltipReserve >= expectedCrossExtent
                   + tooltip.maximumGap + tooltip.shadowOverflow,
                   "the layer-shell reserve must include tooltip, max zoom gap and shadow")
        }

        function test_tooltipPlacementClampsPrimaryAxisAtScreenEdges() {
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 0
            addTasks(["A", "B", "C"])
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                let dock = makeDock(3)
                const edgeIndices = edge === 0 || edge === 1 ? [0, 2] : [0, 2]
                for (const index of edgeIndices) {
                    hoverItem(items(dock)[index])
                    tryCompare(dockTooltip(dock), "visible", true)
                    const tooltip = dockTooltip(dock)
                    verify(tooltip.x >= 0 && tooltip.y >= 0
                           && tooltip.x + tooltip.width <= dock.width
                           && tooltip.y + tooltip.height <= dock.height,
                           "tooltip at a dock endpoint must remain within the layer surface")
                    mouseMove(stage, -1, -1)
                    tryCompare(tooltip, "visible", false)
                }
                dock.destroy()
            }
        }

        function test_windowHoverOpensPreview() {
            addTasks(["A", "B"])
            let dock = makeDock(2)
            hoverItem(items(dock)[1])
            tryCompare(PreviewController, "visible", true)
            compare(PreviewController.parentIndex, 1)
        }

        function test_previewDisabledFallsBackToTooltip() {
            DockSettings.previewEnabled = false
            addTasks(["Konsole"])
            let dock = makeDock(1)
            hoverItem(items(dock)[0])
            tryVerify(() => T.findFirst(dock, o => o.text === "Konsole" && o.visible) !== null)
            verify(!PreviewController.visible)
        }

        function test_groupPreviewClickShowsPopupAndSuppressesTooltip() {
            // Grouped explicit preview must work independently of hover preview.
            DockSettings.previewEnabled = false
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            let dock = makeDock(1)
            let item = items(dock)[0]
            let c = hoverItem(item)
            let tooltip = dockTooltip(dock)
            tryVerify(() => tooltip && tooltip.visible, 2000,
                      "group tooltip never appeared before the click")
            verify(!PreviewController.visible)

            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            compare(PreviewController.parentIndex, 0)
            verify(!tooltip.visible, "explicit preview must hide the text tooltip")

            // Repeated clicks keep the same popup open rather than toggling it.
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            compare(PreviewController.parentIndex, 0)
            verify(!tooltip.visible)
        }

        function test_groupPreviewClickStopsDelayedTooltip() {
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 500
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            let dock = makeDock(1)
            let item = items(dock)[0]
            let c = hoverItem(item)
            let tooltip = dockTooltip(dock)

            // Click before the hover timer fires.
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            let deadline = Date.now() + DockSettings.previewHoverDelay + 100
            tryVerify(() => tooltip.visible || Date.now() >= deadline, 2000)
            verify(!tooltip.visible, "the delayed text tooltip reopened after explicit preview")
        }

        function test_groupPreviewClickReenterDuringHideKeepsTooltipHidden() {
            DockSettings.previewEnabled = false
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            let dock = makeDock(1)
            let item = items(dock)[0]
            let c = hoverItem(item)
            let tooltip = dockTooltip(dock)
            tryVerify(() => tooltip && tooltip.visible, 2000)

            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            verify(!tooltip.visible)

            // The mock keeps the preview surface alive during its delayed hide.
            mouseMove(stage, -1, -1)
            mouseMove(stage, c.x, c.y)
            let deadline = Date.now() + DockSettings.previewHoverDelay + 100
            tryVerify(() => tooltip.visible || Date.now() >= deadline, 2000)
            verify(!tooltip.visible, "re-entering while preview hide is pending must not overlap text")
        }

        function test_previewCloseWhilePointerOverItemRestartsTextTooltip() {
            DockSettings.previewEnabled = false
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            let dock = makeDock(1)
            let item = items(dock)[0]
            let c = hoverItem(item)
            let tooltip = dockTooltip(dock)
            tryVerify(() => tooltip && tooltip.visible, 2000)

            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            verify(!tooltip.visible)

            // Closing the preview while the pointer remains over the item must
            // resume the ordinary launcher/text tooltip path.
            PreviewController.hidePreview()
            tryCompare(tooltip, "visible", true, 2000)
        }

        // --- Context menu hover hold ---

        // Opens the mock menu the way production does: DockShell holds the
        // preview hidden (PreviewController::setHeld) while it is open.
        function openContextMenu() {
            DockContextMenu.open = true
            PreviewController.hidePreview()
        }

        // Hovers item 1 of three windows until its preview is shown, then
        // opens the menu and delivers the pointer events QtWayland produces
        // under the popup grab (a fake leave) plus motion over another icon.
        function holdHoverUnderContextMenu() {
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            let other = centerOf(its[0])
            hoverItem(its[1])
            tryCompare(its[1], "currentScale", DockSettings.maxZoomFactor)
            tryCompare(PreviewController, "visible", true)
            let panel = its[1].parent.parent
            let anchor = Qt.point(panel.mouseX, panel.mouseY)

            openContextMenu()
            mouseMove(stage, -1, -1)
            mouseMove(stage, other.x, other.y)
            return { dock: dock, its: its, panel: panel, anchor: anchor }
        }

        function test_contextMenuHoldsHoverAndZoom() {
            let s = holdHoverUnderContextMenu()
            let shows = PreviewController.callsTo("showPreview").length
            let deadline = Date.now() + DockSettings.previewHoverDelay + 200
            tryVerify(() => PreviewController.callsTo("showPreview").length > shows
                      || Date.now() >= deadline, 2000)

            compare(s.dock.hoveredIndex, 1)
            verify(s.dock._zoomActive)
            compare(s.panel.mouseX, s.anchor.x)
            compare(s.panel.mouseY, s.anchor.y)
            compare(s.its[1].currentScale, DockSettings.maxZoomFactor)
            compare(PreviewController.callsTo("showPreview").length, shows,
                    "a preview was requested while the context menu was open")
            verify(!PreviewController.visible)
            verify(!dockTooltip(s.dock).visible)
            compare(DockVisibility.hovered, true)
        }

        function test_contextMenuCloseWithPointerInsideResumesHover() {
            let s = holdHoverUnderContextMenu()
            let shows = PreviewController.callsTo("showPreview").length

            DockView.pointerInside = true
            DockContextMenu.open = false
            tryVerify(() => PreviewController.callsTo("showPreview").length > shows, 2000,
                      "the held item's preview did not return after the menu closed")
            let calls = PreviewController.callsTo("showPreview")
            compare(calls[calls.length - 1].args[0], 1)
            const item = s.its[1]
            const args = calls[calls.length - 1].args
            const geometry = item.previewAnchorGeometry()
            const centerInSurface = item.mapToItem(null, item.width / 2, item.height / 2)
            const extent = DockView.isVertical ? item.height : item.width
            const expectedSurfacePos = (DockView.isVertical ? centerInSurface.y : centerInSurface.x)
                - extent / 2
            compare(args[1], expectedSurfacePos,
                    "preview along-axis position stays in dock-surface scene coordinates")
            compare(args[3], geometry.restEdgeInSurface,
                    "preview cross-axis anchor uses the same dock-surface coordinate space")
            compare(geometry.coordinateSpace, "dock-surface-logical")
            compare(s.dock.hoveredIndex, 1)
            verify(s.dock._zoomActive)
            compare(s.panel.mouseX, s.anchor.x)
            compare(s.its[1].currentScale, DockSettings.maxZoomFactor)
            compare(DockVisibility.hovered, true)
        }

        function test_contextMenuCloseWithPointerOutsideReleasesHover() {
            let s = holdHoverUnderContextMenu()

            DockView.pointerInside = false
            DockContextMenu.open = false
            tryCompare(s.dock, "hoveredIndex", -1)
            verify(!s.dock._zoomActive)
            compare(s.panel.mouseX, -1)
            for (let it of s.its) tryCompare(it, "currentScale", 1.0)
            compare(DockVisibility.hovered, false)
        }

        // The pointer rests on item 1's preview (the preview keeps the dock
        // hovered), the Focus Dock shortcut starts keyboard navigation and
        // the Menu key opens the menu, whose hold hides that preview.
        function holdPreviewHoverUnderKeyboardMenu() {
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            hoverItem(its[1])
            tryCompare(PreviewController, "visible", true)
            mouseMove(stage, -1, -1) // onto the preview surface
            compare(DockVisibility.hovered, true, "the preview no longer keeps the dock hovered")
            DockVisibility.setKeyboardActive(true)
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Right)
            let selected = dock.hoveredIndex
            verify(selected >= 0, "keyboard navigation selected no item")
            tryCompare(its[selected], "currentScale", DockSettings.maxZoomFactor)
            openContextMenu()
            return { dock: dock, its: its, selected: selected }
        }

        function test_keyboardMenuCloseWithPointerOffDockReleasesPreviewHover() {
            let s = holdPreviewHoverUnderKeyboardMenu()

            DockView.pointerInside = false
            DockContextMenu.open = false
            compare(DockVisibility.hovered, false, "stale preview hover would keep the dock from hiding")
            verify(s.dock.keyboardNavigating)
            compare(s.dock.hoveredIndex, s.selected)
            compare(s.its[s.selected].currentScale, DockSettings.maxZoomFactor)
        }

        function test_keyboardMenuCloseWithPointerOnDockKeepsHover() {
            let s = holdPreviewHoverUnderKeyboardMenu()

            DockView.pointerInside = true
            DockContextMenu.open = false
            compare(DockVisibility.hovered, true)
            verify(s.dock.keyboardNavigating)
            compare(s.dock.hoveredIndex, s.selected)
        }

        // QtWayland sends no enter when the popup closes, so after a resume
        // Qt still thinks the pointer is outside the dock. A real compositor
        // leave then reaches no onExited and must end hover via pointerInside.
        function test_compositorLeaveAfterResumeReleasesStaleHover() {
            let s = holdHoverUnderContextMenu()
            // Last Qt event leaves the dock: the stale state after the grab.
            mouseMove(stage, -1, -1)
            DockView.pointerInside = true
            let shows = PreviewController.callsTo("showPreview").length
            DockContextMenu.open = false
            tryVerify(() => PreviewController.callsTo("showPreview").length > shows, 2000)
            compare(s.dock.hoveredIndex, 1)

            // Pointer jumps to another surface without moving over the dock.
            let hides = PreviewController.callsTo("hidePreviewDelayed").length
            DockView.pointerInside = false
            tryCompare(s.dock, "hoveredIndex", -1)
            verify(PreviewController.callsTo("hidePreviewDelayed").length > hides)
            // Production's delayed hide fires; the preview must stay closed.
            PreviewController.hidePreview()
            shows = PreviewController.callsTo("showPreview").length
            verify(!s.dock._zoomActive)
            compare(DockVisibility.hovered, false)
            wait(DockSettings.previewHoverDelay + 200)
            compare(PreviewController.callsTo("showPreview").length, shows,
                    "the preview reopened after the pointer left the dock")
            verify(!PreviewController.visible)
        }

        // Rows shifting under the held anchor re-run the hit test through
        // scale/geometry callbacks; none of them may move the held hover.
        function test_contextMenuHoldIgnoresGeometryHitTests() {
            let s = holdHoverUnderContextMenu()
            DockModel.tasksModel.removeTask(0)
            tryVerify(() => items(s.dock).length === 2, 2000)
            settleDeferredCallbacks()
            wait(100)  // delegateGeometryRefreshTimer and scale callbacks
            s.dock.updateHoveredItem()
            s.dock.trackPointer(-1, -1)

            compare(s.dock.hoveredIndex, 1)
            compare(s.dock.hoveredName, "B")
            verify(s.dock._zoomActive)
            compare(s.panel.mouseX, s.anchor.x)
            compare(s.panel.mouseY, s.anchor.y)
        }

        // "Close" on the last task from the menu: the window goes away after
        // the menu resumed hover with the pointer resting on the dock.
        function test_heldItemRemovedAfterResumeRehitsHover() {
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            hoverItem(its[2])
            tryCompare(its[2], "currentScale", DockSettings.maxZoomFactor)
            tryCompare(PreviewController, "visible", true)
            openContextMenu()
            mouseMove(stage, -1, -1)

            DockView.pointerInside = true
            DockContextMenu.open = false
            compare(dock.hoveredIndex, 2)
            // The resume reconciles, then restarts the held item's preview.
            let resumed = PreviewController.callsTo("showPreview").length
            tryVerify(() => PreviewController.callsTo("showPreview").length > resumed, 2000,
                      "the held item's preview did not return after the menu closed")
            let shows = PreviewController.callsTo("showPreview").length
            DockModel.tasksModel.removeTask(2)
            tryVerify(() => items(dock).length === 2, 2000)

            tryVerify(() => dock.hoveredIndex < 2, 2000,
                      "hover still points at the removed row")
            verify(dock.hoveredName !== "C")
            wait(DockSettings.previewHoverDelay + 200)
            verify(dock.hoveredIndex < 2)
            let tooltip = dockTooltip(dock)
            verify(!(tooltip.visible && dock.hoveredName === "C"),
                   "the removed task's tooltip was shown")
            let removed = PreviewController.callsTo("showPreview").slice(shows)
                .filter(c => c.args[0] >= 2)
            compare(removed.length, 0, "a preview was requested for the removed row")
        }

        // Rest-centre hit on the primary axis: the item whose slot now holds
        // a stage-space point the pointer never left.
        function itemUnderPoint(dock, panel, point) {
            let local = panel.mapFromItem(stage, point.x, point.y)
            let primary = DockView.isVertical ? local.y : local.x
            let best = -1
            let bestDist = Infinity
            for (let it of items(dock)) {
                let dist = Math.abs(primary - it.itemCenterX)
                if (dist < bestDist) { best = it.index; bestDist = dist }
            }
            return best
        }

        // Hovers `hover`, holds it under the context menu, removes `rows` (in
        // order) while held so the dock re-centres, then closes the menu with
        // the pointer still resting where it was.
        function resumeAfterHeldRemoval(names, hover, rows) {
            addTasks(names)
            let dock = makeDock(names.length)
            let its = items(dock)
            let panel = its[hover].parent.parent
            let pointer = hoverItem(its[hover])
            tryVerify(() => its[hover].currentScale >= DockSettings.maxZoomFactor - 0.001,
                      2000, "held item did not reach the configured zoom factor")
            tryCompare(PreviewController, "visible", true)
            openContextMenu()
            mouseMove(stage, -1, -1)

            for (let row of rows)
                DockModel.tasksModel.removeTask(row)
            tryVerify(() => items(dock).length === names.length - rows.length, 2000)
            settleDeferredCallbacks()
            wait(100)  // delegateGeometryRefreshTimer settles while held
            compare(dock.hoveredIndex, hover, "the hold moved the hover")

            let shows = PreviewController.callsTo("showPreview").length
            DockView.pointerInside = true
            DockContextMenu.open = false
            return { dock: dock, panel: panel, pointer: pointer, shows: shows }
        }

        // Hover B, remove C and D under the menu: the re-centred dock puts A
        // under the resting pointer, which the panel-local anchor misses.
        function test_resumeAfterHeldRecentreHitsItemUnderPointer() {
            let s = resumeAfterHeldRemoval(["A", "B", "C", "D"], 1, [3, 2])
            let expected = () => itemUnderPoint(s.dock, s.panel, s.pointer)
            tryVerify(() => expected() >= 0 && s.dock.hoveredIndex === expected(), 2000,
                      "hover did not follow the item under the resting pointer")
            let target = expected()
            verify(target !== 1, "fixture: re-centring must move another item under the pointer")
            compare(s.dock.hoveredName, items(s.dock)[target].displayName)

            tryVerify(() => PreviewController.callsTo("showPreview").slice(s.shows)
                      .some(c => c.args[0] === target), 2000,
                      "no preview for the item under the pointer")
            wait(DockSettings.previewHoverDelay + 200)
            compare(s.dock.hoveredIndex, target)
            let stray = PreviewController.callsTo("showPreview").slice(s.shows)
                .filter(c => c.args[0] !== target)
            compare(stray.length, 0, "a preview was requested for an item not under the pointer")
        }

        // Zero hover delay: the resume must not restart the preview for the
        // held index (now a shifted row) before reconciliation re-hits it.
        function test_resumeAtZeroDelayWaitsForReconcile() {
            DockSettings.previewHoverDelay = 0
            let s = resumeAfterHeldRemoval(["A", "B", "C", "D", "E"], 2, [1, 0])
            // Row 2 still exists (E) but is no longer under the pointer.
            compare(items(s.dock).length, 3)
            let expected = () => itemUnderPoint(s.dock, s.panel, s.pointer)
            tryVerify(() => expected() >= 0 && s.dock.hoveredIndex === expected(), 2000,
                      "hover did not follow the item under the resting pointer")
            let target = expected()
            verify(target !== 2, "fixture: the held index must now be a shifted row")

            tryVerify(() => PreviewController.callsTo("showPreview").slice(s.shows)
                      .some(c => c.args[0] === target), 2000,
                      "no preview for the item under the pointer")
            wait(200)
            let stray = PreviewController.callsTo("showPreview").slice(s.shows)
                .filter(c => c.args[0] !== target)
            compare(stray.length, 0, "a preview was requested for the stale row before reconciliation")
        }

        // The menu closes before the layout settles, then a row is inserted
        // and a geometry hit test runs while reconciliation is pending: hover
        // stays held until the reconcile, so neither the row insert's auto
        // preview nor the hit test acts on the held index, which the insert
        // turns into a valid but unrelated row (H).
        function test_reconcileWindowHoldsHoverThroughInsertAndHitTest() {
            DockSettings.previewHoverDelay = 0
            addTasks(["A", "B", "C", "D", "E", "F", "G"])
            let dock = makeDock(7)
            let its = items(dock)
            let panel = its[4].parent.parent
            let pointer = hoverItem(its[4])
            tryCompare(its[4], "currentScale", DockSettings.maxZoomFactor)
            tryCompare(PreviewController, "visible", true)
            openContextMenu()
            mouseMove(stage, -1, -1)

            for (let row of [2, 1, 0])
                DockModel.tasksModel.removeTask(row)
            let shows = PreviewController.callsTo("showPreview").length
            DockView.pointerInside = true
            DockContextMenu.open = false
            verify(dock._hoverHeld, "hover released before the post-menu reconcile")
            addTasks(["H"])
            dock.updateHoveredItem()
            compare(dock.hoveredIndex, 4, "the reconcile window moved the held hover")
            compare(PreviewController.callsTo("showPreview").length, shows,
                    "a preview was requested during the reconcile window")

            tryVerify(() => !dock._hoverHeld, 2000, "reconciliation never ran")
            tryCompare(dock, "hoveredIndex", 3, 2000)
            let target = itemUnderPoint(dock, panel, pointer)
            compare(target, 3, "fixture: G must sit under the resting pointer")
            compare(dock.hoveredName, "G")
            tryVerify(() => PreviewController.callsTo("showPreview").slice(shows)
                      .some(c => c.args[0] === target), 2000,
                      "no preview for the item under the pointer")
            wait(200)
            let stray = PreviewController.callsTo("showPreview").slice(shows)
                .filter(c => c.args[0] !== target)
            compare(stray.length, 0, "a preview was requested for a row not under the pointer")
        }

        // Real motion over the dock while the reconcile is pending ends it and
        // is tracked normally.
        function test_motionDuringReconcileWindowTracksPointer() {
            let s = holdHoverUnderContextMenu()
            // The held move already reached its[0]; Qt drops a move to the same spot.
            let other = centerOf(s.its[0])
            other.x += 1
            // Keep the layout refresh pending so the reconcile cannot run first.
            s.dock.scheduleDelegateGeometryRefresh()
            DockView.pointerInside = true
            DockContextMenu.open = false
            verify(s.dock._hoverReconciling)
            let shows = PreviewController.callsTo("showPreview").length

            mouseMove(stage, other.x, other.y)
            verify(!s.dock._hoverReconciling, "real motion did not end the reconcile window")
            verify(!s.dock._hoverHeld)
            tryCompare(s.dock, "hoveredIndex", 0, 2000)
            tryVerify(() => PreviewController.callsTo("showPreview").slice(shows)
                      .some(c => c.args[0] === 0), 2000,
                      "the tracked item's preview did not open")
            let stale = PreviewController.callsTo("showPreview").slice(shows)
                .filter(c => c.args[0] !== 0)
            compare(stale.length, 0, "a preview was requested for the held item after motion")
        }

        function test_fastLauncherTooltipAtZeroDelay() {
            DockSettings.previewHoverDelay = 0
            DockModel.tasksModel.addTask({
                display: "Fast Launcher",
                IsWindow: false,
                IsLauncher: true,
            })
            let dock = makeDock(1)
            hoverItem(items(dock)[0])
            tryCompare(dockTooltip(dock), "visible", true, 2000)
            verify(!PreviewController.visible)
        }

        function test_fastLauncherTooltipRecoversAfterPreviewClose() {
            DockSettings.previewHoverDelay = 0
            addTasks(["Window"])
            DockModel.tasksModel.addTask({
                display: "Fast Launcher",
                IsWindow: false,
                IsLauncher: true,
            })
            let dock = makeDock(2)
            let its = items(dock)
            hoverItem(its[0])
            tryCompare(PreviewController, "visible", true, 2000)
            hoverItem(its[1])
            tryVerify(() => its[1].currentScale >= DockSettings.maxZoomFactor - 0.001,
                      2000, "launcher did not reach the configured zoom factor")

            // Only recovery is asserted here. Overlap while a surface is
            // pending hide is covered by the separate explicit-preview test.
            PreviewController.hidePreview()
            tryCompare(dockTooltip(dock), "visible", true, 2000)
        }

        function test_previewClosePreservesPendingHoverDeadline() {
            DockSettings.previewHoverDelay = 1000
            // Keep the handoff target inside a stable hit region while A is
            // animating out. This test measures timer preservation, not the
            // extreme displacement produced by the global maximum zoom.
            DockSettings.maxZoomFactor = 1.3
            addTasks(["A", "B"])
            let dock = makeDock(2)
            let its = items(dock)
            hoverItem(its[0])
            tryCompare(PreviewController, "visible", true, 2000)
            compare(PreviewController.parentIndex, 0)

            let started = Date.now()
            hoverItem(its[1])
            tryCompare(dock, "hoveredIndex", 1, 2000)
            tryVerify(() => Date.now() - started >= 750, 2000)
            verify(PreviewController.visible && PreviewController.parentIndex === 0,
                "runner was too slow: B appeared before A could close while its hover was pending")

            // Most of B's original hover delay has elapsed before A closes.
            // Restarting that delay would make B wait a full second again.
            let closedAt = Date.now()
            PreviewController.hidePreview()
            let observedAfterClose = -1
            tryVerify(() => {
                if (!PreviewController.visible || PreviewController.parentIndex !== 1)
                    return false
                if (observedAfterClose < 0)
                    observedAfterClose = Date.now() - closedAt
                return true
            }, 3000, "B's hover preview never appeared after A closed")
            verify(observedAfterClose < 750,
                "closing A restarted B's pending hover delay: B appeared after "
                + observedAfterClose + " ms")
            verify(!dockTooltip(dock).visible)
        }

        function test_previewInvalidationDuringDragDoesNotReopenTooltip() {
            DockSettings.previewEnabled = false
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            addTasks(["Fallback"])
            let dock = makeDock(2)
            let item = items(dock)[0]
            let c = hoverItem(item)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)

            mousePress(stage, c.x, c.y, Qt.LeftButton)
            let delta = 20
            tryVerify(() => {
                mouseMove(stage, c.x + delta, c.y, -1, Qt.LeftButton)
                delta = delta === 20 ? 21 : 20
                return item.isDragSource
            }, 2000, "drag source visual feedback never appeared")
            PreviewController.hidePreview()
            DockModel.tasksModel.removeTask(0)
            tryVerify(() => items(dock).length === 1, 2000)
            let tooltip = dockTooltip(dock)
            let deadline = Date.now() + DockSettings.previewHoverDelay + 100
            tryVerify(() => tooltip.visible || PreviewController.visible || Date.now() >= deadline, 2000)
            verify(!tooltip.visible, "preview invalidation reopened tooltip during drag")
            verify(!PreviewController.visible, "preview invalidation reopened popup during drag")
            mouseRelease(stage, c.x + delta, c.y, Qt.LeftButton)
            tryVerify(() => items(dock).every(it => !it.isDragSource), 2000)
            verify(!PreviewController.visible)
        }

        function test_group0ClickDoesNotOpenPreview() {
            DockSettings.groupedWindowClickAction = 0
            DockSettings.previewEnabled = false
            addGroupTask()
            let dock = makeDock(1)
            let c = hoverItem(items(dock)[0])
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(PreviewController.visible, false)
        }

        function test_explicitWindowClickDismissesPreviewAndStaysDismissed_data() {
            return [
                { tag: "activate", singleAction: 0, groupedAction: 0, grouped: false, expectedCall: "activate" },
                { tag: "restore-or-minimize", singleAction: 1, groupedAction: 0, grouped: false, expectedCall: "activateOrMinimize" },
                { tag: "group-cycle", singleAction: 0, groupedAction: 0, grouped: true, expectedCall: "activate" },
            ]
        }

        function test_explicitWindowClickDismissesPreviewAndStaysDismissed(data) {
            DockSettings.singleWindowClickAction = data.singleAction
            DockSettings.groupedWindowClickAction = data.groupedAction
            if (data.grouped)
                addGroupTask("Click Group")
            else
                addTasks(["Click Window"])

            const dock = makeDock(1)
            const item = items(dock)[0]
            const point = hoverItem(item)
            tryCompare(PreviewController, "visible", true, 2000)
            const shownBeforeClick = PreviewController.callsTo("showPreview").length

            mouseClick(stage, point.x, point.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", false, 1000)
            compare(PreviewController.dismissedTaskIndex, 0)
            compare(DockActions.callsTo(data.expectedCall).length, 1)

            wait(DockSettings.previewHoverDelay + 150)
            compare(PreviewController.callsTo("showPreview").length, shownBeforeClick,
                    "the hover timer must not reopen the preview while the pointer stays on the clicked icon")
            verify(!PreviewController.visible)
        }

        function test_singleClickDoesNotOpenPreview() {
            DockSettings.singleWindowClickAction = 1
            DockSettings.groupedWindowClickAction = 1
            DockSettings.previewEnabled = false
            addTasks(["Single"])
            let dock = makeDock(1)
            let c = hoverItem(items(dock)[0])
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(PreviewController.visible, false)
        }

        function test_membershipTransitionsUseCurrentGroupingAction() {
            DockSettings.singleWindowClickAction = 1
            DockSettings.groupedWindowClickAction = 1
            DockSettings.previewEnabled = false
            let row = DockModel.tasksModel.addTask({
                display: "Adaptive",
                AppId: "adaptive",
                IsWindow: true,
                IsGroupParent: false,
            })
            DockModel.tasksModel.addChildTask(row, {
                display: "Adaptive child 1",
                IsWindow: true,
                IsActive: true,
            })
            let dock = makeDock(1)
            let c = hoverItem(items(dock)[0])

            // One child: single-window setting, so no explicit preview.
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(PreviewController.visible, false)

            // Two children: grouped setting, so the same click opens preview.
            DockModel.tasksModel.addChildTask(row, {
                display: "Adaptive child 2",
                IsWindow: true,
                IsActive: false,
            })
            DockModel.tasksModel.setTaskData(row, "IsGroupParent", true)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)

            // Back to one child: leave the popup and return to single behavior.
            PreviewController.hidePreview()
            DockModel.tasksModel.removeChildTask(row, 1)
            DockModel.tasksModel.setTaskData(row, "IsGroupParent", false)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(PreviewController.visible, false)
        }

        function test_nonLeftKeyboardAndDragNeverOpenPreview_data() {
            return [
                { tag: "single0-group0", single: 0, grouped: 0 },
                { tag: "single0-group1", single: 0, grouped: 1 },
                { tag: "single0-group2", single: 0, grouped: 2 },
                { tag: "single1-group0", single: 1, grouped: 0 },
                { tag: "single1-group1", single: 1, grouped: 1 },
                { tag: "single1-group2", single: 1, grouped: 2 },
            ]
        }

        function test_nonLeftKeyboardAndDragNeverOpenPreview(data) {
            DockSettings.singleWindowClickAction = data.single
            DockSettings.groupedWindowClickAction = data.grouped
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 1000
            addGroupTask()
            let dock = makeDock(1)
            let c = hoverItem(items(dock)[0])

            mouseClick(stage, c.x, c.y, Qt.MiddleButton)
            compare(PreviewController.visible, false)
            mouseClick(stage, c.x, c.y, Qt.RightButton)
            compare(PreviewController.visible, false)
            mouseWheel(stage, c.x, c.y, 0, 120)
            mouseWheel(stage, c.x, c.y, 0, -120)
            compare(PreviewController.visible, false)

            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Return)
            compare(PreviewController.visible, false)
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Space)
            compare(PreviewController.visible, false)

            // Hold and move far enough to become an internal drag. The left
            // release must not be reinterpreted as an explicit preview click.
            mouseMove(stage, c.x + 1, c.y)
            tryCompare(dock, "hoveredIndex", 0, 2000)
            mousePress(stage, c.x + 1, c.y, Qt.LeftButton)
            let delta = 20
            tryVerify(() => {
                mouseMove(stage, c.x + delta, c.y, -1, Qt.LeftButton)
                delta = delta === 20 ? 21 : 20
                return items(dock)[0].isDragSource
            }, 2000, "drag source visual feedback never appeared")
            mouseRelease(stage, c.x + delta, c.y, Qt.LeftButton)
            tryCompare(items(dock)[0], "isDragSource", false, 2000)
            compare(PreviewController.visible, false)
            verify(!dockTooltip(dock).visible)
        }

        function test_dragExitAndReentryReleaseDoesNotOpenPreview() {
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 1000
            DockSettings.groupedWindowClickAction = 1
            addGroupTask()
            let dock = makeDock(1)

            // Give the actual MouseArea a smaller surface so leaving it still
            // delivers events inside the visible test window.
            dock.anchors.fill = null
            dock.width = stage.width / 2
            dock.height = stage.height / 2
            dock.x = stage.width / 4
            dock.y = stage.height / 4
            let item = items(dock)[0]
            let settledCenter = null
            let settledSince = 0
            tryVerify(() => {
                let c = centerOf(item)
                let now = Date.now()
                let origin = dock.mapToItem(stage, 0, 0)
                let inside = c.x > origin.x && c.x < origin.x + dock.width
                    && c.y > origin.y && c.y < origin.y + dock.height
                if (settledCenter
                    && Math.abs(c.x - settledCenter.x) < 0.1
                    && Math.abs(c.y - settledCenter.y) < 0.1) {
                    settledSince = settledSince || now
                } else {
                    settledCenter = c
                    settledSince = now
                }
                return inside && now - settledSince >= 250
            }, 2000, "icon did not settle inside the test dock surface")

            let from = hoverItem(item)
            mousePress(stage, from.x, from.y, Qt.LeftButton)
            let delta = 20
            tryVerify(() => {
                mouseMove(stage, from.x + delta, from.y, -1, Qt.LeftButton)
                delta = delta === 20 ? 21 : 20
                return item.isDragSource
            }, 2000, "drag source visual feedback never appeared")

            let origin = dock.mapToItem(stage, 0, 0)
            let outside = dock.mapToItem(stage, -DockSettings.iconSize, dock.height / 2)
            verify(outside.x < origin.x)
            verify(outside.x >= 0 && outside.x < stage.width
                && outside.y >= 0 && outside.y < stage.height)
            mouseMove(stage, outside.x, outside.y, -1, Qt.LeftButton)
            tryCompare(item, "isDragSource", false, 2000)
            verify(!PreviewController.visible)
            verify(!dockTooltip(dock).visible)

            // The same held-button sequence returns to the icon and releases.
            // It is still a cancelled drag, not a fresh explicit-preview click.
            let reentry = centerOf(item)
            mouseMove(stage, reentry.x, reentry.y, -1, Qt.LeftButton)
            mouseRelease(stage, reentry.x, reentry.y, Qt.LeftButton)
            verify(!item.isDragSource)
            compare(PreviewController.visible, false)
            verify(!dockTooltip(dock).visible)

            // A new normal click must still open the group's explicit preview.
            let fresh = centerOf(item)
            mouseClick(stage, fresh.x, fresh.y, Qt.LeftButton)
            tryCompare(PreviewController, "visible", true, 2000)
            compare(PreviewController.parentIndex, 0)
            verify(!dockTooltip(dock).visible)
        }

        // --- Launch feedback ---

        function test_launchBounceDirectionAndIntensityForAllEdges_data() {
            return [
                { tag: "top", edge: 0, axis: "y", sign: 1 },
                { tag: "bottom", edge: 1, axis: "y", sign: -1 },
                { tag: "left", edge: 2, axis: "x", sign: 1 },
                { tag: "right", edge: 3, axis: "x", sign: -1 }
            ]
        }

        function test_launchBounceDirectionAndIntensityForAllEdges(data) {
            addTasks(["A"])
            const item = items(makeDock(1))[0]
            DockView.edge = data.edge
            compare(item._bounceProp, data.axis)
            compare(item._bounceTarget, data.sign * 15)
            DockSettings.launchBounceIntensity = 200
            compare(item._bounceTarget, data.sign * 20)
            DockSettings.iconSize = 80
            compare(item._bounceTarget, data.sign * 40)
        }

        function test_clickBounceIsShortAndDoesNotChangeHitGeometry() {
            addTasks(["A"])
            let item = items(makeDock(1))[0]
            const x = item.x, y = item.y, width = item.width, height = item.height
            item.startClickBounce()
            tryCompare(item, "clickBounceRunning", true)
            compare(item._clickBounceTarget, -4.8)
            compare(item.x, x)
            compare(item.y, y)
            compare(item.width, width)
            compare(item.height, height)
            tryCompare(item, "clickBounceRunning", false, 1000)
            const translate = findChild(item, "launchBounceTranslate")
            verify(translate)
            compare(translate.x, 0)
            compare(translate.y, 0)
        }

        function test_clickBounceDirectionUsesAllDockEdges_data() {
            return [
                { tag: "top", edge: 0, axis: "y", sign: 1 },
                { tag: "bottom", edge: 1, axis: "y", sign: -1 },
                { tag: "left", edge: 2, axis: "x", sign: 1 },
                { tag: "right", edge: 3, axis: "x", sign: -1 }
            ]
        }

        function test_clickBounceDirectionUsesAllDockEdges(data) {
            addTasks(["A"])
            const item = items(makeDock(1))[0]
            DockView.edge = data.edge
            compare(item._bounceProp, data.axis)
            compare(item._clickBounceTarget, data.sign * 4.8)
        }

        function test_runningTaskClickBouncesForActivateAndToggleActions() {
            addTasks(["A"], { IsActive: false })
            let dock = makeDock(1)
            let item = items(dock)[0]
            let c = centerOf(item)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(DockActions.callsTo("activate").length, 0)
            compare(DockActions.callsTo("activateOrMinimize").length, 1)
            verify(item.clickBounceRunning)
            wait(500)
            verify(!item.clickBounceRunning)

            DockActions.reset()
            DockSettings.singleWindowClickAction = 0
            c = centerOf(item)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(DockActions.callsTo("activate").length, 1)
            verify(item.clickBounceRunning)
        }

        function test_groupClickBounceOnlyForActivationOrMinimize() {
            addGroupTask()
            const dock = makeDock(1)
            const item = items(dock)[0]
            DockSettings.groupedWindowClickAction = 1
            let c = centerOf(item)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            compare(PreviewController.visible, true)
            verify(!item.clickBounceRunning)

            PreviewController.hidePreview()
            DockSettings.groupedWindowClickAction = 0
            c = centerOf(item)
            mouseClick(stage, c.x, c.y, Qt.LeftButton)
            verify(item.clickBounceRunning)
            compare(DockActions.callsTo("activate").length, 1)
        }

        function test_hoverDoesNotStartClickBounceAndLaunchHasPriority() {
            addTasks(["A"])
            const item = items(makeDock(1))[0]
            hoverItem(item)
            wait(100)
            verify(!item.clickBounceRunning)
            DockActions.taskLaunching(0)
            item.startClickBounce()
            verify(item.launching)
            verify(!item.clickBounceRunning)
            verify(item._launchBounceSession)
        }

        function test_clickBounceDefersAttentionAndHonorsDisableSetting() {
            addTasks(["A"], { IsActive: false, IsDemandingAttention: true })
            const item = items(makeDock(1))[0]
            verify(item._attentionPending)
            item.startClickBounce()
            verify(item.clickBounceRunning)
            verify(!item._showAttentionAnim)
            tryVerify(() => !item.clickBounceRunning && item._showAttentionAnim,
                      1500, "attention animation should resume after click feedback")

            DockSettings.clickBounceEnabled = false
            item.startClickBounce()
            verify(!item.clickBounceRunning)
        }

        function test_disablingLaunchBounceStopsCurrentMotion() {
            addTasks(["A"])
            const item = items(makeDock(1))[0]
            DockActions.taskLaunching(0)
            verify(item.launching)
            DockSettings.launchBounceEnabled = false
            compare(item._launchBounceSession, false)
            const translate = findChild(item, "launchBounceTranslate")
            verify(translate)
            compare(translate.x, 0)
            compare(translate.y, 0)
        }

        function test_attentionWaitsUntilLaunchBounceFinishes() {
            addTasks(["A"])
            const item = items(makeDock(1))[0]
            DockActions.taskLaunching(0)
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            verify(item._attentionPending)
            verify(!item._showAttentionAnim)
            DockModel.tasksModel.setTaskData(0, "ChildCount", 2)
            tryCompare(item, "launching", false)
            tryVerify(() => item._showAttentionAnim
                || (item._animationActive && item._attentionIndicatorActive),
                5000, "attention should start or remain visibly pending after launch motion")
        }

        function test_launchSignalBouncesRunningApp() {
            addTasks(["A", "B"])
            let dock = makeDock(2)
            let its = items(dock)
            DockActions.taskLaunching(1)
            verify(its[1].launching)
            verify(!its[0].launching)
            compare(its[1].accessibleDescription, "Starting")
            // No startup task arrives (TasksModel filters them for apps with a
            // window): launch state outlives the 500 ms handoff bridge, while
            // the animation stops after its five-cycle cap.
            tryCompare(its[1], "_launchBounceCount", 5, 8000)
            verify(its[1].launching)
            compare(its[1]._launchBounceSession, false)
            wait(700)
            compare(its[1]._launchBounceCount, 5)
            // Launch state ends when the new window joins the group.
            DockModel.tasksModel.setTaskData(1, "ChildCount", 2)
            tryCompare(its[1], "launching", false)
        }

        function test_launchBounceFinishesCurrentCycleWhenWindowAppears() {
            addTasks(["A"])
            let dock = makeDock(1)
            let item = items(dock)[0]
            DockActions.taskLaunching(0)
            tryCompare(item, "_launchBounceCount", 1, 3000)

            DockModel.tasksModel.setTaskData(0, "ChildCount", 2)
            tryCompare(item, "launching", false)
            verify(item._isWindow, "the launched window must remain represented as a running task")
            tryCompare(item, "_launchBounceCount", 2, 3000)
            wait(700)
            compare(item._launchBounceCount, 2)
            compare(item._launchBounceSession, false)
        }

        function test_repeatedLaunchRestartsBoundedBounce() {
            addTasks(["A"])
            let item = items(makeDock(1))[0]
            DockActions.taskLaunching(0)
            tryCompare(item, "_launchBounceCount", 1, 3000)

            DockActions.taskLaunching(0)
            compare(item._launchBounceCount, 0)
            tryCompare(item, "_launchBounceCount", 5, 8000)
            compare(item._launchBounceSession, false)
            verify(item.launching)
        }

        function test_simultaneousLaunchesHaveIndependentBounceLimits() {
            addTasks(["A", "B"])
            let its = items(makeDock(2))
            DockActions.taskLaunching(0)
            DockActions.taskLaunching(1)

            tryCompare(its[0], "_launchBounceCount", 5, 8000)
            tryCompare(its[1], "_launchBounceCount", 5, 8000)
            compare(its[0]._launchBounceSession, false)
            compare(its[1]._launchBounceSession, false)
            verify(its[0].launching)
            verify(its[1].launching)
        }

        function test_startupNotificationDoesNotRestartCappedBounce() {
            addTasks(["A"])
            let item = items(makeDock(1))[0]
            DockModel.tasksModel.setTaskData(0, "IsStartup", true)
            tryCompare(item, "_launchBounceCount", 5, 8000)
            verify(item.launching)
            compare(item._launchBounceSession, false)

            // A late startup-state transition must not start another set of
            // bounces after the visual limit has already been reached.
            wait(700)
            compare(item._launchBounceCount, 5)
            verify(item.launching)
        }

        function test_launchSignalOnActiveAppEndsWithoutNewWindow() {
            addTasks(["A"], { IsActive: true })
            let dock = makeDock(1)
            let item = items(dock)[0]
            DockActions.taskLaunching(0)
            verify(item.launching)
            // A single-instance app ignoring the request opens no window: the
            // no-op detection ends the feedback after the launch feedback timeout.
            wait(3000)
            verify(item.launching)
            tryCompare(item, "launching", false, 5000)
        }

        function test_launchSignalBouncesLauncherUntilItsWindowMaps() {
            // A pinned launcher with no startup task (a plain KWin session never
            // reports one): the click alone must drive the feedback, past the
            // 500 ms startup handoff, until the launcher row gives way to the app.
            DockModel.tasksModel.addTask({ display: "Launcher", IsWindow: false, IsLauncher: true })
            let item = items(makeDock(1))[0]
            DockActions.taskLaunching(0)
            verify(item.launching)
            compare(item.accessibleDescription, "Pinned, Starting")
            wait(1000)
            verify(item.launching, "launch feedback dropped before the app's window mapped")
        }

        function test_startupNotificationDrivesLaunchState() {
            addTasks(["A"])
            let item = items(makeDock(1))[0]
            DockModel.tasksModel.setTaskData(0, "IsStartup", true)
            tryCompare(item, "launching", true)
            // A new window appearing ends the launch state.
            DockModel.tasksModel.setTaskData(0, "IsStartup", false)
            DockModel.tasksModel.setTaskData(0, "ChildCount", 2)
            tryCompare(item, "launching", false)
        }

        // --- Keyboard navigation ---

        function test_keyboardNavigationMovesFocusAndReturnEndsNavigation() {
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            dock.startKeyboardNavigation()
            compare(dock.hoveredIndex, 0)
            verify(its[0].isKeyboardFocused)
            tryCompare(its[0], "currentScale", DockSettings.maxZoomFactor)
            keyClick(Qt.Key_Right)
            tryCompare(dock, "hoveredIndex", 1)
            verify(its[1].isKeyboardFocused && !its[0].isKeyboardFocused)
            keyClick(Qt.Key_Right)
            keyClick(Qt.Key_Right) // clamps at the last item
            tryCompare(dock, "hoveredIndex", 2)
            keyClick(Qt.Key_Left)
            tryCompare(dock, "hoveredIndex", 1)
            keyClick(Qt.Key_Return)
            compare(dock.keyboardNavigating, false)
            compare(dock.hoveredIndex, -1)
            for (let it of its) tryCompare(it, "currentScale", 1.0)
        }

        function test_keyboardEscapeEndsNavigation() {
            addTasks(["A", "B"])
            let dock = makeDock(2)
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Right)
            tryCompare(dock, "hoveredIndex", 1)
            keyClick(Qt.Key_Escape)
            tryCompare(dock, "keyboardNavigating", false)
            compare(DockVisibility.keyboardActive, false)
        }

        function test_pointerMotionOffDockEndsKeyboardNavigation() {
            addTasks(["A", "B"])
            let dock = makeDock(2)
            let its = items(dock)
            dock.startKeyboardNavigation()
            DockVisibility.setKeyboardActive(true)
            PreviewController.startPreviewKeyboardNav()
            verify(its[0].isKeyboardFocused)
            DockVisibility.pointerMovedDuringKeyboardNavigation()
            compare(dock.keyboardNavigating, false)
            compare(dock.hoveredIndex, -1)
            verify(!its[0].isKeyboardFocused)
            compare(DockVisibility.keyboardActive, false)
            compare(PreviewController.previewKeyboardActive, false)
            // Keys no longer navigate.
            keyClick(Qt.Key_Right)
            compare(dock.hoveredIndex, -1)
            for (let it of its) tryCompare(it, "currentScale", 1.0)
        }

        function test_keyboardVerticalDockUsesUpDown() {
            DockView.edge = 3
            addTasks(["A", "B"])
            let dock = makeDock(2)
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Right) // not a navigation key on a vertical dock
            compare(dock.hoveredIndex, 0)
            keyClick(Qt.Key_Down)
            tryCompare(dock, "hoveredIndex", 1)
        }

        function test_keyboardOpensPreviewForWindows() {
            addTasks(["A"])
            DockModel.tasksModel.addTask({ display: "Launcher", IsWindow: false })
            let dock = makeDock(2)
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Up) // bottom dock: Up opens the preview
            tryCompare(PreviewController, "visible", true)
            compare(PreviewController.parentIndex, 0)
            compare(PreviewController.previewKeyboardActive, true)
            keyClick(Qt.Key_Escape) // back to dock navigation, preview stays
            compare(PreviewController.previewKeyboardActive, false)
            compare(dock.keyboardNavigating, true)
            PreviewController.hidePreview()
            keyClick(Qt.Key_Right)
            tryCompare(dock, "hoveredIndex", 1)
            keyClick(Qt.Key_Up) // launcher: nothing to preview
            verify(!PreviewController.visible)
        }

        function test_keyboardThumbnailActivationSuppressesOnlyWhenPointerStillOnTask_data() {
            return [
                { tag: "pointer-on-dock", pointerOnDock: true },
                { tag: "pointer-outside-dock", pointerOnDock: false },
            ]
        }

        function test_keyboardThumbnailActivationSuppressesOnlyWhenPointerStillOnTask(data) {
            addTasks(["A"])
            let dock = makeDock(1)
            dock._pointerOnDock = data.pointerOnDock
            if (data.pointerOnDock) {
                dock.hoveredIndex = 0
            }
            dock.startKeyboardNavigation()
            keyClick(Qt.Key_Up) // bottom dock: open the grouped/single preview
            tryCompare(PreviewController, "visible", true)
            keyClick(Qt.Key_Return)
            const calls = PreviewController.callsTo("activatePreviewThumbnail")
            compare(calls.length, 1)
            compare(calls[0].args[0], data.pointerOnDock)
        }

        // --- Drag reorder and drop helpers ---

        function test_computeDropIndexPicksNearestIcon() {
            addTasks(["A", "B", "C", "D"])
            let dock = makeDock(4)
            let its = items(dock)
            for (let i = 0; i < its.length; i++) {
                let cx = its[i].mapToItem(dock, its[i].width / 2, 0).x
                compare(dock.computeDropIndex(cx), i)
                compare(dock.computeDropIndex(cx + its[i].width * 0.4), i)
            }
            compare(dock.computeDropIndex(-1000), 0)
            compare(dock.computeDropIndex(100000), 3)
        }

        function test_launcherUrlFromPlasmaTaskMime() {
            addTasks(["A"])
            let dock = makeDock(1)
            compare(dock.launcherUrlFromTaskMime(
                        ["application/x-orgkdeplasmataskmanager_taskbuttonitem",
                         "text/x-orgkdeplasmataskmanager_taskurl"],
                        "applications:org.kde.kate.desktop\n"),
                    "applications:org.kde.kate.desktop")
            compare(dock.launcherUrlFromTaskMime(
                        ["application/x-orgkdeplasmataskmanager_taskbuttonitem"], ""), "")
        }

        function test_externalDirectoryDropAddsFolderStack() {
            let dock = makeDock(0)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            let drop = {
                hasUrls: true,
                urls: [Qt.resolvedUrl("file:///tmp")],
                formats: [],
                accepted: false,
            }
            area.dropTargetIndex = -1
            area.processDrop(drop)
            verify(drop.accepted)
            compare(DockActions.callsTo("addFolderStack").length, 1)
            compare(DockActions.callsTo("addFolderStack")[0].args[0].toString(), "file:///tmp")
        }

        function test_externalFileDropOpensWithTargetApplication() {
            addTasks(["Editor"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            let drop = {
                hasUrls: true,
                urls: [Qt.resolvedUrl("file:///tmp/note.txt")],
                formats: [],
                accepted: false,
            }
            area.dropTargetIndex = 0
            area.processDrop(drop)
            verify(drop.accepted)
            compare(DockActions.callsTo("openUrlsWithTask").length, 1)
            compare(DockActions.callsTo("openUrlsWithTask")[0].args[0], 0)
        }

        function test_externalDropRejectsUnsupportedMimeAndFilesOnFolderStack() {
            let dock = makeDock(0)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            verify(!area.supportsDrag({ hasUrls: false, formats: ["image/png"], getDataAsString: function() { return "" } }))
            let unsupported = { hasUrls: false, urls: [], formats: ["image/png"], accepted: true }
            area.processDrop(unsupported)
            verify(!unsupported.accepted)

            let backgroundFileDrop = {
                hasUrls: true,
                urls: [Qt.resolvedUrl("file:///tmp/note.txt")],
                formats: [],
                accepted: true,
            }
            area.processDrop(backgroundFileDrop)
            verify(!backgroundFileDrop.accepted)

            DockModel.tasksModel.addTask({
                entryType: "folderStack",
                entryId: "fixture-stack",
                entryUrl: Qt.resolvedUrl("file:///tmp"),
                display: "tmp",
                taskIndex: -1,
                isPinned: true,
            })
            dock = makeDock(1)
            area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            let fileDrop = {
                hasUrls: true,
                urls: [Qt.resolvedUrl("file:///tmp/note.txt")],
                formats: [],
                accepted: true,
            }
            area.dropTargetIndex = 0
            area.processDrop(fileDrop)
            verify(!fileDrop.accepted)
            compare(DockActions.callsTo("openUrlsWithTask").length, 0)
        }

        function test_externalMultiFileHoverActivatesWithoutForwardingFiles() {
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            verify(area)
            const position = items(dock)[0].itemCenterX
            const files = ["file:///tmp/one.txt", "file:///tmp/two.txt"]
            area.updateActivationTarget({ hasUrls: true, urls: files, x: position, y: position })
            compare(area.activationTargetIndex, 0)
            wait(150)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
            wait(220)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 1)
            compare(DockActions.callsTo("activateWindowForExternalDrag")[0].args[0], 0)
            compare(DockActions.callsTo("openUrlsWithTask").length, 0)
            verify(!PreviewController.visible, "external drag hover must not open the window preview")

            // Additional motion over the same icon cannot activate it again.
            area.updateActivationTarget({ hasUrls: true, x: position, y: position })
            wait(350)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 1)
        }

        function test_externalDragLeavingIconCancelsPendingActivation() {
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            const position = items(dock)[0].itemCenterX
            area.updateActivationTarget({ hasUrls: true, x: position, y: position })
            wait(100)
            area.clearActivationTarget()
            wait(350)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
        }

        function test_externalDragWithoutFileUrlsDoesNotActivate() {
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            const position = items(dock)[0].itemCenterX
            area.updateActivationTarget({ hasUrls: false, x: position, y: position })
            wait(350)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
        }

        function test_externalDragEscapeCancellationStopsPendingActivation() {
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            const position = items(dock)[0].itemCenterX
            area.updateActivationTarget({ hasUrls: true, x: position, y: position })
            wait(100)
            // Qt delivers cancellation as DropArea.onExited; this is the same
            // cleanup path used when Escape cancels an external drag.
            area.clearActivationTarget()
            wait(350)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
        }

        function test_externalDragMovingBetweenIconsRestartsDelayForFinalTarget() {
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser", "Mail"])
            let dock = makeDock(2)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            const first = items(dock)[0].itemCenterX
            const second = items(dock)[1].itemCenterX
            area.updateActivationTarget({ hasUrls: true, x: first, y: first })
            wait(180)
            area.updateActivationTarget({ hasUrls: true, x: second, y: second })
            compare(area.activationTargetIndex, 1)
            wait(180)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
            wait(180)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 1)
            compare(DockActions.callsTo("activateWindowForExternalDrag")[0].args[0], 1)
        }

        function test_externalDragActivationCanBeDisabled() {
            DockSettings.activateWindowOnExternalDrag = false
            DockSettings.externalDragActivationDelay = 300
            addTasks(["Browser"])
            let dock = makeDock(1)
            let area = T.findFirst(dock, o => o.objectName === "externalDropArea")
            const position = items(dock)[0].itemCenterX
            area.updateActivationTarget({ hasUrls: true, x: position, y: position })
            wait(350)
            compare(DockActions.callsTo("activateWindowForExternalDrag").length, 0)
        }
        function test_separatedDragIndicatorUsesRunningRestSlots_data() {
            return dockEdges()
        }

        function test_separatedDragIndicatorUsesRunningRestSlots(data) {
            DockView.edge = data.edge
            DockSettings.iconSize = 32
            DockSettings.iconSpacing = 7
            DockSettings.maxZoomFactor = 1
            DockSettings.separateLaunchers = true
            DockSettings.previewEnabled = false
            addSeparatedTasks()
            let dock = makeDock(4)
            let its = items(dock)
            for (let direction of [{ from: 2, to: 3 }, { from: 3, to: 2 }]) {
                // The last drag ended at the next source without updating
                // hover. Leave the dock first so re-entry delivers a genuine
                // motion event instead of repeating an identical cursor point.
                mouseMove(stage, stage.width / 2, stage.height / 2)
                tryCompare(dock, "hoveredIndex", -1)
                let source = its[direction.from]
                tryCompare(source, "currentScale", 1)
                tryCompare(source, "currentOffset", 0)
                let sourceCenter = centerOf(source)
                let targetCenter = centerOf(its[direction.to])
                let from = Qt.point(Math.round(sourceCenter.x), Math.round(sourceCenter.y))
                let to = Qt.point(Math.round(targetCenter.x), Math.round(targetCenter.y))
                mouseMove(stage, from.x, from.y)
                tryCompare(dock, "hoveredIndex", direction.from)
                mousePress(stage, from.x, from.y, Qt.LeftButton)
                // Model a real hold: the production gesture arms at 300 ms,
                // then movement beyond its 10 px threshold starts the drag.
                wait(350)
                mouseMove(stage, from.x + (DockView.isVertical ? 0 : 12),
                          from.y + (DockView.isVertical ? 12 : 0), -1, Qt.LeftButton)
                tryCompare(source, "isDragSource", true)
                mouseMove(stage, to.x, to.y, -1, Qt.LeftButton)
                let indicator = null
                tryVerify(() => {
                    indicator = T.findFirst(dock, o => o.visible && o.color !== undefined
                        && primaryExtent(o) === 2
                        && (DockView.isVertical ? o.width : o.height) === DockSettings.iconSize)
                    return indicator !== null
                }, 2000, "real running-zone drag did not draw an insertion indicator")
                let targetBounds = drawnBounds(its[direction.to], dock)
                let marker = drawnBounds(indicator, dock)
                let expected = direction.to > direction.from
                    ? primaryNear(targetBounds) + primaryExtent(targetBounds) + DockSettings.iconSpacing / 2
                    : primaryNear(targetBounds) - DockSettings.iconSpacing / 2
                fuzzyCompare(primaryNear(marker) + primaryExtent(marker) / 2, expected, 1e-6)
                dock.forceActiveFocus()
                keyClick(Qt.Key_Escape)
                tryCompare(source, "isDragSource", false)
                mouseRelease(stage, to.x, to.y, Qt.LeftButton)
                verify(!indicator.visible)
            }
        }


        function test_isDesktopFileUrl_data() {
            return [
                { tag: "file-desktop", url: "file:///usr/share/applications/org.kde.kate.desktop", expect: true },
                { tag: "applications-scheme", url: "applications:org.kde.dolphin.desktop", expect: true },
                { tag: "plain-file", url: "file:///home/user/notes.txt", expect: false },
                { tag: "web", url: "https://kde.org", expect: false },
            ]
        }

        function test_isDesktopFileUrl(data) {
            addTasks(["A"])
            let dock = makeDock(1)
            compare(dock.isDesktopFileUrl(data.url), data.expect)
        }

        function test_escapeCancelsDragVisualFeedback() {
            DockSettings.previewEnabled = false
            addTasks(["A", "B", "C"])
            let dock = makeDock(3)
            let its = items(dock)
            let from = centerOf(its[0])
            let to = centerOf(its[2])
            mouseMove(stage, from.x, from.y)
            tryCompare(dock, "hoveredIndex", 0)
            mousePress(stage, from.x, from.y, Qt.LeftButton)
            let delta = 20
            tryVerify(() => {
                mouseMove(stage, from.x + delta, from.y, -1, Qt.LeftButton)
                delta = delta === 20 ? 21 : 20
                return its[0].isDragSource
            }, 2000, "drag source visual feedback never appeared")
            mouseMove(stage, to.x, to.y, -1, Qt.LeftButton)
            dock.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            tryCompare(its[0], "isDragSource", false, 2000)
            compare(DockVisibility.dragActive, false)
            compare(DockVisibility.interacting, false)
            // Moving with the button still held must not restart visual drag.
            mouseMove(stage, centerOf(its[1]).x, to.y, -1, Qt.LeftButton)
            verify(!its[0].isDragSource)
            mouseRelease(stage, centerOf(its[1]).x, to.y, Qt.LeftButton)
            verify(!PreviewController.visible)

            const beforeCancelledMoves = entryOrder().join(",")
            for (let attempt = 0; attempt < 3; ++attempt) {
                const source = centerOf(its[1])
                const target = centerOf(its[0])
                mouseMove(stage, source.x, source.y)
                mousePress(stage, source.x, source.y, Qt.LeftButton)
                let nudge = 18
                tryVerify(() => {
                    mouseMove(stage, source.x + nudge, source.y, -1, Qt.LeftButton)
                    nudge = nudge === 18 ? 19 : 18
                    return its[1].isDragSource
                }, 2000, "repeated drag attempt did not reach active state")
                mouseMove(stage, target.x, target.y, -1, Qt.LeftButton)
                keyClick(Qt.Key_Escape)
                tryCompare(its[1], "isDragSource", false, 2000)
                compare(DockVisibility.dragActive, false)
                compare(entryOrder().join(","), beforeCancelledMoves,
                        "cancelling must never persist a partial reorder")
                mouseRelease(stage, target.x, target.y, Qt.LeftButton)
            }
        }

        // Samples dockPanel.zoomAmount on Qt's shared animation clock, not
        // after a wall-clock sleep: a linear reference animation started in the
        // same turn as the zoom transition reports the timeline fraction each
        // frame (same pattern as tst_dockitem_zoom.qml's durationProbeComponent).
        Component {
            id: zoomProbeComponent
            Item {
                id: probe
                property var targetPanel
                property int duration: 0
                property real progress: 0.0
                property var samples: []
                property bool finished: false
                function start(ms) {
                    finished = false
                    samples = []
                    duration = ms
                    reference.start()
                }
                onProgressChanged: {
                    if (progress <= 0.0 || progress >= 1.0) return
                    // Let both animations update before observing the panel.
                    Qt.callLater(function() {
                        if (probe.progress > 0.0 && probe.progress < 1.0)
                            probe.samples.push({
                                progress: probe.progress,
                                amount: probe.targetPanel.zoomAmount,
                            })
                    })
                }
                NumberAnimation {
                    id: reference
                    target: probe
                    property: "progress"
                    from: 0.0
                    to: 1.0
                    duration: probe.duration
                    onFinished: probe.finished = true
                }
            }
        }
    }
}
