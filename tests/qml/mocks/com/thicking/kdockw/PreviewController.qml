// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of PreviewController (production: context property).
pragma Singleton
import QtQuick

QtObject {
    // Recorded calls: [{ name, args }]. Reassigned (not mutated) so bindings notify.
    property var calls: []
    function _record(name, args) { calls = calls.concat([{ name: name, args: Array.from(args) }]) }
    function callsTo(name) { return calls.filter(c => c.name === name) }
    property bool visible: false
    property int parentIndex: -1
    property string appName: ""
    property real contentX: 0
    property real contentY: 0
    property real contentWidth: 0
    property real contentHeight: 0
    property real maxPopupWidth: 1100
    property real previewAnchorOffset: 0
    property real simulatedCurrentZoomOverflow: 0
    property bool previewHovered: false
    property bool previewKeyboardActive: false
    property int focusedThumbnailIndex: -1
    property bool cpuCaptureOnly: false
    property int previewFrameRevision: 0
    property int dismissedTaskIndex: -1
    property var previewFrameUrls: ({})
    property var frameStoreRequests: []
    signal captureModeChanged()
    signal previewFramesChanged()
    function setCaptureMode(cpuOnly) {
        if (cpuCaptureOnly === cpuOnly) return
        cpuCaptureOnly = cpuOnly
        captureModeChanged()
    }
    function showPreview(i, pos, ext, restEdge, maxZoomOverflow, shadowMargin) {
        _record("showPreview", arguments)
        if (dismissedTaskIndex === i) return
        if (dismissedTaskIndex >= 0) clearDismissedTask()
        previewAnchorOffset = maxZoomOverflow
        parentIndex = i
        visible = true
    }
    function updatePreviewAnchorGeometry(pos, ext, restEdge, maxZoomOverflow, shadowMargin) {
        _record("updatePreviewAnchorGeometry", arguments)
        previewAnchorOffset = maxZoomOverflow
    }
    function hidePreview() { _record("hidePreview", arguments); visible = false }
    function suppressPreviewUntilPointerLeavesTask(i) { dismissedTaskIndex = i }
    function clearDismissedTask() { dismissedTaskIndex = -1 }
    function hidePreviewDelayed() { _record("hidePreviewDelayed", arguments) }
    function cancelHide() { _record("cancelHide", arguments) }
    function setPreviewHovered(v) { previewHovered = v }
    function setContentSize(w, h) { contentWidth = w; contentHeight = h }
    function previewFrameUrl(uuid) {
        const revision = previewFrameRevision
        return previewFrameUrls[uuid] || ""
    }
    function cachedPreviewFrameUuids() { return Object.keys(previewFrameUrls) }
    function storeMinimizedPreviewFrame(uuid, image) {
        frameStoreRequests = frameStoreRequests.concat([{ uuid: uuid, imageSize: Qt.size(image.width, image.height) }])
        let updated = Object.assign({}, previewFrameUrls)
        updated[uuid] = "image://previewframes/mock/" + uuid + "?v=" + (previewFrameRevision + 1)
        previewFrameUrls = updated
        ++previewFrameRevision
        Qt.callLater(function() { previewFramesChanged() })
        return true
    }
    function capturePreviewFrame(item, uuid, size) {
        if (!item || !uuid) return false
        frameStoreRequests = frameStoreRequests.concat([{ uuid: uuid, imageSize: size }])
        let updated = Object.assign({}, previewFrameUrls)
        updated[uuid] = "image://previewframes/mock/" + uuid + "?v=" + (previewFrameRevision + 1)
        previewFrameUrls = updated
        ++previewFrameRevision
        Qt.callLater(function() { previewFramesChanged() })
        return true
    }
    function removePreviewFrame(uuid) {
        _record("removePreviewFrame", [uuid])
        let updated = Object.assign({}, previewFrameUrls)
        delete updated[uuid]
        previewFrameUrls = updated
        ++previewFrameRevision
        return true
    }
    function startPreviewKeyboardNav() { _record("startPreviewKeyboardNav", arguments); previewKeyboardActive = true; focusedThumbnailIndex = 0 }
    function endPreviewKeyboardNav() { _record("endPreviewKeyboardNav", arguments); previewKeyboardActive = false }
    function navigatePreviewThumbnail(d) { _record("navigatePreviewThumbnail", arguments) }
    function activatePreviewThumbnail(suppressHoverReopen) {
        if (suppressHoverReopen)
            suppressPreviewUntilPointerLeavesTask(parentIndex)
        _record("activatePreviewThumbnail", arguments)
    }
    function closePreviewThumbnail() { _record("closePreviewThumbnail", arguments) }
    function focusedThumbnailTitle() { return "" }
    function focusedThumbnailIsActive() { return false }
    function focusedThumbnailIsMinimized() { return false }
    function previewThumbnailCount() { return 0 }

    // Restores every property listed in _resettable to its declared value.
    readonly property var _resettable: ["calls", "visible", "parentIndex", "appName", "contentX", "contentY", "contentWidth", "contentHeight", "maxPopupWidth", "previewAnchorOffset", "simulatedCurrentZoomOverflow", "previewHovered", "previewKeyboardActive", "focusedThumbnailIndex", "cpuCaptureOnly", "previewFrameRevision", "previewFrameUrls", "frameStoreRequests", "dismissedTaskIndex"]
    property var _defaults: ({})
    Component.onCompleted: {
        for (const k of _resettable) _defaults[k] = this[k]
    }
    function reset() {
        for (const k of _resettable) this[k] = _defaults[k]
    }
}
