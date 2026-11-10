// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor
import "PreviewBorderColor.js" as PreviewBorderColor

/**
 * A single window thumbnail in the preview popup.
 *
 * Uses PipeWire + ScreencastingRequest for GPU-accelerated live thumbnails.
 * Tracks pointer/focus selection for the preview header's close control and
 * activates the window on click.
 */
Item {
    id: root

    property var winId
    property string title: ""
    property bool isMinimized: false
    property bool isActive: false
    // A minimized window can expose a stream before KWin has delivered a
    // usable frame. Retain the app icon until we have observed a frame while
    // the window was visible, then keep that frame through minimize/restore.
    property bool hasFrameWhileVisible: false
    property bool frameSnapshotPending: false
    property double lastFrameSnapshotAt: 0
    property int parentIndex: -1
    property int childIndex: 0
    property bool isKeyboardFocused: false
    property bool showCloseButton: false
    // The popup may narrow thumbnail slots when a group would exceed the
    // available output width. Zero keeps standalone/test thumbnails at the
    // configured preset width.
    property real slotWidth: 0
    signal closeRequested(var uuid)
    readonly property bool pointerHovered: thumbnailHover.hovered
    property bool forceCpuCapture: false
    property var captureWinId: undefined
    readonly property var captureItem: captureLoader.item ? captureLoader.item.sourceItem : null
    readonly property var captureViewport: captureLoader.item
    readonly property string cachedFrameSource: {
        const revision = PreviewController.previewFrameRevision
        return PreviewController.previewFrameUrl(root.winId)
    }
    readonly property string captureClipMode: {
        const requested = typeof IconDiagnostics !== "undefined" ? IconDiagnostics.previewClipMode : ""
        return requested === "raw" || requested === "center50" || requested === "rounded"
            ? requested : "rounded"
    }
    readonly property string captureSourceMode: {
        const requested = typeof IconDiagnostics !== "undefined" ? IconDiagnostics.previewSourceMode : ""
        return requested === "image" ? "image" : "pipewire"
    }

    Accessible.role: Accessible.Button
    Accessible.name: {
        let parts = [title]
        if (isActive) parts.push(i18n("Active"))
        if (isMinimized) parts.push(i18n("Minimized"))
        return parts.join(", ")
    }
    Accessible.focusable: true
    Accessible.focused: isKeyboardFocused
    Accessible.onPressAction: thumbnailMouseArea.clicked(null)

    property real sourceAspectRatio: 1.6
    // Keep a stable 16:10 preview slot for every app. The image fills the
    // inner card area and a scene-graph clip rounds its visible corners.
    readonly property real thumbnailWidth: Math.min(
        slotWidth > 0 ? slotWidth : DockSettings.previewThumbnailSize,
        DockSettings.previewMaximumHeight * 1.6)
    readonly property real thumbnailHeight: thumbnailWidth / 1.6
    readonly property real titleToThumbnailSpacing: Kirigami.Units.smallSpacing / 2
    readonly property real titleRowHeight: titleRow.height
    readonly property real captureBorderWidth: isActive ? 2 : 0
    readonly property real captureViewportWidth: thumbnailWidth - 2 * captureBorderWidth
    readonly property real captureViewportHeight: thumbnailHeight - 2 * captureBorderWidth
    readonly property real captureViewportRadius: Math.max(0, thumbnailRadius - captureBorderWidth)
    readonly property real captureContentWidth: Math.max(
        captureViewportWidth, captureViewportHeight * sourceAspectRatio)
    readonly property real captureContentHeight: captureContentWidth / sourceAspectRatio
    readonly property real thumbnailRadius: Math.min(
        DockSettings.cornerRadius, thumbnailWidth / 2, thumbnailHeight / 2)
    readonly property color panelColor: DockView.backgroundColor.a > 0
        ? DockView.backgroundColor
        : Qt.alpha(Kirigami.Theme.backgroundColor, DockSettings.backgroundOpacity)
    readonly property color panelForeground: BadgeTextColor.choose(
        panelColor, Kirigami.Theme.textColor)
    readonly property color inactiveBorderColor: PreviewBorderColor.colorForSurface(
        panelColor, Kirigami.Theme.backgroundColor, thumbnailHover.hovered)

    implicitWidth: thumbnailWidth
    // The image is anchored below the fixed-height title row. Using the
    // label's smaller implicit height under-reported this item's height and
    // left a visibly smaller inset below the image than beside it.
    implicitHeight: titleRow.height + titleToThumbnailSpacing + thumbnailHeight

    // PipeWire screencasting: uuid → nodeId
    // Match Plasma's pattern: pass winId directly, let QML engine handle QVariant→QString
    TaskManager.ScreencastingRequest {
        id: screencastRequest
        uuid: root.winId ?? ""
        onNodeIdChanged: function() {
            console.log("[kdockw.preview] nodeId:", screencastRequest.nodeId,
                "for uuid:", screencastRequest.uuid)
        }
    }

    // Retry screencast when nodeId is 0 (KWin hadn't registered the window yet).
    // Called from PreviewPopup.rebuildChildModel() on each KDE model event.
    function retryScreencast() {
        if (screencastRequest.nodeId === 0 && root.winId) {
            screencastRequest.uuid = ""
            screencastRequest.uuid = root.winId ?? ""
        }
    }

    function updateSourceAspectRatio() {
        const capture = root.captureItem
        if (!capture || !capture.ready)
            return

        const size = capture.streamSize
        const maxDimension = 32768
        const maxPixels = 268435456
        if (!size || size.width < 1 || size.height < 1
                || size.width > maxDimension || size.height > maxDimension
                || size.width * size.height > maxPixels)
            return

        const ratio = size.width / size.height
        if (!Number.isFinite(ratio) || ratio < 1 / 32 || ratio > 32)
            return

        root.sourceAspectRatio = ratio
    }

    function captureRectInViewport(capture) {
        const topLeft = capture.mapToItem(root.captureViewport, 0, 0)
        const bottomRight = capture.mapToItem(
            root.captureViewport, capture.width, capture.height)
        return {
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        }
    }

    function retryWithoutDmaBuf() {
        if (forceCpuCapture)
            return

        console.warn("[kdockw.preview] no frame received while streaming; retrying without DMA-BUF, nodeId:",
            screencastRequest.nodeId)
        forceCpuCapture = true
        hasFrameWhileVisible = false
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    function restartCapture() {
        forceCpuCapture = false
        hasFrameWhileVisible = false
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    function resetCaptureForWindowChange() {
        // A grouped row may be reused for a different UUID after removal/reorder.
        // Destroy the old source so its last texture can never be shown for the
        // new window while ScreencastingRequest resolves the replacement node.
        forceCpuCapture = false
        hasFrameWhileVisible = false
        sourceAspectRatio = 1.6
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    function cacheLastRenderedFrame(reason) {
        if (frameSnapshotPending || !PreviewController.visible || isMinimized || !hasFrameWhileVisible
                || !captureItem || !captureItem.ready || !captureLoader.visible)
            return false

        const now = Date.now()
        if (PreviewController.previewFrameUrl(winId).length > 0
                && now - lastFrameSnapshotAt < 1500)
            return false

        const uuidAtRequest = winId
        const window = root.Window.window
        const reportedDpr = window ? window.devicePixelRatio : root.Screen.devicePixelRatio
        const dpr = Number.isFinite(reportedDpr) && reportedDpr > 0 ? reportedDpr : 1
        const width = Math.max(1, Math.min(640, Math.ceil(captureLoader.width * dpr)))
        const height = Math.max(1, Math.min(400, Math.ceil(captureLoader.height * dpr)))
        const accepted = PreviewController.capturePreviewFrame(
            captureLoader, uuidAtRequest, Qt.size(width, height))
        if (accepted) {
            frameSnapshotPending = true
            lastFrameSnapshotAt = now
            frameSnapshotTimeoutTimer.restart()
            logPreviewLifecycle("frame-capture-requested", {
                reason: reason,
                uuid: uuidAtRequest,
                size: width + "x" + height,
                previewVisible: PreviewController.visible
            })
        }
        if (!accepted && typeof IconDiagnostics !== "undefined" && IconDiagnostics.taskDiagnosticsEnabled)
            console.warn("[KDOCKW_PREVIEW_FRAME_CACHE] phase=" + reason + " accepted=false")
        return accepted
    }

    function logPreviewLifecycle(phase, details) {
        if (typeof IconDiagnostics === "undefined" || !IconDiagnostics.taskDiagnosticsEnabled)
            return
        const capture = root.captureItem
        const frameUrl = PreviewController.previewFrameUrl(root.winId)
        console.info("[KDOCKW_PREVIEW_LIFECYCLE]", JSON.stringify(Object.assign({
            phase: phase,
            uuid: root.winId,
            captureUuid: root.captureWinId,
            minimized: root.isMinimized,
            active: root.isActive,
            previewVisible: PreviewController.visible,
            hasFrameWhileVisible: root.hasFrameWhileVisible,
            cacheAvailable: frameUrl.length > 0,
            frameUrl: frameUrl,
            captureReady: capture ? capture.ready : false,
            captureState: capture ? capture.state : -1,
            freezeFrame: capture && capture.freezeFrame !== undefined ? capture.freezeFrame : false,
            retainedImageVisible: retainedFrameImage.visible,
            fallbackVisible: fallbackIcon.visible
        }, details || {})))
    }

    onCaptureItemChanged: updateSourceAspectRatio()
    onIsMinimizedChanged: {
        logPreviewLifecycle("minimized-state-changed", {
            frameSnapshotPending: frameSnapshotPending
        })
        if (!isMinimized && captureItem && captureItem.ready) {
            hasFrameWhileVisible = true
        }
    }
    Component.onCompleted: {
        captureWinId = winId
        updateSourceAspectRatio()
    }
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onScreenChanged() { root.logCaptureState("preview-screen-changed") }
        function onFrameSwapped() {
            if (!root.frameSnapshotPending)
                root.cacheLastRenderedFrame("live-frame-swapped")
        }
    }
    Connections {
        target: PreviewController
        function onPreviewFramesChanged() {
            if (PreviewController.previewFrameUrl(root.winId).length > 0) {
                root.frameSnapshotPending = false
                frameSnapshotTimeoutTimer.stop()
                root.logPreviewLifecycle("frame-cache-available")
            }
        }
    }
    onWinIdChanged: {
        if (captureWinId === undefined) {
            captureWinId = winId
            logPreviewLifecycle("window-uuid-initialized")
            return
        }
        if (captureWinId === winId)
            return
        logPreviewLifecycle("window-uuid-changing", { previousUuid: captureWinId, nextUuid: winId })
        captureWinId = winId
        resetCaptureForWindowChange()
        frameSnapshotPending = false
        lastFrameSnapshotAt = 0
        logPreviewLifecycle("window-uuid-changed")
    }

    function logCaptureState(reason) {
        const capture = root.captureItem
        if (!capture)
            return
        if (IconDiagnostics.previewCaptureMetrics
                && root.captureSourceMode === "pipewire") {
            const dpr = root.Screen.devicePixelRatio > 0
                ? root.Screen.devicePixelRatio : IconDiagnostics.windowDevicePixelRatio
            const stream = capture.streamSize
            const viewport = Qt.size(root.captureViewportWidth, root.captureViewportHeight)
            const content = Qt.size(root.captureContentWidth, root.captureContentHeight)
            const mapped = root.captureRectInViewport(capture)
            const painted = capture.paintedRect
            console.info("[kdockw.preview.metrics]", JSON.stringify({
                event: reason,
                pipeWireFramePixels: { width: stream.width, height: stream.height },
                frameReady: capture.ready,
                streamState: capture.state,
                acceptedSourceAspectRatio: root.sourceAspectRatio,
                windowDpr: dpr,
                thumbnailSlotLogical: { width: root.thumbnailWidth, height: root.thumbnailHeight },
                viewportLogical: { width: viewport.width, height: viewport.height },
                viewportPhysical: { width: viewport.width * dpr, height: viewport.height * dpr },
                coverContentLogical: { width: content.width, height: content.height },
                coverContentPhysical: { width: content.width * dpr, height: content.height * dpr },
                physicalPixelsPerStreamPixel: {
                    x: stream.width > 0 ? content.width * dpr / stream.width : null,
                    y: stream.height > 0 ? content.height * dpr / stream.height : null
                },
                sourceMappedToViewport: mapped,
                paintedRect: {
                    x: painted.x, y: painted.y,
                    width: painted.width, height: painted.height
                },
                usingDmaBuf: capture.usingDmaBuf,
                captureMode: root.forceCpuCapture ? "cpu-fallback"
                    : PreviewController.cpuCaptureOnly ? "cpu-only" : "auto"
            }))
        }
        if (root.captureSourceMode === "image") {
            console.log("[kdockw.preview] source-test", reason,
                "source: QML Image", "clipMode:", root.captureClipMode,
                "sourceGeometry:", Qt.rect(capture.x, capture.y, capture.width, capture.height),
                "viewport:", Qt.size(root.captureViewportWidth, root.captureViewportHeight),
                "mappedToViewport:", root.captureRectInViewport(capture))
            return
        }
        const error = capture.state === 0 ? capture.error() : ""
        console.log("[kdockw.preview] capture", reason,
            "nodeId:", capture.nodeId,
            "captureMode:", root.forceCpuCapture ? "cpu-fallback"
                : PreviewController.cpuCaptureOnly ? "cpu-only" : "auto",
            "clipMode:", root.captureClipMode,
            "state:", capture.state,
            "ready:", capture.ready,
            "streamSize:", capture.streamSize,
            "sourceGeometry:", Qt.rect(capture.x, capture.y, capture.width, capture.height),
            "sourceMappedToViewport:", root.captureRectInViewport(capture),
            "paintedRect:", capture.paintedRect,
            "itemRect:", Qt.size(capture.width, capture.height),
            "visible/opacity/z:", capture.visible, capture.opacity, capture.z,
            "viewport:", Qt.size(root.thumbnailWidth, root.thumbnailHeight),
            "imageViewport:", Qt.size(root.captureViewportWidth, root.captureViewportHeight),
            "coverRect:", Qt.size(root.captureContentWidth, root.captureContentHeight),
            "dmaBuf:", capture.usingDmaBuf,
            "error:", error)
    }

    // Keyboard focus ring for preview thumbnail
    Rectangle {
        id: previewFocusRing
        anchors.fill: thumbnailContainer
        anchors.margins: -2
        radius: root.thumbnailRadius + 2
        color: "transparent"
        border.color: Kirigami.Theme.focusColor
        border.width: 2
        visible: root.isKeyboardFocused
        Accessible.ignored: true
    }

    // Thumbnail container
    Rectangle {
        id: thumbnailContainer
        objectName: "previewThumbnailContainer"
        anchors.top: titleRow.bottom
        anchors.topMargin: root.titleToThumbnailSpacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.thumbnailWidth
        height: root.thumbnailHeight
        radius: root.thumbnailRadius
        color: root.panelColor

        // The popup uses the hovered thumbnail to retain the exact grouped
        // window target when the pointer moves to the shared header control.
        HoverHandler {
            id: thumbnailHover
        }

        // One timeout per asynchronous readback keeps a missing completion
        // from blocking later captures. The controller owns outstanding grabs.
        Timer {
            id: frameSnapshotTimeoutTimer
            interval: 5000
            repeat: false
            onTriggered: root.frameSnapshotPending = false
        }

        border.color: root.isActive ? Kirigami.Theme.highlightColor : "transparent"
        border.width: root.isActive ? 2 : 0

        // GPU-accelerated PipeWire thumbnail
        Loader {
            id: captureLoader
            objectName: "previewImageViewport"
            anchors.fill: parent
            anchors.margins: root.captureBorderWidth
            // Keep the PipeWire stream alive while minimized. When no frame
            // was captured from a visible window, show the app icon instead
            // of KWin's empty minimized-window buffer.
            opacity: !root.isMinimized || root.hasFrameWhileVisible ? 1 : 0
            sourceComponent: root.captureClipMode === "raw" ? rawCaptureComponent
                : root.captureClipMode === "center50" ? center50CaptureComponent
                : root.captureSourceMode === "image" ? roundedImageReferenceComponent
                : roundedPipeWireCaptureComponent
            onLoaded: Qt.callLater(() => root.logCaptureState("component-loaded"))

            Component {
                id: pipeWireSourceComponent
                PipeWire.PipeWireSourceItem {
                    nodeId: screencastRequest.nodeId
                    allowDmaBuf: !PreviewController.cpuCaptureOnly && !root.forceCpuCapture
                    Accessible.ignored: true
                }
            }

            Component {
                id: imageSourceComponent
                Image {
                    source: Qt.resolvedUrl("fixtures/preview-clip-pattern.svg")
                    fillMode: Image.Stretch
                    smooth: true
                    Accessible.ignored: true
                }
            }

            Component {
                id: rawCaptureComponent
                Item {
                    objectName: "rawCaptureViewport"
                    property alias sourceItem: sourceLoader.item
                    Loader {
                        id: sourceLoader
                        width: root.captureContentWidth
                        height: root.captureContentHeight
                        x: (parent.width - width) / 2
                        y: (parent.height - height) / 2
                        sourceComponent: root.captureSourceMode === "image"
                            ? imageSourceComponent : pipeWireSourceComponent
                        onLoaded: {
                            if (item) {
                                item.width = width
                                item.height = height
                            }
                        }
                    }
                }
            }

            Component {
                id: center50CaptureComponent
                Item {
                    objectName: "center50CaptureViewport"
                    property alias sourceItem: sourceLoader.item
                    Item {
                        id: center50Clip
                        objectName: "center50BuiltInClip"
                        width: root.captureContentWidth / 2
                        height: root.captureContentHeight / 2
                        x: (parent.width - root.captureContentWidth) / 2 + width / 2
                        y: (parent.height - root.captureContentHeight) / 2 + height / 2
                        clip: true
                        Loader {
                            id: sourceLoader
                            width: root.captureContentWidth
                            height: root.captureContentHeight
                            x: -width / 4
                            y: -height / 4
                            sourceComponent: root.captureSourceMode === "image"
                                ? imageSourceComponent : pipeWireSourceComponent
                            onLoaded: {
                                if (item) {
                                    item.width = width
                                    item.height = height
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: roundedPipeWireCaptureComponent
                Item {
                    objectName: "roundedCaptureViewport"
                    property alias sourceItem: captureSource
                    ClippedPipeWireSourceItem {
                        id: captureSource
                        objectName: "roundedPipeWireSource"
                        width: root.captureContentWidth
                        height: root.captureContentHeight
                        x: (parent.width - width) / 2
                        y: (parent.height - height) / 2
                        clipMode: "rounded"
                        clipViewportRect: Qt.rect(
                            (width - root.captureViewportWidth) / 2,
                            (height - root.captureViewportHeight) / 2,
                            root.captureViewportWidth,
                            root.captureViewportHeight)
                        clipRadius: root.captureViewportRadius
                        nodeId: screencastRequest.nodeId
                        allowDmaBuf: !PreviewController.cpuCaptureOnly && !root.forceCpuCapture
                        freezeFrame: root.isMinimized && root.hasFrameWhileVisible
                        Accessible.ignored: true
                    }
                }
            }

            Component {
                id: roundedImageReferenceComponent
                Item {
                    objectName: "roundedImageReferenceViewport"
                    property alias sourceItem: sourceImage
                    clip: true
                    Image {
                        id: sourceImage
                        objectName: "imageSourceReference"
                        source: Qt.resolvedUrl("fixtures/preview-clip-pattern.svg")
                        width: root.captureContentWidth
                        height: root.captureContentHeight
                        x: (parent.width - width) / 2
                        y: (parent.height - height) / 2
                        fillMode: Image.Stretch
                        smooth: true
                        Accessible.ignored: true
                    }
                }
            }

            Connections {
                target: root.captureItem
                ignoreUnknownSignals: true
                function onStateChanged() { root.logCaptureState("state-changed") }
                function onReadyChanged() {
                    root.updateSourceAspectRatio()
                    if (root.captureItem && root.captureItem.ready && !root.isMinimized) {
                        root.hasFrameWhileVisible = true
                    }
                    root.logPreviewLifecycle("capture-ready-changed")
                    root.logCaptureState("ready-changed")
                }
                function onStreamSizeChanged() {
                    root.updateSourceAspectRatio()
                    root.logCaptureState("stream-size-changed")
                }
                function onUsingDmaBufChanged() { root.logCaptureState("dma-buf-changed") }
            }

            Connections {
                target: PreviewController
                function onCaptureModeChanged() { root.restartCapture() }
            }

            // KWin can briefly publish DMA-BUF buffers before PipeWire has
            // resolved their memory type. KPipeWire drops those frames; retry
            // once with CPU-readable buffers if Streaming produces no frame.
            Timer {
                interval: 1500
                repeat: false
                running: !root.forceCpuCapture
                    && !PreviewController.cpuCaptureOnly
                    && root.captureItem !== null
                    && root.captureItem.visible
                    && root.captureItem.state === 4 // PipeWireSourceItem::Streaming
                    && !root.captureItem.ready
                onTriggered: root.retryWithoutDmaBuf()
            }
        }

        Image {
            id: retainedFrameImage
            objectName: "minimizedCachedFrame"
            anchors.fill: captureLoader
            z: 1
            source: root.cachedFrameSource
            // `Image.source` is a QUrl in QML, not a JS string, so it has no
            // reliable `length` property. Test the URL string binding instead.
            visible: root.isMinimized && root.cachedFrameSource.length > 0
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            cache: false
            Accessible.ignored: true
        }

        // Fallback: icon until PipeWire has received a frame.
        Item {
            id: fallbackIcon
            objectName: "previewFallbackIcon"
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: Kirigami.Units.iconSizes.large
            readonly property string iconName: {
                // iconName() is invokable, so track the model's artwork revision.
                let iconCacheVersion = DockView.iconCacheVersion
                return DockModel.iconName(root.parentIndex) || "application-x-executable"
            }
            readonly property bool isRawIcon: iconName.startsWith("raw:")
            visible: !root.cachedFrameSource.length && (!root.captureItem || !root.captureItem.ready
                || (root.isMinimized && !root.hasFrameWhileVisible))

            Kirigami.Icon {
                anchors.fill: parent
                source: fallbackIcon.isRawIcon ? "" : fallbackIcon.iconName
                visible: !fallbackIcon.isRawIcon
            }

            Image {
                anchors.fill: parent
                source: fallbackIcon.isRawIcon
                    ? "image://icon/" + fallbackIcon.iconName + "?v=" + DockView.iconCacheVersion
                    : ""
                sourceSize: Qt.size(width, height)
                smooth: true
                visible: fallbackIcon.isRawIcon
            }
        }

        // Hover highlight
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Kirigami.Theme.highlightColor
            opacity: thumbnailHover.hovered ? 0.1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
        }

        // Keep the inactive outline above the PipeWire frame without adding
        // capture insets, changing the fixed thumbnail size, or allocating an
        // offscreen layer. The active KDE accent border remains on the parent.
        Rectangle {
            objectName: "previewInactiveBorder"
            anchors.fill: parent
            radius: root.thumbnailRadius
            color: "transparent"
            border.color: root.inactiveBorderColor
            border.width: 1
            antialiasing: true
            visible: !root.isActive
            Accessible.ignored: true
        }

        // Click to activate window
        MouseArea {
            id: thumbnailMouseArea
            objectName: "previewThumbnailActivationArea"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            Accessible.ignored: true

            onClicked: {
                // childIndex < 0 = single window (parent row IS the window)
                let modelIndex = (root.childIndex < 0)
                    ? DockModel.tasksModel.index(root.parentIndex, 0)
                    : DockModel.tasksModel.makeModelIndex(root.parentIndex, root.childIndex)
                if (!modelIndex.valid)
                    return
                PreviewController.suppressPreviewUntilPointerLeavesTask(root.parentIndex)
                DockModel.tasksModel.requestActivate(modelIndex)
                PreviewController.hidePreview()
            }
        }
    }

    // Keep the title and its per-window close control in one stable row above
    // the image. The button receives pointer input outside the activation area.
    RowLayout {
        id: titleRow
        objectName: "previewThumbnailTitleRow"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing
        height: 22

        QQC2.Label {
            id: titleLabel
            objectName: "previewThumbnailTitle"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.title
            color: root.panelForeground
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font: Kirigami.Theme.smallFont
        }

        PreviewCloseButton {
            objectName: "previewThumbnailCloseButton"
            visible: root.showCloseButton
            Layout.preferredWidth: root.showCloseButton ? 22 : 0
            Layout.minimumWidth: root.showCloseButton ? 22 : 0
            Layout.maximumWidth: root.showCloseButton ? 22 : 0
            Layout.preferredHeight: 22
            Layout.minimumHeight: 22
            Layout.maximumHeight: 22
            windowTitle: root.title
            onClicked: root.closeRequested(root.winId)
        }
    }
}
