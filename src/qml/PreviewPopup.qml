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

    Component.onCompleted: root.rebuildChildModel("component-completed")

    function logPreviewLifecycle(phase, details) {
        if (typeof IconDiagnostics === "undefined" || !IconDiagnostics.taskDiagnosticsEnabled)
            return
        console.info("[KDOCKW_PREVIEW_LIFECYCLE]", JSON.stringify(Object.assign({
            phase: phase,
            parentIndex: PreviewController.parentIndex,
            previewVisible: PreviewController.visible,
            childCount: childWindowModel.count
        }, details || {})))
    }

    function setThumbnailForWindow(index, entry) {
        let existingIndex = -1
        for (let i = 0; i < childWindowModel.count; i++) {
            if (childWindowModel.get(i).winId === entry.winId) {
                existingIndex = i
                break
            }
        }
        if (existingIndex >= 0 && existingIndex !== index) {
            childWindowModel.move(existingIndex, index, 1)
        } else if (existingIndex < 0 && index >= childWindowModel.count) {
            childWindowModel.append(entry)
            return
        }
        childWindowModel.set(index, entry)
    }

    function rebuildChildModel(reason) {
        let parentIdx = PreviewController.parentIndex
        logPreviewLifecycle("model-rebuild-start", { reason: reason || "unspecified" })
        if (parentIdx < 0) {
            popup.groupedPreview = false
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
        const parentTaskIndex = DockModel.dockPresentationModel.taskIndexForDockIndex(parentIdx)
        if (parentTaskIndex < 0) {
            popup.groupedPreview = false
            return
        }
        let parentModelIdx = DockModel.tasksModel.index(parentTaskIndex, 0)
        let allWinIds = DockModel.tasksModel.data(
            parentModelIdx, TaskManager.AbstractTasksModel.WinIdList) || []

        let childCount = DockModel.childCount(parentTaskIndex)
        // Keep this state signal-driven by model rebuilds; DockModel.childCount
        // is a method call and does not itself participate in QML bindings.
        popup.groupedPreview = childCount > 0

        // === Single window (not grouped): parent row IS the window ===
        // KDE TasksModel tree: single window → rowCount(idx) = 0 (no children)
        // Group (2+ windows) → rowCount(idx) = N (N children)
        if (childCount === 0) {
            if (allWinIds.length === 1) {
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
                logPreviewLifecycle("model-row", {
                    reason: reason || "unspecified",
                    uuid: entry.winId,
                    minimized: entry.isMinimized,
                    cacheAvailable: PreviewController.previewFrameUrl(entry.winId).length > 0
                })
                // When a group collapses to one window, keep that window's
                // existing delegate and PipeWire stream even if its child row
                // moves to the parent row. Index-based reuse can otherwise
                // replace it with a just-closed sibling's source.
                setThumbnailForWindow(0, entry)
                while (childWindowModel.count > 1) {
                    childWindowModel.remove(childWindowModel.count - 1)
                }
            } else if (DockModel.tasksModel.data(
                           parentModelIdx, TaskManager.AbstractTasksModel.IsWindow)) {
                // During group-to-single transitions KWin can publish an
                // empty or stale multi-window WinIdList. Keep the current
                // delegates until the parent row reports exactly one UUID.
                logPreviewLifecycle("single-window-id-unresolved", {
                    reason: reason || "unspecified",
                    winIds: allWinIds,
                    retainedThumbnails: childWindowModel.count
                })
            } else {
                // Launcher only (no windows) — clear model
                while (childWindowModel.count > 0) {
                    childWindowModel.remove(childWindowModel.count - 1)
                }
            }
        } else {
            // === Grouped (2+ windows): use child rows ===
            // Incremental update: set() preserves existing delegates (and their
            // PipeWire streams), append() adds new ones, remove() trims excess.
            // The parent aggregate WinIdList can lag child row updates; use
            // child UUIDs as identity. When the aggregate is nonempty, use it
            // only as an exact-membership filter, never as an index into the
            // child list. An empty aggregate is a transient model update and
            // must not destroy streams or frame ownership.
            let allChildUuidsResolved = true
            let matchedChildCount = 0
            for (let i = 0; i < childCount; i++) {
                let childModelIndex = DockModel.tasksModel.makeModelIndex(parentTaskIndex, i)
                let childWinIds = DockModel.tasksModel.data(
                    childModelIndex, TaskManager.AbstractTasksModel.WinIdList) || []
                if (childWinIds.length === 0) {
                    allChildUuidsResolved = false
                    break
                }
                if (allWinIds.length > 0 && allWinIds.indexOf(childWinIds[0]) < 0)
                    continue
                let entry = {
                    winId: childWinIds[0],
                    title: DockModel.tasksModel.data(childModelIndex, Qt.DisplayRole) || "",
                    isMinimized: DockModel.tasksModel.data(
                        childModelIndex, TaskManager.AbstractTasksModel.IsMinimized) || false,
                    isActive: DockModel.tasksModel.data(
                        childModelIndex, TaskManager.AbstractTasksModel.IsActive) || false,
                    childIndex: i
                }
                logPreviewLifecycle("model-row", {
                    reason: reason || "unspecified",
                    row: i,
                    uuid: entry.winId,
                    minimized: entry.isMinimized,
                    cacheAvailable: PreviewController.previewFrameUrl(entry.winId).length > 0
                })

                setThumbnailForWindow(matchedChildCount, entry)
                matchedChildCount++
            }

            // Remove excess items from the end
            if (allChildUuidsResolved && (allWinIds.length > 0 || childCount === 0)) {
                while (childWindowModel.count > matchedChildCount) {
                    childWindowModel.remove(childWindowModel.count - 1)
                }
            }
        }

        // Retry screencast for delegates where KWin hadn't registered the window yet.
        // Called on each KDE model event (dataChanged, rowsInserted, etc.),
        // so new windows get multiple retry chances without timers.
        for (let i = 0; i < thumbnailRepeater.count; i++) {
            let item = thumbnailRepeater.itemAt(i)
            if (item) item.retryScreencast()
        }

        if (!popup.closeTargetEntry())
            popup.selectDefaultCloseTarget()
        logPreviewLifecycle("model-rebuild-complete", { reason: reason || "unspecified" })
    }

    Connections {
        target: PreviewController
        function onParentIndexChanged() {
            if (PreviewController.parentIndex >= 0) {
                // Different app = different PipeWire streams, must recreate delegates
                popup.closeTargetWinId = null
                childWindowModel.clear()
            }
            root.rebuildChildModel("parent-index-changed")
        }
        function onVisibleChanged() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                // A titlebar minimize can arrive while the overlay is hidden.
                // In that state task data changes are deferred, so refresh from
                // the live model on every open, even when the parent index did
                // not change between hide and reopen.
                root.rebuildChildModel("preview-reopened")
                let count = childWindowModel.count
                root.logPreviewLifecycle("preview-visible", { windowCount: count })
                root.announcePreviewOpen(PreviewController.appName, count)
            } else {
                root.logPreviewLifecycle("preview-hidden")
            }
        }
    }

    // Also rebuild when the underlying model data changes (window close, title change)
    Connections {
        target: DockModel.tasksModel
        function onDataChanged(topLeft, bottomRight, roles) {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                root.logPreviewLifecycle("task-data-changed", {
                    topRow: topLeft ? topLeft.row : -1,
                    bottomRow: bottomRight ? bottomRight.row : -1,
                    roles: roles || []
                })
                root.rebuildChildModel("task-data-changed")
            } else if (PreviewController.parentIndex >= 0) {
                root.logPreviewLifecycle("task-data-changed-while-hidden", {
                    topRow: topLeft ? topLeft.row : -1,
                    bottomRow: bottomRight ? bottomRight.row : -1,
                    roles: roles || []
                })
            }
        }
        function onRowsInserted() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                root.rebuildChildModel("rows-inserted")
            }
        }
        function onRowsRemoved() {
            if (PreviewController.visible && PreviewController.parentIndex >= 0) {
                // Child removed: check if parent still valid
                let parentIdx = PreviewController.parentIndex
                let parentTaskIndex = DockModel.dockPresentationModel.taskIndexForDockIndex(parentIdx)
                if (parentTaskIndex < 0) {
                    PreviewController.hidePreview()
                    return
                }
                let parentModelIdx = DockModel.tasksModel.index(parentTaskIndex, 0)
                if (!parentModelIdx.valid) {
                    PreviewController.hidePreview()
                } else {
                    root.rebuildChildModel("rows-removed")
                }
            }
        }
    }

    // The visible popup card. Its outer item includes the shadow bounds so
    // placement clamping and the Wayland input region account for the effect.
    Item {
        id: popup
        objectName: "previewCardPopup"
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
        property bool groupedPreview: false
        // The header close button keeps the last hovered window as its target.
        // This preserves per-window close behavior in grouped previews while
        // allowing the pointer to travel from a thumbnail to the header.
        property var closeTargetWinId: null

        function closeTargetEntry() {
            if (PreviewController.previewKeyboardActive) {
                const focusedIndex = PreviewController.focusedThumbnailIndex
                if (focusedIndex >= 0 && focusedIndex < childWindowModel.count)
                    return childWindowModel.get(focusedIndex)
            }
            for (let i = 0; i < childWindowModel.count; i++) {
                const entry = childWindowModel.get(i)
                if (entry.winId === closeTargetWinId)
                    return entry
            }
            for (let i = 0; i < childWindowModel.count; i++) {
                const entry = childWindowModel.get(i)
                if (entry.isActive)
                    return entry
            }
            return childWindowModel.count > 0 ? childWindowModel.get(0) : null
        }

        function selectDefaultCloseTarget() {
            const entry = closeTargetEntry()
            closeTargetWinId = entry ? entry.winId : null
        }

        // Resolve the UUID against the live TaskManager tree at click time.
        // Thumbnail childIndex can become stale while rows are removed or
        // reordered; the child's own WinIdList is the identity source.
        function closeWindowByUuid(uuid) {
            if (uuid === undefined || uuid === null || PreviewController.parentIndex < 0)
                return false

            const uuidKey = String(uuid)
            const parentTaskIndex = DockModel.dockPresentationModel.taskIndexForDockIndex(PreviewController.parentIndex)
            if (parentTaskIndex < 0)
                return false
            const parentModelIndex = DockModel.tasksModel.index(parentTaskIndex, 0)
            if (!parentModelIndex.valid)
                return false

            const childCount = DockModel.childCount(parentTaskIndex)
            if (childCount === 0) {
                const parentWinIds = DockModel.tasksModel.data(
                    parentModelIndex, TaskManager.AbstractTasksModel.WinIdList) || []
                // A childless parent is a single window only when its own ID
                // list is singular. During TaskManager regrouping a parent may
                // briefly retain an aggregate ID list; never close that row.
                if (parentWinIds.length !== 1 || String(parentWinIds[0]) !== uuidKey)
                    return false
                DockModel.tasksModel.requestClose(parentModelIndex)
                return true
            }

            for (let i = 0; i < childCount; i++) {
                const childModelIndex = DockModel.tasksModel.makeModelIndex(parentTaskIndex, i)
                if (!childModelIndex.valid)
                    continue
                const childWinIds = DockModel.tasksModel.data(
                    childModelIndex, TaskManager.AbstractTasksModel.WinIdList) || []
                if (childWinIds.length > 0 && String(childWinIds[0]) === uuidKey) {
                    DockModel.tasksModel.requestClose(childModelIndex)
                    return true
                }
            }

            // The child may have closed between rendering and the click.
            return false
        }

        visible: requestedVisible || opacity > 0.01
        opacity: requestedVisible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        // popupContent fills the card, while the card fills this item; deriving
        // the item's size from the layout's implicit size creates a circular
        // zero-width hint. The thumbnail row is the width authority (the app
        // header is constrained to it), and the two stable rows define height.
        implicitWidth: groupedRow.implicitWidth + 2 * (cardPadding + shadowMargin)
        implicitHeight: headerRow.implicitHeight + popupContent.spacing
            + groupedRow.implicitHeight + 2 * (cardPadding + shadowMargin)
        width: implicitWidth
        height: implicitHeight

        function logPosition(stage) {
            if (typeof IconDiagnostics === "undefined" || !IconDiagnostics.previewCaptureMetrics)
                return
            console.info("[kdockw.preview.position.qml]", JSON.stringify({
                stage: stage,
                coordinateSpace: "preview-surface-logical",
                edge: DockView.edge,
                popupRect: { x: x, y: y, width: width, height: height },
                cardBodyRect: {
                    x: x + shadowMargin, y: y + shadowMargin,
                    width: width - 2 * shadowMargin,
                    height: height - 2 * shadowMargin
                },
                fixedAnchorOffset: PreviewController.previewAnchorOffset,
                surfaceSize: { width: parent.width, height: parent.height }
            }))
        }

        Accessible.role: Accessible.PopupMenu
        Accessible.name: PreviewController.appName
            ? i18n("Preview for %1", PreviewController.appName)
            : ""
        x: {
            if (DockView.edge === 2) return PreviewController.previewAnchorOffset // Left
            if (DockView.edge === 3) return parent.width - width
                - PreviewController.previewAnchorOffset                 // Right
            return PreviewController.contentX                            // Top/Bottom → centered
        }
        y: {
            if (DockView.edge === 0) return PreviewController.previewAnchorOffset // Top
            if (DockView.edge === 1) return parent.height - height
                - PreviewController.previewAnchorOffset                 // Bottom
            return PreviewController.contentY                            // Left/Right → centered
        }
        onXChanged: logPosition("x-changed")
        onYChanged: logPosition("y-changed")
        // Report size to controller for input region + positioning
        onWidthChanged: PreviewController.setContentSize(width, height)
        onHeightChanged: PreviewController.setContentSize(width, height)

        Kirigami.ShadowedRectangle {
            id: card
            objectName: "previewCardSurface"
            Accessible.role: Accessible.Pane
            Accessible.name: i18n("Window preview card")
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
                id: headerRow
                objectName: "previewHeader"
                Layout.fillWidth: true
                Layout.maximumWidth: groupedRow.implicitWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                Item {
                    objectName: "previewAppIconSlot"
                    readonly property int taskIndex: DockModel.dockPresentationModel.taskIndexForDockIndex(PreviewController.parentIndex)
                    readonly property string iconName: taskIndex >= 0 ? DockModel.iconName(taskIndex)
                        || "application-x-executable"
                        : "application-x-executable"
                    readonly property bool rawIcon: iconName.startsWith("raw:")
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    Layout.minimumWidth: 22
                    Layout.maximumWidth: 22
                    Layout.minimumHeight: 22
                    Layout.maximumHeight: 22

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: parent.rawIcon ? "" : parent.iconName
                        visible: !parent.rawIcon
                        Accessible.ignored: true
                    }
                    Image {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.small
                        height: width
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
                    objectName: "previewAppName"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: PreviewController.appName
                        color: popup.foregroundColor
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                PreviewCloseButton {
                    id: closeButton
                    objectName: "previewCloseButton"
                    visible: !popup.groupedPreview && childWindowModel.count === 1
                    windowTitle: popup.closeTargetEntry()?.title || PreviewController.appName
                    onClicked: popup.closeWindowByUuid(popup.closeTargetEntry()?.winId)
                }
            }

            // Grouped windows: horizontal row of thumbnails
            Item {
                id: groupedRow
                objectName: "previewThumbnailRow"
                Layout.alignment: Qt.AlignHCenter
                // Repeater delegates are not included in an enclosing
                // positioner's implicit size. Publish the fixed thumbnail
                // geometry here so the card measures the full row. When a
                // group would exceed the available output width, shrink each
                // slot uniformly while preserving its 16:10 image ratio.
                readonly property real requestedThumbnailSlotWidth: Math.min(
                    DockSettings.previewThumbnailSize, DockSettings.previewMaximumHeight * 1.6)
                readonly property real rowSpacing: Kirigami.Units.smallSpacing
                readonly property real availableRowWidth: Math.max(1,
                    PreviewController.maxPopupWidth
                        - 2 * (popup.cardPadding + popup.shadowMargin))
                readonly property real thumbnailSlotWidth: Math.min(
                    requestedThumbnailSlotWidth,
                    Math.max(1, (availableRowWidth
                        - Math.max(0, thumbnailRepeater.count - 1) * rowSpacing)
                        / Math.max(1, thumbnailRepeater.count)))
                implicitWidth: thumbnailRepeater.count * thumbnailSlotWidth
                    + Math.max(0, thumbnailRepeater.count - 1) * rowSpacing
                implicitHeight: thumbnailRepeater.count > 0 && thumbnailRepeater.itemAt(0)
                    ? thumbnailRepeater.itemAt(0).implicitHeight : 0
                // Retain thumbnails through the fade-out so the content and
                // card opacity animate together; source items pause when the
                // outer popup finishes fading and becomes invisible.
                visible: popup.visible

                Row {
                    anchors.fill: parent
                    spacing: groupedRow.rowSpacing

                    Repeater {
                        id: thumbnailRepeater
                        model: childWindowModel

                        PreviewThumbnail {
                            winId: model.winId
                            title: model.title
                            slotWidth: groupedRow.thumbnailSlotWidth
                            isMinimized: model.isMinimized
                            isActive: model.isActive
                            parentIndex: PreviewController.parentIndex
                            childIndex: model.childIndex
                            showCloseButton: popup.groupedPreview
                            onCloseRequested: function(uuid) {
                                popup.closeWindowByUuid(uuid)
                            }
                            onPointerHoveredChanged: {
                                if (pointerHovered)
                                    popup.closeTargetWinId = winId
                            }
                            // Focus ring driven by C++ PreviewController state
                            isKeyboardFocused: PreviewController.previewKeyboardActive
                                && PreviewController.focusedThumbnailIndex === index
                        }
                    }
                }
            }

        }
    }
}
