// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// The real PreviewPopup.qml + PreviewThumbnail.qml: thumbnail model built
// from the task tree, incremental updates, activation/close, geometry.
// PipeWire/ScreencastingRequest are inert mocks (no live frames).
import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import kdockw.test 1.0
import "../../src/qml" as KDockW
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

        function card(popup) {
            return T.findFirst(container(popup), c => c.radius !== undefined && c.shadow !== undefined)
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
            waitThumbs(popup, 3)
            let t = thumbs(popup)[2]
            let close = T.findFirst(t, o => o.icon !== undefined && o.icon.name === "window-close")
            verify(close, "close button not found")
            mouseClick(close)
            tryCompare(DockModel.tasksModel, "closeRequests", 1)
            compare(DockModel.tasksModel.lastRequestRow, 1)
            compare(DockModel.tasksModel.lastRequestChild, 2)
            compare(DockModel.tasksModel.activateRequests, 0)
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

        function test_thumbnailUsesFixedViewportAndCoverGeometry() {
            DockSettings.previewThumbnailSize = 320
            DockSettings.previewMaximumHeight = 180
            let popup = makePopup()
            show(0, "Kate")
            let t = waitThumbs(popup, 1)[0]
            t.isActive = false
            tryVerify(() => t.captureItem !== null)
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
