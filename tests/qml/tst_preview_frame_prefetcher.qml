// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml" as KDockW
import "TestUtils.js" as T

Item {
    id: root
    width: 800
    height: 500

    Item {
        id: stage
        anchors.fill: parent
    }

    Component {
        id: fakeCaptureComponent
        Item {
            id: viewport
            objectName: "prefetchTestViewport"
            width: 200
            height: 125
            visible: true
            property alias sourceItem: fakeSource

            Item {
                id: fakeSource
                objectName: "prefetchTestSource"
                property int nodeId: 42
                property bool ready: false
                property int state: 4
                property var streamSize: Qt.size(1581, 904)
                property bool usingDmaBuf: false
            }
        }
    }

    Component {
        id: prefetcherComponent
        KDockW.PreviewFramePrefetcher {
            captureComponent: fakeCaptureComponent
            useKWinScreencastRequest: false
            sourceNodeIdOverride: 42
            nextAttemptDelay: 20
            attemptTimeout: 1500
            orphanConfirmDelay: 80
        }
    }

    Component {
        id: popupComponent
        KDockW.PreviewPopup {}
    }

    TestCase {
        name: "PreviewFramePrefetcher"
        when: windowShown

        function init() {
            KDockWMocks.resetAll()
            DockSettings.previewEnabled = true
            DockSettings.previewThumbnailSize = 200
            DockSettings.previewMaximumHeight = 180
        }

        function makePrefetcher() {
            const item = createTemporaryObject(prefetcherComponent, stage)
            verify(item)
            return item
        }

        function test_launchedWindowIsSnapshottedBeforePopupAndSurvivesExternalMinimize() {
            DockModel.tasksModel.addTask({
                display: "New app",
                IsWindow: true,
                IsActive: true,
                WinIdList: ["new-window-uuid"]
            })
            const prefetcher = makePrefetcher()
            tryCompare(prefetcher, "activeUuid", "new-window-uuid", 2000)
            verify(!PreviewController.visible, "prefetch must work without opening the popup")

            const source = T.findFirst(prefetcher, item => item.objectName === "prefetchTestSource")
            verify(source)
            source.ready = true
            tryVerify(() => PreviewController.previewFrameUrl("new-window-uuid").length > 0, 1500)
            verify(!prefetcher.active, "the one-shot stream must be released after caching a frame")

            DockModel.tasksModel.setTaskData(0, "IsMinimized", true)
            PreviewController.parentIndex = 0
            PreviewController.visible = true
            const popup = createTemporaryObject(popupComponent, stage)
            verify(popup)
            const thumbnail = T.findFirst(popup,
                item => item.retryScreencast !== undefined && item.winId === "new-window-uuid")
            tryVerify(() => thumbnail && thumbnail.isMinimized, 1000)
            const retained = T.findFirst(thumbnail,
                item => item.objectName === "minimizedCachedFrame")
            const fallback = T.findFirst(thumbnail,
                item => item.objectName === "previewFallbackIcon")
            tryVerify(() => retained && retained.visible, 1000,
                      "the externally minimized window must show the pre-opened cached frame")
            compare(String(retained.source), PreviewController.previewFrameUrl("new-window-uuid"))
            verify(fallback && !fallback.visible)
        }

        function test_onlyOnePrefetchStreamRunsAtATimeAcrossSeveralWindows() {
            for (let i = 0; i < 5; ++i) {
                DockModel.tasksModel.addTask({
                    display: "Window " + i,
                    IsWindow: true,
                    IsActive: i === 3,
                    WinIdList: ["prefetch-" + i]
                })
            }

            const prefetcher = makePrefetcher()
            let activeStreams = 0
            let maximumConcurrentStreams = 0
            const started = []
            const finished = []
            prefetcher.attemptStarted.connect(uuid => {
                started.push(uuid)
                ++activeStreams
                maximumConcurrentStreams = Math.max(maximumConcurrentStreams, activeStreams)
            })
            prefetcher.attemptFinished.connect((uuid, cached) => {
                finished.push({ uuid: uuid, cached: cached })
                --activeStreams
            })

            const expectedOrder = ["prefetch-3", "prefetch-0", "prefetch-1", "prefetch-2", "prefetch-4"]
            let previousRow = 3
            for (let orderIndex = 0; orderIndex < expectedOrder.length; ++orderIndex) {
                const uuid = expectedOrder[orderIndex]
                const row = Number(uuid.slice("prefetch-".length))
                if (orderIndex > 0) {
                    DockModel.tasksModel.setTaskData(previousRow, "IsActive", false)
                    DockModel.tasksModel.setTaskData(row, "IsActive", true)
                }
                tryCompare(prefetcher, "activeUuid", uuid, 2500)
                const source = T.findFirst(prefetcher, item => item.objectName === "prefetchTestSource")
                verify(source)
                source.ready = true
                tryVerify(() => PreviewController.previewFrameUrl(uuid).length > 0, 1200)
                previousRow = row
            }
            tryVerify(() => !prefetcher.active, 1500)

            compare(started, expectedOrder)
            compare(finished.length, expectedOrder.length)
            verify(finished.every(item => item.cached))
            compare(maximumConcurrentStreams, 1)
            compare(activeStreams, 0)
            compare(PreviewController.cachedPreviewFrameUuids().length, 5,
                    "the scheduler processed each exact UUID; the C++ cache's four-entry bound is tested separately")
        }

        function test_closingAnUncachedWindowReleasesTheActiveStream() {
            DockModel.tasksModel.addTask({
                display: "Closing app",
                IsWindow: true,
                IsActive: true,
                WinIdList: ["closing-window-uuid"]
            })
            const prefetcher = makePrefetcher()
            tryCompare(prefetcher, "activeUuid", "closing-window-uuid", 2000)
            DockModel.tasksModel.removeTask(0)
            tryVerify(() => !prefetcher.active, 1000)
            verify(!PreviewController.previewFrameUrl("closing-window-uuid").length)
            verify(prefetcher.attemptsByUuid["closing-window-uuid"] === undefined)
        }

        function test_closedWindowCacheEntryIsReleasedAfterModelSettles() {
            PreviewController.previewFrameUrls = ({
                "already-closed-uuid": "image://previewframes/closed?v=1"
            })
            const prefetcher = makePrefetcher()
            verify(prefetcher)
            tryVerify(() => !PreviewController.previewFrameUrl("already-closed-uuid").length,
                      2000, "a UUID absent from two settled model scans must release its cached image")
            compare(prefetcher.active, false)
        }

        function test_minimizeBeforeFirstFrameStopsWithoutRetryLoopAndRestoreCanRetry() {
            DockModel.tasksModel.addTask({
                display: "Fast minimize",
                IsWindow: true,
                IsActive: true,
                WinIdList: ["fast-minimize-uuid"]
            })
            const prefetcher = makePrefetcher()
            let startCount = 0
            prefetcher.attemptStarted.connect(() => ++startCount)
            tryCompare(prefetcher, "activeUuid", "fast-minimize-uuid", 2000)

            DockModel.tasksModel.setTaskData(0, "IsMinimized", true)
            tryVerify(() => !prefetcher.active, 1000)
            wait(500)
            compare(startCount, 1, "a missing first frame must not trigger repeated attempts")
            compare(prefetcher.failedCaptures, 1)

            DockModel.tasksModel.setTaskData(0, "IsMinimized", false)
            tryCompare(prefetcher, "activeUuid", "fast-minimize-uuid", 2000,
                       "restoring the window allows one fresh attempt")
            const source = T.findFirst(prefetcher, item => item.objectName === "prefetchTestSource")
            verify(source)
            source.ready = true
            tryVerify(() => PreviewController.previewFrameUrl("fast-minimize-uuid").length > 0, 1200)
            tryVerify(() => !prefetcher.active, 1000)
            compare(startCount, 2)
        }
    }
}
