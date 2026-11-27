// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor
import "ShadowVector.js" as ShadowVector

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
    property alias builtInWidgetManager: widgetManager

    Accessible.role: Accessible.ToolBar
    Accessible.name: i18n("KDockW Dock")

    // C++ singletons: DockView, DockModel, DockActions, DockContextMenu, DockVisibility, DockSettings, PreviewController

    // Hovered item tracking (for custom tooltip and click targeting)
    property int hoveredIndex: -1
    // A preview request may wait for an unpinned media popup to finish closing.
    // Store the stable presentation identity so model reordering cannot retarget it.
    property string _pendingPreviewHandoffEntryId: ""
    // A separator is a real primary-axis slot, not an overlay in the normal
    // inter-icon gap. The boundary remains a model-free index so task and
    // keyboard indices are unchanged.
    readonly property int taskZoneBoundary: {
        // isPinnedDockIndex() reads model row data through an invokable, which
        // does not itself create a QML binding dependency. Re-evaluate the
        // boundary when presentation rows move even if the row count is stable.
        const layoutRevision = dockRepeater.layoutRevision
        if (!DockSettings.separateLaunchers || DockModel.pinnedDockEntryCount === 0)
            return -1
        for (let i = 0; i < dockRepeater.count; ++i) {
            if (!DockModel.dockPresentationModel.isPinnedDockIndex(i))
                return i > 0 ? i : -1
        }
        return -1
    }
    readonly property real taskZoneSeparatorThickness: 1
    readonly property var taskZoneSeparatorItems: {
        const revision = dockRepeater.layoutRevision
        const boundary = taskZoneBoundary
        return {
            pinned: boundary > 0 ? dockRepeater.itemAt(boundary - 1) : null,
            running: boundary >= 0 ? dockRepeater.itemAt(boundary) : null
        }
    }
    readonly property real taskZoneSeparatorSecondaryCenter: {
        const pair = taskZoneSeparatorItems
        if (!pair.pinned || !pair.running) {
            return DockView.isVertical
                ? dockRow.x + dockRow.width / 2
                : dockRow.y + dockRow.height / 2
        }
        const pinnedSpan = _secondarySpan(pair.pinned, pair.pinned.currentScale)
        const runningSpan = _secondarySpan(pair.running, pair.running.currentScale)
        return (pinnedSpan.near + pinnedSpan.far + runningSpan.near + runningSpan.far) / 4
    }

    function taskZoneSeparatorSecondaryCenterIn(item) {
        // mapFromItem() does not create bindings for the source geometry, so
        // read it explicitly to follow layout and Spring Magnification moves.
        const geometryRevision = taskZonesSeparator.x + taskZonesSeparator.y
            + taskZonesSeparator.width + taskZonesSeparator.height
        const point = item.mapFromItem(
            taskZonesSeparator, taskZonesSeparator.width / 2, taskZonesSeparator.height / 2)
        return DockView.isVertical ? point.x : point.y
    }
    readonly property real taskZoneGap: taskZoneBoundary >= 0
        ? DockSettings.iconSpacing + taskZoneSeparatorThickness : 0
    property string hoveredName: ""
    // The ordinary item resolver retains a validated Compact identity only
    // while applying its in-motion maximum-zoom envelope.
    property int _compactMediaMagnificationIndex: -1
    property string _compactMediaMagnificationEntryId: ""
    property var _lastHitTestResolution: ({})
    property int _hoverTraceScenarioSerial: 0
    property int _hoverTraceInteractionSerial: 0
    property int _lastHoverTraceDelegateIndex: -1
    property int _lastTracedCompactAnchor: -2
    property string _lastTracedCompactAnchorEntryId: ""
    property string _hoverTraceScenarioId: "unmarked"
    property string _hoverTraceInteractionId: "unmarked"
    property string _hoverTraceInteractionKind: "none"
    property string _lastHoverTraceHitSignature: ""
    property real _lastHoverTracePointerMs: -1000

    function hoverTraceContext() {
        return {
            scenarioId: _hoverTraceScenarioId,
            interactionId: _hoverTraceInteractionId,
            interactionKind: _hoverTraceInteractionKind
        }
    }

    function beginHoverTraceInteraction(kind, index, source) {
        if (!DockView.mediaHoverDebugEnabled) return
        _hoverTraceInteractionSerial++
        _hoverTraceInteractionKind = kind
        _hoverTraceInteractionId = _hoverTraceScenarioId + "/" + kind + "-" + _hoverTraceInteractionSerial
        if (typeof DockView.setDiagnosticInteractionContext === "function") {
            DockView.setDiagnosticInteractionContext(_hoverTraceScenarioId,
                _hoverTraceInteractionId, _hoverTraceInteractionKind)
        }
        traceMagnificationState("interaction-start", index, source, -1, index, {
            transition: kind
        })
    }

    function recordHoverTraceMarker(label) {
        if (!DockView.mediaHoverDebugEnabled) return
        traceMagnificationState("owner-marker", hoveredIndex, "local-ipc",
            hoveredIndex, hoveredIndex, { marker: label })
    }

    function traceMagnificationState(event, index, source, rawHitTestIndex,
                                     resolvedHitTestIndex, extra = ({})) {
        if (!DockView.mediaHoverDebugEnabled) return
        DockView.traceMediaHover(event,
            hoverTraceSnapshot(index, source, rawHitTestIndex, resolvedHitTestIndex, extra))
    }

    function hoverTraceSnapshot(index, source, rawHitTestIndex,
                                resolvedHitTestIndex, extra = ({})) {
        const observedIndex = index >= 0 ? index
            : hoveredIndex >= 0 ? hoveredIndex
            : _lastHoverTraceDelegateIndex
        const item = observedIndex >= 0 && observedIndex < dockRepeater.count
            ? dockRepeater.itemAt(observedIndex) : null
        if (index >= 0 && item)
            _lastHoverTraceDelegateIndex = index
        const itemPoint = item ? item.mapToItem(root, 0, 0) : null
        const media = item ? item.mediaPlayerWidget : null
        const focusKnown = DockView.pointerFocusKnown
        const focusWindow = DockView.pointerFocusWindow
        const focusIsDock = focusKnown && focusWindow === root.Window.window
        const geometry = item ? {
            x: itemPoint.x, y: itemPoint.y, width: item.width, height: item.height,
            currentScale: item.currentScale, targetScale: item.zoomScale
        } : null
        const details = {
            scenarioId: _hoverTraceScenarioId,
            interactionId: _hoverTraceInteractionId,
            interactionKind: _hoverTraceInteractionKind,
            delegateType: !item ? "none" : item.isMediaPlayer
                ? (DockSettings.mediaPlayerDisplayMode === 0 ? "compact-media" : "media-player")
                : item._isWindow ? "application-window" : (item.model.entryType || "dock-entry"),
            entryId: item ? item.dockEntryId : "",
            dockIndex: index,
            observedDelegateIndex: observedIndex,
            pointerMotionSerial: pointerMotionSerial,
            source: source,
            waylandSurfaceFocus: !focusKnown ? "unknown" : (focusIsDock ? "dock" : "other"),
            pointerFocusWindowObjectName: focusWindow ? focusWindow.objectName : "",
            pointerFocusWindowType: focusWindow ? focusWindow.type : -1,
            pointerSourceMode: DockView.pointerSourceMode,
            pointerSampleSequence: DockView.pointerSampleSequence,
            pointerSampleSurfaceId: DockView.pointerSampleSurfaceId,
            pointerSampleSurfaceGeneration: DockView.pointerSampleSurfaceGeneration,
            pointerSamplePosition: DockView.pointerSamplePosition,
            pointerLocal: { x: _pointerRootX, y: _pointerRootY },
            dockPanelPointer: { x: dockPanel.mouseX, y: dockPanel.mouseY },
            delegateGeometry: geometry,
            rawHitTestIndex: rawHitTestIndex,
            resolvedHitTestIndex: resolvedHitTestIndex,
            hoveredIndex: hoveredIndex,
            magnificationAnchor: hoveredIndex,
            compactMagnificationIndex: _compactMediaMagnificationIndex,
            compactMagnificationEntryId: _compactMediaMagnificationEntryId,
            zoomActive: _zoomActive,
            mouseInside: dockPanel.mouseInside,
            dragActive: _dragActive,
            springTargetAmount: dockPanel.magnificationMode === 1
                ? springZoom.targetAmount : (dockPanel.mouseInside ? 1 : 0),
            springAmount: dockPanel.magnificationMode === 1 ? springZoom.amount : 0,
            springCursor: dockPanel.zoomCursor,
            currentScale: item ? item.currentScale : 1,
            popupVisible: media ? media.diagnosticPopupVisible : false,
            popupHoldIndex: _mediaPopupHoldIndex,
            popupHoldEntryId: _mediaPopupHoldEntryId,
            mediaHoverGate: media ? media.pointerOverDockWidget : false,
            previewVisible: PreviewController.visible
        }
        for (const key in extra) details[key] = extra[key]
        return details
    }

    // Queried only through diagnostic IPC. This returns cached hover and
    // magnification state plus current item geometry; it deliberately does
    // not call trackPointer(), resolveDockItemHit(), or update any state.
    function mediaHoverDiagnosticSnapshot() {
        const compactIndex = _compactMediaMagnificationIndex
        const popupIndex = _mediaPopupHoldIndex
        let observedIndex = compactIndex >= 0 ? compactIndex
            : popupIndex >= 0 ? popupIndex : hoveredIndex
        let item = observedIndex >= 0 && observedIndex < dockRepeater.count
            ? dockRepeater.itemAt(observedIndex) : null
        if (item && compactIndex >= 0 && _compactMediaMagnificationEntryId.length > 0
                && item.dockEntryId !== _compactMediaMagnificationEntryId) {
            item = null
        }
        const media = item ? item.mediaPlayerWidget : null
        // Keep the diagnostic snapshot useful when hover is currently on a
        // different item (or no item). In particular, a failed return from a
        // detached popup may have already cleared both the Compact anchor and
        // the hovered index, so geometry must not depend on either state.
        let mediaWidgetIndex = -1
        const preferredMediaEntryId = _mediaPopupHoldEntryId.length > 0
            ? _mediaPopupHoldEntryId
            : _compactMediaMagnificationEntryId.length > 0
                ? _compactMediaMagnificationEntryId
                : item && item.isMediaPlayer ? item.dockEntryId : ""
        for (let i = 0; i < dockRepeater.count; ++i) {
            const candidate = dockRepeater.itemAt(i)
            if (!candidate || !candidate.isMediaPlayer) continue
            if (mediaWidgetIndex < 0) mediaWidgetIndex = i
            if (preferredMediaEntryId.length > 0
                    && candidate.dockEntryId === preferredMediaEntryId) {
                mediaWidgetIndex = i
                break
            }
        }
        const mediaWidget = mediaWidgetIndex >= 0
            ? dockRepeater.itemAt(mediaWidgetIndex) : null
        const rowPoint = dockRow.mapToItem(root, 0, 0)
        const panelPoint = dockPanel.mapToItem(root, 0, 0)
        const screen = DockView.screenGeometry
        const window = root.Window.window
        const hitResolution = Object.assign({}, _lastHitTestResolution)
        return {
            schemaVersion: 1,
            coordinateSpaces: {
                pointerRoot: "last QML pointer sample in dock-root logical coordinates; it is not refreshed by this snapshot",
                dockPanelMouse: "last stored primary/secondary pointer sample in dockPanel coordinates",
                rowGeometry: "dock-root logical coordinates",
                globalPointer: "unavailable through QtWayland QCursor; use the recorded wl_pointer surface-local sample"
            },
            pointer: {
                pointerMotionSerial: pointerMotionSerial,
                lastQmlPointerRoot: { x: _pointerRootX, y: _pointerRootY },
                dockPanelMouse: { x: dockPanel.mouseX, y: dockPanel.mouseY },
                pointerOnDock: _pointerOnDock,
                compositorPointerInsideDock: DockView.pointerInside,
                pointerFocusKnown: DockView.pointerFocusKnown,
                focusWindowObjectName: DockView.pointerFocusWindow
                    ? DockView.pointerFocusWindow.objectName : "",
                focusWindowType: DockView.pointerFocusWindow ? DockView.pointerFocusWindow.type : -1
            },
            dock: {
                edge: DockView.edge,
                isVertical: DockView.isVertical,
                screenGeometry: { x: screen.x, y: screen.y, width: screen.width, height: screen.height },
                devicePixelRatio: window ? window.devicePixelRatio : 1,
                surfaceLogicalGeometry: { x: root.x, y: root.y, width: root.width, height: root.height },
                panelGeometry: { x: panelPoint.x, y: panelPoint.y, width: dockPanel.width, height: dockPanel.height },
                rowGeometry: { x: rowPoint.x, y: rowPoint.y, width: dockRow.width, height: dockRow.height },
                rowCount: dockRepeater.count
            },
            hitTest: {
                lastProcessedResult: hitResolution,
                rawIndex: hitResolution.rawIndex === undefined ? -1 : hitResolution.rawIndex,
                resolvedIndex: hitResolution.resolvedIndex === undefined ? -1 : hitResolution.resolvedIndex,
                sampleWasRecomputed: false
            },
            magnification: {
                hoveredIndex: hoveredIndex,
                hoveredName: hoveredName,
                magnificationAnchor: hoveredIndex,
                compactMagnificationIndex: compactIndex,
                compactMagnificationEntryId: _compactMediaMagnificationEntryId,
                compactAnchorMatchesCurrentRow: !!item && compactIndex === observedIndex,
                zoomActive: _zoomActive,
                mouseInside: dockPanel.mouseInside,
                springTargetAmount: dockPanel.magnificationMode === 1
                    ? springZoom.targetAmount : (dockPanel.mouseInside ? 1 : 0),
                springAmount: dockPanel.magnificationMode === 1 ? springZoom.amount : 0,
                springCursor: dockPanel.zoomCursor,
                currentScale: item ? item.currentScale : 1,
                itemTargetScale: item ? item.zoomScale : 1,
                magnificationMode: dockPanel.magnificationMode
            },
            mediaPopup: {
                visible: !!media && media.diagnosticPopupVisible,
                state: media ? media.popupStateName(media.popupState) : "closed",
                hovered: !!media && media.popupHovered,
                pinned: !!media && media.popupPinned,
                dockHoverLease: !!media && media.dockHoverLease,
                mediaHoverGate: !!media && media.pointerOverDockWidget,
                popupHoldIndex: popupIndex,
                popupHoldEntryId: _mediaPopupHoldEntryId,
                mediaWidgetIndex: mediaWidgetIndex,
                mediaWidgetEntryId: mediaWidget ? mediaWidget.dockEntryId : "",
                mediaWidgetDisplayMode: DockSettings.mediaPlayerDisplayMode,
                compactWidgetGeometry: DockSettings.mediaPlayerDisplayMode === 0
                    && mediaWidget ? _compactMediaWidgetGeometry(mediaWidgetIndex) : null,
                mediaWidgetGeometry: mediaWidget
                    ? _compactMediaWidgetGeometry(mediaWidgetIndex) : null,
                mediaDelegateGeometry: mediaWidget
                    ? _dockItemHitGeometry(mediaWidget) : null,
                delegateGeometry: item ? _dockItemHitGeometry(item) : null
            },
            windowPreview: {
                visible: PreviewController.visible,
                parentIndex: PreviewController.parentIndex
            }
        }
    }

    function traceHitTestResolution(source, rawIndex, resolvedIndex, fallbackReason = "",
                                    procedure = "dock-item-geometry", candidateIndex = -1) {
        if (!DockView.mediaHoverDebugEnabled) return
        const target = dockPanel.magnificationMode === 1
            ? springZoom.targetAmount : (dockPanel.mouseInside ? 1 : 0)
        const signature = [rawIndex, resolvedIndex, hoveredIndex,
            _compactMediaMagnificationIndex, _zoomActive, dockPanel.mouseInside, target,
            fallbackReason, procedure, candidateIndex].join(":")
        if (signature === _lastHoverTraceHitSignature) return
        _lastHoverTraceHitSignature = signature
        if (_lastTracedCompactAnchor !== _compactMediaMagnificationIndex
                || _lastTracedCompactAnchorEntryId !== _compactMediaMagnificationEntryId) {
            const previousAnchor = _lastTracedCompactAnchor
            const previousEntryId = _lastTracedCompactAnchorEntryId
            _lastTracedCompactAnchor = _compactMediaMagnificationIndex
            _lastTracedCompactAnchorEntryId = _compactMediaMagnificationEntryId
            traceMagnificationState("compact-anchor-changed",
                _compactMediaMagnificationIndex >= 0 ? _compactMediaMagnificationIndex : previousAnchor,
                source, rawIndex, resolvedIndex, {
                    previousAnchor: previousAnchor,
                    previousEntryId: previousEntryId,
                    compactMagnificationIndex: _compactMediaMagnificationIndex,
                    compactMagnificationEntryId: _compactMediaMagnificationEntryId,
                    reason: fallbackReason || "standard-hit-test-resolution"
                })
        }
        traceMagnificationState("magnification-hit-test", resolvedIndex >= 0 ? resolvedIndex : hoveredIndex,
            source, rawIndex, resolvedIndex, {
                fallbackApplied: rawIndex < 0 && resolvedIndex >= 0,
                fallbackReason: fallbackReason,
                hitTestProcedure: procedure,
                candidateIndex: candidateIndex,
                candidateEntryId: candidateIndex >= 0 && candidateIndex < dockRepeater.count
                    ? dockRepeater.itemAt(candidateIndex).dockEntryId : "",
                candidateGeometry: candidateIndex >= 0 && candidateIndex < dockRepeater.count
                    ? _dockItemHitGeometry(dockRepeater.itemAt(candidateIndex)) : null,
                candidateWidgetGeometry: candidateIndex >= 0 && candidateIndex < dockRepeater.count
                    ? _compactMediaWidgetGeometry(candidateIndex) : null
            })
    }

    function tracePointerSample(source, entryEnvelope, force = false) {
        if (!DockView.mediaHoverDebugEnabled) return
        const now = DockView.monotonicNowMs()
        if (!force && now - _lastHoverTracePointerMs < 40) return
        _lastHoverTracePointerMs = now
        traceMagnificationState("pointer-sample", hoveredIndex, source, null, hoveredIndex, {
            entryEnvelope: entryEnvelope,
            pointerRoot: { x: _pointerRootX, y: _pointerRootY },
            pointerSourceMode: DockView.pointerSourceMode,
            pointerSampleSequence: DockView.pointerSampleSequence,
            pointerSampleSurfaceId: DockView.pointerSampleSurfaceId,
            pointerSampleSurfaceGeneration: DockView.pointerSampleSurfaceGeneration,
            pointerSamplePosition: DockView.pointerSamplePosition,
            hitTestResolution: _lastHitTestResolution
        })
    }

    Connections {
        target: DockView
        function onMediaHoverMarkerReceived(label) {
            root.recordHoverTraceMarker(label)
        }
    }

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
    // space trackPointer() takes. Not updated while context-menu hover is held.
    property real _pointerRootX: -1
    property real _pointerRootY: -1
    // Wayland samples are strictly ordered independently from wl_pointer's
    // enter/leave serials. Qt Quick remains responsible for interaction and
    // drag handling, but cannot supersede this sequence for hover/zoom.
    property double _lastWaylandPointerSampleSequence: 0
    // Changes only on real pointer input, not layout or hit-test updates.
    property int pointerMotionSerial: 0
    property int _perfPointerEnters: 0
    property int _perfPointerMoves: 0
    property int _perfPointerLeaves: 0
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
        // If compositor input arrived while the popup grab held hover, consume
        // that newer sample before falling back to the last accepted position.
        if (DockView.pointerSourceMode === 1 && processAuthoritativePointerSample())
            return
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

    // The tracker reports surface-local logical coordinates. Map them through
    // the Qt Quick scene into this root item's coordinates so panel offsets,
    // orientation and content insets are applied exactly once.
    function processAuthoritativePointerSample() {
        if (DockView.pointerSourceMode !== 1 || _hoverHeld
                || _dragPending || _dragActive)
            return false
        const sequence = DockView.pointerSampleSequence
        if (sequence <= _lastWaylandPointerSampleSequence)
            return false
        _lastWaylandPointerSampleSequence = sequence

        if (!DockView.pointerSampleValid) {
            if (_pointerOnDock)
                _pointerLeft("authoritative-pointer-sample-invalid")
            return true
        }

        const sample = DockView.pointerSamplePosition
        const mapped = root.mapFromItem(null, sample.x, sample.y)
        if (!Number.isFinite(mapped.x) || !Number.isFinite(mapped.y))
            return true

        _pointerRootX = mapped.x
        _pointerRootY = mapped.y
        if (keyboardNavigating) {
            keyboardNavigating = false
            DockVisibility.setKeyboardActive(false)
        }
        if (!_pointerOnDock) {
            _handleDockPointerEntered(mapped.x, mapped.y)
        } else {
            DockVisibility.setHovered(true)
            if (_hoverReconciling)
                _reconcileAt(mapped.x, mapped.y)
            else
                trackPointer(mapped.x, mapped.y, false, "wayland-pointer-sample")
            cancelPreviewHideIfPointerReturnedToOwner()
        }
        pointerMotionSerial++
        tracePointerSample("wayland-pointer-sample", false)
        return true
    }

    function cancelPreviewHideIfPointerReturnedToOwner() {
        if (!PreviewController.visible || hoveredIndex < 0
                || hoveredIndex >= dockRepeater.count)
            return false
        const item = dockRepeater.itemAt(hoveredIndex)
        if (!item || !PreviewController.parentEntryId
                || item.dockEntryId !== PreviewController.parentEntryId)
            return false
        PreviewController.cancelHide()
        return true
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

    Timer {
        id: performanceStateTimer
        interval: 5000
        repeat: true
        running: DockView.performanceDiagnosticsEnabled
        onTriggered: {
            console.info("[KDOCKW_PERF_QML] " + JSON.stringify({
                dockVisible: DockVisibility.dockVisible,
                dockSurface: [root.width, root.height],
                dockEdge: DockView.edge,
                dockRows: dockRepeater.count,
                pointerInside: DockView.pointerInside,
                pointerOnDock: root._pointerOnDock,
                pointerLocal: [root._pointerRootX, root._pointerRootY],
                pointerEvents: [root._perfPointerEnters,
                    root._perfPointerMoves, root._perfPointerLeaves],
                hoveredIndex: root.hoveredIndex,
                zoomActive: root._zoomActive,
                launcherPopupVisible: appLauncherPopup.visible,
                launcherPopupGeometry: [appLauncherPopup.x, appLauncherPopup.y,
                    appLauncherPopup.width, appLauncherPopup.height]
            }))
            root._perfPointerEnters = 0
            root._perfPointerMoves = 0
            root._perfPointerLeaves = 0
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
        if (!item) return "task"
        if (item.isBuiltInWidget) return "builtInWidget"
        return item.isFolderStack ? "folderStack" : "task"
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
        const sourceWidget = entryTypeAtDockIndex(fromDockIndex) === "builtInWidget"
        const targetWidget = entryTypeAtDockIndex(toDockIndex) === "builtInWidget"
        if ((sourceWidget || targetWidget) && sourcePinned && targetPinned) {
            return DockModel.moveDockEntry(sourceEntryId, targetEntryId)
        }
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
                if (item && item.isApplicationLauncher)
                    appLauncherPopup.openFor(item)
                else if (item && item.isTrash)
                    DockModel.trashState.open()
                else if (item && item.isFolderStack)
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
    // A media popup has an independent lifecycle marker; pointer coordinates
    // and magnification continue to follow dock items normally.
    readonly property bool _hoverHeld: _menuHeld || _hoverReconciling
    // Pointer on the dock as the dock tracks it. Replaces
    // dockMouseArea.containsMouse, which stays false after the fake leave.
    property bool _pointerOnDock: false
    // A detached media Popup.Window temporarily takes pointer ownership away
    // from the layer-shell dock. This marker keeps the dock visible and allows
    // hover re-hit-testing after dismissal; it is not a zoom anchor.
    property int _mediaPopupHoldIndex: -1
    property string _mediaPopupHoldEntryId: ""
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
        const sourceWidget = entryTypeAtDockIndex(root._dragSourceIndex) === "builtInWidget"
        const sourcePinned = isPinnedDockIndex(root._dragSourceIndex)
        if (DockView.isVertical) {
            let panelRelY = globalMousePos - dockPanel.y
            let items = []
            for (let i = 0; i < dockRepeater.count; i++) {
                let item = dockRepeater.itemAt(i)
                if (!item) continue
                if (item.isBuiltInWidget && !sourceWidget) continue
                if (sourceWidget && !isPinnedDockIndex(i)) continue
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
                if (item.isBuiltInWidget && !sourceWidget) continue
                if (sourceWidget && !isPinnedDockIndex(i)) continue
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

    // A drag may reorder only while the pointer remains inside the same
    // secondary-axis zone used by dock hit testing. Qt Quick keeps the press
    // grab after the pointer leaves the dock, so the event handler must reject
    // outside releases explicitly instead of choosing the nearest primary
    // axis item anyway.
    function pointerWithinDockDragDropArea(rootX, rootY) {
        const zoomExtension = DockSettings.iconSize * (DockSettings.maxZoomFactor - 1.0)
        if (DockView.isVertical) {
            const panelNear = dockPanel.x
            const panelFar = dockPanel.x + dockPanel.width
            return DockView.edge === 2
                ? rootX >= panelNear && rootX <= panelFar + zoomExtension
                : rootX >= panelNear - zoomExtension && rootX <= panelFar
        }

        const panelNear = dockPanel.y
        const panelFar = dockPanel.y + dockPanel.height
        return DockView.edge === 0
            ? rootY >= panelNear && rootY <= panelFar + zoomExtension
            : rootY >= panelNear - zoomExtension && rootY <= panelFar
    }

    function computeDragTargetIndex(rootX, rootY) {
        if (!pointerWithinDockDragDropArea(rootX, rootY)) return -1
        return computeDropIndex(DockView.isVertical ? rootY : rootX)
    }

    // A real button press delivered to the dock is a fresh positional sample.
    // On Wayland it can be the first input after the row changed under a
    // stationary pointer, while compositor motion samples correctly remain the
    // authority for continuous hover updates.
    function refreshHoverFromPointerPress(rootX, rootY) {
        if (_menuHeld || keyboardNavigating) return false
        _pointerRootX = rootX
        _pointerRootY = rootY
        if (_hoverReconciling)
            _reconcileAt(rootX, rootY)
        else if (!_pointerOnDock)
            _handleDockPointerEntered(rootX, rootY)
        else
            trackPointer(rootX, rootY, false, "dockMouseArea.onPressed")
        return true
    }

    // Compute which icon is under an external drop cursor (unscaled hit test).
    function computeExternalDropIndex(primaryPosition) {
        for (let i = 0; i < dockRepeater.count; i++) {
            let item = dockRepeater.itemAt(i)
            if (!item) continue
            // The Trash widget is the only built-in widget that takes file drops.
            if (item.isBuiltInWidget && !item.isTrash) continue
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
        if (!item || !item.dockEntryId)
            return

        // A hover Window Preview supersedes an unpinned Media Popup. Close the
        // latter through its own controller and resume by stable entry ID after
        // its real close event; pinned media remains independent.
        const media = unpinnedMediaPopupForHandoff()
        if (media) {
            _pendingPreviewHandoffEntryId = item.dockEntryId
            media.closeHoverPopupForPreviewHandoff()
            if (_pendingPreviewHandoffEntryId === item.dockEntryId
                    && !media.diagnosticPopupVisible && !media.popupOpenRequested)
                completePreviewAfterMediaPopupClose()
            return
        }
        _pendingPreviewHandoffEntryId = ""
        showPreviewForItemNow(index, item)
    }

    function unpinnedMediaPopupForHandoff() {
        for (let i = 0; i < dockRepeater.count; ++i) {
            const item = dockRepeater.itemAt(i)
            const media = item ? item.mediaPlayerWidget : null
            if (media && !media.popupPinned
                    && (media.diagnosticPopupVisible || media.popupOpenRequested))
                return media
        }
        return null
    }

    function completePreviewAfterMediaPopupClose() {
        const entryId = _pendingPreviewHandoffEntryId
        if (!entryId)
            return
        _pendingPreviewHandoffEntryId = ""
        const index = DockModel.dockPresentationModel.dockIndexForEntryId(entryId)
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        if (!item || item.dockEntryId !== entryId)
            return
        const current = hoveredIndex >= 0 && hoveredIndex < dockRepeater.count
            ? dockRepeater.itemAt(hoveredIndex) : null
        if (!keyboardNavigating && (!current || current.dockEntryId !== entryId))
            return
        showPreviewForItemNow(index, item)
    }

    function showPreviewForItemNow(index, item) {
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
        function onWindowGapChanged() { Qt.callLater(root.refreshVisiblePreviewAnchor) }
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
    function trackPointer(x, y, entryEnvelope = false, source = "trackPointer") {
        // The context menu holds hover and magnification. Media popup lifecycle
        // is independent: magnification always follows the actual dock pointer.
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
        if (entryEnvelope)
            tracePointerSample(source, true, true)
        updateHoveredItem(entryEnvelope, dockPanel.mouseX, dockPanel.mouseY, source)
    }

    // Shared by MouseArea.onEntered and QML tests so the real event ordering
    // (pointer ownership -> entry sample -> sync -> hit-test) is exercised.
    function _handleDockPointerEntered(x, y) {
        if (_menuHeld) return
        _pointerRootX = x
        _pointerRootY = y
        _pointerOnDock = true
        DockVisibility.setHovered(true)
        if (_hoverReconciling)
            _reconcileAt(x, y, true)
        else
            trackPointer(x, y, true, "_handleDockPointerEntered")
        cancelPreviewHideIfPointerReturnedToOwner()
    }

    function _dockItemHitGeometry(item) {
        if (!item) return null
        const a = item.mapToItem(root, 0, 0)
        const b = item.mapToItem(root, item.width, 0)
        const c = item.mapToItem(root, 0, item.height)
        const d = item.mapToItem(root, item.width, item.height)
        const left = Math.min(a.x, b.x, c.x, d.x)
        const top = Math.min(a.y, b.y, c.y, d.y)
        const right = Math.max(a.x, b.x, c.x, d.x)
        const bottom = Math.max(a.y, b.y, c.y, d.y)
        return { x: left, y: top, width: right - left, height: bottom - top,
            currentScale: item.currentScale, targetScale: item.zoomScale }
    }

    function _compactMediaWidgetGeometry(index) {
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        const widget = item ? item.mediaPlayerWidget : null
        if (!widget) return null
        const a = widget.mapToItem(root, 0, 0)
        const b = widget.mapToItem(root, widget.width, 0)
        const c = widget.mapToItem(root, 0, widget.height)
        const d = widget.mapToItem(root, widget.width, widget.height)
        const left = Math.min(a.x, b.x, c.x, d.x)
        const top = Math.min(a.y, b.y, c.y, d.y)
        const right = Math.max(a.x, b.x, c.x, d.x)
        const bottom = Math.max(a.y, b.y, c.y, d.y)
        return { x: left, y: top, width: right - left, height: bottom - top,
            visible: widget.visible }
    }

    function _dockIndexForEntryId(entryId) {
        if (!entryId) return -1
        for (let i = 0; i < dockRepeater.count; ++i) {
            const item = dockRepeater.itemAt(i)
            if (item && item.dockEntryId === entryId) return i
        }
        return -1
    }

    function _setCompactMagnificationAnchor(index) {
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        const isCompactMedia = item && item.isMediaPlayer
            && DockSettings.mediaPlayerDisplayMode === 0
        _compactMediaMagnificationIndex = isCompactMedia ? index : -1
        _compactMediaMagnificationEntryId = isCompactMedia ? item.dockEntryId : ""
    }

    function _currentCompactMagnificationAnchor() {
        if (DockSettings.mediaPlayerDisplayMode !== 0) return -1
        const index = _compactMediaMagnificationEntryId.length > 0
            ? _dockIndexForEntryId(_compactMediaMagnificationEntryId)
            : _compactMediaMagnificationIndex
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        if (!item || !item.isMediaPlayer) {
            _setCompactMagnificationAnchor(-1)
            return -1
        }
        _compactMediaMagnificationIndex = index
        _compactMediaMagnificationEntryId = item.dockEntryId
        return index
    }

    // The popup hold tracks popup lifecycle. Its entry ID is resolved against
    // the current delegate order; the held index alone never constitutes a hit.
    function compactMediaCandidateIndex() {
        if (DockSettings.mediaPlayerDisplayMode !== 0 || _mediaPopupHoldIndex < 0)
            return -1
        const index = _mediaPopupHoldEntryId.length > 0
            ? _dockIndexForEntryId(_mediaPopupHoldEntryId) : _mediaPopupHoldIndex
        if (index < 0 || index >= dockRepeater.count) return -1
        const item = dockRepeater.itemAt(index)
        if (!item || !item.isMediaPlayer
                || (_mediaPopupHoldEntryId.length > 0
                    && item.dockEntryId !== _mediaPopupHoldEntryId)
                || !item.mediaPlayerWidget || !item.mediaPlayerWidget.diagnosticPopupVisible)
            return -1
        return index
    }

    function compactMediaWidgetContainsPointer(index, sampleX, sampleY) {
        if (index < 0 || index >= dockRepeater.count) return false
        const item = dockRepeater.itemAt(index)
        const widget = item ? item.mediaPlayerWidget : null
        if (!widget || !widget.visible || widget.width <= 0 || widget.height <= 0) return false
        const rootPoint = DockView.isVertical
            ? dockPanel.mapToItem(root, sampleY, sampleX)
            : dockPanel.mapToItem(root, sampleX, sampleY)
        const localPoint = widget.mapFromItem(root, rootPoint.x, rootPoint.y)
        return localPoint.x >= 0 && localPoint.x <= widget.width
            && localPoint.y >= 0 && localPoint.y <= widget.height
    }

    // Resolve every pointer sample through this single dock-item geometry pass.
    // The established Parabolic and In-place calculations remain unchanged;
    // Compact retention is only considered after an ordinary item hit misses.
    function resolveDockItemHit(sampleX, sampleY, entryEnvelope = false, source = "hit-test") {
        let rawIndex = -1
        let bestDistance = Infinity
        let bestNormalizedDistance = Infinity
        const parabolic = dockPanel.zoomStyle !== 1
        const hysteresisFactor = 0.25
        const maxExtension = DockSettings.iconSize * (DockSettings.maxZoomFactor - 1.0)
        let rowNear = DockView.isVertical ? dockRow.x : dockRow.y
        let rowFar = rowNear + (DockView.isVertical ? dockRow.width : dockRow.height)
        if (DockView.edge === 0 || DockView.edge === 2)
            rowFar += maxExtension
        else
            rowNear -= maxExtension
        const outsideRowDepth = sampleY < rowNear || sampleY > rowFar

        if (parabolic) {
            let slot = -1
            let slotDistance = Infinity
            for (let i = 0; i < dockRepeater.count; ++i) {
                const item = dockRepeater.itemAt(i)
                if (!item) continue
                if (outsideRowDepth && item.isMediaPlayer
                        && DockSettings.mediaPlayerDisplayMode === 0)
                    continue
                const distance = Math.abs(sampleX - (item.itemCenterX + item.currentOffset))
                const hitScale = entryEnvelope && !outsideRowDepth
                    ? Math.max(item.currentScale, DockSettings.maxZoomFactor) : item.currentScale
                const halfPrimary = DockSettings.iconSize * hitScale / 2 + DockSettings.iconSpacing / 2
                if (distance <= halfPrimary && distance < slotDistance) {
                    slot = i
                    slotDistance = distance
                }
            }
            const slotItem = slot >= 0 ? dockRepeater.itemAt(slot) : null
            if (slotItem) {
                const hitScale = entryEnvelope && !outsideRowDepth
                    ? Math.max(slotItem.currentScale, DockSettings.maxZoomFactor) : slotItem.currentScale
                const span = _secondarySpan(slotItem, hitScale)
                if (sampleY >= span.near && sampleY <= span.far)
                    rawIndex = slot
            }
        } else {
            for (let i = 0; i < dockRepeater.count; ++i) {
                const item = dockRepeater.itemAt(i)
                if (!item) continue
                if (outsideRowDepth && item.isMediaPlayer
                        && DockSettings.mediaPlayerDisplayMode === 0)
                    continue
                const hitScale = entryEnvelope && !outsideRowDepth
                    ? Math.max(item.currentScale, DockSettings.maxZoomFactor) : item.currentScale
                const distance = Math.abs(sampleX - item.itemCenterX)
                const halfPrimary = ((DockView.isVertical ? item.height : item.width) * hitScale) / 2
                const normalizedDistance = distance / Math.max(0.001, halfPrimary)
                const sticky = !outsideRowDepth && i === hoveredIndex
                if (normalizedDistance >= (sticky ? 1.0 + hysteresisFactor : 1.0)) continue
                const span = _secondarySpan(item, hitScale)
                if (sampleY < span.near || sampleY > span.far) continue
                const score = sticky ? normalizedDistance * (1.0 - hysteresisFactor) : normalizedDistance
                if (score < bestNormalizedDistance) {
                    rawIndex = i
                    bestNormalizedDistance = score
                }
            }
        }

        if (rawIndex >= 0) {
            const item = dockRepeater.itemAt(rawIndex)
            const procedure = parabolic ? "parabolic-visible-slot" : "in-place-scaled-bounds"
            _lastHitTestResolution = {
                source: source, procedure: procedure, reason: "ordinary-item-geometry",
                rawIndex: rawIndex, resolvedIndex: rawIndex,
                candidateEntryId: item.dockEntryId, geometry: _dockItemHitGeometry(item)
            }
            return { rawIndex: rawIndex, resolvedIndex: rawIndex,
                reason: "ordinary-item-geometry", procedure: procedure, candidateIndex: rawIndex }
        }

        // Preserve the existing out-of-row actual-widget geometry and the
        // in-row in-motion envelope for the active stable-ID anchor.
        const activeIndex = _currentCompactMagnificationAnchor()
        if (activeIndex >= 0) {
            const item = dockRepeater.itemAt(activeIndex)
            if (outsideRowDepth
                    && compactMediaWidgetContainsPointer(activeIndex, sampleX, sampleY)) {
                _lastHitTestResolution = {
                    source: source, procedure: "dock-item-geometry",
                    reason: "active-compact-visible-geometry", rawIndex: -1,
                    resolvedIndex: activeIndex, candidateEntryId: item.dockEntryId,
                    geometry: _dockItemHitGeometry(item),
                    widgetGeometry: _compactMediaWidgetGeometry(activeIndex)
                }
                return { rawIndex: -1, resolvedIndex: activeIndex,
                    reason: "active-compact-visible-geometry",
                    procedure: "dock-item-geometry", candidateIndex: activeIndex,
                    releaseZoom: false }
            }
            const scale = DockSettings.maxZoomFactor
            const center = item.itemCenterX + item.currentOffset
            const halfPrimary = ((DockView.isVertical ? item.height : item.width) * scale) / 2
            const span = _secondarySpan(item, scale)
            if (!outsideRowDepth && Math.abs(sampleX - center) <= halfPrimary
                    && sampleY >= span.near && sampleY <= span.far) {
                _lastHitTestResolution = {
                    source: source, procedure: "dock-item-geometry",
                    reason: "active-compact-zoom-envelope", rawIndex: -1,
                    resolvedIndex: activeIndex, candidateEntryId: item.dockEntryId,
                    geometry: _dockItemHitGeometry(item)
                }
                return { rawIndex: -1, resolvedIndex: activeIndex,
                    reason: "active-compact-zoom-envelope",
                    procedure: "dock-item-geometry", candidateIndex: activeIndex }
            }
        }

        // A popup candidate may recover a lost anchor, but only a sample inside
        // the widget's current transformed rectangle can select it. Since this
        // follows the normal loop, any actual neighbor hit has priority.
        const popupCandidate = compactMediaCandidateIndex()
        if (popupCandidate >= 0 && compactMediaWidgetContainsPointer(popupCandidate, sampleX, sampleY)) {
            const item = dockRepeater.itemAt(popupCandidate)
            _lastHitTestResolution = {
                source: source, procedure: "dock-item-geometry",
                reason: "popup-compact-visible-geometry", rawIndex: -1,
                resolvedIndex: popupCandidate, candidateEntryId: item.dockEntryId,
                geometry: _dockItemHitGeometry(item)
            }
            return { rawIndex: -1, resolvedIndex: popupCandidate,
                reason: "popup-compact-visible-geometry",
                procedure: "dock-item-geometry", candidateIndex: popupCandidate }
        }

        const reason = outsideRowDepth ? "outside-row-depth"
            : popupCandidate >= 0 ? "popup-candidate-outside-visible-geometry"
            : activeIndex >= 0 ? "outside-active-compact-envelope" : "no-ordinary-hit"
        const candidateIndex = popupCandidate >= 0 ? popupCandidate : activeIndex
        _lastHitTestResolution = {
            source: source, procedure: "dock-item-geometry", reason: reason,
            rawIndex: -1, resolvedIndex: -1, candidateIndex: candidateIndex,
            candidateEntryId: candidateIndex >= 0 && candidateIndex < dockRepeater.count
                ? dockRepeater.itemAt(candidateIndex).dockEntryId : ""
        }
        return { rawIndex: -1, resolvedIndex: -1, reason: reason,
            procedure: "dock-item-geometry", candidateIndex: candidateIndex }
    }

    function updateHoveredItem(entryEnvelope = false,
                               sampleX = dockPanel.mouseX,
                               sampleY = dockPanel.mouseY,
                               source = "updateHoveredItem") {
        if (_hoverHeld) return
        if (sampleX < 0) {
            const previousAnchor = _compactMediaMagnificationIndex
            hoveredIndex = -1
            hoveredName = ""
            _zoomActive = false
            _setCompactMagnificationAnchor(-1)
            _lastHitTestResolution = { source: source, procedure: "none",
                reason: "sample-outside-dock-zone", rawIndex: -1, resolvedIndex: -1 }
            if (DockView.mediaHoverDebugEnabled)
                traceHitTestResolution(source, -1, -1,
                    previousAnchor >= 0 ? "sample-outside-dock-zone" : "sample-outside-dock-zone-no-anchor",
                    "none", compactMediaCandidateIndex())
            return
        }
        // Do not re-hover stale coordinates while another surface owns input.
        // A subsequent valid enter/motion sample always reaches the resolver.
        if (!_pointerOnDock) return

        const resolution = resolveDockItemHit(sampleX, sampleY, entryEnvelope, source)
        const index = resolution.resolvedIndex
        if (index >= 0) {
            _zoomActive = true
            _setCompactMagnificationAnchor(index)
            if (hoveredIndex !== index) {
                hoveredIndex = index
                hoveredName = dockRepeater.itemAt(index).displayName
                if (!externalDropArea.externalFileDragActive)
                    tooltipTimer.restart()
            }
        } else {
            _setCompactMagnificationAnchor(-1)
            hoveredIndex = -1
            hoveredName = ""
            if (resolution.releaseZoom === true || resolution.reason === "outside-row-depth")
                _zoomActive = false
            // Keep zoom active across the ordinary primary-axis gap hysteresis.
            // A true outside-zone sample above still releases it immediately.
        }
        if (DockView.mediaHoverDebugEnabled)
            traceHitTestResolution(source, resolution.rawIndex, index, resolution.reason,
                                   resolution.procedure, resolution.candidateIndex)
    }

    function _shouldRetainCompactMediaMagnificationOnSurfaceLeave(failures = null) {
        if (!failures) {
            const index = _currentCompactMagnificationAnchor()
            if (DockSettings.magnificationMode !== 1
                    || DockSettings.mediaPlayerDisplayMode !== 0
                    || _dragActive || !_pointerOnDock || !_zoomActive
                    || index < 0 || index >= dockRepeater.count
                    || hoveredIndex !== index
                    || !DockView.pointerInside || !DockView.pointerFocusKnown
                    || DockView.pointerFocusWindow !== root.Window.window
                    || (DockView.pointerSourceMode === 1 && !DockView.pointerSampleValid))
                return false
            const item = dockRepeater.itemAt(index)
            return !!item && item.isMediaPlayer
        }
        const rejected = []
        const index = _currentCompactMagnificationAnchor()
        if (DockSettings.magnificationMode !== 1) rejected.push("not-spring-mode")
        if (DockView.pointerSourceMode === 1 && !DockView.pointerSampleValid)
            rejected.push("authoritative-pointer-sample-not-current-dock-surface")
        if (DockSettings.mediaPlayerDisplayMode !== 0) rejected.push("not-compact-media-mode")
        if (_dragActive) rejected.push("drag-active")
        if (!_pointerOnDock) rejected.push("pointer-not-marked-on-dock")
        if (!_zoomActive) rejected.push("zoom-inactive")
        if (index < 0 || index >= dockRepeater.count) rejected.push("invalid-compact-anchor")
        if (hoveredIndex !== index) rejected.push("hovered-index-does-not-match-anchor")
        if (!DockView.pointerInside) rejected.push("compositor-pointer-outside-dock")
        if (!DockView.pointerFocusKnown) rejected.push("pointer-focus-unknown")
        if (DockView.pointerFocusWindow !== root.Window.window) rejected.push("focus-is-not-dock-surface")
        if (rejected.length === 0) {
            const item = dockRepeater.itemAt(index)
            if (!item || !item.isMediaPlayer) rejected.push("anchor-is-not-media-widget")
        }
        failures.push(...rejected)
        return rejected.length === 0
    }

    // Pointer left the dock: release zoom and hover unless the preview keeps
    // them (dock→preview transition), and end a drag as a drag-out.
    function _pointerLeft(source = "unspecified") {
        // Qt Quick can send a local MouseArea leave while the compositor still
        // reports the stationary pointer on the dock surface as the media
        // popup is being prepared. Preserve the Compact target through that
        // surface-local transition; real pointer movement or surface focus
        // leaving the dock will take the normal cleanup path below.
        const leaveGuardFailures = DockView.mediaHoverDebugEnabled ? [] : null
        const retainCompactTarget = _shouldRetainCompactMediaMagnificationOnSurfaceLeave(leaveGuardFailures)
        const mediaPopupHoldItem = _mediaPopupHoldIndex >= 0
            ? dockRepeater.itemAt(_mediaPopupHoldIndex) : null
        const mediaPopupHoldWidget = mediaPopupHoldItem ? mediaPopupHoldItem.mediaPlayerWidget : null
        if (DockView.mediaHoverDebugEnabled) {
            traceMagnificationState("compact-surface-leave-guard", _compactMediaMagnificationIndex,
                "_pointerLeft", hoveredIndex, hoveredIndex, {
                    caller: source,
                    retained: retainCompactTarget,
                    guardFailures: leaveGuardFailures,
                    dockMouseAreaContainsMouse: dockMouseArea.containsMouse,
                    pointerOnDock: _pointerOnDock,
                    pointerInside: DockView.pointerInside,
                    pointerFocusKnown: DockView.pointerFocusKnown,
                    pointerFocusIsDock: DockView.pointerFocusWindow === root.Window.window,
                    pointerFocusWindowObjectName: DockView.pointerFocusWindow
                        ? DockView.pointerFocusWindow.objectName : "",
                    panelPointer: { x: dockPanel.mouseX, y: dockPanel.mouseY },
                    mouseInside: dockPanel.mouseInside,
                    hoveredIndex: hoveredIndex,
                    compactMagnificationIndex: _compactMediaMagnificationIndex,
                    activeHit: _lastHitTestResolution,
                    zoomActive: _zoomActive,
                    springTargetAmount: dockPanel.magnificationMode === 1
                        ? springZoom.targetAmount : (dockPanel.mouseInside ? 1 : 0),
                    springAmount: dockPanel.magnificationMode === 1 ? springZoom.amount : 0,
                    mediaPopupHoldIndex: _mediaPopupHoldIndex,
                    mediaPopupHoldEntryId: _mediaPopupHoldEntryId,
                    popupVisible: !!mediaPopupHoldWidget && mediaPopupHoldWidget.diagnosticPopupVisible,
                    popupState: mediaPopupHoldWidget
                        ? mediaPopupHoldWidget.popupStateName(mediaPopupHoldWidget.popupState) : "closed",
                    popupHovered: !!mediaPopupHoldWidget && mediaPopupHoldWidget.popupHovered,
                    popupPinned: !!mediaPopupHoldWidget && mediaPopupHoldWidget.popupPinned,
                    popupWindowObjectName: mediaPopupHoldWidget && mediaPopupHoldWidget.popupWindow
                        ? mediaPopupHoldWidget.popupWindow.objectName : "",
                    compactGeometry: _compactMediaMagnificationIndex >= 0
                        && _compactMediaMagnificationIndex < dockRepeater.count
                        ? _dockItemHitGeometry(dockRepeater.itemAt(_compactMediaMagnificationIndex))
                        : null
                })
        }
        if (retainCompactTarget) {
            DockView.traceMediaHover("compact-media-surface-leave-retained", {
                index: _compactMediaMagnificationIndex,
                hoveredIndex: hoveredIndex,
                pointerMotionSerial: pointerMotionSerial,
                springTargetAmount: dockPanel && dockPanel.magnificationMode === 1
                    ? springZoom.targetAmount : 0,
                pointerInside: DockView.pointerInside,
                focusIsDock: DockView.pointerFocusWindow === root.Window.window
            })
            return
        }
        const mediaPopupKeepsDockVisible = _mediaPopupHoldIndex >= 0
        _pointerOnDock = false
        _hoverReconciling = false
        const anchorBeforeLeave = _compactMediaMagnificationIndex
        const anchorEntryIdBeforeLeave = _compactMediaMagnificationEntryId
        _setCompactMagnificationAnchor(-1)
        PreviewController.clearDismissedTask()
        if (mediaPopupKeepsDockVisible) {
            // Keep the dock visible for the independent media popup lifecycle,
            // while allowing the spring to follow the pointer off the dock.
            DockVisibility.setHovered(true)
        }
        // Ordinary Window Preview retains its established dock→preview anchor.
        // A media popup does not retain the Compact spring target.
        if (!PreviewController.visible || mediaPopupKeepsDockVisible) {
            dockPanel.mouseX = -1
            dockPanel.mouseY = -1
            _zoomActive = false
        }
        hoveredIndex = -1
        hoveredName = ""
        if (anchorBeforeLeave >= 0) {
            _lastTracedCompactAnchor = -1
            _lastTracedCompactAnchorEntryId = ""
            traceMagnificationState("compact-anchor-cleared", anchorBeforeLeave,
                "_pointerLeft", anchorBeforeLeave, -1, {
                    clearReason: "real-surface-leave",
                    compactMagnificationEntryId: anchorEntryIdBeforeLeave
                })
        }
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
        if (!PreviewController.visible && !mediaPopupKeepsDockVisible) {
            DockVisibility.setHovered(false)
        }
    }

    function holdMediaPopup(index) {
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        if (item) {
            _mediaPopupHoldIndex = index
            _mediaPopupHoldEntryId = item.isMediaPlayer ? item.dockEntryId : ""
            if (DockView.mediaHoverDebugEnabled)
                traceMagnificationState("media-popup-hit-test-candidate-held", index,
                    "holdMediaPopup", hoveredIndex, index, {
                        popupHoldIndex: index,
                        popupHoldEntryId: _mediaPopupHoldEntryId,
                        candidateGeometry: _dockItemHitGeometry(item),
                        candidateWidgetGeometry: item.isMediaPlayer
                            ? _compactMediaWidgetGeometry(index) : null
                    })
        }
    }

    function mediaPopupGeometrySnapshot(index) {
        function geometryFor(item) {
            if (!item) return null
            const point = item.mapToItem(null, 0, 0)
            return { x: point.x, y: point.y, width: item.width, height: item.height,
                scale: item.currentScale, targetScale: item.zoomScale }
        }
        const current = dockRepeater.itemAt(index)
        const previous = dockRepeater.itemAt(index - 1)
        const next = dockRepeater.itemAt(index + 1)
        return {
            pointerInside: DockView.pointerInside,
            pointerRoot: { x: _pointerRootX, y: _pointerRootY },
            pointerPanel: dockPanel ? { x: dockPanel.mouseX, y: dockPanel.mouseY } : null,
            hoveredIndex: hoveredIndex,
            mediaPopupHoldIndex: _mediaPopupHoldIndex,
            mediaPopupHoldEntryId: _mediaPopupHoldEntryId,
            compactMagnificationIndex: _compactMediaMagnificationIndex,
            compactMagnificationEntryId: _compactMediaMagnificationEntryId,
            zoomActive: _zoomActive,
            springFactor: dockPanel ? dockPanel.zoomAmount : 0,
            springTargetAmount: dockPanel && dockPanel.magnificationMode === 1
                ? springZoom.targetAmount : (dockPanel && dockPanel.mouseInside ? 1 : 0),
            springCursor: dockPanel ? dockPanel.zoomCursor : 0,
            previewVisible: PreviewController.visible,
            current: geometryFor(current),
            previous: geometryFor(previous),
            next: geometryFor(next)
        }
    }

    function releaseMediaPopup(index) {
        const item = index >= 0 && index < dockRepeater.count ? dockRepeater.itemAt(index) : null
        const releasingId = item ? item.dockEntryId : ""
        if (_mediaPopupHoldEntryId.length > 0) {
            if (releasingId.length > 0 && releasingId !== _mediaPopupHoldEntryId)
                return
            if (releasingId.length === 0 && _mediaPopupHoldIndex !== index)
                return
        } else if (_mediaPopupHoldIndex !== index) {
            return
        }
        _mediaPopupHoldIndex = -1
        const releasedEntryId = _mediaPopupHoldEntryId
        _mediaPopupHoldEntryId = ""
        if (DockView.mediaHoverDebugEnabled)
            traceMagnificationState("media-popup-hit-test-candidate-released", index,
                "releaseMediaPopup", hoveredIndex, -1, {
                    releasedEntryId: releasedEntryId,
                    popupHoldIndex: -1,
                    popupHoldEntryId: ""
                })
        Qt.callLater(() => {
            if (!DockView.pointerInside) {
                root._pointerLeft("releaseMediaPopup.pointerOutside")
                return
            }
            DockVisibility.setHovered(true)
            if (DockView.pointerSourceMode === 1) {
                root.processAuthoritativePointerSample()
            } else {
                root._pointerOnDock = true
                if (!root._menuHeld && !root.keyboardNavigating
                        && root._pointerRootX >= 0 && root._pointerRootY >= 0)
                    root.trackPointer(root._pointerRootX, root._pointerRootY)
            }
            root.cancelPreviewHideIfPointerReturnedToOwner()
        })
    }

    // Popup.Window can take pointer focus from the layer-shell surface. When
    // it closes, re-evaluate hover only if KWin's Wayland focus tracker says
    // the pointer is actually back over the dock. Do not infer hover from the
    // popup's old anchor when the pointer was dismissed elsewhere.
    function folderStackPopupClosed() {
        Qt.callLater(() => {
            if (!DockView.pointerInside) {
                root._pointerLeft("folderStackPopupClosed.pointerOutside")
                return
            }
            DockVisibility.setHovered(true)
            if (DockView.pointerSourceMode === 1) {
                root.processAuthoritativePointerSample()
            } else {
                root._pointerOnDock = true
                if (!root._menuHeld && !root.keyboardNavigating
                        && root._pointerRootX >= 0 && root._pointerRootY >= 0)
                    root.trackPointer(root._pointerRootX, root._pointerRootY)
            }
            root.cancelPreviewHideIfPointerReturnedToOwner()
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
        function onManageWidgetsRequested() { widgetManager.open() }
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
                root._pointerLeft("DockContextMenu.onOpenChanged")
            }
        }
    }

    // After a popup grab Qt's hover is stale (it thinks the pointer is
    // outside), so a real compositor leave reaches no onExited; end hover here.
    Connections {
        target: DockView
        function onBackgroundStyleTypeChanged() { dockPanel.reportPanelRect() }
        function onBackgroundColorChanged() { dockPanel.reportPanelRect() }
        function onPointerSourceModeChanged() {
            if (DockView.pointerSourceMode === 1) {
                root._pointerOnDock = false
                root._pointerRootX = -1
                root._pointerRootY = -1
                root._lastWaylandPointerSampleSequence = 0
                if (root._zoomActive || root.hoveredIndex >= 0)
                    root._pointerLeft("pointer-source-changed-to-wayland")
                root.processAuthoritativePointerSample()
            } else {
                root._lastWaylandPointerSampleSequence = DockView.pointerSampleSequence
                if (root._pointerOnDock)
                    root._pointerLeft("pointer-source-changed-to-qt-quick")
            }
        }
        function onPointerSampleChanged() { root.processAuthoritativePointerSample() }
        function onPointerInsideChanged() {
            if (DockView.pointerSourceMode === 0
                    && !DockView.pointerInside && !root._menuHeld && root._pointerOnDock
                    && !dockMouseArea.containsMouse)
                root._pointerLeft("DockView.onPointerInsideChanged")
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
            if (DockView.performanceDiagnosticsEnabled)
                root._perfPointerEnters++
            if (DockView.pointerSourceMode === 0)
                root._handleDockPointerEntered(mouseX, mouseY)
        }
        onExited: {
            if (root._menuHeld || DockView.pointerSourceMode === 1) return
            if (DockView.performanceDiagnosticsEnabled)
                root._perfPointerLeaves++
            root._pointerLeft("dockMouseArea.onExited")
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
            if (!root._menuHeld && DockView.pointerSourceMode === 0) {
                root._pointerRootX = mouse.x
                root._pointerRootY = mouse.y
            }
            if (DockView.pointerSourceMode === 0) {
                if (root._hoverReconciling && !root._menuHeld)
                    root._reconcileAt(mouse.x, mouse.y)
                else if (!root.keyboardNavigating)
                    root.trackPointer(mouse.x, mouse.y, false, "dockMouseArea.onPositionChanged")
            } else if (mouse.button === Qt.LeftButton) {
                root.refreshHoverFromPointerPress(mouse.x, mouse.y)
            }
            if (mouse.button === Qt.LeftButton && root.hoveredIndex >= 0) {
                const item = dockRepeater.itemAt(root.hoveredIndex)
                if (item) {
                    root._dragStartX = mouse.x
                    root._dragStartY = mouse.y
                    root._dragStartEntryId = root.dockEntryIdAt(root.hoveredIndex)
                    dragHoldTimer.restart()
                }
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
            root.processAuthoritativePointerSample()
        }

        onCanceled: {
            root.logDockOrderTrace("pointer-cancel", root._dragSourceEntryId, root._dragTargetEntryId)
            root.clearDragState()
            root.processAuthoritativePointerSample()
        }

        // Click handling: uses hoveredIndex from scaled hit testing
        // so clicks work correctly on zoomed icons
        onClicked: function(mouse) {
            // Suppress clicks for the entire held-button cycle after a drag.
            if (root._dragWasActive) return
            if (mouse.button === Qt.RightButton) {
                const item = root.hoveredIndex >= 0 ? dockRepeater.itemAt(root.hoveredIndex) : null
                if (item && item.isTrash) {
                    DockContextMenu.showForTrash()
                    return
                }
                if (!item || item.isBuiltInWidget) {
                    DockContextMenu.showForDock()
                    return
                }
            }
            if (root.hoveredIndex < 0) return
            if (mouse.button === Qt.LeftButton) {
                let item = dockRepeater.itemAt(root.hoveredIndex)
                if (item && item.isApplicationLauncher) {
                    appLauncherPopup.openFor(item)
                    return
                }
                if (item && item.isFolderStack) {
                    item.openFolderStack()
                    return
                }
                if (item && item.isMediaPlayer) {
                    item.openMediaPlayerPopup()
                    return
                }
                if (item && item.isTrash) {
                    DockModel.trashState.open()
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
            if (DockView.performanceDiagnosticsEnabled)
                root._perfPointerMoves++
            if (DockView.pointerSourceMode === 0) {
                root._pointerOnDock = true
                root._pointerRootX = mouse.x
                root._pointerRootY = mouse.y
            }

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
                root._dragTargetIndex = root.computeDragTargetIndex(mouse.x, mouse.y)
                const targetId = root._dragTargetIndex >= 0
                    ? root.dockEntryIdAt(root._dragTargetIndex) : ""
                if (targetId !== root._dragTargetEntryId) {
                    root._dragTargetEntryId = targetId
                    root.logDockOrderTrace("target-change", root._dragSourceEntryId, targetId)
                }
                return  // Skip normal zoom handling during drag
            }

            // Qt Quick continues to own pointer grabs and the complete click
            // and drag path, but stale/synthetic motion must not race the
            // compositor samples for hover or magnification.
            if (DockView.pointerSourceMode === 1)
                return

            if (root._hoverReconciling)
                root._reconcileAt(mouse.x, mouse.y)
            else
                root.trackPointer(mouse.x, mouse.y)
            // Notify composite widgets after the authoritative dock hit-test
            // has consumed this real motion sample.
            root.pointerMotionSerial++
            root.tracePointerSample("dockMouseArea.onPositionChanged", false)
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
        property real lightX: ShadowVector.lightX(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
        property real lightY: ShadowVector.lightY(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
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
            updateSpringTarget("DockPanel.Component.onCompleted")
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

        function updateSpringTarget(source = "updateSpringTarget") {
            if (magnificationMode !== 1) return
            const previousTarget = springZoom.targetAmount
            if (root._dragActive) {
                springZoom.synchronize(zoomCursor, 0)
                if (DockView.mediaHoverDebugEnabled && previousTarget !== springZoom.targetAmount)
                    root.traceMagnificationState("spring-target-change", root.hoveredIndex,
                        source, root.hoveredIndex, root.hoveredIndex, {
                            previousTargetAmount: previousTarget,
                            springTargetAmount: springZoom.targetAmount,
                            cause: "drag-synchronize"
                        })
                return
            }
            springZoom.setTarget(zoomCursor, mouseInside ? 1.0 : 0.0,
                DockSettings.springStiffness, DockSettings.springDamping,
                DockSettings.springSpeed, 0,
                DockView.isVertical ? root.height : root.width)
            if (DockView.mediaHoverDebugEnabled && previousTarget !== springZoom.targetAmount)
                root.traceMagnificationState("spring-target-change", root.hoveredIndex,
                    source, root.hoveredIndex, root.hoveredIndex, {
                        previousTargetAmount: previousTarget,
                        springTargetAmount: springZoom.targetAmount,
                        cause: source
                    })
        }
        onZoomCursorChanged: updateSpringTarget("zoom-cursor-changed")
        onMouseInsideChanged: updateSpringTarget("mouse-inside-changed")
        onMagnificationModeChanged: {
            if (magnificationMode === 1) {
                // Start from the visible Classic amount when changing modes,
                // so the live dock does not snap to rest before the spring
                // takes over.
                springZoom.synchronize(zoomCursor, classicZoomAmount)
                updateSpringTarget("magnification-mode-changed")
            } else {
                springZoom.synchronize(zoomCursor, 0)
            }
        }
        Connections {
            target: DockSettings
            function onSpringStiffnessChanged() { dockPanel.updateSpringTarget("spring-stiffness-changed") }
            function onSpringDampingChanged() { dockPanel.updateSpringTarget("spring-damping-changed") }
            function onSpringSpeedChanged() { dockPanel.updateSpringTarget("spring-speed-changed") }
        }
        Connections {
            target: root
            function on_DragActiveChanged() { dockPanel.updateSpringTarget("drag-active-changed") }
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
        readonly property var zoomLayout: DockView.zoomLayoutForItems(
            DockModel.dockPresentationModel.zoomLayoutSpecs(DockSettings.iconSize), _restStart,
            DockSettings.iconSpacing,
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
            updateSpringTarget("DockPanel.onWidthChanged")
            reportPanelRect()
            root.scheduleDelegateGeometryRefresh()
        }
        onHeightChanged: {
            updateSpringTarget("DockPanel.onHeightChanged")
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
                    zoomScale: isBuiltInWidget && !isApplicationLauncher && !isTrash
                            && !(isMediaPlayer && DockSettings.mediaPlayerDisplayMode === 0)
                        ? 1.0 : (dockPanel.zoomLayout.scales?.[index] ?? 1.0)
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
                    onApplicationLauncherRequested: appLauncherPopup.openFor(taskDelegate)


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
        DockSeparator {
            id: taskZonesSeparator
            objectName: "taskZonesSeparator"
            z: -0.5
            readonly property int boundary: root.taskZoneBoundary
            readonly property bool hasBoundary: boundary >= 0
            readonly property var pinnedItem: root.taskZoneSeparatorItems.pinned
            readonly property var runningItem: root.taskZoneSeparatorItems.running
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
            readonly property real secondaryCenter: root.taskZoneSeparatorSecondaryCenter
            readonly property real thickness: root.taskZoneSeparatorThickness
            readonly property real length: Math.min(DockSettings.iconSize, Kirigami.Units.gridUnit * 2)
            visible: hasBoundary && pinnedItem !== null && runningItem !== null
            verticalDock: DockView.isVertical
            lineLength: length
            lineThickness: thickness
            primaryPosition: primaryCenter
            crossAxisPosition: secondaryCenter
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

                // Files, folders and .desktop files dropped on the Trash go to the
                // trash; they are never pinned. Plasma task drags carry no files.
                if (targetItem && targetItem.isTrash) {
                    const isTaskDrag = drop.formats.indexOf("text/x-orgkdeplasmataskmanager_taskurl") >= 0
                    if (!drop.hasUrls || isTaskDrag) {
                        drop.accepted = false
                        dropTargetIndex = -1
                        return
                    }
                    DockModel.trashState.moveToTrash(drop.urls)
                    drop.accepted = true
                    dropTargetIndex = -1
                    return
                }

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
            if (PreviewController.visible && root.hoveredIndex >= 0)
                root.beginHoverTraceInteraction("window-preview", root.hoveredIndex,
                    "PreviewController.onVisibleChanged")
            DockView.traceMediaHover("window-preview-visibility-changed", {
                scenarioId: root._hoverTraceScenarioId,
                interactionId: root._hoverTraceInteractionId,
                interactionKind: root._hoverTraceInteractionKind,
                previousVisible: !PreviewController.visible,
                visible: PreviewController.visible,
                hoveredIndex: root.hoveredIndex,
                pointerOnDock: root._pointerOnDock,
                pointerInside: DockView.pointerInside,
                pointerFocusIsDock: DockView.pointerFocusWindow === root.Window.window,
                mouseX: dockPanel.mouseX,
                mouseY: dockPanel.mouseY,
                mouseInside: dockPanel.mouseInside,
                zoomActive: root._zoomActive,
                springTargetAmount: dockPanel.magnificationMode === 1
                    ? springZoom.targetAmount : (dockPanel.mouseInside ? 1 : 0),
                springAmount: dockPanel.magnificationMode === 1 ? springZoom.amount : 0,
                springCursor: dockPanel.zoomCursor
            })
            if (DockView.mediaHoverDebugEnabled)
                root.traceMagnificationState("window-preview-magnification-state",
                    root.hoveredIndex, "PreviewController.onVisibleChanged",
                    root.hoveredIndex, root.hoveredIndex, {
                        previewVisible: PreviewController.visible
                    })
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

    Connections {
        target: DockView
        function onMediaHoverMarkerReceived(label) {
            root.recordHoverTraceMarker(label)
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
        shadow.xOffset: -ShadowVector.lightX(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
            * DockSettings.shadowElevation / Math.max(1, DockSettings.shadowLightZ)
        shadow.yOffset: -ShadowVector.lightY(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
            * DockSettings.shadowElevation / Math.max(1, DockSettings.shadowLightZ)
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

    ApplicationLauncherPopup {
        id: appLauncherPopup
        dockRoot: root
    }

    // Diagnostic-only, opt-in route for opening the real launcher popup on a
    // live Wayland surface without synthesizing keyboard or pointer input.
    Timer {
        id: launcherDiagnosticOpenTimer
        interval: 1200
        repeat: true
        running: typeof DockView.launcherDiagnosticPage === "string"
            && DockView.launcherDiagnosticPage.length > 0
        onTriggered: {
            if (!DockModel.applicationCatalog.ready) {
                DockModel.applicationCatalog.ensureLoaded()
                return
            }
            if (dockRepeater.count < 1) return
            const route = DockView.launcherDiagnosticPage
            const style = route.startsWith("start-") ? "start"
                : route.startsWith("hierarchical-") ? "hierarchical" : "launchpad"
            DockModel.applicationLauncherState.style = style
            appLauncherPopup.openFor(dockRepeater.itemAt(0))
            stop()
        }
    }

    QQC2.Dialog {
        id: widgetManager
        objectName: "builtInWidgetManager"
        title: i18n("Manage Dock Widgets")
        modal: false
        popupType: QQC2.Popup.Window
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        standardButtons: QQC2.Dialog.Close
        readonly property bool showsEmptyState: DockModel.dockEntriesModel.count === 0
        readonly property bool hasApplicationLauncher: DockModel.dockEntriesModel.hasApplicationLauncher
        readonly property bool hasMediaPlayer: DockModel.dockEntriesModel.hasMediaPlayer
        readonly property bool hasTrash: DockModel.dockEntriesModel.hasTrash
        readonly property real screenWidth: DockView.screenGeometry.width > 0
            ? DockView.screenGeometry.width : root.width
        readonly property real screenHeight: DockView.screenGeometry.height > 0
            ? DockView.screenGeometry.height : root.height
        readonly property real usableScreenWidth: Math.max(1,
            screenWidth - Kirigami.Units.largeSpacing * 4)
        readonly property real usableScreenHeight: Math.max(1,
            screenHeight - Kirigami.Units.largeSpacing * 4)
        readonly property real preferredManagerWidth: Math.min(720, usableScreenWidth)
        readonly property real minimumManagerWidth: Math.min(520, usableScreenWidth)
        width: Math.max(minimumManagerWidth, preferredManagerWidth)
        height: Math.min(usableScreenHeight, implicitHeight)
        padding: Kirigami.Units.largeSpacing

        contentItem: QQC2.ScrollView {
            id: widgetManagerScroll
            objectName: "widgetManagerScroll"
            implicitWidth: Math.max(1, widgetManager.width - widgetManager.leftPadding - widgetManager.rightPadding)
            implicitHeight: Math.min(widgetManagerContent.implicitHeight,
                                     widgetManager.usableScreenHeight * 0.78)
            contentWidth: availableWidth
            clip: true
            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ColumnLayout {
                id: widgetManagerContent
                width: widgetManagerScroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18n("Add, arrange, and configure the items shown in your dock.")
                }

                Flow {
                    objectName: "widgetManagerAddActions"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Button {
                        text: i18n("Add separator")
                        icon.name: "insert-horizontal-rule"
                        onClicked: DockModel.dockEntriesModel.appendSeparator("center")
                    }
                    QQC2.Button {
                        objectName: "addMediaPlayerWidgetButton"
                        text: widgetManager.hasMediaPlayer
                            ? i18n("Media player already added") : i18n("Add Media Player")
                        icon.name: "audio-x-generic"
                        enabled: !widgetManager.hasMediaPlayer
                        Accessible.description: widgetManager.hasMediaPlayer
                            ? i18n("The dock already has a media player widget.")
                            : i18n("Add the single media player widget for all MPRIS sources.")
                        onClicked: DockModel.dockEntriesModel.appendMediaPlayer("end")
                    }
                    QQC2.Button {
                        text: i18n("Add spacer")
                        icon.name: "go-next-view-page"
                        onClicked: DockModel.dockEntriesModel.appendSpacer(24, "center")
                    }
                    QQC2.Button {
                        objectName: "addApplicationLauncherButton"
                        text: widgetManager.hasApplicationLauncher
                            ? i18n("Application menu already added") : i18n("Add Application Menu")
                        icon.name: "applications-all-symbolic"
                        enabled: !widgetManager.hasApplicationLauncher
                        Accessible.description: widgetManager.hasApplicationLauncher
                            ? i18n("The dock already has an Application Launcher.")
                            : i18n("Add an application menu to the dock.")
                        onClicked: DockModel.dockEntriesModel.appendApplicationLauncher("center")
                    }
                    QQC2.Button {
                        objectName: "addTrashWidgetButton"
                        text: widgetManager.hasTrash ? i18n("Trash already added") : i18n("Add Trash")
                        icon.name: "user-trash"
                        enabled: !widgetManager.hasTrash
                        Accessible.description: widgetManager.hasTrash
                            ? i18n("The dock already has a Trash widget.")
                            : i18n("Add a Trash widget that shows when the trash is full and takes dropped files.")
                        onClicked: DockModel.dockEntriesModel.appendTrash("end")
                    }
                }

                QQC2.Label {
                    objectName: "applicationLauncherLimitNotice"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: widgetManager.hasApplicationLauncher
                    text: i18n("Only one Application Launcher is supported because its style and pinned applications are shared. Remove extra entries manually if this dock already has several.")
                }
                QQC2.Label {
                    objectName: "mediaPlayerLimitNotice"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: widgetManager.hasMediaPlayer
                    text: i18n("One media player widget serves all available MPRIS sources. Configure its display mode in Settings → Media Player.")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("Application Launcher style")
                        font.weight: Font.DemiBold
                    }
                    QQC2.ComboBox {
                        objectName: "widgetManagerLauncherStyle"
                        Layout.fillWidth: true
                        model: [i18n("macOS Launchpad"), i18n("Windows Start"), i18n("KDE Hierarchical")]
                        currentIndex: DockModel.applicationLauncherState.style === "start" ? 1
                            : DockModel.applicationLauncherState.style === "hierarchical" ? 2 : 0
                        onActivated: index => DockModel.applicationLauncherState.style =
                            ["launchpad", "start", "hierarchical"][index]
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18n("Widgets follow the dock order. Drag and drop remains reserved for applications and folders.")
                }

                Repeater {
                    id: widgetEntries
                    objectName: "widgetManagerEntries"
                    model: DockModel.dockEntriesModel
                    delegate: QQC2.Frame {
                        required property int index
                        required property string entryType
                        required property string entryId
                        required property string widgetKind
                        required property int widgetSize
                        required property bool widgetVisible
                        required property string placementSlot
                        Layout.fillWidth: true
                        visible: entryType === "builtInWidget"
                        padding: Kirigami.Units.smallSpacing
                        background: Rectangle {
                            color: Kirigami.Theme.backgroundColor
                            border.color: Kirigami.Theme.disabledTextColor
                            radius: Kirigami.Units.smallSpacing
                        }

                        ColumnLayout {
                            width: parent.width
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: widgetKind === "spacer" ? i18n("Spacer")
                                        : widgetKind === "applicationLauncher" ? i18n("Application Launcher")
                                        : widgetKind === "mediaPlayer" ? i18n("Media Player")
                                        : widgetKind === "trash" ? i18n("Trash") : i18n("Separator")
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                QQC2.Label {
                                    objectName: "widgetManagerOrderLabel"
                                    text: i18n("Order")
                                }
                                QQC2.ToolButton {
                                    text: "↑"
                                    enabled: index > 0
                                    Accessible.name: i18n("Move up")
                                    onClicked: DockModel.dockEntriesModel.moveEntry(index, index - 1)
                                }
                                QQC2.ToolButton {
                                    text: "↓"
                                    enabled: index + 1 < DockModel.dockEntriesModel.count
                                    Accessible.name: i18n("Move down")
                                    onClicked: DockModel.dockEntriesModel.moveEntry(index, index + 1)
                                }
                                Item { Layout.fillWidth: true }
                                QQC2.ToolButton {
                                    objectName: "widgetManagerRemove"
                                    icon.name: "edit-delete"
                                    text: i18n("Remove")
                                    Accessible.name: i18n("Remove %1", widgetKind === "spacer"
                                        ? i18n("Spacer") : widgetKind === "applicationLauncher"
                                        ? i18n("Application Launcher") : widgetKind === "trash"
                                        ? i18n("Trash") : i18n("Separator"))
                                    onClicked: DockModel.dockEntriesModel.removeBuiltInWidget(entryId)
                                }
                                }

                            GridLayout {
                                    id: widgetControls
                                objectName: "widgetManagerControls"
                                    Layout.fillWidth: true
                                    columns: width >= 520 ? 2 : 1
                                    columnSpacing: Kirigami.Units.largeSpacing
                                    rowSpacing: Kirigami.Units.smallSpacing

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing / 2
                                        QQC2.Label { text: i18n("Position along dock") }
                                        QQC2.ComboBox {
                                            objectName: "widgetManagerSlot"
                                            Layout.fillWidth: true
                                            model: [i18n("Start"), i18n("Center"), i18n("End")]
                                            currentIndex: placementSlot === "start" ? 0 : placementSlot === "end" ? 2 : 1
                                            onActivated: DockModel.dockEntriesModel.setBuiltInWidgetSlot(
                                                entryId, ["start", "center", "end"][currentIndex])
                                        }
                                    }
                                    ColumnLayout {
                                        visible: widgetKind !== "applicationLauncher"
                                        && widgetKind !== "mediaPlayer" && widgetKind !== "trash"
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing / 2
                                        QQC2.Label { text: i18n("Size") }
                                        QQC2.SpinBox {
                                            objectName: "widgetManagerSize"
                                            Layout.fillWidth: true
                                            from: 4
                                            to: 512
                                            value: Math.max(4, widgetSize || DockSettings.iconSize)
                                            onValueModified: DockModel.dockEntriesModel.setBuiltInWidgetSize(entryId, value)
                                            Accessible.name: i18n("Widget size in pixels")
                                        }
                                    }
                                    QQC2.CheckBox {
                                        objectName: "widgetManagerVisibility"
                                        Layout.columnSpan: widgetControls.columns
                                        text: i18n("Show this widget")
                                        checked: widgetVisible
                                        onToggled: DockModel.dockEntriesModel.setBuiltInWidgetVisible(entryId, checked)
                                    }
                                    QQC2.Button {
                                        visible: widgetKind === "applicationLauncher"
                                        Layout.columnSpan: widgetControls.columns
                                        text: i18n("Choose icon…")
                                        icon.name: "preferences-desktop-icons"
                                        onClicked: DockModel.chooseBuiltInWidgetIcon(entryId, Window.window)
                                    }
                            }
                        }
                    }
                }

                QQC2.Label {
                    objectName: "widgetManagerEmptyState"
                    visible: widgetManager.showsEmptyState
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18n("No built-in widgets. Use the buttons above to add one.")
                }
            }
        }

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
    }

}
