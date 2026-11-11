// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import org.kde.taskmanager as TaskManager
import com.thicking.kdockw 1.0

/**
 * Takes one short-lived PipeWire capture for an unminimized window which has
 * no retained frame yet. A single Loader is reused for the whole queue, so
 * background capture never creates one stream per task delegate.
 */
Item {
    id: root

    property int maximumQueueLength: 16
    property int attemptTimeout: 3000
    property int nextAttemptDelay: 250
    property int orphanConfirmDelay: 600
    property var pendingCandidates: []
    property var attemptsByUuid: ({})
    property var lastMinimizedByUuid: ({})
    property var lastActiveByUuid: ({})
    property var missingCacheScans: ({})
    property var activeCandidate: null
    property string activeUuid: ""
    property string requestUuid: ""
    property bool frameGrabPending: false
    property bool forceCpuCapture: false
    property int requestRetries: 0
    property double activeStartedAt: 0
    property double streamReadyAt: 0
    property int successfulCaptures: 0
    property int failedCaptures: 0
    // Component injection keeps the one-at-a-time scheduler testable without
    // opening real KWin streams in offscreen QML tests.
    property Component captureComponent: captureViewportComponent
    property Component requestComponent: screencastRequestComponent
    property bool useKWinScreencastRequest: true
    property int sourceNodeIdOverride: -1

    readonly property real viewportWidth: Math.max(1, Math.min(
        DockSettings.previewThumbnailSize, DockSettings.previewMaximumHeight * 1.6))
    readonly property real viewportHeight: Math.max(1, Math.min(
        DockSettings.previewMaximumHeight, DockSettings.previewThumbnailSize / 1.6))
    readonly property bool active: activeUuid.length > 0
    readonly property int sourceNodeId: sourceNodeIdOverride >= 0
        ? sourceNodeIdOverride
        : requestLoader.item ? requestLoader.item.nodeId : 0

    signal attemptStarted(string uuid)
    signal attemptFinished(string uuid, bool cached, string reason)

    function log(phase, details) {
        if (typeof IconDiagnostics === "undefined" || !IconDiagnostics.taskDiagnosticsEnabled)
            return
        console.info("[KDOCKW_PREVIEW_PREFETCH]", JSON.stringify(Object.assign({
            phase: phase,
            uuid: activeUuid,
            queueDepth: pendingCandidates.length,
            attempts: activeUuid ? (attemptsByUuid[activeUuid] || 0) : 0,
            streamReady: captureLoader.item ? captureLoader.item.sourceItem.ready : false,
            frameGrabPending: frameGrabPending,
            elapsedMs: activeStartedAt ? Date.now() - activeStartedAt : 0
        }, details || {})))
    }

    function scheduleScan(reason) {
        scanReason = reason || "unspecified"
        scanTimer.restart()
    }

    property string scanReason: "initial"

    function makeCandidate(modelIndex, childIndex) {
        const isWindow = DockModel.tasksModel.data(
            modelIndex, TaskManager.AbstractTasksModel.IsWindow)
        if (!isWindow)
            return null

        const ids = DockModel.tasksModel.data(
            modelIndex, TaskManager.AbstractTasksModel.WinIdList) || []
        if (!ids.length || ids[0] === undefined || ids[0] === null)
            return null

        const uuid = String(ids[0])
        if (!uuid.length)
            return null

        return {
            uuid: uuid,
            minimized: !!DockModel.tasksModel.data(
                modelIndex, TaskManager.AbstractTasksModel.IsMinimized),
            active: !!DockModel.tasksModel.data(
                modelIndex, TaskManager.AbstractTasksModel.IsActive),
            parentRow: modelIndex.row,
            childIndex: childIndex
        }
    }

    function scanTasks() {
        const model = DockModel.tasksModel
        const found = []
        const present = ({})

        function append(candidate) {
            if (!candidate)
                return
            present[candidate.uuid] = true

            const hadMinimizedState = Object.prototype.hasOwnProperty.call(
                root.lastMinimizedByUuid, candidate.uuid)
            const minimizedChanged = hadMinimizedState
                && root.lastMinimizedByUuid[candidate.uuid] !== candidate.minimized
            if (hadMinimizedState && root.lastMinimizedByUuid[candidate.uuid]
                    && !candidate.minimized) {
                // A restore permits one fresh attempt after an earlier
                // minimized-before-frame timeout, but never a retry loop.
                let attempts = Object.assign({}, root.attemptsByUuid)
                attempts[candidate.uuid] = 0
                root.attemptsByUuid = attempts
            }
            const hadActiveState = Object.prototype.hasOwnProperty.call(
                root.lastActiveByUuid, candidate.uuid)
            if (hadActiveState && !root.lastActiveByUuid[candidate.uuid] && candidate.active) {
                let attempts = Object.assign({}, root.attemptsByUuid)
                attempts[candidate.uuid] = 0
                root.attemptsByUuid = attempts
            }
            let minimizedState = Object.assign({}, root.lastMinimizedByUuid)
            minimizedState[candidate.uuid] = candidate.minimized
            root.lastMinimizedByUuid = minimizedState
            // Cache eviction priority follows the live TaskManager state, so
            // a retained minimized frame survives ordinary prefetch churn.
            const priorityChanged = PreviewController.setPreviewFrameMinimized(
                candidate.uuid, candidate.minimized)
            if (!hadMinimizedState || minimizedChanged || priorityChanged) {
                log("task-window-state", {
                    windowUuid: candidate.uuid,
                    minimized: candidate.minimized,
                    active: candidate.active,
                    cached: root.previewControllerHasFrame(candidate.uuid),
                    cachePriorityChanged: priorityChanged
                })
            }
            let activeState = Object.assign({}, root.lastActiveByUuid)
            activeState[candidate.uuid] = candidate.active
            root.lastActiveByUuid = activeState

            // Only prefetch the foreground window. This covers the launch and
            // activate-before-minimize paths while avoiding background scans
            // that would open streams for every window on the desktop.
            if (!candidate.active || candidate.minimized
                    || root.previewControllerHasFrame(candidate.uuid))
                return
            if ((root.attemptsByUuid[candidate.uuid] || 0) >= 1)
                return
            found.push(candidate)
        }

        for (let row = 0; row < model.rowCount(); ++row) {
            const parentIndex = model.index(row, 0)
            const childCount = DockModel.childCount(row)
            if (childCount > 0) {
                for (let child = 0; child < childCount; ++child) {
                    const childIndex = model.makeModelIndex(row, child)
                    append(makeCandidate(childIndex, child))
                }
            } else {
                append(makeCandidate(parentIndex, -1))
            }
        }

        let minimizedState = Object.assign({}, lastMinimizedByUuid)
        let activeState = Object.assign({}, lastActiveByUuid)
        let attempts = Object.assign({}, attemptsByUuid)
        for (const uuid of Object.keys(minimizedState)) {
            if (!present[uuid]) {
                delete minimizedState[uuid]
                delete activeState[uuid]
                delete attempts[uuid]
            }
        }
        lastMinimizedByUuid = minimizedState
        lastActiveByUuid = activeState
        attemptsByUuid = attempts

        cleanupClosedWindowFrames(present)

        if (activeCandidate) {
            const current = foundCandidateForUuid(activeCandidate.uuid, model)
            if (!current || ((!current.active || current.minimized) && !frameGrabPending)) {
                finishAttempt(false, !current ? "window-closed"
                    : current.minimized ? "minimized-before-frame" : "backgrounded-before-frame")
            } else if (current.minimized) {
                // Let an already accepted one-shot readback finish; the source
                // itself will be released immediately when it is cached.
                log("window-minimized-after-grab")
            }
        }

        if (!DockSettings.previewEnabled || PreviewController.visible) {
            pendingCandidates = []
            if (activeCandidate)
                finishAttempt(false, PreviewController.visible ? "popup-opened" : "preview-disabled")
            return
        }

        found.sort((a, b) => {
            if (a.active !== b.active)
                return a.active ? -1 : 1
            if (a.parentRow !== b.parentRow)
                return a.parentRow - b.parentRow
            return a.childIndex - b.childIndex
        })
        pendingCandidates = found.slice(0, maximumQueueLength)
        if (activeCandidate)
            pendingCandidates = pendingCandidates.filter(c => c.uuid !== activeCandidate.uuid)

        log("task-scan", {
            reason: scanReason,
            eligible: found.length,
            queued: pendingCandidates.length,
            activeWindowCount: countLiveWindows(present)
        })
        pumpTimer.restart()
    }

    function countLiveWindows(present) {
        return Object.keys(present).length
    }

    function foundCandidateForUuid(uuid, model) {
        for (let row = 0; row < model.rowCount(); ++row) {
            const parentIndex = model.index(row, 0)
            const childCount = DockModel.childCount(row)
            if (childCount > 0) {
                for (let child = 0; child < childCount; ++child) {
                    const candidate = makeCandidate(model.makeModelIndex(row, child), child)
                    if (candidate && candidate.uuid === uuid)
                        return candidate
                }
            } else {
                const candidate = makeCandidate(parentIndex, -1)
                if (candidate && candidate.uuid === uuid)
                    return candidate
            }
        }
        return null
    }

    function previewControllerHasFrame(uuid) {
        return PreviewController.previewFrameUrl(uuid).length > 0
    }

    function cleanupClosedWindowFrames(present) {
        const cached = PreviewController.cachedPreviewFrameUuids()
        let missing = Object.assign({}, missingCacheScans)
        for (const uuid of cached) {
            if (present[uuid]) {
                delete missing[uuid]
                continue
            }
            missing[uuid] = (missing[uuid] || 0) + 1
            if (missing[uuid] >= 2) {
                PreviewController.removePreviewFrame(uuid)
                delete missing[uuid]
                log("closed-window-frame-removed", { cachedUuid: uuid })
            }
        }
        for (const uuid of Object.keys(missing)) {
            if (!cached.includes(uuid))
                delete missing[uuid]
        }
        missingCacheScans = missing
        if (Object.keys(missing).length > 0)
            orphanConfirmTimer.restart()
    }

    function beginAttempt(candidate) {
        if (!candidate || activeCandidate || PreviewController.visible || !DockSettings.previewEnabled)
            return
        const current = foundCandidateForUuid(candidate.uuid, DockModel.tasksModel)
        if (!current || current.minimized || previewControllerHasFrame(candidate.uuid)) {
            scheduleScan("candidate-no-longer-eligible")
            return
        }
        candidate = current

        let attempts = Object.assign({}, attemptsByUuid)
        attempts[candidate.uuid] = (attempts[candidate.uuid] || 0) + 1
        attemptsByUuid = attempts
        activeCandidate = candidate
        activeUuid = candidate.uuid
        requestUuid = candidate.uuid
        frameGrabPending = false
        forceCpuCapture = false
        requestRetries = 0
        activeStartedAt = Date.now()
        streamReadyAt = 0
        attemptTimer.interval = attemptTimeout
        captureLoader.active = true
        attemptTimer.restart()
        nodeRetryTimer.restart()
        attemptStarted(candidate.uuid)
        log("stream-started", { parentRow: candidate.parentRow, childIndex: candidate.childIndex })
    }

    function pump() {
        if (activeCandidate || !pendingCandidates.length || PreviewController.visible
                || !DockSettings.previewEnabled)
            return
        const candidate = pendingCandidates.shift()
        pendingCandidates = pendingCandidates.slice()
        beginAttempt(candidate)
    }

    function finishAttempt(cached, reason) {
        if (!activeCandidate)
            return
        const finishedUuid = activeUuid
        const elapsed = Date.now() - activeStartedAt
        if (cached)
            successfulCaptures++
        else
            failedCaptures++
        log("stream-finished", { cached: cached, reason: reason, totalElapsedMs: elapsed })
        attemptFinished(finishedUuid, cached, reason)
        attemptTimer.stop()
        snapshotTimer.stop()
        cpuFallbackTimer.stop()
        nodeRetryTimer.stop()
        captureLoader.active = false
        requestUuid = ""
        activeCandidate = null
        activeUuid = ""
        frameGrabPending = false
        forceCpuCapture = false
        activeStartedAt = 0
        streamReadyAt = 0
        if (reason === "timeout" || reason === "frame-grab-rejected")
            scheduleOrphanAwareRescan()
        pumpTimer.restart()
    }

    function scheduleOrphanAwareRescan() {
        scheduleScan("attempt-finished")
    }

    function sourceBecameReady() {
        if (!activeCandidate || !captureLoader.item || frameGrabPending)
            return
        streamReadyAt = Date.now()
        log("first-frame-ready", {
            streamSize: captureLoader.item.sourceItem.streamSize,
            usingDmaBuf: captureLoader.item.sourceItem.usingDmaBuf,
            streamReadyElapsedMs: streamReadyAt - activeStartedAt
        })
        snapshotTimer.restart()
    }

    function captureFirstFrame() {
        if (!activeCandidate || !captureLoader.item || frameGrabPending)
            return
        const source = captureLoader.item.sourceItem
        if (!source || !source.ready || activeCandidate.minimized)
            return

        const dprValue = root.Window.window ? root.Window.window.devicePixelRatio : root.Screen.devicePixelRatio
        const dpr = Number.isFinite(dprValue) && dprValue > 0 ? dprValue : 1
        const targetSize = Qt.size(
            Math.max(1, Math.min(640, Math.ceil(viewportWidth * dpr))),
            Math.max(1, Math.min(400, Math.ceil(viewportHeight * dpr))))
        const accepted = PreviewController.capturePreviewFrame(
            captureLoader.item, activeUuid, targetSize)
        if (!accepted) {
            finishAttempt(false, "frame-grab-rejected")
            return
        }
        frameGrabPending = true
        attemptTimer.interval = 5500
        attemptTimer.restart()
        log("frame-grab-requested", {
            targetWidth: targetSize.width,
            targetHeight: targetSize.height,
            readbackWaitMs: Date.now() - streamReadyAt
        })
        if (typeof IconDiagnostics !== "undefined" && IconDiagnostics.previewCaptureMetrics) {
            // Counters and elapsed times only; never log image data or content.
            console.info("[kdockw.preview.prefetch.metrics]", JSON.stringify({
                uuid: activeUuid,
                concurrentStreams: 1,
                targetPixels: targetSize.width * targetSize.height,
                targetBytesUpperBound: targetSize.width * targetSize.height * 4,
                streamReadyMs: streamReadyAt - activeStartedAt,
                readbackWaitMs: Date.now() - streamReadyAt
            }))
        }
    }

    function onSourceStateChanged() {
        if (!activeCandidate || !captureLoader.item)
            return
        const source = captureLoader.item.sourceItem
        if (source.state === 4 && !source.ready && !PreviewController.cpuCaptureOnly)
            cpuFallbackTimer.restart()
    }

    function retrySourceWithoutDmaBuf() {
        if (!activeCandidate || frameGrabPending || forceCpuCapture || !captureLoader.item)
            return
        const source = captureLoader.item.sourceItem
        if (!source || source.ready || source.state !== 4)
            return
        forceCpuCapture = true
        log("dma-buf-timeout-cpu-retry")
        captureLoader.active = false
        Qt.callLater(() => {
            if (activeCandidate)
                captureLoader.active = true
        })
    }

    function retryNodeRequest() {
        if (!activeCandidate || requestRetries > 0 || sourceNodeId !== 0)
            return
        requestRetries++
        log("screencast-node-retry")
        requestUuid = ""
        Qt.callLater(() => {
            if (activeCandidate)
                requestUuid = activeUuid
        })
    }

    function onPreviewFramesChanged() {
        if (activeUuid.length && previewControllerHasFrame(activeUuid))
            finishAttempt(true, "frame-cached")
        scheduleScan("preview-frames-changed")
    }

    Component.onCompleted: scheduleScan("component-completed")

    Connections {
        target: DockModel.tasksModel
        function onRowsInserted() { root.scheduleScan("rows-inserted") }
        function onRowsRemoved() { root.scheduleScan("rows-removed") }
        function onRowsMoved() { root.scheduleScan("rows-moved") }
        function onDataChanged() { root.scheduleScan("data-changed") }
        function onModelReset() { root.scheduleScan("model-reset") }
        function onLayoutChanged() { root.scheduleScan("layout-changed") }
    }

    Connections {
        target: PreviewController
        function onVisibleChanged() { root.scheduleScan("preview-visibility-changed") }
        function onPreviewFramesChanged() { root.onPreviewFramesChanged() }
    }

    Connections {
        target: DockSettings
        function onPreviewEnabledChanged() { root.scheduleScan("preview-setting-changed") }
    }

    Connections {
        target: captureLoader.item ? captureLoader.item.sourceItem : null
        ignoreUnknownSignals: true
        function onReadyChanged() {
            if (captureLoader.item && captureLoader.item.sourceItem.ready)
                root.sourceBecameReady()
        }
        function onStateChanged() { root.onSourceStateChanged() }
    }

    Component {
        id: screencastRequestComponent
        TaskManager.ScreencastingRequest {
            uuid: root.requestUuid
        }
    }

    Loader {
        id: requestLoader
        active: root.useKWinScreencastRequest && root.requestUuid.length > 0
        sourceComponent: root.requestComponent
    }

    Connections {
        target: requestLoader.item
        ignoreUnknownSignals: true
        function onNodeIdChanged() {
            if (root.sourceNodeId > 0) {
                root.nodeRetryTimer.stop()
                root.log("screencast-node-ready", { nodeId: root.sourceNodeId })
                root.onSourceStateChanged()
            }
        }
    }

    Loader {
        id: captureLoader
        objectName: "previewFramePrefetchCapture"
        active: false
        x: -root.viewportWidth - 2
        y: -root.viewportHeight - 2
        width: root.viewportWidth
        height: root.viewportHeight
        sourceComponent: root.captureComponent
        onLoaded: {
            if (item && item.sourceItem && item.sourceItem.ready)
                root.sourceBecameReady()
        }
    }

    Component {
        id: captureViewportComponent
        Item {
            id: viewport
            objectName: "previewFramePrefetchViewport"
            width: root.viewportWidth
            height: root.viewportHeight
            clip: true
            visible: true
            Accessible.ignored: true
            property alias sourceItem: source

            readonly property real sourceRatio: {
                if (!source.ready)
                    return 1.6
                const size = source.streamSize
                if (size.width < 1 || size.height < 1)
                    return 1.6
                return Math.max(1 / 32, Math.min(32, size.width / size.height))
            }
            readonly property real contentWidth: Math.max(width, height * sourceRatio)
            readonly property real contentHeight: contentWidth / sourceRatio

            ClippedPipeWireSourceItem {
                id: source
                objectName: "previewFramePrefetchPipeWireSource"
                nodeId: root.sourceNodeId
                // Shell recreation and isolated QML test contexts can briefly
                // instantiate this component before its per-shell controller
                // is injected. Keep that transient state on the CPU-safe path.
                allowDmaBuf: PreviewController !== null && PreviewController !== undefined
                    && !PreviewController.cpuCaptureOnly && !root.forceCpuCapture
                width: viewport.contentWidth
                height: viewport.contentHeight
                x: (viewport.width - width) / 2
                y: (viewport.height - height) / 2
                clipMode: "rounded"
                clipViewportRect: Qt.rect(
                    (width - viewport.width) / 2,
                    (height - viewport.height) / 2,
                    viewport.width,
                    viewport.height)
                clipRadius: Math.min(
                    DockSettings.cornerRadius, viewport.width / 2, viewport.height / 2)
                Accessible.ignored: true

            }
        }
    }

    Timer {
        id: scanTimer
        interval: 120
        repeat: false
        onTriggered: root.scanTasks()
    }

    Timer {
        id: pumpTimer
        interval: root.nextAttemptDelay
        repeat: false
        onTriggered: root.pump()
    }

    Timer {
        id: attemptTimer
        interval: root.attemptTimeout
        repeat: false
        onTriggered: root.finishAttempt(false, "timeout")
    }

    Timer {
        id: snapshotTimer
        interval: 60
        repeat: false
        onTriggered: root.captureFirstFrame()
    }

    Timer {
        id: cpuFallbackTimer
        interval: 1500
        repeat: false
        onTriggered: root.retrySourceWithoutDmaBuf()
    }

    Timer {
        id: nodeRetryTimer
        interval: 700
        repeat: false
        onTriggered: root.retryNodeRequest()
    }

    Timer {
        id: orphanConfirmTimer
        interval: root.orphanConfirmDelay
        repeat: false
        onTriggered: root.scheduleScan("orphan-confirm")
    }
}
