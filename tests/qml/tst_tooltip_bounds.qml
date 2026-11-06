// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Focused geometry test for the in-scene app-name tooltip and its layer-shell
// surface reserve. The live compositor still requires manual visual QA.
import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml" as KDockW
import "TestUtils.js" as T

Item {
    id: fixture
    width: 800
    height: 240

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "TooltipBounds"
        when: windowShown

        function init() {
            KDockWMocks.resetAll()
            DockSettings.previewEnabled = false
            DockSettings.previewHoverDelay = 0
            DockModel.tasksModel.addTask({
                display: "Tooltip bounds fixture",
                AppId: "tooltip-bounds-fixture",
                IsWindow: false,
                IsLauncher: true,
            })
        }

        function cleanup() {
            mouseMove(stage, -1, -1)
        }

        function dockItems(dock) {
            return T.findAll(dock, T.isDockItem).sort((a, b) => a.index - b.index)
        }

        function tooltip(dock) {
            return T.findFirst(dock, object => object.objectName === "dockTooltip")
        }

        function test_tooltipFitsSurfaceOnEveryEdge() {
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                const component = Qt.createComponent(Qt.resolvedUrl("../../src/qml/main.qml"))
                compare(component.status, Component.Ready, component.errorString())
                const dock = createTemporaryObject(component, stage)
                verify(dock)
                tryVerify(() => dockItems(dock).length === 1, 2000)
                const item = dockItems(dock)[0]
                tryVerify(() => item._delegateGeometryReady, 2000)
                mouseMove(item, item.width / 2, item.height / 2)

                const label = tooltip(dock)
                tryCompare(label, "visible", true, 2000)
                verify(label.x >= 0 && label.y >= 0
                       && label.x + label.width <= dock.width
                       && label.y + label.height <= dock.height,
                       "tooltip rectangle must be inside the dock surface at edge " + edge)
                const expectedExtent = DockView.isVertical
                    ? label.maxSideWidth : label.height
                verify(DockView.tooltipReserve >= expectedExtent
                       + label.maximumGap + label.shadowOverflow,
                       "surface reserve must contain label, zoom gap and shadow")

                mouseMove(stage, -1, -1)
                tryCompare(label, "visible", false)
                dock.destroy()
            }
        }
    }
}
