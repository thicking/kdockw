// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// The real PreviewPopup.qml + PreviewThumbnail.qml: thumbnail model built
// from the task tree, incremental updates, activation/close, geometry.
// PipeWire/ScreencastingRequest are inert mocks (no live frames).
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import kdockw.test 1.0
import "../../src/qml" as KDockW
import "../../src/qml/BadgeTextColor.js" as BadgeTextColor
import "../../src/qml/PreviewBorderColor.js" as PreviewBorderColor
import "TestUtils.js" as T

// TestCase is an invisible Item: visual fixtures live under `stage`, a visible
// sibling, so effective visibility, layout and pointer delivery are real.
Item {
    id: root
    width: 900
    height: 400

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "PreviewPopup"
        when: windowShown

        Component {
            id: popupComponent
            KDockW.PreviewPopup {}
        }

        function init() {
            KDockWMocks.resetAll()
            IconDiagnostics.previewClipMode = ""
            IconDiagnostics.previewSourceMode = ""
            // Row 0: single-window app. Row 1: grouped app with three windows.
            DockModel.tasksModel.addTask({ display: "Kate", IsWindow: true, IsActive: true, WinIdList: ["kate-1"] })
            DockModel.tasksModel.addTask({ display: "Konsole", IsWindow: true, WinIdList: ["k-1", "k-2", "k-3"] })
            DockModel.tasksModel.addChildTask(1, { display: "Konsole 1", IsActive: true, WinIdList: ["k-1"] })
            DockModel.tasksModel.addChildTask(1, { display: "Konsole 2", WinIdList: ["k-2"] })
            DockModel.tasksModel.addChildTask(1, { display: "Konsole 3", IsMinimized: true, WinIdList: ["k-3"] })
            // Row 2: launcher without windows.
            DockModel.tasksModel.addTask({ display: "Okular", IsWindow: false })
        }

        function cleanup() {
            PreviewController.previewKeyboardActive = false
            mouseMove(stage, -1, -1)
        }

        function makePopup() {
            let popup = createTemporaryObject(popupComponent, stage)
            verify(popup)
            return popup
        }

        function show(index, name) {
            PreviewController.appName = name
            PreviewController.parentIndex = index
            PreviewController.visible = true
        }

        // Thumbnail delegates in model order.
        function thumbs(popup) {
            return T.findAll(popup, o => o.retryScreencast !== undefined && o.childIndex !== undefined)
                    .sort((a, b) => a.childIndex - b.childIndex)
        }

        // Waits for `n` thumbnails laid out left-to-right by the popup's Row
        // (new delegates sit at x=0 until the Row polishes).
        function waitThumbs(popup, n) {
            tryVerify(() => {
                let ts = thumbs(popup)
                if (ts.length !== n) return false
                for (let i = 1; i < ts.length; i++)
                    if (ts[i].x <= ts[i - 1].x) return false
                return true
            }, 2000, "expected " + n + " laid-out thumbnails, have " + thumbs(popup).length)
            return thumbs(popup)
        }

        function container(popup) {
            // The outer item includes the shadow and is the geometry registered
            // as the Wayland input region. The inner ShadowedRectangle is visual.
            return T.directChildren(popup, c => c.requestedVisible !== undefined)[0]
        }

        function composite(color, over, alpha) {
            return Qt.rgba(color.r * alpha + over.r * (1 - alpha),
                           color.g * alpha + over.g * (1 - alpha),
                           color.b * alpha + over.b * (1 - alpha), 1)
        }

        function card(popup) {
            return T.findFirst(container(popup), c => c.radius !== undefined && c.shadow !== undefined)
        }

        function rgbHex(color) {
            return color.toString().slice(-6).toLowerCase()
        }

        function test_hiddenUntilControllerShows() {
            let popup = makePopup()
            verify(!container(popup).visible)
            compare(thumbs(popup).length, 0)
            show(1, "Konsole")
            tryVerify(() => container(popup).visible)
            PreviewController.visible = false
            tryVerify(() => !container(popup).visible)
        }

        function test_singleWindowUsesParentRow() {
            let popup = makePopup()
            show(0, "Kate")
            waitThumbs(popup, 1)
            let t = thumbs(popup)[0]
            compare(t.title, "Kate")
            compare(t.isActive, true)
            compare(t.childIndex, -1)
            compare(t.winId, "kate-1")
            compare(t.parentIndex, 0)
        }

        function test_popupEdgeOffsetTracksClassicZoomWithoutChangingCardSize_data() {
            return [
                { tag: "top", edge: 0 }, { tag: "bottom", edge: 1 },
                { tag: "left", edge: 2 }, { tag: "right", edge: 3 },
            ]
        }

        function test_popupAnchorIsFixedAtConfiguredMaximumZoomAcrossAnimation_data() {
            return [
                { tag: "top", edge: 0 }, { tag: "bottom", edge: 1 },
                { tag: "left", edge: 2 }, { tag: "right", edge: 3 },
            ]
        }

        function test_popupAnchorIsFixedAtConfiguredMaximumZoomAcrossAnimation(data) {
            DockView.edge = data.edge
            let preview = makePopup()
            show(0, "Kate")
            waitThumbs(preview, 1)
            let cardPopup = T.findFirst(preview, o => o.objectName === "previewCardPopup")
            verify(cardPopup)
            const width = cardPopup.width
            const height = cardPopup.height

            PreviewController.updatePreviewAnchorGeometry(100, 48, 80, 24, 8)
            const maxZoomX = cardPopup.x
            const maxZoomY = cardPopup.y
            if (data.edge === 0) compare(maxZoomY, 24)
            else if (data.edge === 1) compare(maxZoomY, cardPopup.parent.height - height - 24)
            else if (data.edge === 2) compare(maxZoomX, 24)
            else compare(maxZoomX, cardPopup.parent.width - width - 24)

            // Partial and zero zoom are transient icon states. They must not
            // change the popup's cross-axis anchor from the maximum-zoom edge.
            for (const animatedOverflow of [0, 12, 24]) {
                PreviewController.simulatedCurrentZoomOverflow = animatedOverflow
                compare(cardPopup.x, maxZoomX)
                compare(cardPopup.y, maxZoomY)
            }

            compare(cardPopup.width, width)
            compare(cardPopup.height, height)

            // Settings may change while the popup is visible; a fresh maximum
            // geometry moves it directly to the newly configured anchor.
            PreviewController.updatePreviewAnchorGeometry(100, 48, 80, 0, 8)
            if (data.edge === 0 || data.edge === 1) compare(cardPopup.y, data.edge === 0 ? 0 : cardPopup.parent.height - height)
            else compare(cardPopup.x, data.edge === 2 ? 0 : cardPopup.parent.width - width)
        }

        function test_cpuOnlyModeDisablesDmaBufFromCaptureCreation() {
            PreviewController.cpuCaptureOnly = true
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            tryVerify(() => t.captureItem !== null)
            compare(t.captureItem.allowDmaBuf, false)
        }

        function test_captureClipModesKeepTheSameViewportAndSourceGeometry() {
            IconDiagnostics.previewClipMode = "raw"
            let popup = makePopup()
            show(0, "Kate")
            let thumbnail = waitThumbs(popup, 1)[0]
            for (const mode of ["raw", "center50", "rounded"]) {
                IconDiagnostics.previewClipMode = mode
                let expectedObjectName = mode === "raw" ? "rawCaptureViewport"
                    : mode === "center50" ? "center50CaptureViewport"
                    : "roundedCaptureViewport"
                tryVerify(() => thumbnail.captureViewport
                    && thumbnail.captureViewport.objectName === expectedObjectName)
                compare(thumbnail.captureClipMode, mode)
                compare(thumbnail.captureViewport.width, thumbnail.captureViewportWidth)
                compare(thumbnail.captureViewport.height, thumbnail.captureViewportHeight)
                compare(thumbnail.captureItem.width, thumbnail.captureContentWidth)
                compare(thumbnail.captureItem.height, thumbnail.captureContentHeight)
                if (mode === "rounded")
                    compare(thumbnail.captureItem.clipRadius, thumbnail.captureViewportRadius)
                if (mode === "center50") {
                    compare(thumbnail.captureItem.parent.parent.objectName, "center50BuiltInClip")
                    compare(thumbnail.captureItem.parent.parent.clip, true)
                    compare(thumbnail.captureItem.parent.parent.width, thumbnail.captureContentWidth / 2)
                    compare(thumbnail.captureItem.parent.parent.height, thumbnail.captureContentHeight / 2)
                }
            }
        }

        function test_center50ClipAppliesToQmlImageAndPipeWireInTheSameItemHierarchy() {
            IconDiagnostics.previewClipMode = "center50"
            IconDiagnostics.previewSourceMode = "pipewire"
            let popup = makePopup()
            show(0, "Kate")
            let thumbnail = waitThumbs(popup, 1)[0]
            tryVerify(() => thumbnail.captureItem && thumbnail.captureItem.nodeId !== undefined)
            let pipeWireSource = thumbnail.captureItem
            let clipItem = pipeWireSource.parent.parent
            compare(clipItem.objectName, "center50BuiltInClip")
            compare(clipItem.clip, true)

            IconDiagnostics.previewSourceMode = "image"
            tryVerify(() => thumbnail.captureItem && thumbnail.captureItem.source !== undefined)
            let imageSource = thumbnail.captureItem
            compare(imageSource.parent.parent.objectName, "center50BuiltInClip")
            compare(imageSource.width, pipeWireSource.width)
            compare(imageSource.height, pipeWireSource.height)
            compare(imageSource.x, pipeWireSource.x)
            compare(imageSource.y, pipeWireSource.y)
        }

        function test_autoModeFallsBackToCpuWhenNoFirstFrameArrives() {
            PreviewController.cpuCaptureOnly = false
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            tryVerify(() => t.captureItem !== null)
            compare(t.captureItem.allowDmaBuf, true)
            t.captureItem.state = 4 // Streaming without a received frame.
            tryVerify(() => t.captureItem.allowDmaBuf === false, 2500,
                     "auto mode should retry once without DMA-BUF after the first-frame timeout")
        }

        function test_cpuOnlyModeDoesNotTriggerTheAutoFallbackRetry() {
            PreviewController.cpuCaptureOnly = true
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            tryVerify(() => t.captureItem !== null)
            let firstCapture = t.captureItem
            compare(firstCapture.allowDmaBuf, false)
            firstCapture.state = 4 // Streaming without a received frame.
            wait(1700)
            verify(t.captureItem === firstCapture, "cpu-only must not restart the source through Auto fallback")
        }

        function test_captureModeChangeRestartsExistingGroupedStreams() {
            PreviewController.setCaptureMode(false)
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            let originalItems = ts.map(t => t.captureItem)
            tryVerify(() => originalItems.every(item => item !== null))
            verify(originalItems.every(item => item.allowDmaBuf), "Auto should allow DMA-BUF")
            let activeBeforeSwitch = PipeWireTracker.activeCount

            PreviewController.setCaptureMode(true)
            tryVerify(() => ts.every((t, i) => t.captureItem !== originalItems[i]))
            tryVerify(() => ts.every(t => t.captureItem && !t.captureItem.allowDmaBuf))
            tryCompare(PipeWireTracker, "activeCount", activeBeforeSwitch)
            verify(ts.every(t => t.captureItem && !t.captureItem.allowDmaBuf),
                   "CPU compatibility mode should disable DMA-BUF")

            let cpuItems = ts.map(t => t.captureItem)
            PreviewController.setCaptureMode(false)
            tryVerify(() => ts.every((t, i) => t.captureItem !== cpuItems[i]))
            tryVerify(() => ts.every(t => t.captureItem && t.captureItem.allowDmaBuf))
            tryCompare(PipeWireTracker, "activeCount", activeBeforeSwitch)
            verify(ts.every(t => t.captureItem && t.captureItem.allowDmaBuf),
                   "switching back to Auto should restore DMA-BUF")
        }

        function test_groupedWindowsOneThumbnailEach() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            let ts = thumbs(popup)
            compare(ts.map(t => t.title), ["Konsole 1", "Konsole 2", "Konsole 3"])
            compare(ts.map(t => t.childIndex), [0, 1, 2])
            compare(ts.map(t => t.winId), ["k-1", "k-2", "k-3"])
            compare(ts.map(t => t.isActive), [true, false, false])
            compare(ts.map(t => t.isMinimized), [false, false, true])
            let header = T.findFirst(popup, o => o.text === "Konsole" && o.font !== undefined)
            verify(header && header.visible, "app name header missing")
        }

        function test_inactiveBordersAdaptLiveAndPreserveActiveAccent() {
            let popup = makePopup()
            show(1, "Konsole")
            const ts = waitThumbs(popup, 3)
            const frames = ts.map(t => T.findFirst(t,
                o => o.objectName === "previewThumbnailContainer"))
            const borders = ts.map(t => T.findFirst(t,
                o => o.objectName === "previewInactiveBorder"))
            verify(frames.every(Boolean) && borders.every(Boolean))

            const cornerRadius = DockSettings.cornerRadius
            const initialSize = ts.map(t => [t.thumbnailWidth, t.thumbnailHeight])
            DockView.backgroundColor = "#22262c"
            tryVerify(() => rgbHex(borders[1].border.color)
                === PreviewBorderColor.colorForSurface(
                    ts[1].panelColor, Kirigami.Theme.backgroundColor, false).slice(-6))

            verify(borders[1].visible && borders[2].visible,
                   "all inactive grouped windows, including minimized, need an outline")
            compare(borders[1].border.width, 1)
            compare(borders[1].radius, ts[1].thumbnailRadius)
            compare(frames[0].border.width, 2)
            compare(frames[0].border.color, Kirigami.Theme.highlightColor,
                    "the active window keeps the KDE accent border")
            compare(borders[0].visible, false)

            const darkColor = borders[1].border.color.toString()
            DockView.backgroundColor = "#f2efe9"
            tryVerify(() => borders[1].border.color.toString() !== darkColor)
            const lightExpected = PreviewBorderColor.colorForSurface(
                ts[1].panelColor, Kirigami.Theme.backgroundColor, false)
            compare(rgbHex(borders[1].border.color), lightExpected.slice(-6))

            DockView.backgroundColor = Qt.rgba(0.18, 0.25, 0.35, 0.38)
            const translucentExpected = PreviewBorderColor.colorForSurface(
                ts[1].panelColor, Kirigami.Theme.backgroundColor, false)
            tryVerify(() => rgbHex(borders[1].border.color)
                === translucentExpected.slice(-6))
            compare(frames[0].border.color, Kirigami.Theme.highlightColor)
            compare(DockSettings.cornerRadius, cornerRadius)
            compare(ts.map(t => [t.thumbnailWidth, t.thumbnailHeight]), initialSize)
        }

        function test_inactiveBorderHoverOnlyStrengthensNeutralContrast() {
            let popup = makePopup()
            show(1, "Konsole")
            const ts = waitThumbs(popup, 3)
            const inactive = ts[1]
            const border = T.findFirst(inactive,
                o => o.objectName === "previewInactiveBorder")
            verify(border && border.visible)

            DockView.backgroundColor = "#30343a"
            const restingRatio = PreviewBorderColor.surfaceContrastRatio(
                border.border.color, inactive.panelColor, Kirigami.Theme.backgroundColor)
            const center = inactive.mapToItem(stage,
                inactive.thumbnailWidth / 2, inactive.thumbnailHeight / 2)
            mouseMove(stage, center.x, center.y)
            tryCompare(inactive, "pointerHovered", true)
            const hoveredRatio = PreviewBorderColor.surfaceContrastRatio(
                border.border.color, inactive.panelColor, Kirigami.Theme.backgroundColor)
            verify(hoveredRatio > restingRatio)
            compare(border.border.color.r, border.border.color.g)
            compare(border.border.color.g, border.border.color.b)
            compare(border.border.width, 1)
        }

        function test_minimizedWindowRetainsItsReadyThumbnail() {
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            let minimized = ts[2]
            let capture = minimized.captureItem
            verify(capture)
            compare(capture.opacity, 1, "PipeWire render item must retain its normal scene-graph opacity")
            capture.ready = true

            DockModel.tasksModel.setChildTaskData(1, 2, "IsMinimized", true)
            tryCompare(minimized, "isMinimized", true)
            compare(minimized.captureItem, capture, "minimizing must not recreate or discard this window's capture")
            verify(capture.visible, "PipeWire source must remain active while minimized")
            let fallback = T.findFirst(minimized, o => o.iconName !== undefined)
            verify(fallback && !fallback.visible, "a ready minimized thumbnail must not show the app icon")

            DockModel.tasksModel.setChildTaskData(1, 2, "IsMinimized", false)
            tryCompare(minimized, "isMinimized", false)
            compare(minimized.captureItem, capture, "restore must resume the existing capture")
            verify(capture.visible)
            compare(capture.opacity, 1)
        }

        function test_windowIdChangeReplacesSourceBeforeShowingAnotherWindowsFrame() {
            let popup = makePopup()
            show(1, "Konsole")
            let t = waitThumbs(popup, 3)[1]
            let oldCapture = t.captureItem
            oldCapture.ready = true
            t.winId = "different-window-uuid"
            tryVerify(() => t.captureItem !== null && t.captureItem !== oldCapture)
            compare(t.captureItem.opacity, 1, "PipeWire source keeps its default opacity while resolving a new UUID")
            verify(t.captureItem.visible, "the source must remain active while waiting for the new UUID frame")
            let fallback = T.findFirst(t, o => o.iconName !== undefined)
            verify(fallback && fallback.visible, "the app icon covers the new source until its first frame")
            t.captureItem.ready = true
            tryVerify(() => !fallback.visible)
        }

        function test_rapidMinimizeRestoreKeepsGroupedCapturesBoundToWindows() {
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            let captures = ts.map(t => t.captureItem)
            verify(captures.every(c => c !== null))

            for (let i = 0; i < 8; i++) {
                DockModel.tasksModel.setChildTaskData(1, 1, "IsMinimized", true)
                DockModel.tasksModel.setChildTaskData(1, 1, "IsMinimized", false)
            }

            compare(thumbs(popup).map(t => t.winId), ["k-1", "k-2", "k-3"])
            verify(thumbs(popup).every((t, i) => t.captureItem === captures[i]),
                   "rapid state changes must preserve each delegate's own PipeWire source")
            verify(captures.every(c => c.visible))
        }

        function test_closedGroupedWindowReleasesItsThumbnailDelegate() {
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            let closedSource = ts[1].captureItem
            verify(closedSource)
            DockModel.tasksModel.removeChildTask(1, 1)
            let duringParentIdLag = waitThumbs(popup, 2)
            compare(duringParentIdLag.map(t => t.winId), ["k-1", "k-3"],
                    "child rows retain their own UUIDs while parent WinIdList is stale")
            DockModel.tasksModel.setTaskData(1, "WinIdList", ["k-1", "k-3"])
            let remaining = waitThumbs(popup, 2)
            compare(remaining.map(t => t.winId), ["k-1", "k-3"])
            tryVerify(() => ts[1].captureItem !== null && ts[1].captureItem !== closedSource)
            verify(!remaining.some(t => t.captureItem === closedSource),
                   "closed window's PipeWire source and cached texture must be released")
        }

        function test_launcherWithoutWindowsHasNoThumbnails() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            show(2, "Okular")
            tryVerify(() => thumbs(popup).length === 0)
        }

        function test_winIdListLagLimitsThumbnails() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            // KWin updated the child rows before WinIdList: show only windows with an id.
            DockModel.tasksModel.setTaskData(1, "WinIdList", ["k-1", "k-2"])
            waitThumbs(popup, 2)
        }

        function test_incrementalUpdatePreservesDelegates() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            let first = thumbs(popup)[0]
            DockModel.tasksModel.addChildTask(1, { display: "Konsole 4", WinIdList: ["k-4"] })
            DockModel.tasksModel.setTaskData(1, "WinIdList", ["k-1", "k-2", "k-3", "k-4"])
            waitThumbs(popup, 4)
            // Existing delegates (and their PipeWire streams) survive the update.
            verify(thumbs(popup)[0] === first, "first thumbnail delegate was recreated")
            compare(thumbs(popup)[3].title, "Konsole 4")
        }

        function test_captureCanFallBackFromDmaBuf() {
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            verify(t.captureItem)
            compare(t.captureItem.allowDmaBuf, true)

            t.retryWithoutDmaBuf()
            tryVerify(() => t.captureItem && !t.captureItem.allowDmaBuf)
            compare(t.forceCpuCapture, true)
        }

        function test_switchingAppRebuildsThumbnails() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            show(0, "Kate")
            waitThumbs(popup, 1)
            compare(thumbs(popup)[0].title, "Kate")
        }

        function test_removedParentHidesPreview() {
            let popup = makePopup()
            show(2, "Okular")
            DockModel.tasksModel.removeTask(2)
            tryVerify(() => PreviewController.callsTo("hidePreview").length === 1)
        }

        function test_clickThumbnailActivatesThatWindow_data() {
            return [
                { tag: "grouped-child", parent: 1, thumb: 1, count: 3, row: 1, child: 1 },
                { tag: "single-window", parent: 0, thumb: 0, count: 1, row: 0, child: -1 },
            ]
        }

        function test_clickThumbnailActivatesThatWindow(data) {
            let popup = makePopup()
            show(data.parent, "App")
            waitThumbs(popup, data.count)
            let t = thumbs(popup)[data.thumb]
            // Lower-left area of the thumbnail (away from the close button).
            mouseClick(t, t.width * 0.25, t.thumbnailHeight * 0.75)
            tryCompare(DockModel.tasksModel, "activateRequests", 1)
            compare(DockModel.tasksModel.lastRequestRow, data.row)
            compare(DockModel.tasksModel.lastRequestChild, data.child)
            compare(PreviewController.callsTo("hidePreview").length, 1)
            compare(DockModel.tasksModel.closeRequests, 0)
        }

        function test_closeButtonClosesThatWindow() {
            let popup = makePopup()
            show(1, "Konsole")
            const ts = waitThumbs(popup, 3)
            const close = T.findFirst(popup, o => o.objectName === "previewCloseButton")
            verify(close, "close button not found")
            const thumbnailCenter = ts[2].mapToItem(stage,
                ts[2].thumbnailWidth / 2, ts[2].thumbnailHeight / 2)
            mouseMove(stage, thumbnailCenter.x, thumbnailCenter.y)
            tryCompare(ts[2], "pointerHovered", true)
            const closeCenter = close.mapToItem(stage, close.width / 2, close.height / 2)
            mouseMove(stage, closeCenter.x, closeCenter.y)
            mouseClick(stage, closeCenter.x, closeCenter.y)
            tryCompare(DockModel.tasksModel, "closeRequests", 1)
            compare(DockModel.tasksModel.lastRequestRow, 1)
            compare(DockModel.tasksModel.lastRequestChild, 2)
            compare(DockModel.tasksModel.activateRequests, 0)
        }

        function test_closeButtonUsesApprovedIdleHoverPressedAppearance() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            const close = T.findFirst(popup, o => o.objectName === "previewCloseButton")
            verify(close, "close button not found")
            const background = close.background
            const cross = T.findFirst(close, o => o.objectName === "previewCloseCross")
            verify(background && cross, "the button circle and cross must be present")
            compare(close.width, 22)
            compare(close.height, 22)
            compare(background.radius, close.width / 2)
            compare(background.color.toString().toLowerCase(), "#ff5f57")
            verify(background.visible, "the red circle must remain visible while idle")
            compare(cross.visible, false, "the cross must be hidden while idle")
            verify(BadgeTextColor.contrastRatio(cross.color, background.color) >= 4.5,
                   "the dark hover cross must contrast with the idle red circle")

            const closeCenter = close.mapToItem(stage, close.width / 2, close.height / 2)
            mouseMove(stage, -1, -1)
            tryCompare(close, "hovered", false)
            tryCompare(close, "down", false)
            compare(background.color.toString().toLowerCase(), "#ff5f57")
            compare(cross.visible, false)

            mouseMove(stage, closeCenter.x, closeCenter.y)
            tryCompare(close, "hovered", true)
            tryCompare(cross, "visible", true)
            compare(background.color.toString().toLowerCase(), "#ff5f57")
            compare(close.width, 22)
            compare(close.height, 22)

            mousePress(stage, closeCenter.x, closeCenter.y, Qt.LeftButton)
            tryCompare(close, "down", true)
            tryCompare(cross, "visible", true)
            compare(background.color.toString().toLowerCase(), "#e6534d")
            verify(BadgeTextColor.contrastRatio(cross.color, background.color) >= 4.5,
                   "the dark pressed cross must contrast with the pressed red circle")
            compare(close.width, 22)
            compare(close.height, 22)

            mouseRelease(stage, closeCenter.x, closeCenter.y, Qt.LeftButton)
            tryCompare(DockModel.tasksModel, "closeRequests", 1)
            compare(DockModel.tasksModel.lastRequestRow, 1)
            compare(DockModel.tasksModel.lastRequestChild, 0,
                    "without a hovered or keyboard-focused target, close the active group window")
        }

        function test_closeButtonIsAnchoredToTopRightHeader() {
            let popup = makePopup()
            show(1, "Konsole")
            const ts = waitThumbs(popup, 3)
            const header = T.findFirst(popup, o => o.objectName === "previewHeader")
            const iconSlot = T.findFirst(popup, o => o.objectName === "previewAppIconSlot")
            const close = T.findFirst(popup, o => o.objectName === "previewCloseButton")
            verify(close, "close button not found")
            verify(header && iconSlot, "header app icon or row missing")
            compare(iconSlot.x, 0)
            compare(close.x + close.width, header.width)
            compare(close.y + close.height / 2, iconSlot.y + iconSlot.height / 2)
            compare(iconSlot.x, header.width - close.x - close.width,
                    "the app icon and close control have symmetric side insets")
            compare(close.width, 22)
            compare(close.height, 22)
            const frame = T.findFirst(ts[0], o => o.objectName === "previewThumbnailContainer")
            verify(frame && header.mapToItem(popup, 0, header.height).y
                   <= frame.mapToItem(popup, 0, 0).y,
                   "the close control must remain in the header above the window image")
        }

        function test_closeButtonPositionAndHeaderHeightAcrossSizePresets_data() {
            const sizes = [
                { tag: "compact", width: 180, height: 113 },
                { tag: "standard", width: 220, height: 138 },
                { tag: "enlarged", width: 260, height: 163 },
                { tag: "large", width: 320, height: 200 },
            ]
            const edges = ["top", "bottom", "left", "right"]
            const rows = []
            for (const size of sizes) {
                for (let edge = 0; edge < edges.length; edge++) {
                    rows.push({
                        tag: size.tag + "-" + edges[edge],
                        width: size.width,
                        height: size.height,
                        edge,
                    })
                }
            }
            return rows
        }

        function test_closeButtonPositionAndHeaderHeightAcrossSizePresets(data) {
            DockView.edge = data.edge
            DockSettings.previewThumbnailSize = data.width
            DockSettings.previewMaximumHeight = data.height
            const popup = makePopup()
            show(0, "A very long application title that must be shortened")
            const ts = waitThumbs(popup, 1)
            const header = T.findFirst(popup, o => o.objectName === "previewHeader")
            const appName = T.findFirst(popup, o => o.objectName === "previewAppName")
            const close = T.findFirst(popup, o => o.objectName === "previewCloseButton")
            verify(header && appName && close)
            tryCompare(header, "height", 22)
            tryVerify(() => header.width > 0, 2000,
                      "header layout must settle to the preview card content width")
            compare(close.x + close.width, header.width)
            verify(appName.x + appName.width <= close.x,
                   "elided application title must not overlap the close button")
            compare(ts[0].thumbnailWidth, data.width)
            compare(ts[0].thumbnailHeight, data.width / 1.6)
        }

        function test_closeButtonTargetsKeyboardFocusedGroupedWindow() {
            const popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            PreviewController.previewKeyboardActive = true
            PreviewController.focusedThumbnailIndex = 1
            const close = T.findFirst(popup, o => o.objectName === "previewCloseButton")
            verify(close)
            const center = close.mapToItem(stage, close.width / 2, close.height / 2)
            mouseClick(stage, center.x, center.y)
            tryCompare(DockModel.tasksModel, "closeRequests", 1)
            compare(DockModel.tasksModel.lastRequestRow, 1)
            compare(DockModel.tasksModel.lastRequestChild, 1)
        }

        function test_thumbnailSizeFollowsSetting() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            let t = thumbs(popup)[0]
            compare(t.thumbnailWidth, 200)
            compare(t.thumbnailHeight, 125)
            let before = container(popup).width
            DockSettings.previewMaximumHeight = 240
            DockSettings.previewThumbnailSize = 300
            compare(t.thumbnailWidth, 300)
            compare(t.thumbnailHeight, 187.5)
            tryVerify(() => container(popup).width > before)
            // The popup reports its size for the input region.
            tryVerify(() => PreviewController.contentWidth === container(popup).width)
            tryVerify(() => PreviewController.contentHeight === container(popup).height)
        }

        function test_readyMadeThumbnailSizesUseExistingSettingsImmediately_data() {
            const sizes = [
                { name: "compact", width: 180, maximumHeight: 113, expectedHeight: 112.5 },
                { name: "standard", width: 220, maximumHeight: 138, expectedHeight: 137.5 },
                { name: "enlarged", width: 260, maximumHeight: 163, expectedHeight: 162.5 },
                { name: "large", width: 320, maximumHeight: 200, expectedHeight: 200 },
            ]
            const edges = ["top", "bottom", "left", "right"]
            let rows = []
            for (const size of sizes) {
                for (let edge = 0; edge < edges.length; ++edge) {
                    rows.push({
                        tag: size.name + "-" + edges[edge],
                        width: size.width,
                        maximumHeight: size.maximumHeight,
                        expectedHeight: size.expectedHeight,
                        edge,
                    })
                }
            }
            return rows
        }

        function test_readyMadeThumbnailSizesUseExistingSettingsImmediately(data) {
            DockView.edge = data.edge
            DockSettings.previewThumbnailSize = data.width
            DockSettings.previewMaximumHeight = data.maximumHeight
            const popup = makePopup()
            show(0, "Kate")
            const thumbnail = waitThumbs(popup, 1)[0]
            compare(thumbnail.thumbnailWidth, data.width)
            compare(thumbnail.thumbnailHeight, data.expectedHeight)
            compare(thumbnail.captureViewportWidth, data.width - 2 * thumbnail.captureBorderWidth)
            compare(thumbnail.captureViewportHeight, data.expectedHeight - 2 * thumbnail.captureBorderWidth)
            const frame = T.findFirst(thumbnail, item => item.objectName === "previewThumbnailContainer")
            verify(frame)
            compare(frame.width, data.width)
        }

        function test_thumbnailUsesFixedViewportAndCoverGeometry() {
            DockSettings.previewThumbnailSize = 320
            DockSettings.previewMaximumHeight = 180
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            tryVerify(() => t.captureItem !== null)
            t.captureItem.ready = true
            compare(t.thumbnailWidth, 288)
            compare(t.thumbnailHeight, 180)
            compare(t.captureViewportWidth, 288)
            compare(t.captureViewportHeight, 180)
            t.captureItem.streamSize = Qt.size(1600, 900)
            tryCompare(t, "captureContentWidth", 320)
            tryCompare(t, "captureContentHeight", 180)
            t.captureItem.streamSize = Qt.size(1600, 1200)
            tryCompare(t, "captureContentWidth", 288)
            tryCompare(t, "captureContentHeight", 216)
            compare(t.thumbnailWidth, 288, "the preview slot stays fixed for a 4:3 source")
            DockSettings.previewMaximumHeight = 240
            tryCompare(t, "thumbnailWidth", 320)
            tryCompare(t, "thumbnailHeight", 200)
            compare(t.captureViewportWidth, 320)
            compare(t.captureViewportHeight, 200)
            t.captureItem.streamSize = Qt.size(900, 1600)
            tryCompare(t, "captureContentWidth", 320)
            tryCompare(t, "captureContentHeight", 568.8888888889)
            compare(t.thumbnailWidth, 320, "portrait sources do not shrink the shared slot")
        }

        function test_imageFillsRoundedInnerViewport() {
            DockSettings.cornerRadius = 32
            DockSettings.previewThumbnailSize = 320
            DockSettings.previewMaximumHeight = 200
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            compare(t.thumbnailRadius, 32)
            compare(t.thumbnailWidth, 320)
            compare(t.thumbnailHeight, 200)
            compare(t.captureViewportWidth, 320)
            compare(t.captureViewportHeight, 200)
            compare(t.captureViewportRadius, 32)
            tryVerify(() => t.captureViewport !== null)
            compare(t.captureViewport.width, 320)
            compare(t.captureViewport.height, 200)
            compare(t.captureItem.clipRadius, 32)
        }

        function test_windowTitlesAndAspectRatiosDoNotChangeCardCellSize() {
            DockSettings.previewThumbnailSize = 240
            DockSettings.previewMaximumHeight = 150
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            ts.forEach(item => item.captureItem.ready = true)
            ts[0].captureItem.streamSize = Qt.size(1920, 1080)
            ts[1].captureItem.streamSize = Qt.size(1080, 1920)
            ts[2].captureItem.streamSize = Qt.size(1000, 1000)
            tryCompare(ts[0], "captureContentWidth", ts[0].captureViewportHeight * 1920 / 1080)
            tryCompare(ts[0], "captureContentHeight", ts[0].captureViewportHeight)
            tryCompare(ts[1], "captureContentWidth", ts[1].captureViewportWidth)
            tryCompare(ts[1], "captureContentHeight", ts[1].captureViewportWidth * 1920 / 1080)
            tryCompare(ts[2], "captureContentWidth", ts[2].captureViewportWidth)
            tryCompare(ts[2], "captureContentHeight", ts[2].captureViewportWidth)
            verify(ts.every(t => t.thumbnailWidth === 240 && t.thumbnailHeight === 150),
                   "all aspect ratios must occupy the same configured preview slot")
            let fixedImplicitHeight = ts[0].implicitHeight
            ts[0].title = "A very long window title that should be elided on one line"
            tryCompare(ts[0], "implicitHeight", fixedImplicitHeight)
            compare(ts[0].implicitWidth, 240)
        }

        function test_compactCardUsesConfiguredPaddingAndHeader() {
            DockSettings.cornerRadius = 16
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            let c = card(popup)
            verify(c)
            compare(c.color, DockView.backgroundColor,
                    "the preview surface follows the resolved panel color")
            compare(c.radius, Math.min(DockSettings.cornerRadius, c.width / 2, c.height / 2),
                    "the card uses the dock's configured corner radius")
            let thumb = T.findFirst(t, o => o.objectName === "previewThumbnailContainer")
            verify(thumb)
            let titleLabel = T.findFirst(t, o => o.text === t.title && o.font !== undefined)
            verify(titleLabel)
            verify(titleLabel.y + titleLabel.height < thumb.y,
                   "window title belongs above its thumbnail")
            compare(thumb.radius, DockSettings.cornerRadius)
            compare(t.captureViewport.width, thumb.width - 2 * t.captureBorderWidth)
            compare(t.captureViewport.height, thumb.height - 2 * t.captureBorderWidth)
            compare(t.captureItem.clipRadius, thumb.radius - t.captureBorderWidth)
            verify(t.captureItem.visible,
                   "the PipeWire source remains active for CPU-only frames and minimized windows")
            compare(t.captureItem.opacity, 1,
                    "the PipeWire source is not hidden with an opacity binding")
            compare(t.captureItem.parent, t.captureViewport,
                    "the PipeWireSourceItem is the direct viewport child")
            compare(t.captureItem.clipRadius, t.thumbnailRadius - t.captureBorderWidth,
                    "the viewport rounds to the same inner contour as the card")
            let before = container(popup).width
            DockSettings.previewCardPadding = 16
            tryVerify(() => container(popup).width > before)
            tryVerify(() => PreviewController.contentWidth === container(popup).width)
            compare(T.findFirst(popup, o => o.text === "Kate").text, "Kate")
        }

        function test_previewUsesDirectPipeWireItemAndClippedCoverViewport() {
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            tryVerify(() => t.captureItem !== null)
            compare(t.captureItem.parent, t.captureViewport,
                    "the source item must remain directly owned by the viewport")
            verify(t.captureItem.width >= t.captureViewport.width
                   && t.captureItem.height >= t.captureViewport.height,
                   "the source geometry must cover the fixed 16:10 viewport")
            let thumb = T.findFirst(t, o => o.objectName === "previewThumbnailContainer")
            verify(thumb)
            compare(thumb.clip, false)
            compare(t.captureViewport.objectName, "roundedCaptureViewport")
            compare(t.captureItem.clipViewportRect,
                    Qt.rect((t.captureItem.width - t.captureViewportWidth) / 2,
                            (t.captureItem.height - t.captureViewportHeight) / 2,
                            t.captureViewportWidth, t.captureViewportHeight))
            compare(t.captureItem.clipRadius, t.thumbnailRadius - t.captureBorderWidth)
            compare(t.captureItem.visible, true)
            compare(t.captureItem.opacity, 1)
        }

        function test_coverCropPerEdgeAndSourceAspect_data() {
            const edges = [
                { name: "top", value: 0 }, { name: "bottom", value: 1 },
                { name: "left", value: 2 }, { name: "right", value: 3 },
            ]
            const sources = [
                { name: "portrait", size: Qt.size(900, 1600) },
                { name: "square", size: Qt.size(1000, 1000) },
                { name: "wide", size: Qt.size(1920, 1080) },
                { name: "ultrawide", size: Qt.size(3200, 1000) },
            ]
            const rows = []
            for (const edge of edges)
                for (const source of sources)
                    rows.push({ tag: edge.name + "_" + source.name, edge: edge.value, size: source.size })
            return rows
        }

        function test_coverCropPerEdgeAndSourceAspect(data) {
            DockView.edge = data.edge
            DockSettings.previewThumbnailSize = 240
            DockSettings.previewMaximumHeight = 150
            let popup = makePopup()
            show(1, "Konsole")
            let ts = waitThumbs(popup, 3)
            let t = ts[1]
            compare(t.winId, "k-2", "cover geometry remains attached to the child window UUID")
            t.captureItem.ready = true
            t.captureItem.streamSize = data.size
            tryVerify(() => t.sourceAspectRatio === data.size.width / data.size.height)

            const expectedWidth = Math.max(t.captureViewportWidth, t.captureViewportHeight * t.sourceAspectRatio)
            const expectedHeight = expectedWidth / t.sourceAspectRatio
            tryCompare(t, "captureContentWidth", expectedWidth)
            tryCompare(t, "captureContentHeight", expectedHeight)
            verify(t.captureContentWidth >= t.captureViewportWidth)
            verify(t.captureContentHeight >= t.captureViewportHeight)
            compare(t.captureItem.x, -(t.captureContentWidth - t.captureViewportWidth) / 2,
                    "horizontal overflow is centered, producing symmetric side crops")
            compare(t.captureItem.y, -(t.captureContentHeight - t.captureViewportHeight) / 2,
                    "vertical overflow is centered, producing symmetric top/bottom crops")
            verify(ts.every(item => item.thumbnailWidth === 240 && item.thumbnailHeight === 150),
                   "source aspect and dock edge never alter card dimensions")
            verify(ts.every(item => item.captureItem && item.captureItem.visible),
                   "all grouped PipeWire sources remain active across dock edges")
        }

        function test_coverCropIgnoresUntrustedPipeWireSizesUntilAValidFrame() {
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            tryVerify(() => t.captureItem !== null)
            compare(t.sourceAspectRatio, 1.6)

            t.captureItem.streamSize = Qt.size(3801189, 2097152)
            compare(t.sourceAspectRatio, 1.6, "unready format dimensions must not resize the cover item")
            t.captureItem.streamSize = Qt.size(116, 7929972)
            compare(t.sourceAspectRatio, 1.6, "pathological portrait dimensions must be rejected")
            verify(t.captureContentHeight < 1000, "invalid dimensions cannot create an offscreen-sized item")

            t.captureItem.ready = true
            t.captureItem.streamSize = Qt.size(1581, 904)
            tryVerify(() => Math.abs(t.sourceAspectRatio - 1581 / 904) < 0.000001)
            const acceptedRatio = t.sourceAspectRatio
            t.captureItem.ready = false
            t.captureItem.streamSize = Qt.size(116, 7929972)
            compare(t.sourceAspectRatio, acceptedRatio,
                    "a paused stream retains its last valid aspect ratio")

            t.captureItem.ready = true
            t.captureItem.streamSize = Qt.size(3801189, 2097152)
            compare(t.sourceAspectRatio, acceptedRatio,
                    "oversized negotiated dimensions cannot replace a valid ratio")
            t.captureItem.streamSize = Qt.size(116, 7929972)
            compare(t.sourceAspectRatio, acceptedRatio,
                    "invalid aspect ratios cannot resize the live preview")
            t.captureItem.streamSize = Qt.size(900, 1600)
            tryCompare(t, "sourceAspectRatio", 900 / 1600)
        }

        function test_cardTracksPanelColorAndAdaptiveText() {
            let popup = makePopup()
            show(0, "Kate")
            waitThumbs(popup, 1)
            let c = card(popup)
            DockView.backgroundColor = "#fff4e8"
            tryCompare(c, "color", "#fff4e8")
            let label = T.findFirst(popup, o => o.text === "Kate" && o.font !== undefined)
            verify(label)
            tryCompare(label, "color", "#000000")
            DockView.backgroundColor = "#a0000000"
            tryCompare(c, "color", "#a0000000")
        }

        function test_keyboardFocusRingFollowsController() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            PreviewController.focusedThumbnailIndex = 1
            PreviewController.previewKeyboardActive = true
            compare(thumbs(popup).map(t => t.isKeyboardFocused), [false, true, false])
            PreviewController.previewKeyboardActive = false
            compare(thumbs(popup).map(t => t.isKeyboardFocused), [false, false, false])
        }

        function test_popupPlacementPerEdge_data() {
            return [
                { tag: "top", edge: 0 },
                { tag: "bottom", edge: 1 },
                { tag: "left", edge: 2 },
                { tag: "right", edge: 3 },
            ]
        }

        function test_popupPlacementPerEdge(data) {
            DockView.edge = data.edge
            PreviewController.contentX = 123
            PreviewController.contentY = 45
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            let c = container(popup)
            switch (data.edge) {
            case 0: compare(c.y, 0); compare(c.x, 123); break
            case 1: tryCompare(c, "y", popup.height - c.height); compare(c.x, 123); break
            case 2: compare(c.x, 0); compare(c.y, 45); break
            case 3: tryCompare(c, "x", popup.width - c.width); compare(c.y, 45); break
            }
        }

        function test_hoverKeepsPreviewAndCancelsKeyboardNav() {
            let popup = makePopup()
            show(1, "Konsole")
            waitThumbs(popup, 3)
            PreviewController.previewKeyboardActive = true
            let c = container(popup)
            mouseMove(popup, c.x + c.width / 2, c.y + c.height / 2)
            tryCompare(PreviewController, "previewHovered", true)
            tryCompare(PreviewController, "previewKeyboardActive", false)
            mouseMove(stage, -1, -1)
        }
    }
}
