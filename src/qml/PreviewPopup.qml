// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

/**
 * Preview popup root component.
 *
 * Loaded into a full-width layer-shell overlay surface.
 * Only the popup rectangle receives input (via input region in C++).
 *
 * Keyboard navigation is driven entirely from the dock surface via
 * PreviewController C++ properties (previewKeyboardActive, focusedThumbnailIndex).
 * This avoids unreliable focus transfer between layer-shell surfaces.
 */
Item {
    id: root
    anchors.fill: parent

    // C++ singletons: PreviewController, DockModel

    function announcePreviewOpen(appName, count) {
        Accessible.announce(
            i18n("Preview for %1, %2", appName, i18np("1 window", "%1 windows", count)),
            Accessible.Polite)
    }

    // Surface-level hover detection: keep preview visible when mouse is anywhere
    // on this surface. The C++ input region (updateInputRegion) already constrains
    // which events reach this surface to the visible popup rectangle, so detecting
    // hover at the surface root is equivalent to detecting hover on the popup.
    // This is more reliable than a popup-child MouseArea because it doesn't depend
    // on popup geometry, which can shift during layout.
    HoverHandler {
        id: surfaceHover
        onHoveredChanged: {
            PreviewController.setPreviewHovered(hovered)
            // Mouse movement cancels keyboard navigation in preview
            if (hovered && PreviewController.previewKeyboardActive) {
                PreviewController.endPreviewKeyboardNav()
            }
        }
    }

    // Child window model for grouped preview.
    // Uses ListModel instead of JS array so Repeater preserves delegates
    // on incremental updates — critical for keeping PipeWire streams alive.
    ListModel {
        id: childWindowModel
    }

    function rebuildChildModel() {
        let parentIdx = PreviewController.parentIndex
        if (parentIdx < 0) {
            // Keep delegates alive so PipeWire streams pause/resume naturally
            // via visibility cascade. Destroying delegates triggers
            // ScreencastingRequest race conditions on reopen.
            return
        }

        // The parent WinIdList is useful for knowing how many grouped window
        // rows currently have IDs, but each child's own WinIdList is the stable
        // identity for its thumbnail. Do not index into the parent list: after
        // a child is removed, its child row may shift before the aggregate list
        // is updated, which could temporarily assign a neighbor's old UUID.
        let parentModelIdx = DockModel.tasksModel.index(parentIdx, 0)
        let allWinIds = DockModel.tasksModel.data(
            parentModelIdx, TaskManager.AbstractTasksModel.WinIdList) || []

        let childCount = DockModel.childCount(parentIdx)

        // === Single window (not grouped): parent row IS the window ===
        // KDE TasksModel tree: single window → rowCount(idx) = 0 (no children)
        // Group (2+ windows) → rowCount(idx) = N (N children)
        if (childCount === 0) {
            if (allWinIds.length > 0) {
                let entry = {
                    winId: allWinIds[0],
                    title: DockModel.tasksModel.data(
                        parentModelIdx, Qt.DisplayRole) || "",
                    isMinimized: DockModel.tasksModel.data(
                        parentModelIdx,
                        TaskManager.AbstractTasksModel.IsMinimized) || false,
                    isActive: DockModel.tasksModel.data(
                        parentModelIdx,
                        TaskManager.AbstractTasksModel.IsActive) || false,
                    childIndex: -1  // sentinel: use parent row directly
                }
                if (childWindowModel.count > 0) {
                    childWindowModel.set(0, entry)
                } else {
                    childWindowModel.append(entry)
                }
                while (childWindowModel.count > 1) {
                    childWindowModel.remove(childWindowModel.count - 1)
                }
            } else {
                // Launcher only (no windows) — clear model
                while (childWindowModel.count > 0) {
                    childWindowModel.remove(childWindowModel.count - 1)
                }
            }
        } else {
            // === Grouped (2+ windows): use child rows ===
            // Use the lesser of childCount and aggregate ID count when the parent
            // list is briefly behind. Individual child IDs still come from the
            // matching child row, so row removal/reordering cannot reuse a
            // neighbor's previous UUID.
            let maxCount = Math.min(childCount, allWinIds.length)

            // Incremental update: set() preserves existing delegates (and their
            // PipeWire streams), append() adds new ones, remove() trims excess.
            for (let i = 0; i < maxCount; i++) {
                let childModelIndex = DockModel.tasksModel.makeModelIndex(parentIdx, i)
                let childWinIds = DockModel.tasksModel.data(
                    childModelIndex, TaskManager.AbstractTasksModel.WinIdList) || []
                if (childWinIds.length === 0)
                    break
                let entry = {
                    winId: childWinIds[0],
                    title: DockModel.tasksModel.data(childModelIndex, Qt.DisplayRole) || "",
                    isMinimized: DockModel.tasksModel.data(
                        childModelIndex, TaskManager.AbstractTasksModel.IsMinimized) || false,
                    isActive: DockModel.tasksModel.data(
                        childModelIndex, TaskManager.AbstractTasksModel.IsActive) || false,
                    childIndex: i
                }

                if (i < childWindowModel.count) {
                    childWindowModel.set(i, entry)
                } else {
                    childWindowModel.append(entry)
                }
            }

            // Remove excess items from the end
            while (childWindowModel.count > maxCount) {
                childWindowModel.remove(childWindowModel.count - 1)
            }
        }

        // Retry screencast for delegates where KWin hadn't registered the window yet.
        // Called on each KDE model event (dataChanged, rowsInserted, etc.),
        // so new windows get multiple retry chances without timers.
        for (let i = 0; i < thumbnailRepeater.count; i++) {
            let item = thumbnailRepeater.itemAt(i)
            if (item) item.retryScreencast()
        }
    }

    Connections {
        target: PreviewController
        function onParentIndexChanged() {
            if (PreviewController.parentIndex >= 0) {
                // Different app = different PipeWire streams, must recreate delegates
                childWindowModel.clear()
            }
            root.rebuildChildModel()
        }
        function onVisibleChanged() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                let count = childWindowModel.count
                root.announcePreviewOpen(PreviewController.appName, count)
            }
        }
    }

    // Also rebuild when the underlying model data changes (window close, title change)
    Connections {
        target: DockModel.tasksModel
        function onDataChanged() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                root.rebuildChildModel()
            }
        }
        function onRowsInserted() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                root.rebuildChildModel()
            }
        }
        function onRowsRemoved() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                // Child removed: check if parent still valid
                let parentIdx = PreviewController.parentIndex
                let parentModelIdx = DockModel.tasksModel.index(parentIdx, 0)
                if (!parentModelIdx.valid) {
                    PreviewController.hidePreview()
                } else {
                    root.rebuildChildModel()
                }
            }
        }
    }

    // The visible popup card. Its outer item includes the shadow bounds so
    // placement clamping and the Wayland input region account for the effect.
    Item {
        id: popup
        readonly property bool requestedVisible: PreviewController.visible && PreviewController.parentIndex >= 0
        readonly property real cardPadding: DockSettings.previewCardPadding
        readonly property real shadowMargin: Kirigami.Units.smallSpacing * 2
        // Follow the dock's resolved Header/Selection/tint color, not the
        // unrelated Window color from the current Plasma color scheme.
        readonly property color surfaceColor: DockView.backgroundColor.a > 0
            ? DockView.backgroundColor
            : Qt.alpha(Kirigami.Theme.backgroundColor, DockSettings.backgroundOpacity)
        readonly property color foregroundColor: BadgeTextColor.choose(
            surfaceColor, Kirigami.Theme.textColor)
        readonly property color outlineColor: Qt.alpha(foregroundColor, 0.27)

        visible: requestedVisible || opacity > 0.01
        opacity: requestedVisible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        implicitWidth: popupContent.implicitWidth + 2 * (cardPadding + shadowMargin)
        implicitHeight: popupContent.implicitHeight + 2 * (cardPadding + shadowMargin)
        width: implicitWidth
        height: implicitHeight

        Accessible.role: Accessible.PopupMenu
        Accessible.name: PreviewController.appName
            ? i18n("Preview for %1", PreviewController.appName)
            : ""
        x: {
            if (DockView.edge === 2) return 0                            // Left → left edge
            if (DockView.edge === 3) return parent.width - width         // Right → right edge
            return PreviewController.contentX                            // Top/Bottom → centered
        }
        y: {
            if (DockView.edge === 0) return 0                            // Top → top edge
            if (DockView.edge === 1) return parent.height - height       // Bottom → bottom edge
            return PreviewController.contentY                            // Left/Right → centered
        }
        // Report size to controller for input region + positioning
        onWidthChanged: PreviewController.setContentSize(width, height)
        onHeightChanged: PreviewController.setContentSize(width, height)

        Kirigami.ShadowedRectangle {
            id: card
            anchors.fill: parent
            anchors.margins: popup.shadowMargin
            radius: Math.min(DockSettings.cornerRadius, width / 2, height / 2)
            color: popup.surfaceColor
            border.color: popup.outlineColor
            border.width: 1
            shadow.size: DockSettings.shadowEnabled ? DockSettings.shadowLightRadius * 2 : 0
            shadow.xOffset: -DockSettings.shadowLightX * DockSettings.shadowElevation
                / Math.max(1, DockSettings.shadowLightZ)
            shadow.yOffset: -DockSettings.shadowLightY * DockSettings.shadowElevation
                / Math.max(1, DockSettings.shadowLightZ)
            shadow.color: Qt.alpha(DockSettings.shadowColor, DockSettings.shadowIntensity)

            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            Kirigami.Theme.inherit: false
        }

        ColumnLayout {
            id: popupContent
            anchors.fill: card
            anchors.margins: popup.cardPadding
            spacing: Kirigami.Units.smallSpacing

            // Compact app header. The app name is part of this card, so the
            // dock's separate app-name tooltip must stay hidden while it is open.
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: groupedRow.implicitWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                Item {
                    readonly property string iconName: DockModel.iconName(PreviewController.parentIndex)
                        || "application-x-executable"
                    readonly property bool rawIcon: iconName.startsWith("raw:")
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small

                    Kirigami.Icon {
                        anchors.fill: parent
                        source: parent.rawIcon ? "" : parent.iconName
                        visible: !parent.rawIcon
                        Accessible.ignored: true
                    }
                    Image {
                        anchors.fill: parent
                        source: parent.rawIcon
                            ? "image://icon/" + parent.iconName + "?v=" + DockView.iconCacheVersion
                            : ""
                        sourceSize: Qt.size(width, height)
                        smooth: true
                        visible: parent.rawIcon
                        Accessible.ignored: true
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: PreviewController.appName
                        color: popup.foregroundColor
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            // Grouped windows: horizontal row of thumbnails
            Row {
                id: groupedRow
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing
                // Retain thumbnails through the fade-out so the content and
                // card opacity animate together; source items pause when the
                // outer popup finishes fading and becomes invisible.
                visible: popup.visible

                Repeater {
                    id: thumbnailRepeater
                    model: childWindowModel

                    PreviewThumbnail {
                        winId: model.winId
                        title: model.title
                        isMinimized: model.isMinimized
                        isActive: model.isActive
                        parentIndex: PreviewController.parentIndex
                        childIndex: model.childIndex
                        // Focus ring driven by C++ PreviewController state
                        isKeyboardFocused: PreviewController.previewKeyboardActive
                            && PreviewController.focusedThumbnailIndex === index
                    }
                }
            }

        }
    }
}
