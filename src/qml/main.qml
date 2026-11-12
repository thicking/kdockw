// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

/**
 * Main dock container.
 *
 * The root item fills the layer-shell surface. The visible dock panel
 * is a centered rounded rectangle that hugs its content.
 * The panel slides in/out based on DockVisibility.dockVisible.
 */
Item {
    id: root
    anchors.fill: parent

    Accessible.role: Accessible.ToolBar
    Accessible.name: i18n("KDockW Dock")

    // C++ singletons: DockView, DockModel, DockActions, DockContextMenu, DockVisibility, DockSettings, PreviewController

    // Hovered item tracking (for custom tooltip and click targeting)
    property int hoveredIndex: -1
    // A separator is a real primary-axis slot, not an overlay in the normal
    // inter-icon gap. The boundary remains a model-free index so task and
    // keyboard indices are unchanged.
    readonly property int taskZoneBoundary: DockSettings.separateLaunchers
        && DockModel.pinnedDockEntryCount > 0
        && DockModel.pinnedDockEntryCount < dockRepeater.count
        ? DockModel.pinnedDockEntryCount : -1
    readonly property real taskZoneSeparatorThickness: 1
    readonly property real taskZoneGap: taskZoneBoundary >= 0
        ? DockSettings.iconSpacing + taskZoneSeparatorThickness : 0
    property string hoveredName: ""

    // Keyboard navigation state
    property bool keyboardNavigating: false

    focus: true

    // Lazily maintain one short-lived PipeWire stream to seed the bounded
    // minimized-frame cache for windows whose preview has never been opened.
    // The component is removed entirely when window previews are disabled.
    Loader {
        id: previewFramePrefetcherLoader
        objectName: "previewFramePrefetcherLoader"
        active: DockSettings.previewEnabled
        source: active ? "qrc:/qml/PreviewFramePrefetcher.qml" : ""
    }

    // Dock movement and model relayout can emit several geometry changes.
    // Debounce them until the stable slots settle; hover zoom transforms do
    // not participate in this refresh.
    function scheduleDelegateGeometryRefresh() {
        if (delegateGeometryRefreshTimer)
            delegateGeometryRefreshTimer.restart()
    }

    // Rows removed/moved/reset under a resting pointer leave hoveredIndex on
    // a shifted or missing row with no motion to re-hit-test it. Once the
    // layout has settled (delegateGeometryRefreshTimer), re-run the hit test
    // from the last real pointer sample in root coordinates: the dock
    // re-centres, so the panel-local zoom anchor no longer marks the spot
    // under the pointer. A pending request survives the context menu hold and
    // runs after the menu closes.
    property bool _hoverRehitPending: false
    // Menu closed with the pointer on the dock, reconciliation not yet run:
    // hover stays held (see _hoverHeld) so geometry callbacks, row inserts
    // and timers cannot act on a row that shifted under the pointer.
    property bool _hoverReconciling: false
    // Last real pointer position in root (dock window) coordinates, the
    // space trackPointer() takes. Not updated while hover is held.
    property real _pointerRootX: -1
    property real _pointerRootY: -1
    function scheduleHoverRehit() {
        if (hoveredIndex < 0) return
        _hoverRehitPending = true
        scheduleDelegateGeometryRefresh()
    }
    function _runHoverRehit() {
        if (!_hoverRehitPending || _menuHeld) return
        let resuming = _hoverReconciling
        _hoverRehitPending = false
        // Release the hold in the same block as the hit test it lets run.
        _hoverReconciling = false
        if (!_pointerOnDock || keyboardNavigating || (hoveredIndex < 0 && !resuming))
            return
        let before = hoveredIndex
        trackPointer(_pointerRootX, _pointerRootY)
        if (hoveredIndex < 0 || hoveredIndex !== before) return
        // Same index, different row: the hit test only renames on a change.
        hoveredName = dockRepeater.itemAt(hoveredIndex)?.displayName ?? ""
        // A changed index restarted the pipeline in onHoveredIndexChanged;
        // an unchanged one resumes it here, once.
        if (resuming && hoveredIndex < dockRepeater.count)
            tooltipTimer.restart()
    }
    // Deferred from the menu close; waits for a pending layout refresh,
    // which runs the reconcile itself.
    function _reconcileAfterHold() {
        if (!_hoverReconciling || _menuHeld || delegateGeometryRefreshTimer.running) return
        _runHoverRehit()
    }
    // Real pointer input during the reconcile window: reconcile at it now.
    function _reconcileAt(x, y, entryEnvelope = false) {
        _pointerRootX = x
        _pointerRootY = y
        _hoverRehitPending = true
        if (entryEnvelope) {
            _hoverRehitPending = false
            _hoverReconciling = false
            trackPointer(x, y, true)
        } else {
            _runHoverRehit()
        }
    }

    Timer {
        id: delegateGeometryRefreshTimer
        interval: 50
        onTriggered: {
            for (let i = 0; i < dockRepeater.count; ++i) {
                let item = dockRepeater.itemAt(i)
                if (item)
                    item.publishDelegateGeometry()
            }
            root._runHoverRehit()
        }
    }

    Connections {
        target: DockVisibility
        function onDockVisibleChanged() {
            root.scheduleDelegateGeometryRefresh()
        }
    }

    onXChanged: scheduleDelegateGeometryRefresh()
    onYChanged: scheduleDelegateGeometryRefresh()
    onWidthChanged: scheduleDelegateGeometryRefresh()
    onHeightChanged: scheduleDelegateGeometryRefresh()
    Component.onCompleted: scheduleDelegateGeometryRefresh()

    function announceLaunch(name) {
        Accessible.announce(i18n("Starting %1", name), Accessible.Assertive)
    }

    function taskIndexAtDockIndex(dockIndex) {
        return DockModel.dockPresentationModel.taskIndexForDockIndex(dockIndex)
    }

    function isPinnedDockIndex(dockIndex) {
        return DockModel.dockPresentationModel.isPinnedDockIndex(dockIndex)
    }

    function entryTypeAtDockIndex(dockIndex) {
        const item = dockRepeater.itemAt(dockIndex)
        return item && item.isFolderStack ? "folderStack" : "task"
    }

    function dockEntryIdAt(dockIndex) {
        return DockModel.dockPresentationModel.entryIdForDockIndex(dockIndex)
    }

    function dockRowTrace(index) {
        const item = dockRepeater.itemAt(index)
        if (!item) return { dockIndex: index, missingDelegate: true }
        const taskIndex = taskIndexAtDockIndex(index)
        return {
            dockIndex: index,
            type: item.isFolderStack ? "folderStack" : "task",
            stableId: dockEntryIdAt(index),
            pinned: isPinnedDockIndex(index),
            taskIndex: taskIndex,
            desktopId: taskIndex >= 0 ? DockModel.appId(taskIndex) : ""
        }
    }

    function logDockOrderTrace(phase, sourceId, targetId, moved = null) {
        if (!DockModel.taskDiagnosticsEnabled) return
        let rows = []
        for (let i = 0; i < dockRepeater.count; ++i)
            rows.push(dockRowTrace(i))
        console.info("[KDOCKW_DND_TRACE] " + JSON.stringify({
            phase: phase,
            sourceId: sourceId || "",
            targetId: targetId || "",
            moved: moved,
            rows: rows
        }))
    }

    // Resolve both endpoints from the presentation model at the last possible
    // moment. Mixed pinned Task/FolderStack order is persisted by stable entry
    // IDs; TaskManager rows are used for running-task and combined-zone moves.
    function reorderDockItems(fromDockIndex, toDockIndex) {
        if (fromDockIndex < 0 || toDockIndex < 0 || fromDockIndex === toDockIndex)
            return false
        return reorderDockEntries(dockEntryIdAt(fromDockIndex), dockEntryIdAt(toDockIndex))
    }

    function reorderDockEntries(sourceEntryId, targetEntryId) {
        if (!sourceEntryId || !targetEntryId || sourceEntryId === targetEntryId)
            return false
        const fromDockIndex = DockModel.dockPresentationModel.dockIndexForEntryId(sourceEntryId)
        const toDockIndex = DockModel.dockPresentationModel.dockIndexForEntryId(targetEntryId)
        if (fromDockIndex < 0 || toDockIndex < 0 || fromDockIndex === toDockIndex)
            return false
        const sourcePinned = isPinnedDockIndex(fromDockIndex)
        const targetPinned = isPinnedDockIndex(toDockIndex)
        if (!DockSettings.separateLaunchers
                && entryTypeAtDockIndex(fromDockIndex) === "task"
                && entryTypeAtDockIndex(toDockIndex) === "task") {
            const fromTaskIndex = taskIndexAtDockIndex(fromDockIndex)
            const toTaskIndex = taskIndexAtDockIndex(toDockIndex)
            return fromTaskIndex >= 0 && toTaskIndex >= 0
                ? DockActions.moveTask(fromTaskIndex, toTaskIndex) : false
        }
        if (sourcePinned && targetPinned) {
            return DockModel.moveDockEntry(sourceEntryId, targetEntryId)
        }
        if (!sourcePinned && !targetPinned) {
            const fromTaskIndex = taskIndexAtDockIndex(fromDockIndex)
            const toTaskIndex = taskIndexAtDockIndex(toDockIndex)
            return fromTaskIndex >= 0 && toTaskIndex >= 0
                ? DockActions.moveTask(fromTaskIndex, toTaskIndex) : false
        }
        return false
    }

    function startKeyboardNavigation() {
        keyboardNavigating = true
        _hoverReconciling = false
        // Suppress tooltip and preview auto-triggers during keyboard nav
        tooltipTimer.stop()
        tooltipItem.show = false
        if (dockRepeater.count > 0) {
            if (hoveredIndex < 0)
                hoveredIndex = 0
            // Set zoom position to the focused item's center
            let item = dockRepeater.itemAt(hoveredIndex)
            if (item) {
                dockPanel.mouseX = item.itemCenterX
                dockPanel.mouseY = dockRow.y + item.height / 2
                _zoomActive = true
            }
        }
        root.forceActiveFocus()
    }

    // Retry forceActiveFocus when the window becomes active from compositor.
    // Layer-shell keyboard interactivity is async (Wayland round-trip),
    // so forceActiveFocus() may fail if called before the window is active.
    Connections {
        target: root.Window.window
        function onXChanged() { root.scheduleDelegateGeometryRefresh() }
        function onYChanged() { root.scheduleDelegateGeometryRefresh() }
        function onWidthChanged() { root.scheduleDelegateGeometryRefresh() }
        function onHeightChanged() { root.scheduleDelegateGeometryRefresh() }
        function onScreenChanged() { root.scheduleDelegateGeometryRefresh() }
        function onVisibleChanged() { root.scheduleDelegateGeometryRefresh() }
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active
                    && (root.keyboardNavigating || root._dragActive) && !root.activeFocus) {
                root.forceActiveFocus()
            }
        }
    }

    // restoreFocus=false when a task was just activated: that activation
    // already moves focus, returning it would override the user's choice.
    function endKeyboardNavigation(restoreFocus = true) {
        keyboardNavigating = false
        hoveredIndex = -1
        hoveredName = ""
        _zoomActive = false
        dockPanel.mouseX = -1
        dockPanel.mouseY = -1
        DockVisibility.setKeyboardActive(false, restoreFocus)
    }

    // Pointer motion anywhere on screen ends keyboard navigation. Motion over
    // the dock is also seen by dockMouseArea.onPositionChanged; motion over
    // other windows reaches the dock only through KWin.
    Connections {
        target: DockVisibility
        function onPointerMovedDuringKeyboardNavigation() {
            if (!root.keyboardNavigating)
                return
            PreviewController.endPreviewKeyboardNav()
            root.endKeyboardNavigation()
        }
    }

    function navigateItem(delta) {
        keyboardNavigating = true
        _hoverReconciling = false
        let count = dockRepeater.count
        if (count === 0) return

        if (hoveredIndex < 0) {
            hoveredIndex = delta > 0 ? 0 : count - 1
        } else {
            hoveredIndex = Math.max(0, Math.min(count - 1, hoveredIndex + delta))
        }
        hoveredName = dockRepeater.itemAt(hoveredIndex)?.displayName ?? ""

        // Reuse zoom logic: move the zoom cursor to the focused item's rest center
        let item = dockRepeater.itemAt(hoveredIndex)
        if (item) {
            dockPanel.mouseX = item.itemCenterX
            dockPanel.mouseY = dockRow.y + item.height / 2
            _zoomActive = true

            // Announce to screen reader
            let msg = item.displayName
            if (item.accessibleDescription)
                msg += ", " + item.accessibleDescription
            msg += ", " + i18n("%1 of %2", hoveredIndex + 1, count)
            Accessible.announce(msg, Accessible.Polite)
        }
    }

    // Announce preview thumbnail navigation (called after C++ state changes)
    function announcePreviewThumbnail() {
        let title = PreviewController.focusedThumbnailTitle()
        if (!title) return
        let msg = title
        if (PreviewController.focusedThumbnailIsActive())
            msg += ", " + i18n("Active")
        if (PreviewController.focusedThumbnailIsMinimized())
            msg += ", " + i18n("Minimized")
        msg += ", " + i18n("%1 of %2",
            PreviewController.focusedThumbnailIndex + 1,
            PreviewController.previewThumbnailCount())
        Accessible.announce(msg, Accessible.Polite)
    }

    Keys.onPressed: function(event) {
        // Escape cancels an internal reorder drag (the dock grabs keyboard
        // interactivity while dragging, see DockVisibility.setDragActive)
        if (_dragActive && event.key === Qt.Key_Escape) {
            cancelDrag()
            event.accepted = true
            return
        }

        if (!keyboardNavigating) return

        // Preview keyboard mode: route keys to PreviewController
        if (PreviewController.previewKeyboardActive) {
            // Thumbnail navigation follows dock axis (Left/Right for horizontal, Up/Down for vertical)
            let thumbPrev = DockView.isVertical ? Qt.Key_Up : Qt.Key_Left
            let thumbNext = DockView.isVertical ? Qt.Key_Down : Qt.Key_Right
            // Return to dock: key toward the dock edge
            let backKey = DockView.isVertical
                ? (DockView.edge === 2 ? Qt.Key_Left : Qt.Key_Right)
                : (DockView.edge === 0 ? Qt.Key_Up : Qt.Key_Down)

            switch (event.key) {
            case thumbPrev:
                PreviewController.navigatePreviewThumbnail(-1)
                announcePreviewThumbnail()
                event.accepted = true
                break
            case thumbNext:
                PreviewController.navigatePreviewThumbnail(1)
                announcePreviewThumbnail()
                event.accepted = true
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                PreviewController.activatePreviewThumbnail(
                    root._pointerOnDock && root.hoveredIndex === PreviewController.parentIndex)
                endKeyboardNavigation(false)
                event.accepted = true
                break
            case Qt.Key_Delete:
                PreviewController.closePreviewThumbnail()
                announcePreviewThumbnail()
                event.accepted = true
                break
            case Qt.Key_Escape:
            case backKey:
                // Return to dock navigation (keep preview visible)
                PreviewController.endPreviewKeyboardNav()
                event.accepted = true
                break
            }
            return
        }

        // Normal dock navigation — keys depend on orientation
        let navPrev = DockView.isVertical ? Qt.Key_Up : Qt.Key_Left
        let navNext = DockView.isVertical ? Qt.Key_Down : Qt.Key_Right
        // Preview open key: perpendicular to dock axis, away from edge
        let previewKey = DockView.isVertical
            ? (DockView.edge === 2 ? Qt.Key_Right : Qt.Key_Left)   // Left→Right, Right→Left
            : (DockView.edge === 0 ? Qt.Key_Down : Qt.Key_Up)      // Top→Down, Bottom→Up (was Key_Down for bottom)

        switch (event.key) {
        case navPrev:
            navigateItem(-1)
            event.accepted = true
            break
        case navNext:
            navigateItem(1)
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (hoveredIndex >= 0) {
                const item = dockRepeater.itemAt(hoveredIndex)
                if (item && item.isFolderStack)
                    item.openFolderStack()
                else if (item)
                    DockActions.activate(taskIndexAtDockIndex(hoveredIndex))
                endKeyboardNavigation(false)
            }
            event.accepted = true
            break
        case Qt.Key_Escape:
            // If preview is visible, hide it first
            if (PreviewController.visible) {
                PreviewController.hidePreview()
            }
            endKeyboardNavigation()
            event.accepted = true
            break
        case previewKey:
            // Open preview for the focused item (if it has windows); not for
            // a held hover that still awaits its post-menu reconcile.
            if (hoveredIndex >= 0 && !_hoverHeld) {
                const taskIndex = taskIndexAtDockIndex(hoveredIndex)
                if (taskIndex < 0) break
                let idx = DockModel.tasksModel.index(taskIndex, 0)
                let isWindow = DockModel.tasksModel.data(
                    idx, TaskManager.AbstractTasksModel.IsWindow)
                if (isWindow) {
                    let item = dockRepeater.itemAt(hoveredIndex)
                    if (item) {
                        showPreviewForItem(hoveredIndex, item)
                        PreviewController.startPreviewKeyboardNav()
                        announcePreviewThumbnail()
                    }
                }
            }
            event.accepted = true
            break
        case Qt.Key_Menu:
            if (hoveredIndex >= 0) {
                DockContextMenu.showForTask(hoveredIndex)
            }
            event.accepted = true
            break
        }
    }

    // Hysteresis flag: once zoom activates (mouse on an icon), it stays active
    // until the mouse leaves the panel zone entirely. This prevents rapid zoom
    // on/off flickering when moving between icons through tiny gaps.
    property bool _zoomActive: false

    // Hover hold while the context menu is open. Its popup grab makes
    // QtWayland send the dock a fake leave (the compositor keeps pointer
    // focus) and no enter when it closes, so dock pointer events must not
    // change hover/zoom until the menu closes and the real focus is checked.
    // Null-safe: the context property goes away first when a dock shell is torn down.
    readonly property bool _menuHeld: DockContextMenu?.open ?? false
    // Also held until the post-menu reconciliation runs (_hoverReconciling).
    readonly property bool _hoverHeld: _menuHeld || _hoverReconciling
    // Pointer on the dock as the dock tracks it. Replaces
    // dockMouseArea.containsMouse, which stays false after the fake leave.
    property bool _pointerOnDock: false
    // Explicit activation hides the preview and prevents hover-triggered
    // reopening until the pointer leaves that task's icon.
    function dismissPreviewAfterTaskAction(index, dispatched, action) {
        if (typeof IconDiagnostics !== "undefined" && IconDiagnostics.taskDiagnosticsEnabled) {
            console.info("[KDOCKW_PREVIEW_LIFECYCLE]", JSON.stringify({
                phase: "dock-task-action-dispatched",
                action: action,
                index: index,
                dispatched: dispatched,
                previewVisible: PreviewController.visible
            }))
        }
        if (!dispatched)
            return false
        PreviewController.suppressPreviewUntilPointerLeavesTask(index)
        tooltipItem.show = false
        tooltipTimer.stop()
        PreviewController.hidePreview()
        return true
    }
    // --- Internal drag state ---
    property bool _dragActive: false
    property int _dragSourceIndex: -1
    property int _dragTargetIndex: -1
    property string _dragStartEntryId: ""
    property string _dragSourceEntryId: ""
    property string _dragTargetEntryId: ""
    property real _dragCurrentX: 0
    property real _dragCurrentY: 0
    property real _dragStartX: 0
    property real _dragStartY: 0
    property bool _dragPending: false      // press-hold started but not yet moved enough
    property bool _dragWasActive: false     // was drag active during this press cycle (suppress click)
    readonly property real _dragThreshold: 10

    Timer {
        id: dragHoldTimer
        interval: 300
        onTriggered: {
            const resolvedSource = root._dragStartEntryId.length > 0
                ? DockModel.dockPresentationModel.dockIndexForEntryId(root._dragStartEntryId) : -1
            if (resolvedSource >= 0) {
                root._dragPending = true
                root._dragSourceIndex = resolvedSource
                root._dragSourceEntryId = root._dragStartEntryId
                root._dragTargetIndex = resolvedSource
                root._dragTargetEntryId = root._dragSourceEntryId
                root.logDockOrderTrace("hold-start", root._dragSourceEntryId, root._dragTargetEntryId)
            } else {
                root.clearDragState()
            }
        }
    }

    function clearDragState() {
        dragHoldTimer.stop()
        _dragActive = false
        _dragPending = false
        _dragSourceIndex = -1
        _dragTargetIndex = -1
        _dragStartEntryId = ""
        _dragSourceEntryId = ""
        _dragTargetEntryId = ""
        DockVisibility.setDragActive(false)
    }

    // Cancel an active internal drag without reordering (Escape). The button is
    // still held: _dragWasActive stays set so the eventual release is not a click.
    function cancelDrag() {
        root.logDockOrderTrace("escape-cancel", root._dragSourceEntryId, root._dragTargetEntryId)
        root.clearDragState()
    }
    // Return an item's unscaled rest-slot start in dockPanel coordinates.
    // The primary axis includes the allocated separator slot; the secondary
    // axis intentionally remains the Flow coordinate.
    function _primaryRestSlotStart(item) {
        return DockView.isVertical
            ? dockRow.y + item.y + item.restOffset
            : dockRow.x + item.x + item.restOffset
    }


    // Plasma's task manager includes this plain URL MIME alongside its
    // task-specific payload. Preserve applications: URLs as supplied; KDE's
    // TaskManager resolves them when adding the launcher.
    function launcherUrlFromTaskMime(formats, urlData) {
        return formats.indexOf("text/x-orgkdeplasmataskmanager_taskurl") >= 0
                ? urlData.trim() : ""
    }

    // Compute the target index where the dragged item would be inserted.
    // Compares mouse X with each icon's center X (including the source so
    // that dropping near the original position keeps the item in place).
    function computeDropIndex(globalMousePos) {
        const separate = DockSettings.separateLaunchers
        const sourcePinned = separate && isPinnedDockIndex(root._dragSourceIndex)
        if (DockView.isVertical) {
            let panelRelY = globalMousePos - dockPanel.y
            let items = []
            for (let i = 0; i < dockRepeater.count; i++) {
                let item = dockRepeater.itemAt(i)
                if (!item) continue
                if (separate && isPinnedDockIndex(i) !== sourcePinned) continue
                items.push({ idx: i, cx: _primaryRestSlotStart(item) + item.height / 2 })
            }
            if (items.length === 0) return -1
            let bestIdx = items[0].idx
            let bestDist = Math.abs(panelRelY - items[0].cx)
            for (let j = 1; j < items.length; j++) {
                let d = Math.abs(panelRelY - items[j].cx)
                if (d < bestDist) { bestDist = d; bestIdx = items[j].idx }
            }
            return bestIdx
        } else {
            let panelRelX = globalMousePos - dockPanel.x
            let items = []
            for (let i = 0; i < dockRepeater.count; i++) {
                let item = dockRepeater.itemAt(i)
                if (!item) continue
                if (separate && isPinnedDockIndex(i) !== sourcePinned) continue
                items.push({ idx: i, cx: _primaryRestSlotStart(item) + item.width / 2 })
            }
            if (items.length === 0) return -1
            let bestIdx = items[0].idx
            let bestDist = Math.abs(panelRelX - items[0].cx)
            for (let j = 1; j < items.length; j++) {
                let d = Math.abs(panelRelX - items[j].cx)
                if (d < bestDist) { bestDist = d; bestIdx = items[j].idx }
            }
            return bestIdx
        }
    }

    // Compute which icon is under an external drop cursor (unscaled hit test).
    function computeExternalDropIndex(primaryPosition) {
        for (let i = 0; i < dockRepeater.count; i++) {
            let item = dockRepeater.itemAt(i)
            if (!item) continue
            let itemLeft = _primaryRestSlotStart(item)
            let itemRight = itemLeft + item.width
            if (primaryPosition >= itemLeft && primaryPosition <= itemRight) return i
        }
        return -1
    }

    function isDesktopFileUrl(url) {
        let str = url.toString()
        return str.endsWith(".desktop") || str.startsWith("applications:")
    }

    function _tryAutoPreview() {
        if (_hoverHeld) return
        if (externalDropArea.externalFileDragActive) return
        if (!DockSettings.previewEnabled) return
        if (hoveredIndex < 0 || PreviewController.visible) return
        const taskIndex = taskIndexAtDockIndex(hoveredIndex)
        if (taskIndex < 0) return
        let idx = DockModel.tasksModel.index(taskIndex, 0)
        let isWindow = DockModel.tasksModel.data(
            idx, TaskManager.AbstractTasksModel.IsWindow)
        if (isWindow) {
            tooltipItem.show = false
            tooltipTimer.stop()
            let item = dockRepeater.itemAt(hoveredIndex)
            if (item) showPreviewForItem(hoveredIndex, item)
        }
    }

    // Show the preview popup centred on the item's VISUAL (zoomed, pushed)
    // centre in the dock surface's scene coordinates. Global window coordinates
    // are unavailable/reliable for layer-shell surfaces on Wayland.
    function logPreviewPositionGeometry(stage, geometry) {
        if (typeof IconDiagnostics === "undefined" || !IconDiagnostics.previewCaptureMetrics)
            return
        console.info("[kdockw.preview.position.qml]", JSON.stringify({
            stage: stage,
            coordinateSpace: geometry.coordinateSpace,
            edge: DockView.edge,
            dockSurfaceLogical: { width: DockView.width, height: DockView.height },
            iconBoundsInSurface: geometry.iconBoundsInSurface,
            iconRestEdgeInSurface: geometry.restEdgeInSurface,
            iconCurrentEdgeInSurface: geometry.currentEdgeInSurface,
            zoomOverflow: geometry.zoomOverflow,
            maxZoomOverflow: geometry.maxZoomOverflow
        }))
    }

    function showPreviewForItem(index, item) {
        let centre = item.mapToItem(null, item.width / 2, item.height / 2)
        let ext = DockView.isVertical ? item.height : item.width
        let pos = (DockView.isVertical ? centre.y : centre.x) - ext / 2
        const geometry = item.previewAnchorGeometry()
        logPreviewPositionGeometry("show", geometry)
        PreviewController.showPreview(index, pos, ext,
            geometry.restEdgeInSurface, geometry.maxZoomOverflow,
            Kirigami.Units.smallSpacing * 2)
    }

    function refreshPreviewAnchorForItem(index, item) {
        if (!PreviewController.visible || PreviewController.parentIndex !== index)
            return
        const centre = item.mapToItem(null, item.width / 2, item.height / 2)
        const extent = DockView.isVertical ? item.height : item.width
        const pos = (DockView.isVertical ? centre.y : centre.x) - extent / 2
        const geometry = item.previewAnchorGeometry()
        logPreviewPositionGeometry("anchor-refresh", geometry)
        PreviewController.updatePreviewAnchorGeometry(
            pos, extent, geometry.restEdgeInSurface, geometry.maxZoomOverflow,
            Kirigami.Units.smallSpacing * 2)
    }

    function refreshVisiblePreviewAnchor() {
        if (!PreviewController.visible || PreviewController.parentIndex < 0)
            return
        const item = dockRepeater.itemAt(PreviewController.parentIndex)
        if (item)
            refreshPreviewAnchorForItem(PreviewController.parentIndex, item)
    }

    Connections {
        target: DockView
        function onEdgeChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
    }

    Connections {
        target: DockSettings
        function onZoomStyleChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onMaxZoomFactorChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onIconSizeChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onIconScaleChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onIconSpacingChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onRunningIndicatorSizeChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onRunningIndicatorPositionChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onFloatingChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onFloatingMarginChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onContentPaddingLeftChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onContentPaddingRightChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onContentPaddingTopChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
        function onContentPaddingBottomChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
    }

    // Scaled extent of an item on the SECONDARY axis, in dockPanel coords.
    // dockPanel.mouseY is the secondary-axis cursor (y for horizontal docks,
    // x for vertical docks). Icons grow away from the screen edge — the Scale
    // transform origin pins the edge-facing side (DockItem.qml):
    // Bottom: bottom fixed, grows up; Top: top fixed, grows down;
    // Left: left fixed, grows right; Right: right fixed, grows left.
    // Returns {near, far} in ascending secondary-axis coordinates.
    function _secondarySpan(item, scale) {
        let restNear, extent
        if (DockView.isVertical) {
            restNear = dockRow.x + item.x
            extent = item.width
        } else {
            restNear = dockRow.y + item.y
            extent = item.height
        }
        // Edge 1 = Bottom, 3 = Right: far side pinned to the screen edge.
        let farPinned = DockView.edge === 1 || DockView.edge === 3
        if (farPinned) {
            let far = restNear + extent
            return { near: far - extent * scale, far: far }
        }
        return { near: restNear, far: restNear + extent * scale }
    }

    // Map a pointer position (root coordinates) onto the zoom/hover state and
    // re-run the hit test. dockPanel.mouseX = primary axis (along the dock),
    // dockPanel.mouseY = secondary axis (depth), so all zoom/hover logic works
    // identically regardless of orientation; -1 = outside the dock zone.
    function trackPointer(x, y, entryEnvelope = false) {
        // The context menu holds the zoom anchor (see _hoverHeld).
        if (_hoverHeld) return
        let zoomExtension = DockSettings.iconSize * (DockSettings.maxZoomFactor - 1.0)
        let primarySample = -1
        let secondarySample = -1

        if (DockView.isVertical) {
            // Vertical: primary = Y screen axis, secondary = X screen axis
            let panelNear = dockPanel.x
            let panelFar = dockPanel.x + dockPanel.width
            let inZone = (DockView.edge === 2)
                ? (x >= panelNear && x <= panelFar + zoomExtension)    // Left
                : (x >= panelNear - zoomExtension && x <= panelFar)    // Right
            if (inZone) {
                primarySample = y - dockPanel.y     // primary = Y
                secondarySample = x - dockPanel.x   // secondary = X
            }
        } else {
            // Horizontal: primary = X screen axis, secondary = Y screen axis
            let panelTop = dockPanel.y
            let panelBottom = dockPanel.y + dockPanel.height
            let inZone = (DockView.edge === 0)
                ? (y >= panelTop && y <= panelBottom + zoomExtension)   // Top
                : (y >= panelTop - zoomExtension && y <= panelBottom)   // Bottom
            if (inZone) {
                primarySample = x - dockPanel.x
                secondarySample = y - dockPanel.y
            }
        }
        // MouseArea.onEntered is the authoritative start of a new pointer
        // session. Re-anchor before the first hit-test activates zoom, even if
        // a visible preview kept mouseInside true while the pointer was away.
        if (entryEnvelope && primarySample >= 0 && dockPanel.magnificationMode === 1) {
            springZoom.synchronizeCursor(primarySample, 0,
                DockView.isVertical ? root.height : root.width)
        }
        if (primarySample >= 0) {
            dockPanel.mouseX = primarySample
            dockPanel.mouseY = secondarySample
        } else {
            dockPanel.mouseX = -1
            dockPanel.mouseY = -1
        }
        updateHoveredItem(entryEnvelope)
    }

    // Shared by MouseArea.onEntered and QML tests so the real event ordering
    // (pointer ownership -> entry sample -> sync -> hit-test) is exercised.
    function _handleDockPointerEntered(x, y) {
        if (_menuHeld) return
        PreviewController.cancelHide()
        _pointerOnDock = true
        DockVisibility.setHovered(true)
        if (_hoverReconciling)
            _reconcileAt(x, y, true)
        else
            trackPointer(x, y, true)
    }

    function updateHoveredItem(entryEnvelope = false) {
        // Geometry/scale callbacks must not move the held hover.
        if (_hoverHeld) return
        if (dockPanel.mouseX < 0) {
            hoveredIndex = -1
            hoveredName = ""
            _zoomActive = false
            return
        }
        // Hit-test only a pointer the dock has. After the pointer left for the
        // preview, onExited keeps mouseX/mouseY as the zoom anchor; icons that
        // move under that stale position (re-centring for a new task row) must
        // not re-hover an item, or its preview reopens with the pointer away.
        if (!_pointerOnDock)
            return

        // Rough secondary-axis check: outside the dockRow + zoom extension on
        // the side icons grow toward (away from the screen edge) → reset zoom.
        let maxExt = DockSettings.iconSize * (DockSettings.maxZoomFactor - 1.0)
        let rowNear, rowFar
        if (DockView.isVertical) {
            rowNear = dockRow.x
            rowFar = dockRow.x + dockRow.width
        } else {
            rowNear = dockRow.y
            rowFar = dockRow.y + dockRow.height
        }
        // Edge 1 = Bottom, 3 = Right: far side pinned; icons grow toward "near".
        // Edge 0 = Top, 2 = Left: near side pinned; icons grow toward "far".
        if (DockView.edge === 0 || DockView.edge === 2) {
            rowFar += maxExt
        } else {
            rowNear -= maxExt
        }
        if (dockPanel.mouseY < rowNear || dockPanel.mouseY > rowFar) {
            hoveredIndex = -1
            hoveredName = ""
            _zoomActive = false
            return
        }

        if (dockPanel.zoomStyle !== 1) {
            // Parabolic: the item whose VISIBLE slot contains the cursor on the
            // primary axis — rest centre + current offset, current scale — so
            // tooltip and click follow what is on screen, including while
            // zoomAmount eases in or out.
            let slot = -1
            let bestDist = Infinity
            for (let i = 0; i < dockRepeater.count; i++) {
                let it = dockRepeater.itemAt(i)
                if (!it) continue
                let dist = Math.abs(dockPanel.mouseX - (it.itemCenterX + it.currentOffset))
                let hitScale = entryEnvelope ? Math.max(it.currentScale, DockSettings.maxZoomFactor) : it.currentScale
                let half = DockSettings.iconSize * hitScale / 2 + DockSettings.iconSpacing / 2
                if (dist <= half && dist < bestDist) { slot = i; bestDist = dist }
            }
            let slotItem = slot >= 0 ? dockRepeater.itemAt(slot) : null
            let hit = false
            if (slotItem) {
                // Secondary axis: scaled extent honours the edge-pinned Scale origin
                let hitScale = entryEnvelope
                    ? Math.max(slotItem.currentScale, DockSettings.maxZoomFactor) : slotItem.currentScale
                let span = _secondarySpan(slotItem, hitScale)
                hit = dockPanel.mouseY >= span.near && dockPanel.mouseY <= span.far
            }
            if (hit) {
                _zoomActive = true  // Activate zoom; stays until mouse leaves panel
                if (hoveredIndex !== slot) {
                    hoveredIndex = slot
                    hoveredName = slotItem.displayName
                    if (!externalDropArea.externalFileDragActive)
                        tooltipTimer.restart()
                }
            } else {
                // _zoomActive kept, same hysteresis as in-place mode below.
                hoveredIndex = -1
                hoveredName = ""
            }
            return
        }

        // In-place mode: find the closest icon whose SCALED 2D bounds contain the mouse.
        // Uses Schmitt-trigger hysteresis: the currently-hovered icon has a wider
        // effective claim radius (exit threshold), so small mouse movements toward
        // a neighbor don't immediately switch the selection. This prevents
        // accidental clicks on the wrong icon when the hovered icon is largest.
        // Ref: Grossman & Balakrishnan (CHI 2005, Bubble Cursor), Amazon mega-menu.
        let bestIndex = -1
        let bestNormDist = Infinity
        // Hysteresis factor: 0.15 (light) – 0.35 (strong). Default 0.25.
        let hysteresisFactor = 0.25
        for (let i = 0; i < dockRepeater.count; i++) {
            let item = dockRepeater.itemAt(i)
            if (!item) continue

            // Primary axis: normalized distance (0 = center, 1 = edge of scaled
            // icon). Primary extent is item.width (horizontal) / item.height
            // (vertical); itemCenterX is already axis-aware.
            let dist = Math.abs(dockPanel.mouseX - item.itemCenterX)
            let hitScale = entryEnvelope ? Math.max(item.currentScale, DockSettings.maxZoomFactor) : item.currentScale
            let scaledHalfWidth = ((DockView.isVertical ? item.height : item.width)
                                   * hitScale) / 2
            let normDist = dist / scaledHalfWidth

            // Hysteresis: currently-hovered icon uses wider exit threshold
            let maxNorm = (i === hoveredIndex) ? (1.0 + hysteresisFactor) : 1.0
            if (normDist >= maxNorm) continue

            // Secondary-axis check: scaled extent honours the edge-pinned
            // Scale origin (grows away from the screen edge)
            let span = _secondarySpan(item, hitScale)
            if (dockPanel.mouseY < span.near || dockPanel.mouseY > span.far) continue

            // Comparison: currently-hovered icon gets distance bonus (sticky)
            let effectiveDist = (i === hoveredIndex) ? normDist * (1.0 - hysteresisFactor) : normDist
            if (effectiveDist < bestNormDist) { bestIndex = i; bestNormDist = effectiveDist }
        }

        if (bestIndex >= 0) {
            _zoomActive = true  // Activate zoom; stays until mouse leaves panel
            if (hoveredIndex !== bestIndex) {
                hoveredIndex = bestIndex
                hoveredName = dockRepeater.itemAt(bestIndex).displayName
                if (!externalDropArea.externalFileDragActive)
                    tooltipTimer.restart()
            }
        } else {
            hoveredIndex = -1
            hoveredName = ""
            // _zoomActive intentionally NOT reset here for primary-axis gap hysteresis.
            // When mouse crosses tiny gaps between icons, zoom stays active to prevent
            // flickering. Zoom deactivates only when mouse leaves the depth zone
            // (rough check above) or the panel zone entirely (mouseX becomes -1).
        }
    }

    // Pointer left the dock: release zoom and hover unless the preview keeps
    // them (dock→preview transition), and end a drag as a drag-out.
    function _pointerLeft() {
        _pointerOnDock = false
        _hoverReconciling = false
        PreviewController.clearDismissedTask()
        // Keep zoom state when preview is visible (dock→preview mouse transition)
        if (!PreviewController.visible) {
            dockPanel.mouseX = -1
            dockPanel.mouseY = -1
            _zoomActive = false
        }
        hoveredIndex = -1
        hoveredName = ""
        // Hide preview with delay (allows mouse to move to preview surface)
        PreviewController.hidePreviewDelayed()
        // Drag-out: if an active drag leaves the dock, unpin the launcher
        if (_dragActive) {
            const sourceDockIndex = DockModel.dockPresentationModel.dockIndexForEntryId(_dragSourceEntryId)
            const sourceTaskIndex = taskIndexAtDockIndex(sourceDockIndex)
            if (sourceDockIndex >= 0 && isPinnedDockIndex(sourceDockIndex) && sourceTaskIndex >= 0) {
                DockActions.removeLauncher(sourceTaskIndex)
            }
            clearDragState()
        } else if (_dragPending || _dragStartEntryId.length > 0) {
            clearDragState()
        }
        // preview visible이면 dock hover 상태 유지 (입력 영역 축소 방지)
        if (!PreviewController.visible) {
            DockVisibility.setHovered(false)
        }
    }

    // Popup.Window can take pointer focus from the layer-shell surface. When
    // it closes, re-evaluate hover only if KWin's Wayland focus tracker says
    // the pointer is actually back over the dock. Do not infer hover from the
    // popup's old anchor when the pointer was dismissed elsewhere.
    function folderStackPopupClosed() {
        Qt.callLater(() => {
            if (!DockView.pointerInside) {
                root._pointerLeft()
                return
            }
            root._pointerOnDock = true
            PreviewController.cancelHide()
            DockVisibility.setHovered(true)
            if (!root._menuHeld && !root.keyboardNavigating
                    && root._pointerRootX >= 0 && root._pointerRootY >= 0) {
                root.trackPointer(root._pointerRootX, root._pointerRootY)
            }
            if (DockModel.taskDiagnosticsEnabled) {
                console.info("[KDOCKW_HOVER_RESTORE] " + JSON.stringify({
                    pointerInside: DockView.pointerInside,
                    pointerRoot: { x: root._pointerRootX, y: root._pointerRootY },
                    hoveredIndex: root.hoveredIndex,
                    zoomActive: root._zoomActive
                }))
            }
        })
    }

    function suppressDockTooltip() {
        tooltipTimer.stop()
        tooltipItem.show = false
    }

    // Hold hover state while the context menu is open; on close, reconcile
    // with the compositor's pointer focus since Qt's hover is stale.
    Connections {
        target: DockContextMenu
        function onOpenChanged() {
            if (DockContextMenu.open) {
                root._hoverReconciling = false
                tooltipTimer.stop()
                tooltipItem.show = false
                return
            }
            if (root.keyboardNavigating) {
                // Keep the keyboard selection and its zoom. Only release the
                // pointer hover a mouse-opened preview was keeping: the menu
                // hid that preview while hover was held, so nothing else
                // releases it and the dock could never auto-hide again.
                if (!DockView.pointerInside) {
                    root._pointerOnDock = false
                    if (!PreviewController.visible)
                        DockVisibility.setHovered(false)
                }
                return
            }
            if (DockView.pointerInside) {
                // Next real motion arrives as enter + move and resumes tracking.
                // Until then, keep hover held and re-hit-test the last real
                // pointer sample (rows may have shifted under it while held)
                // before restarting the hover pipeline.
                root._pointerOnDock = true
                root._hoverRehitPending = true
                root._hoverReconciling = true
                Qt.callLater(root._reconcileAfterHold)
            } else {
                root._pointerLeft()
            }
        }
    }

    // After a popup grab Qt's hover is stale (it thinks the pointer is
    // outside), so a real compositor leave reaches no onExited; end hover here.
    Connections {
        target: DockView
        function onBackgroundStyleTypeChanged() { dockPanel.reportPanelRect() }
        function onBackgroundColorChanged() { dockPanel.reportPanelRect() }
        function onPointerInsideChanged() {
            if (DockView.pointerInside)
                PreviewController.cancelHide()
            if (!DockView.pointerInside && !root._menuHeld && root._pointerOnDock
                    && !dockMouseArea.containsMouse)
                root._pointerLeft()
        }
    }

    Connections {
        target: DockSettings
        function onContentPaddingLeftChanged() { dockPanel.reportPanelRect() }
        function onContentPaddingRightChanged() { dockPanel.reportPanelRect() }
        function onContentPaddingTopChanged() { dockPanel.reportPanelRect() }
        function onContentPaddingBottomChanged() { dockPanel.reportPanelRect() }
        function onContentAlignmentChanged() { dockPanel.reportPanelRect() }
    }

    MouseArea {
        id: dockMouseArea
        Accessible.ignored: true
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        // Track hover state for visibility controller. Ignored while the
        // context menu holds hover; real input ends a pending reconcile.
        onEntered: {
            root._handleDockPointerEntered(mouseX, mouseY)
        }
        onExited: {
            if (root._menuHeld) return
            root._pointerLeft()
        }

        // Start drag hold timer on left-button press.
        // The item under a resting pointer can change without any motion
        // event (an item appears, the centred dock re-lays out), leaving
        // hoveredIndex stale: resolve it from the press position first so the
        // press, drag and click target the item actually under the pointer.
        // Keyboard navigation keeps its focused item as the target.
        onPressed: function(mouse) {
            // Preserve drag suppression while any other button remains held.
            if (mouse.buttons === mouse.button)
                root._dragWasActive = false
            // MouseArea fills root: mouse.x/y are root coordinates.
            if (!root._menuHeld) {
                root._pointerRootX = mouse.x
                root._pointerRootY = mouse.y
            }
            if (root._hoverReconciling && !root._menuHeld)
                root._reconcileAt(mouse.x, mouse.y)
            else if (!root.keyboardNavigating)
                root.trackPointer(mouse.x, mouse.y)
            if (mouse.button === Qt.LeftButton && root.hoveredIndex >= 0) {
                root._dragStartX = mouse.x
                root._dragStartY = mouse.y
                root._dragStartEntryId = root.dockEntryIdAt(root.hoveredIndex)
                dragHoldTimer.restart()
            }
        }

        onReleased: function(mouse) {
            dragHoldTimer.stop()

            if (root._dragActive) {
                const sourceId = root._dragSourceEntryId
                const targetId = root._dragTargetEntryId
                const sourceIndex = DockModel.dockPresentationModel.dockIndexForEntryId(sourceId)
                const targetIndex = DockModel.dockPresentationModel.dockIndexForEntryId(targetId)
                let moved = false
                if (sourceIndex >= 0 && targetIndex >= 0 && sourceId !== targetId) {
                    let item = dockRepeater.itemAt(sourceIndex)
                    let name = item ? item.displayName : ""
                    moved = root.reorderDockEntries(sourceId, targetId)
                    root.logDockOrderTrace("drop", sourceId, targetId, moved)
                    if (moved) {
                        Accessible.announce(
                            i18n("Moved %1 to position %2", name, targetIndex + 1),
                            Accessible.Polite)
                    }
                } else {
                    root.logDockOrderTrace("drop-noop", sourceId, targetId, false)
                }
            }
            root.clearDragState()
        }

        onCanceled: {
            root.logDockOrderTrace("pointer-cancel", root._dragSourceEntryId, root._dragTargetEntryId)
            root.clearDragState()
        }

        // Click handling: uses hoveredIndex from scaled hit testing
        // so clicks work correctly on zoomed icons
        onClicked: function(mouse) {
            // Suppress clicks for the entire held-button cycle after a drag.
            if (root._dragWasActive) return
            if (root.hoveredIndex < 0) return
            if (mouse.button === Qt.LeftButton) {
                let item = dockRepeater.itemAt(root.hoveredIndex)
                if (item && item.isFolderStack) {
                    item.openFolderStack()
                    return
                }
                const taskIndex = root.taskIndexAtDockIndex(root.hoveredIndex)
                if (taskIndex < 0) return
                let idx = DockModel.tasksModel.index(taskIndex, 0)
                let isWindow = DockModel.tasksModel.data(
                    idx, TaskManager.AbstractTasksModel.IsWindow)
                let isGroup = DockModel.tasksModel.data(
                    idx, TaskManager.AbstractTasksModel.IsGroupParent)
                // A regular click on a running task produces brief feedback.
                // The explicit group-preview action is navigation only, and
                // launchers retain their separate Launch Bounce behavior.
                if (isWindow && !(isGroup && DockSettings.groupedWindowClickAction === 1)) {
                    let item = dockRepeater.itemAt(root.hoveredIndex)
                    if (item) item.startClickBounce()
                }
                if (isWindow && isGroup && DockSettings.groupedWindowClickAction === 1) {
                    tooltipItem.show = false
                    tooltipTimer.stop()
                    let item = dockRepeater.itemAt(root.hoveredIndex)
                    if (item) {
                        // This is an explicit request to open the group chooser,
                        // so it may override dismissal from an earlier activation.
                        PreviewController.clearDismissedTask()
                        root.showPreviewForItem(root.hoveredIndex, item)
                    }
                } else if (isWindow && (isGroup
                           ? DockSettings.groupedWindowClickAction === 2
                           : DockSettings.singleWindowClickAction === 1)) {
                    const index = root.hoveredIndex
                    const dispatched = DockActions.activateOrMinimize(taskIndex)
                    root.dismissPreviewAfterTaskAction(index, dispatched, "activateOrMinimize")
                } else {
                    const index = root.hoveredIndex
                    const dispatched = DockActions.activate(taskIndex)
                    if (isWindow)
                        root.dismissPreviewAfterTaskAction(index, dispatched, "activate")
                }
            } else if (mouse.button === Qt.MiddleButton) {
                const taskIndex = root.taskIndexAtDockIndex(root.hoveredIndex)
                if (taskIndex >= 0) DockActions.newInstance(taskIndex)
            } else if (mouse.button === Qt.RightButton) {
                let item = dockRepeater.itemAt(root.hoveredIndex)
                if (item && item.isFolderStack)
                    item.openFolderContextMenu()
                else {
                    const taskIndex = root.taskIndexAtDockIndex(root.hoveredIndex)
                    if (taskIndex >= 0) DockContextMenu.showForTask(taskIndex)
                }
            }
        }

        // Mouse wheel: cycle through child windows of the hovered app
        onWheel: function(wheel) {
            if (root._hoverHeld) return
            if (root.hoveredIndex < 0) return
            const taskIndex = root.taskIndexAtDockIndex(root.hoveredIndex)
            if (taskIndex < 0) return
            if (wheel.angleDelta.y > 0) {
                DockActions.cycleWindows(taskIndex, false)
            } else if (wheel.angleDelta.y < 0) {
                DockActions.cycleWindows(taskIndex, true)
            }
        }

        // Track mouse position for parabolic zoom + drag handling
        onPositionChanged: function(mouse) {
            if (root._menuHeld) return
            root._pointerOnDock = true
            root._pointerRootX = mouse.x
            root._pointerRootY = mouse.y

            // Mouse movement cancels keyboard navigation mode
            if (root.keyboardNavigating) {
                root.keyboardNavigating = false
                DockVisibility.setKeyboardActive(false)
            }

            // --- Drag handling ---
            if (root._dragPending || root._dragActive) {
                const resolvedSource = DockModel.dockPresentationModel.dockIndexForEntryId(
                    root._dragSourceEntryId || root._dragStartEntryId)
                if (resolvedSource < 0) {
                    root.logDockOrderTrace("source-disappeared",
                                           root._dragSourceEntryId || root._dragStartEntryId,
                                           root._dragTargetEntryId)
                    root.clearDragState()
                    return
                }
                root._dragSourceIndex = resolvedSource
            }
            if (root._dragPending && !root._dragActive) {
                let dx = mouse.x - root._dragStartX
                let dy = mouse.y - root._dragStartY
                if (Math.sqrt(dx * dx + dy * dy) > root._dragThreshold) {
                    root._dragActive = true
                    root._dragWasActive = true
                    DockVisibility.setDragActive(true)  // Prevent dock hide + grab keyboard for Escape
                    tooltipItem.show = false
                    tooltipTimer.stop()
                }
            }

            if (root._dragActive) {
                root._dragCurrentX = mouse.x
                root._dragCurrentY = mouse.y
                root._dragTargetIndex = computeDropIndex(DockView.isVertical ? mouse.y : mouse.x)
                const targetId = root._dragTargetIndex >= 0
                    ? root.dockEntryIdAt(root._dragTargetIndex) : ""
                if (targetId !== root._dragTargetEntryId) {
                    root._dragTargetEntryId = targetId
                    root.logDockOrderTrace("target-change", root._dragSourceEntryId, targetId)
                }
                return  // Skip normal zoom handling during drag
            }

            if (root._hoverReconciling)
                root._reconcileAt(mouse.x, mouse.y)
            else
                root.trackPointer(mouse.x, mouse.y)
        }
    }

    // Projective SDF drop shadow via ShaderEffect.
    // Each pixel projects a ray from the light source through the ground plane
    // to determine shadow intensity — no blur/offset needed.
    // Shadow renders within available surface space; overflow clips naturally at screen edges.
    ShaderEffect {
        id: dockShadow
        visible: DockSettings.shadowEnabled
        z: dockPanel.z - 1
        Accessible.ignored: true

        // Shader uniforms (names must match outer_shadow.frag UBO fields)
        property real panelWidth: dockBackground.width
        property real panelHeight: dockBackground.height
        property real cornerRadius: dockBackground.radius
        property real elevation: DockSettings.shadowElevation
        property real lightX: DockSettings.shadowLightX
        property real lightY: DockSettings.shadowLightY
        property real lightZ: DockSettings.shadowLightZ
        property real lightRadius: DockSettings.shadowLightRadius
        property color _shadowColor: DockSettings.shadowColor
        property real shadowR: _shadowColor.r
        property real shadowG: _shadowColor.g
        property real shadowB: _shadowColor.b
        property real shadowA: DockSettings.shadowIntensity
        property real margin: _margin

        // Compute shadow margin: how far the shadow can extend beyond the panel
        // Takes the larger of physical projection margin and Gaussian 3-sigma spread
        property real _margin: {
            let denom = Math.max(lightZ - elevation, 1)
            let lightDist = Math.sqrt(lightX * lightX + lightY * lightY)
            let physicalMargin = (lightDist + lightRadius) * elevation / denom
            // Gaussian decays to ~0.1% at 3*sigma
            let softnessMargin = lightRadius * 3.0
            return Math.min(Math.max(physicalMargin, softnessMargin) + 10, 200)
        }

        // Centered on the visible background, expanded by margin on each side
        x: dockPanel.x + dockBackground.x - _margin
        y: dockPanel.y + dockBackground.y - _margin
        width: dockBackground.width + _margin * 2
        height: dockBackground.height + _margin * 2

        fragmentShader: "qrc:/qml/shaders/outer_shadow.frag.qsb"
    }

    // The dock panel: rest-size container (positioned per edge, fits content).
    // The visible background is dockBackground, which also covers zoom growth.
    Rectangle {
        id: dockPanel
        objectName: "dockPanel"

        readonly property real paddingLeft: DockSettings.contentPaddingLeft
        readonly property real paddingRight: DockSettings.contentPaddingRight
        readonly property real paddingTop: DockSettings.contentPaddingTop
        readonly property real paddingBottom: DockSettings.contentPaddingBottom
        readonly property int indicatorReserve: DockSettings.runningIndicatorSize * 2

        function alignedContentStart(available, contentExtent, leadingPadding, trailingPadding, alignment) {
            const freeSpace = Math.max(0, available - leadingPadding - trailingPadding - contentExtent)
            if (alignment === 0)
                return leadingPadding
            if (alignment === 2)
                return leadingPadding + freeSpace
            return leadingPadding + freeSpace / 2
        }

        // Padding belongs to the panel itself. The content's primary-axis
        // alignment is applied separately below, so alignment does not alter
        // the stored inset values.
        width: DockView.isVertical
            ? (DockSettings.iconSize + indicatorReserve + paddingLeft + paddingRight)
            : Math.max(dockRow.animatedContentWidth + paddingLeft + paddingRight, Kirigami.Units.gridUnit * 6)
        height: DockView.isVertical
            ? Math.max(dockRow.animatedContentHeight + paddingTop + paddingBottom, Kirigami.Units.gridUnit * 6)
            : (DockSettings.iconSize + indicatorReserve + paddingTop + paddingBottom)
        color: "transparent"

        // Rest slot coordinates stay at the visible panel position even
        // while the actual panel is slid off-screen for AutoHide/Dodge.
        readonly property real restEdgePos: {
            let fp = DockView.floatingPadding
            switch (DockView.edge) {
            case 0: // Top
                return fp
            case 1: // Bottom
                return parent.height - height - fp
            case 2: // Left
                return fp
            case 3: // Right
                return parent.width - width - fp
            }
            return 0
        }
        readonly property real restX: DockView.isVertical ? restEdgePos : (parent.width - width) / 2
        readonly property real restY: DockView.isVertical ? (parent.height - height) / 2 : restEdgePos

        // Animate only the visibility offset. Keeping the dock's zoom geometry
        // out of this animation prevents a hide/show transition from adding a
        // second easing pass to the icon layout.
        readonly property real hiddenEdgeOffset: {
            let sp = Kirigami.Units.largeSpacing
            switch (DockView.edge) {
            case 0: // Top
                return -height - sp - restY
            case 1: // Bottom
                return parent.height + sp - restY
            case 2: // Left
                return -width - sp - restX
            case 3: // Right
                return parent.width + sp - restX
            }
            return 0
        }
        property real visibilityOffset: DockVisibility.dockVisible ? 0 : hiddenEdgeOffset

        Behavior on visibilityOffset {
            enabled: dockPanel.animationsReady && DockSettings.dockShowHideAnimationEnabled
            NumberAnimation {
                duration: DockSettings.dockShowHideAnimationDuration
                easing.type: Easing.InOutCubic
            }
        }

        // Position: center on the non-edge axis and apply the independently
        // animated slide only along the screen edge axis.
        x: DockView.isVertical ? restX + visibilityOffset : restX
        y: DockView.isVertical ? restY : restY + visibilityOffset

        // Visible background. Rests on the panel extent and grows by the
        // zoom layout's edge-clamped growth on each side (Parabolic only;
        // InPlace never grows it). Tracks the layout directly: the growth is
        // already smoothed by dockPanel.zoomAmount.
        Rectangle {
            id: dockBackground
            z: -1
            readonly property real leadingGrowth: dockPanel.zoomLayout.leadingGrowth ?? 0
            readonly property real trailingGrowth: dockPanel.zoomLayout.trailingGrowth ?? 0

            x: DockView.isVertical ? 0 : -leadingGrowth
            y: DockView.isVertical ? -leadingGrowth : 0
            width: parent.width + (DockView.isVertical ? 0 : leadingGrowth + trailingGrowth)
            height: parent.height + (DockView.isVertical ? leadingGrowth + trailingGrowth : 0)
            radius: DockSettings.cornerRadius
            color: DockView.backgroundStyleType === 3
                   ? "transparent"
                   : DockView.backgroundColor

            onXChanged: dockPanel.reportPanelRect()
            onYChanged: dockPanel.reportPanelRect()
            onWidthChanged: dockPanel.reportPanelRect()
            onHeightChanged: dockPanel.reportPanelRect()

            // Acrylic overlay: tint + noise via GPU shader, composited over KWin blur.
            // Shader handles rounded corners via SDF mask — no clip wrapper needed.
            ShaderEffect {
                anchors.fill: parent
                visible: DockView.backgroundStyleType === 3
                property real tintR: DockView.backgroundColor.r
                property real tintG: DockView.backgroundColor.g
                property real tintB: DockView.backgroundColor.b
                property real tintOpacity: DockView.backgroundColor.a
                property real noiseStrength: 0.02
                property real resX: width
                property real resY: height
                property real cornerRadius: dockBackground.radius
                fragmentShader: "qrc:/qml/shaders/acrylic_overlay.frag.qsb"
            }
        }

        // Delay enabling animations until after initial layout to avoid startup flicker
        property bool animationsReady: false
        Component.onCompleted: {
            // Guaranteed initial panel-rect report; coalesces with any already-queued call.
            reportPanelRect()
            Qt.callLater(function() { animationsReady = true })
            springZoom.synchronize(zoomCursor, classicZoomAmount)
            updateSpringTarget()
        }

        Behavior on width {
            enabled: dockPanel.animationsReady
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }

        Behavior on height {
            enabled: dockPanel.animationsReady && DockView.isVertical
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }

        // Fade animation
        opacity: DockVisibility.dockVisible ? 1.0 : 0.0

        Behavior on opacity {
            enabled: dockPanel.animationsReady && DockSettings.dockShowHideAnimationEnabled
            NumberAnimation { duration: DockSettings.dockShowHideAnimationDuration }
        }

        // Mouse position relative to the panel, -1 when outside
        property real mouseX: -1
        property real mouseY: -1
        // Zoom activates when mouse hits an icon (_zoomActive=true) and stays
        // active until mouse leaves the panel zone (mouseX=-1). This hysteresis
        // prevents zoom flickering when crossing tiny gaps between icons.
        // Zoom is disabled during drag so all icons return to base scale.
        property bool mouseInside: mouseX >= 0 && root._zoomActive && !root._dragActive

        // --- Hover zoom ---
        // ZoomStyle (kdockw.kcfg): 0 = Parabolic (Gaussian magnification;
        // neighbours move aside and the background grows), 1 = InPlace (icons
        // scale over their neighbours, nothing moves).
        readonly property int zoomStyle: DockSettings.zoomStyle
        readonly property int magnificationMode: DockSettings.magnificationMode

        // Last valid primary-axis cursor. Kept when mouseX becomes -1 so the
        // zoom-out animation collapses around the point the cursor left from.
        property real zoomCursor: 0
        onMouseXChanged: if (mouseX >= 0) zoomCursor = mouseX
        Behavior on zoomCursor {
            enabled: root.keyboardNavigating
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        // Global zoom amount (0 = rest, 1 = full zoom): the only animated zoom
        // quantity, for both zoom styles. It eases in when the pointer enters
        // and out when it leaves; per-icon scales/offsets and the background
        // growth track the layout directly, so moving the pointer along the
        // dock never lags.
        property real classicZoomAmount: mouseInside ? 1.0 : 0.0
        ZoomAnimationProfile { id: zoomProfile }
        // Direction comes from Behavior.targetValue (set before the animation
        // starts), so binding evaluation order does not matter. A 0 ms
        // direction snaps synchronously.
        Behavior on classicZoomAmount {
            id: zoomAmountBehavior
            enabled: zoomProfile.animated
            NumberAnimation {
                duration: zoomAmountBehavior.targetValue > 0.5
                    ? zoomProfile.effectiveZoomInDuration
                    : zoomProfile.effectiveZoomOutDuration
                easing.type: zoomAmountBehavior.targetValue > 0.5
                    ? zoomProfile.zoomInEasingType
                    : zoomProfile.zoomOutEasingType
            }
        }
        SpringZoomController {
            id: springZoom
            objectName: "dockSpringZoomController"
        }
        readonly property real zoomAmount: magnificationMode === 1
            ? springZoom.amount : classicZoomAmount
        readonly property real layoutCursor: magnificationMode === 1
            ? springZoom.cursor : zoomCursor

        function updateSpringTarget() {
            if (magnificationMode !== 1) return
            if (root._dragActive) {
                springZoom.synchronize(zoomCursor, 0)
                return
            }
            springZoom.setTarget(zoomCursor, mouseInside ? 1.0 : 0.0,
                DockSettings.springStiffness, DockSettings.springDamping,
                DockSettings.springSpeed, 0,
                DockView.isVertical ? root.height : root.width)
        }
        onZoomCursorChanged: updateSpringTarget()
        onMouseInsideChanged: updateSpringTarget()
        onMagnificationModeChanged: {
            if (magnificationMode === 1) {
                // Start from the visible Classic amount when changing modes,
                // so the live dock does not snap to rest before the spring
                // takes over.
                springZoom.synchronize(zoomCursor, classicZoomAmount)
                updateSpringTarget()
            } else {
                springZoom.synchronize(zoomCursor, 0)
            }
        }
        Connections {
            target: DockSettings
            function onSpringStiffnessChanged() { dockPanel.updateSpringTarget() }
            function onSpringDampingChanged() { dockPanel.updateSpringTarget() }
            function onSpringSpeedChanged() { dockPanel.updateSpringTarget() }
        }
        Connections {
            target: root
            function on_DragActiveChanged() { dockPanel.updateSpringTarget() }
        }
        // A drag snaps icons back to rest at once (drop targeting and the drop
        // indicator use rest coordinates), whatever the animation is doing.
        readonly property real _layoutZoomAmount: root._dragActive ? 0.0 : zoomAmount

        // Scales/offsets/growth computed from REST geometry only (dockRow
        // position and settings), so zoom never feeds back into layout.
        // The output is a direct function of the cursor and zoomAmount.
        readonly property real _restStart: DockView.isVertical ? dockRow.y : dockRow.x
        // Surface bounds in this panel's primary-axis frame: the grown dock
        // background may not cross them.
        readonly property real _minZoomEdge: DockView.isVertical ? -y : -x
        readonly property real _maxZoomEdge: DockView.isVertical
            ? root.height - y
            : root.width - x
        readonly property var zoomLayout: DockView.zoomLayout(
            dockRepeater.count, _restStart,
            DockSettings.iconSize, DockSettings.iconSpacing,
            root.taskZoneBoundary, root.taskZoneGap,
            0, DockView.isVertical ? height : width,
            1.0 + (DockSettings.maxZoomFactor - 1.0) * _layoutZoomAmount,
            zoomStyle,
            _layoutZoomAmount > 0,
            layoutCursor, _minZoomEdge, _maxZoomEdge)
        // Icons keep changing under a still pointer while zoom is engaged
        // (zoom-in/out via zoomAmount; Parabolic also moves them and clamps
        // at the edges), so the icon under it can change without a mouse
        // move: re-run the hit test, coalesced to once per event-loop turn.
        // Only while engaged: a delegate's first scale/offset notification
        // (e.g. an icon appearing under a resting pointer) must not engage
        // zoom; that takes real pointer input, as for every other icon.
        function scheduleHoverUpdate() {
            if (mouseInside && !root.keyboardNavigating)
                Qt.callLater(root.updateHoveredItem)
        }

        // Report the visible background rect (surface frame) for input region + blur.
        // Deferred via Qt.callLater: multiple geometry signals fire per pointer
        // motion in push mode, and callLater coalesces them into a single call
        // per event-loop turn, avoiding Wayland input-region + KWin blur-region
        // rebuild churn.
        function reportPanelRect() {
            Qt.callLater(dockPanel._reportPanelRectNow)
        }
        function _reportPanelRectNow() {
            // Outward-round to integers: the C++ side truncates each component,
            // so floor/ceil avoids losing up to ~2px off the trailing edge.
            // Clamp the primary axis to the surface: the edge-clamped zoom layout can
            // overshoot by float error. The secondary axis is left alone because the
            // hide/show slide legitimately moves the panel past the surface edge.
            let left = Math.floor(x + dockBackground.x)
            let top = Math.floor(y + dockBackground.y)
            let right = Math.ceil(x + dockBackground.x + dockBackground.width)
            let bottom = Math.ceil(y + dockBackground.y + dockBackground.height)
            if (DockView.isVertical) {
                top = Math.max(0, top)
                bottom = Math.min(root.height, bottom)
            } else {
                left = Math.max(0, left)
                right = Math.min(root.width, right)
            }
            DockVisibility.setPanelRect(left, top, right - left, bottom - top)

            // Opaque and blurred backgrounds are visible throughout their
            // inset area. With a fully transparent background, only the row
            // and its parabolic growth should receive input or count for Dodge.
            const style = DockView.backgroundStyleType
            const backgroundVisible = style === 3 || (style !== 1 && DockView.backgroundColor.a > 0)
            let hitLeft = left
            let hitTop = top
            let hitRight = right
            let hitBottom = bottom
            if (!backgroundVisible) {
                const leading = DockView.isVertical ? 0 : dockBackground.leadingGrowth
                const trailing = DockView.isVertical ? 0 : dockBackground.trailingGrowth
                const leadingY = DockView.isVertical ? dockBackground.leadingGrowth : 0
                const trailingY = DockView.isVertical ? dockBackground.trailingGrowth : 0
                hitLeft = Math.floor(x + dockRow.x - leading)
                hitTop = Math.floor(y + dockRow.y - leadingY)
                const screenSideAfter = DockView.edge === 1 || DockView.edge === 3
                const indicatorAfterIcon = DockSettings.runningIndicatorPosition === 0 ? screenSideAfter : !screenSideAfter
                const indicatorBeforeIcon = !indicatorAfterIcon
                const contentX = dockRow.x + (DockView.isVertical && indicatorBeforeIcon ? dockPanel.indicatorReserve : 0)
                const contentY = dockRow.y + (!DockView.isVertical && indicatorBeforeIcon ? dockPanel.indicatorReserve : 0)
                const contentWidth = DockView.isVertical ? DockSettings.iconSize : dockRow.animatedContentWidth
                const contentHeight = DockView.isVertical ? dockRow.animatedContentHeight : DockSettings.iconSize
                hitLeft = Math.floor(x + contentX - leading)
                hitTop = Math.floor(y + contentY - leadingY)
                hitRight = Math.ceil(x + contentX + contentWidth + trailing)
                hitBottom = Math.ceil(y + contentY + contentHeight + trailingY)
                if (contentWidth <= 0 || contentHeight <= 0) {
                    // Never submit an empty QRegion: Wayland interprets it as
                    // accepting input everywhere on the surface.
                    hitLeft = Math.floor(x + width / 2)
                    hitTop = Math.floor(y + height / 2)
                    hitRight = hitLeft + 1
                    hitBottom = hitTop + 1
                }
                if (DockView.isVertical) {
                    hitTop = Math.max(0, hitTop)
                    hitBottom = Math.min(root.height, hitBottom)
                } else {
                    hitLeft = Math.max(0, hitLeft)
                    hitRight = Math.min(root.width, hitRight)
                }
            }
            DockVisibility.setInteractionRect(hitLeft, hitTop, hitRight - hitLeft, hitBottom - hitTop)
        }

        Connections {
            target: DockSettings
            function onRunningIndicatorPositionChanged() { dockPanel.reportPanelRect() }
            function onRunningIndicatorSizeChanged() { dockPanel.reportPanelRect() }
        }
        onXChanged: {
            reportPanelRect()
            root.scheduleDelegateGeometryRefresh()
        }
        onYChanged: {
            reportPanelRect()
            root.scheduleDelegateGeometryRefresh()
        }
        onWidthChanged: {
            updateSpringTarget()
            reportPanelRect()
            root.scheduleDelegateGeometryRefresh()
        }
        onHeightChanged: {
            updateSpringTarget()
            reportPanelRect()
            root.scheduleDelegateGeometryRefresh()
        }

        // Main icon layout (Flow switches between horizontal/vertical)
        Flow {
            id: dockRow
            flow: DockView.isVertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: DockSettings.iconSpacing

            onXChanged: {
                root.scheduleDelegateGeometryRefresh()
                dockPanel.reportPanelRect()
            }
            onYChanged: {
                root.scheduleDelegateGeometryRefresh()
                dockPanel.reportPanelRect()
            }
            onImplicitWidthChanged: root.scheduleDelegateGeometryRefresh()
            onImplicitHeightChanged: root.scheduleDelegateGeometryRefresh()
            onPositioningComplete: root.scheduleDelegateGeometryRefresh()

            // Animate content extent to sync centering with panel size animation.
            property real animatedContentWidth: implicitWidth + (DockView.isVertical ? 0 : root.taskZoneGap)
            property real animatedContentHeight: implicitHeight + (DockView.isVertical ? root.taskZoneGap : 0)
            Behavior on animatedContentWidth {
                enabled: dockPanel.animationsReady && !DockView.isVertical
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InOutQuad
                }
            }
            Behavior on animatedContentHeight {
                enabled: dockPanel.animationsReady && DockView.isVertical
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InOutQuad
                }
            }
            x: DockView.isVertical
                ? dockPanel.alignedContentStart(parent.width, implicitWidth, dockPanel.paddingLeft, dockPanel.paddingRight, DockSettings.contentAlignment)
                : dockPanel.alignedContentStart(parent.width, animatedContentWidth, dockPanel.paddingLeft, dockPanel.paddingRight, DockSettings.contentAlignment)
            y: DockView.isVertical
                ? dockPanel.alignedContentStart(parent.height, animatedContentHeight, dockPanel.paddingTop, dockPanel.paddingBottom, DockSettings.contentAlignment)
                : dockPanel.alignedContentStart(parent.height, implicitHeight, dockPanel.paddingTop, dockPanel.paddingBottom, DockSettings.contentAlignment)

            // Animate existing items displaced by add/remove within the Flow.
            // Disabled during hover zoom (mouseInside) to avoid lagging sibling
            // repositioning — zoom needs immediate response.
            move: Transition {
                enabled: dockPanel.animationsReady && !dockPanel.mouseInside
                NumberAnimation {
                    properties: "x,y"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InOutQuad
                }
            }

            Repeater {
                id: dockRepeater
                model: DockModel.dockPresentationModel
                property int layoutRevision: 0
                onCountChanged: root.scheduleDelegateGeometryRefresh()
                onItemAdded: {
                    layoutRevision++
                    root.scheduleDelegateGeometryRefresh()
                }
                onItemRemoved: {
                    layoutRevision++
                    root.scheduleDelegateGeometryRefresh()
                }

                DockItem {
                    id: taskDelegate
                    // index and model are injected by Repeater into
                    // DockItem's own required properties

                    // This visual-parent-independent item is the geometry
                    // target sent to libtaskmanager. Its QObject ownership
                    // remains with this delegate's declarative object tree,
                    // while parentItem is the dock root so its coordinates
                    // are surface-local and unaffected by panel slide or
                    // DockItem hover transforms.
                    Item {
                        id: delegateGeometryProxy
                        parent: root
                        visible: false
                        x: dockPanel.restX + (DockView.isVertical
                            ? dockRow.x + taskDelegate.x
                            : root._primaryRestSlotStart(taskDelegate))
                        y: dockPanel.restY + (DockView.isVertical
                            ? root._primaryRestSlotStart(taskDelegate)
                            : dockRow.y + taskDelegate.y)
                        width: taskDelegate.width
                        height: taskDelegate.height
                    }

                    delegateGeometryTarget: delegateGeometryProxy
                    dockRoot: root
                    z: (root.hoveredIndex === index) ? 1 : 0
                    isKeyboardFocused: root.keyboardNavigating && root.hoveredIndex === index
                    iconSize: DockSettings.iconSize
                    maxZoomFactor: DockSettings.maxZoomFactor
                    spacing: DockSettings.iconSpacing
                    restOffset: taskZoneBoundary >= 0 && index >= taskZoneBoundary
                        ? taskZoneGap : 0
                    restOffsetAnimationEnabled: dockPanel.animationsReady
                        && !dockPanel.mouseInside
                    zoomScale: dockPanel.zoomLayout.scales?.[index] ?? 1.0
                    zoomOffset: dockPanel.zoomLayout.offsets?.[index] ?? 0.0
                    itemCenterX: DockView.isVertical
                        ? root._primaryRestSlotStart(taskDelegate) + height / 2
                        : root._primaryRestSlotStart(taskDelegate) + width / 2
                    onCurrentOffsetChanged: dockPanel.scheduleHoverUpdate()
                    onCurrentScaleChanged: {
                        dockPanel.scheduleHoverUpdate()
                    }
                    onPreviewAnchorGeometryChanged: root.refreshPreviewAnchorForItem(index, taskDelegate)
                    onDelegateGeometryChanged: root.scheduleDelegateGeometryRefresh()


                    // Drag and drop visual feedback
                    isDragSource: root._dragActive && root._dragSourceEntryId === root.dockEntryIdAt(index)
                    isExternalDropTarget: externalDropArea.containsDrag
                                          && externalDropArea.dropTargetIndex === index
                }
            }

        }
        // Allocate a dedicated separator slot outside the Flow. The native
        // separator is centered between transformed visual edges below, cannot
        // become a task or keyboard stop, and contributes its thickness to
        // root.taskZoneGap for normal spacing on both sides.
        Kirigami.Separator {
            id: taskZonesSeparator
            objectName: "taskZonesSeparator"
            z: -0.5
            readonly property int boundary: root.taskZoneBoundary
            readonly property bool hasBoundary: boundary >= 0
            readonly property var pinnedItem: {
                let revision = dockRepeater.layoutRevision
                let count = dockRepeater.count
                return hasBoundary ? dockRepeater.itemAt(boundary - 1) : null
            }
            readonly property var runningItem: {
                let revision = dockRepeater.layoutRevision
                let count = dockRepeater.count
                return hasBoundary ? dockRepeater.itemAt(boundary) : null
            }
            readonly property real primaryCenter: {
                if (!pinnedItem || !runningItem) return 0
                let pinnedExtent = DockView.isVertical ? pinnedItem.height : pinnedItem.width
                let runningExtent = DockView.isVertical ? runningItem.height : runningItem.width
                let pinnedEdge = pinnedItem.itemCenterX + pinnedItem.currentOffset
                    + pinnedExtent * pinnedItem.currentScale / 2
                let runningEdge = runningItem.itemCenterX + runningItem.currentOffset
                    - runningExtent * runningItem.currentScale / 2
                return (pinnedEdge + runningEdge) / 2
            }
            readonly property real secondaryCenter: {
                if (!pinnedItem || !runningItem) return 0
                let pinnedSpan = root._secondarySpan(pinnedItem, pinnedItem.currentScale)
                let runningSpan = root._secondarySpan(runningItem, runningItem.currentScale)
                return (pinnedSpan.near + pinnedSpan.far + runningSpan.near + runningSpan.far) / 4
            }
            readonly property real thickness: root.taskZoneSeparatorThickness
            readonly property real length: Math.min(DockSettings.iconSize, Kirigami.Units.gridUnit * 2)
            visible: hasBoundary && pinnedItem !== null && runningItem !== null
            width: DockView.isVertical ? length : thickness
            height: DockView.isVertical ? thickness : length
            x: Math.round((DockView.isVertical ? secondaryCenter : primaryCenter) - width / 2)
            y: Math.round((DockView.isVertical ? primaryCenter : secondaryCenter) - height / 2)
            Accessible.role: Accessible.Separator
            Accessible.name: i18n("Pinned and running apps separator")
            Accessible.focusable: false
            Accessible.ignored: !visible

            Connections {
                target: DockModel.dockPresentationModel
                function onLayoutChanged() { dockRepeater.layoutRevision++ }
                function onRowsMoved() { dockRepeater.layoutRevision++ }
                function onModelReset() { dockRepeater.layoutRevision++ }
            }
        }

        // External drag and drop (files, .desktop, URLs from other apps)
        DropArea {
            id: externalDropArea
            objectName: "externalDropArea"
            anchors.fill: parent
            property int dropTargetIndex: -1
            property int activationTargetIndex: -1
            property bool activationRequested: false
            property bool externalFileDragActive: false
            property real externalDragPrimaryPosition: -1

            function supportsDrag(drag) {
                const hasTaskLauncherUrl = drag.formats.indexOf("text/x-orgkdeplasmataskmanager_taskurl") >= 0
                        && root.launcherUrlFromTaskMime(drag.formats,
                            drag.getDataAsString("text/x-orgkdeplasmataskmanager_taskurl")) !== ""
                return drag.hasUrls || hasTaskLauncherUrl
            }

            function processDrop(drop) {
                clearActivationTarget()
                let urls = []
                if (drop.hasUrls) {
                    for (let i = 0; i < drop.urls.length; i++)
                        urls.push(drop.urls[i])
                }

                if (drop.formats.indexOf("text/x-orgkdeplasmataskmanager_taskurl") >= 0) {
                    const taskLauncherUrl = root.launcherUrlFromTaskMime(
                        drop.formats,
                        drop.getDataAsString("text/x-orgkdeplasmataskmanager_taskurl"))
                    if (taskLauncherUrl.length > 0)
                        urls.unshift(taskLauncherUrl)
                }

                if (urls.length === 0) {
                    drop.accepted = false
                    dropTargetIndex = -1
                    return
                }

                const firstUrl = urls[0]
                const isLauncher = DockModel.isDesktopFile(firstUrl)
                const isLocalFolder = DockModel.isLocalDirectory(firstUrl)
                const targetItem = dropTargetIndex >= 0 ? dockRepeater.itemAt(dropTargetIndex) : null

                if (isLauncher) {
                    DockActions.addLauncher(firstUrl)
                } else if (isLocalFolder) {
                    DockActions.addFolderStack(firstUrl)
                } else if (targetItem && targetItem.isFolderStack) {
                    // Folder Stacks are browse-only in this release.
                    drop.accepted = false
                    dropTargetIndex = -1
                    return
                } else if (dropTargetIndex >= 0) {
                    const taskIndex = root.taskIndexAtDockIndex(dropTargetIndex)
                    if (taskIndex >= 0)
                        DockActions.openUrlsWithTask(taskIndex, urls)
                    else {
                        drop.accepted = false
                        dropTargetIndex = -1
                        return
                    }
                } else {
                    drop.accepted = false
                    dropTargetIndex = -1
                    return
                }

                drop.accepted = true
                dropTargetIndex = -1
            }

            function updateActivationTarget(drag) {
                if (!DockSettings.activateWindowOnExternalDrag || !drag.hasUrls || root._dragActive) {
                    const wasActive = externalFileDragActive
                    externalFileDragActive = false
                    externalDragPrimaryPosition = -1
                    activationTimer.stop()
                    activationTargetIndex = -1
                    activationRequested = false
                    if (wasActive)
                        resumeHoverAfterDrag()
                    return
                }

                const primaryPosition = DockView.isVertical ? drag.y : drag.x
                const wasActive = externalFileDragActive
                externalFileDragActive = true
                if (!wasActive) {
                    tooltipTimer.stop()
                    tooltipItem.show = false
                    PreviewController.hidePreview()
                }
                externalDragPrimaryPosition = primaryPosition
                const target = root.computeExternalDropIndex(primaryPosition)
                if (target === activationTargetIndex) return

                activationTimer.stop()
                activationTargetIndex = target
                activationRequested = false
                if (target >= 0) {
                    activationTimer.interval = DockSettings.externalDragActivationDelay
                    activationTimer.start()
                }
            }

            function clearActivationTarget() {
                const wasActive = externalFileDragActive
                externalFileDragActive = false
                externalDragPrimaryPosition = -1
                activationTimer.stop()
                activationTargetIndex = -1
                activationRequested = false
                if (wasActive)
                    resumeHoverAfterDrag()
            }

            function resumeHoverAfterDrag() {
                if (root.hoveredIndex >= 0
                        && (root._pointerOnDock || DockView.pointerInside)
                        && !root.keyboardNavigating
                        && !root._hoverHeld) {
                    tooltipTimer.restart()
                }
            }

            function activatePendingTarget() {
                if (!DockSettings.activateWindowOnExternalDrag
                        || !externalFileDragActive
                        || root._dragActive
                        || activationRequested) {
                    return
                }
                const currentTarget = root.computeExternalDropIndex(externalDragPrimaryPosition)
                if (currentTarget < 0 || currentTarget !== activationTargetIndex) {
                    clearActivationTarget()
                    return
                }
                const taskIndex = root.taskIndexAtDockIndex(currentTarget)
                if (taskIndex < 0) return
                activationRequested = true
                DockActions.activateWindowForExternalDrag(taskIndex)
            }

            Timer {
                id: activationTimer
                repeat: false
                onTriggered: externalDropArea.activatePendingTarget()
            }

            Connections {
                target: DockSettings
                function onActivateWindowOnExternalDragChanged() {
                    if (!DockSettings.activateWindowOnExternalDrag)
                        externalDropArea.clearActivationTarget()
                }
            }

            onEntered: function(drag) {
                drag.accepted = supportsDrag(drag)
                updateActivationTarget(drag)
            }

            onPositionChanged: function(drag) {
                const primaryPosition = DockView.isVertical ? drag.y : drag.x
                dropTargetIndex = root.computeExternalDropIndex(primaryPosition)
                updateActivationTarget(drag)
            }

            onDropped: function(drop) {
                processDrop(drop)
            }

            onExited: {
                dropTargetIndex = -1
                clearActivationTarget()
            }
        }
    }

    // Floating drag ghost icon (follows cursor during internal reorder drag)
    Image {
        id: dragGhost
        Accessible.ignored: true
        visible: root._dragActive && root._dragSourceIndex >= 0
        width: DockSettings.iconSize
        height: DockSettings.iconSize
        source: {
            if (!visible) return ""
            const sourceItem = dockRepeater.itemAt(root._dragSourceIndex)
            if (!sourceItem) return ""
            if (sourceItem.isFolderStack && sourceItem.model.iconUrl)
                return sourceItem.model.iconUrl
            const name = sourceItem.iconName || ""
            if (!name.length) return ""
            return "image://icon/" + name + "?v=" + DockView.iconCacheVersion
        }
        sourceSize: Qt.size(DockSettings.iconSize, DockSettings.iconSize)
        x: root._dragCurrentX - width / 2
        y: root._dragCurrentY - height / 2
        opacity: 0.8
        z: 200
    }

    // Drop position indicator line (shown during internal reorder drag)
    Rectangle {
        id: dropIndicator
        Accessible.ignored: true
        visible: root._dragActive && root._dragTargetIndex >= 0
                 && root._dragTargetIndex !== root._dragSourceIndex
        width: DockView.isVertical ? DockSettings.iconSize : 2
        height: DockView.isVertical ? 2 : DockSettings.iconSize
        color: Kirigami.Theme.highlightColor
        radius: 1
        z: 150

        x: {
            if (!visible || root._dragTargetIndex < 0) return 0
            if (DockView.isVertical) return dockPanel.x + dockRow.x
            let targetItem = dockRepeater.itemAt(root._dragTargetIndex)
            if (!targetItem) return 0
            let itemX = dockPanel.x + root._primaryRestSlotStart(targetItem)
            if (root._dragTargetIndex > root._dragSourceIndex) {
                return itemX + targetItem.width + DockSettings.iconSpacing / 2 - 1
            } else {
                return itemX - DockSettings.iconSpacing / 2 - 1
            }
        }
        y: {
            if (!visible || root._dragTargetIndex < 0) return 0
            if (!DockView.isVertical) return dockPanel.y + dockRow.y
            let targetItem = dockRepeater.itemAt(root._dragTargetIndex)
            if (!targetItem) return 0
            let itemY = dockPanel.y + root._primaryRestSlotStart(targetItem)
            if (root._dragTargetIndex > root._dragSourceIndex) {
                return itemY + targetItem.height + DockSettings.iconSpacing / 2 - 1
            } else {
                return itemY - DockSettings.iconSpacing / 2 - 1
            }
        }
    }

    // Handle launch bounce trigger from C++ signal.
    // manualLaunching is set for every launch, launchers included: a task
    // manager without startup notifications (a plain KWin 6 session) never
    // reports an IsStartup task, so the click itself must start the feedback.
    // For a launcher, the delegate's feedback ends when the launcher row is
    // replaced (hideActivatedLaunchers) by the startup task, which carries
    // on via IsStartup, or by the app's window.
    Connections {
        target: DockActions
        function onTaskLaunching(index) {
            const dockIndex = DockModel.dockPresentationModel.dockIndexForTaskIndex(index)
            let item = dockRepeater.itemAt(dockIndex)
            if (!item) return

            // Announce launch to screen reader (must call on root Item, not Connections)
            root.announceLaunch(item.displayName)

            // Start a bounded visual signal for this request. The launch state
            // remains tracked separately until KDE reports a window or timeout.
            item.startLaunchBounce()
            item.manualLaunching = true
        }
    }

    // Auto-trigger preview when a hovered launcher becomes a window.
    // Polls only while the text tooltip is visible (launcher hover state).
    // When IsWindow becomes true → switches from text tooltip to preview popup.
    Timer {
        id: autoPreviewTimer
        interval: 200
        repeat: true
        running: tooltipItem.visible && !PreviewController.visible && !root._hoverHeld
                 && !externalDropArea.externalFileDragActive
        onTriggered: root._tryAutoPreview()
    }

    // Sync dock hover state when preview closes:
    // If preview was keeping dock hovered and mouse is no longer on dock,
    // release hover so dock can hide.
    Connections {
        target: PreviewController
        function onVisibleChanged() {
            // The menu hold hides the preview; hover is reconciled on close.
            if (root._hoverHeld) return
            if (externalDropArea.externalFileDragActive) return
            if (!PreviewController.visible && PreviewController.dismissedTaskIndex >= 0
                    && PreviewController.dismissedTaskIndex === root.hoveredIndex) return
            if (!PreviewController.visible && !root._pointerOnDock) {
                // Preview closed and mouse not on dock → release zoom smoothly
                dockPanel.mouseX = -1
                dockPanel.mouseY = -1
                root._zoomActive = false
                DockVisibility.setHovered(false)
            } else if (!PreviewController.visible && root.hoveredIndex >= 0
                       && !root.keyboardNavigating && !root._dragActive) {
                // Resume a stopped tooltip without delaying a pending hover.
                tooltipTimer.start()
            }
        }
    }

    // Custom tooltip / preview trigger timer.
    // For window tasks: shows the preview popup (separate layer-shell surface).
    // For launcher-only tasks: shows the in-scene text tooltip.
    Timer {
        id: tooltipTimer
        interval: DockSettings.previewHoverDelay
        onTriggered: {
            if (root.hoveredIndex < 0 || root._hoverHeld
                    || externalDropArea.externalFileDragActive
                    || PreviewController.dismissedTaskIndex === root.hoveredIndex) return
            // Row removed under the hover before the re-hit-test ran.
            if (root.hoveredIndex >= dockRepeater.count
                    || !dockRepeater.itemAt(root.hoveredIndex)) return
            const hoveredItem = dockRepeater.itemAt(root.hoveredIndex)
            if (hoveredItem.isFolderStack) {
                if (!hoveredItem.popupVisible)
                    tooltipItem.show = true
                return
            }
            const taskIndex = root.taskIndexAtDockIndex(root.hoveredIndex)
            if (taskIndex < 0) return
            let idx = DockModel.tasksModel.index(taskIndex, 0)
            let isWindow = DockModel.tasksModel.data(
                idx, TaskManager.AbstractTasksModel.IsWindow)
            if (isWindow && DockSettings.previewEnabled) {
                // Window task → show preview popup
                let item = dockRepeater.itemAt(root.hoveredIndex)
                if (item) root.showPreviewForItem(root.hoveredIndex, item)
            } else if (!PreviewController.visible) {
                // Hover previews disabled or launcher-only → show text tooltip
                tooltipItem.show = true
            }
        }
    }

    // Tooltips are rendered inside the dock's layer-shell surface. Publish the
    // maximum cross-axis extent (text, gap at maximum zoom, shadow) so the
    // compositor surface contains the full tooltip on every dock edge.
    Binding {
        target: DockView
        property: "tooltipReserve"
        value: tooltipItem.requiredSurfaceReserve
    }

    Kirigami.ShadowedRectangle {
        id: tooltipItem
        objectName: "dockTooltip"
        Accessible.ignored: true
        property bool show: false
        visible: show && root.hoveredName.length > 0

        // Reset when hover changes
        onVisibleChanged: if (!visible) show = false

        // Longer names elide on vertical docks instead of clipping at the surface edge
        readonly property real maxSideWidth: Kirigami.Units.gridUnit * 15
        readonly property real maxLabelWidth: DockView.isVertical
            ? maxSideWidth - Kirigami.Units.largeSpacing * 2
            : Math.max(0, root.width - Kirigami.Units.largeSpacing * 4)
        // DockItem scales its full hit/indicator slot, not only iconSize.
        // Include the reserved running-indicator band so the tooltip remains
        // clear at the larger default magnification as well.
        readonly property real maximumZoomGrowth: (DockSettings.iconSize
            + DockSettings.runningIndicatorSize * 2)
            * Math.max(0, DockSettings.maxZoomFactor - 1)
        readonly property real maximumGap: Kirigami.Units.largeSpacing + maximumZoomGrowth
        readonly property real shadowOverflow: shadow.size
            + Math.max(Math.abs(shadow.xOffset), Math.abs(shadow.yOffset))
        readonly property real crossAxisExtent: DockView.isVertical
            ? maxSideWidth
            : height
        readonly property int requiredSurfaceReserve: Math.ceil(
            crossAxisExtent + maximumGap + shadowOverflow)

        // The tooltip sits beyond the zoomed icon's outward edge, not just
        // beyond the dock's rest-size panel. This keeps it clear of the icon
        // while still using the same live zoom scale for launchers and windows.
        function gapForItem(item) {
            return Kirigami.Units.largeSpacing
                + Math.max(0, (DockView.isVertical ? item.width : item.height)
                    * (item.currentScale - 1))
        }

        function clampToSurface(center, extent, available) {
            return Math.max(0, Math.min(available - extent, center - extent / 2))
        }

        // Position on the opposite side of the dock edge
        x: {
            if (root.hoveredIndex < 0 || root.hoveredIndex >= dockRepeater.count)
                return 0
            let item = dockRepeater.itemAt(root.hoveredIndex)
            if (!item) return 0
            let sp = tooltipItem.gapForItem(item)
            if (DockView.edge === 2) return dockPanel.x + dockPanel.width + sp  // Left → right
            if (DockView.edge === 3) return dockPanel.x - width - sp            // Right → left
            // Visual centre: rest centre plus the animated zoom offset (Scale keeps the centre).
            // Clamp along the screen axis so edge icons never put the label
            // outside the layer-shell surface.
            const center = dockPanel.x + root._primaryRestSlotStart(item)
                + item.width / 2 + item.currentOffset
            return tooltipItem.clampToSurface(center, width, root.width)
        }
        y: {
            if (root.hoveredIndex < 0 || root.hoveredIndex >= dockRepeater.count)
                return 0
            let item = dockRepeater.itemAt(root.hoveredIndex)
            if (!item) return 0
            let sp = tooltipItem.gapForItem(item)
            if (DockView.edge === 0) return dockPanel.y + dockPanel.height + sp  // Top → below
            if (DockView.edge === 1) return dockPanel.y - height - sp            // Bottom → above
            const center = dockPanel.y + root._primaryRestSlotStart(item)
                + item.height / 2 + item.currentOffset
            return tooltipItem.clampToSurface(center, height, root.height)
        }

        width: tooltipLabel.width + Kirigami.Units.largeSpacing * 2
        height: tooltipLabel.implicitHeight + Kirigami.Units.largeSpacing
        radius: Math.min(DockSettings.cornerRadius, width / 2, height / 2)
        color: DockView.backgroundColor.a > 0
            ? DockView.backgroundColor
            : Qt.alpha(Kirigami.Theme.backgroundColor, DockSettings.backgroundOpacity)
        border.width: 1
        border.color: Qt.alpha(BadgeTextColor.choose(color, Kirigami.Theme.textColor), 0.27)
        shadow.size: DockSettings.shadowEnabled ? DockSettings.shadowLightRadius * 2 : 0
        shadow.xOffset: -DockSettings.shadowLightX * DockSettings.shadowElevation
            / Math.max(1, DockSettings.shadowLightZ)
        shadow.yOffset: -DockSettings.shadowLightY * DockSettings.shadowElevation
            / Math.max(1, DockSettings.shadowLightZ)
        shadow.color: Qt.alpha(DockSettings.shadowColor, DockSettings.shadowIntensity)
        z: 100

        QQC2.Label {
            id: tooltipLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tooltipItem.maxLabelWidth)
            elide: Text.ElideRight
            text: root.hoveredName
            color: BadgeTextColor.choose(tooltipItem.color, Kirigami.Theme.textColor)
            Accessible.ignored: true
        }

        // Hide tooltip and manage preview when hover changes
        Connections {
            target: root
            function onHoveredIndexChanged() {
                tooltipItem.show = false
                tooltipTimer.stop()
                if (PreviewController.dismissedTaskIndex >= 0
                        && PreviewController.dismissedTaskIndex !== root.hoveredIndex)
                    PreviewController.clearDismissedTask()
                if (root._hoverHeld) return
                if (externalDropArea.externalFileDragActive) return
                if (PreviewController.dismissedTaskIndex === root.hoveredIndex)
                    return
                if (root.hoveredIndex < 0) {
                    // Mouse left dock: start delayed preview hide
                    PreviewController.hidePreviewDelayed()
                } else if (!root.keyboardNavigating) {
                    // Moved to different icon (mouse): restart tooltip timer,
                    // hide preview with delay (allows moving to adjacent icon)
                    PreviewController.hidePreviewDelayed()
                    tooltipTimer.restart()
                }
                // In keyboard mode: don't auto-trigger tooltip/preview
            }
        }
    }

    // Auto-trigger preview when a hovered launcher's window appears.
    // Reacts to TasksModel row insertion — more responsive than polling.
    // _tryAutoPreview() honours the hover-preview setting.
    Connections {
        target: DockModel.dockPresentationModel
        function onRowsInserted() {
            root._tryAutoPreview()
            root.scheduleDelegateGeometryRefresh()
        }
        function onRowsRemoved() {
            root.scheduleDelegateGeometryRefresh()
            root.scheduleHoverRehit()
        }
        function onRowsMoved() {
            root.scheduleDelegateGeometryRefresh()
            root.scheduleHoverRehit()
        }
        function onLayoutChanged() { root.scheduleDelegateGeometryRefresh() }
        function onModelReset() {
            root.scheduleDelegateGeometryRefresh()
            root.scheduleHoverRehit()
        }
    }

    // Debug-only badge overlay prototype. These delegates are siblings of the
    // dock panel under the existing layer-shell root, so glyphs are laid out
    // at their final zoom size without creating another Wayland surface or
    // inheriting DockItem's parabolic Scale transform.
    Repeater {
        model: DockModel.dockPresentationModel
        delegate: Item {
            id: badgeOverlay
            objectName: "badgeOverlayItem"
            // Repeater.itemAt() has no change notification. Depend on the
            // dock repeater's insertion/removal revision so this lookup is
            // retried when its delegates are created asynchronously.
            readonly property int sourceItemRevision: dockRepeater.layoutRevision
            readonly property var sourceItem: sourceItemRevision >= 0
                ? dockRepeater.itemAt(index) : null
            readonly property real sourceScale: sourceItem ? sourceItem.badgeOverlayScale : 1
            readonly property rect mappedBadge: sourceItem && sourceItem.badgeOverlayVisible
                    && sourceScale >= 0
                ? sourceItem.badgeOverlayRectIn(root) : Qt.rect(0, 0, 0, 0)
            x: mappedBadge.x
            y: mappedBadge.y
            width: mappedBadge.width
            height: mappedBadge.height
            visible: !!sourceItem && sourceItem.badgeOverlayVisible
            enabled: false
            z: 250
            Accessible.ignored: true

            Rectangle {
                id: badgeOverlayCircle
                anchors.fill: parent
                radius: width / 2
                color: Kirigami.Theme.highlightColor
            }

            MultiEffect {
                anchors.fill: badgeOverlayCircle
                source: badgeOverlayCircle
                shadowEnabled: true
                shadowColor: Qt.alpha("black", 0.4)
                shadowBlur: 0.3
                shadowVerticalOffset: 1
            }

            QQC2.Label {
                id: badgeOverlayLabel
                objectName: "badgeOverlayLabel"
                width: parent.width - 2
                height: parent.height - 2
                // Keep the label centered at fractional zoom coordinates;
                // QQuick anchors can snap the top-left to an integer pixel.
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2
                text: sourceItem && sourceItem.badgeOverlayCount > 99
                    ? "99+" : (sourceItem ? sourceItem.badgeOverlayCount.toString() : "")
                color: BadgeTextColor.choose(badgeOverlayCircle.color,
                                             Kirigami.Theme.highlightedTextColor)
                renderType: Text.QtRendering
                font.pixelSize: parent.height * 0.55
                font.bold: true
                fontSizeMode: Text.Fit
                minimumPixelSize: 5
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Component.onCompleted: {
                    if (IconDiagnostics.testBadgeTextQt)
                        renderType = Text.QtRendering
                    else if (IconDiagnostics.testBadgeTextNative)
                        renderType = Text.NativeRendering
                    logOverlayMetrics("component-created")
                }
                function renderTypeName() {
                    if (renderType === Text.NativeRendering) return "native"
                    if (renderType === Text.CurveRendering) return "curve"
                    return "qt"
                }
                function logOverlayMetrics(reason) {
                    if (!sourceItem || !IconDiagnostics.testBadgeMetrics)
                        return
                    const topLeft = mapToItem(root, 0, 0)
                    const bottomRight = mapToItem(root, width, height)
                    const rootGeometry = Qt.rect(
                        Math.min(topLeft.x, bottomRight.x),
                        Math.min(topLeft.y, bottomRight.y),
                        Math.abs(bottomRight.x - topLeft.x),
                        Math.abs(bottomRight.y - topLeft.y))
                    IconDiagnostics.logBadgeOverlayRenderMetrics(
                        sourceItem._appId, sourceItem.badgeOverlayCount,
                        renderTypeName(), sourceItem.badgeOverlayScale,
                        parent.height * 0.55, font.pixelSize, fontInfo.pixelSize,
                        baselineOffset, contentWidth, contentHeight,
                        Qt.rect(x, y, width, height), rootGeometry,
                        layer.enabled, badgeOverlay.layer.enabled,
                        scale, badgeOverlay.scale,
                        IconDiagnostics.windowDevicePixelRatio)
                }
                onWidthChanged: logOverlayMetrics("width-changed")
                onHeightChanged: logOverlayMetrics("height-changed")
                onFontChanged: logOverlayMetrics("overlay-font-changed")
                onBaselineOffsetChanged: logOverlayMetrics("overlay-baseline-changed")
                onContentWidthChanged: logOverlayMetrics("overlay-content-width-changed")
                onContentHeightChanged: logOverlayMetrics("overlay-content-height-changed")
            }

            Connections {
                target: sourceItem
                function onBadgeOverlayScaleChanged() {
                    badgeOverlayLabel.logOverlayMetrics("zoom-frame")
                }
            }
        }
    }

}
