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

/**
 * A single window thumbnail in the preview popup.
 *
 * Uses PipeWire + ScreencastingRequest for GPU-accelerated live thumbnails.
 * Shows close button on hover, click to activate window.
 */
Item {
    id: root

    property var winId
    property string title: ""
    property bool isMinimized: false
    property bool isActive: false
    property int parentIndex: -1
    property int childIndex: 0
    property bool isKeyboardFocused: false
    property bool forceCpuCapture: false
    property var captureWinId: undefined
    readonly property var captureItem: captureLoader.item ? captureLoader.item.sourceItem : null
    readonly property var captureViewport: captureLoader.item
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

    readonly property real sourceAspectRatio: {
        const size = root.captureItem ? root.captureItem.streamSize : null
        return size && size.width > 0 && size.height > 0 ? size.width / size.height : 1.6
    }
    // Keep a stable 16:10 preview slot for every app. The image fills the
    // inner card area and a scene-graph clip rounds its visible corners.
    readonly property real thumbnailWidth: Math.min(
        DockSettings.previewThumbnailSize,
        DockSettings.previewMaximumHeight * 1.6)
    readonly property real thumbnailHeight: thumbnailWidth / 1.6
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

    implicitWidth: thumbnailWidth
    implicitHeight: thumbnailHeight + titleLabel.implicitHeight + Kirigami.Units.smallSpacing

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
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    function restartCapture() {
        forceCpuCapture = false
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    function resetCaptureForWindowChange() {
        // A grouped row may be reused for a different UUID after removal/reorder.
        // Destroy the old source so its last texture can never be shown for the
        // new window while ScreencastingRequest resolves the replacement node.
        forceCpuCapture = false
        captureLoader.active = false
        Qt.callLater(function() { captureLoader.active = true })
    }

    Component.onCompleted: captureWinId = winId
    onWinIdChanged: {
        if (captureWinId === undefined) {
            captureWinId = winId
            return
        }
        if (captureWinId === winId)
            return
        captureWinId = winId
        resetCaptureForWindowChange()
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
        anchors.top: titleLabel.bottom
        anchors.topMargin: Kirigami.Units.smallSpacing / 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.thumbnailWidth
        height: root.thumbnailHeight
        radius: root.thumbnailRadius
        color: root.panelColor

        // Passive hover detection — not affected by ToolButton z-order.
        // MouseArea.containsMouse goes false when ToolButton appears on top,
        // but HoverHandler stays hovered because it uses passive grab.
        HoverHandler {
            id: thumbnailHover
        }

        border.color: root.isActive ? Kirigami.Theme.highlightColor : "transparent"
        border.width: root.isActive ? 2 : 0

        // GPU-accelerated PipeWire thumbnail
        Loader {
            id: captureLoader
            objectName: "previewImageViewport"
            anchors.fill: parent
            anchors.margins: root.captureBorderWidth
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
                function onReadyChanged() { root.logCaptureState("ready-changed") }
                function onStreamSizeChanged() { root.logCaptureState("stream-size-changed") }
                function onUsingDmaBufChanged() { root.logCaptureState("dma-buf-changed") }
            }

            Connections {
                target: PreviewController
                function onCaptureModeChanged() { root.restartCapture() }
            }

            Connections {
                target: root.Window.window
                ignoreUnknownSignals: true
                function onScreenChanged() { root.logCaptureState("preview-screen-changed") }
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

        // Fallback: icon until PipeWire has received a frame.
        Item {
            id: fallbackIcon
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: Kirigami.Units.iconSizes.large
            readonly property string iconName: {
                // iconName() is invokable, so track the model's artwork revision.
                let iconCacheVersion = DockView.iconCacheVersion
                return DockModel.iconName(root.parentIndex) || "application-x-executable"
            }
            readonly property bool isRawIcon: iconName.startsWith("raw:")
            visible: !root.captureItem || !root.captureItem.ready

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

        // Close button (top-right corner, always visible)
        QQC2.ToolButton {
            id: closeButton
            objectName: "previewCloseButton"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.smallSpacing
            width: Kirigami.Units.iconSizes.smallMedium
            height: Kirigami.Units.iconSizes.smallMedium
            hoverEnabled: true
            z: 10

            contentItem: Text {
                objectName: "previewCloseCross"
                anchors.fill: parent
                text: "×"
                color: "#351010"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.QtRendering
                visible: closeButton.hovered || closeButton.down
            }

            Accessible.name: i18n("Close %1", root.title)

            onClicked: {
                // childIndex < 0 = single window (parent row IS the window)
                let modelIndex = (root.childIndex < 0)
                    ? DockModel.tasksModel.index(root.parentIndex, 0)
                    : DockModel.tasksModel.makeModelIndex(root.parentIndex, root.childIndex)
                DockModel.tasksModel.requestClose(modelIndex)
            }

            background: Rectangle {
                radius: width / 2
                color: closeButton.down ? "#E6534D" : "#FF5F57"
            }
        }

        // Click to activate window
        MouseArea {
            id: thumbnailMouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            Accessible.ignored: true

            onClicked: {
                // childIndex < 0 = single window (parent row IS the window)
                let modelIndex = (root.childIndex < 0)
                    ? DockModel.tasksModel.index(root.parentIndex, 0)
                    : DockModel.tasksModel.makeModelIndex(root.parentIndex, root.childIndex)
                DockModel.tasksModel.requestActivate(modelIndex)
                PreviewController.hidePreview()
            }
        }
    }

    // Window title
    QQC2.Label {
        id: titleLabel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.thumbnailWidth
        text: root.title
        color: root.panelForeground
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        maximumLineCount: 1
        font: Kirigami.Theme.smallFont
    }
}
