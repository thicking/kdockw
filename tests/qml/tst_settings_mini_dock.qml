// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings

Item {
    id: root
    width: 900
    height: 640

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "SettingsMiniDock"
        when: windowShown

        Component {
            id: dockComponent
            Settings.MiniDock {
                unit: 1
                interactiveHover: false
                zoomInDuration: 0
                zoomOutDuration: 0
            }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function makeDock(edge) {
            const dock = createTemporaryObject(dockComponent, stage, { edge: edge })
            verify(dock, "MiniDock failed to load")
            return dock
        }

        function test_newMagnificationDefaultsFlowIntoMiniDock() {
            const dock = makeDock(1)
            compare(DockSettings.magnificationMode, 1)
            compare(DockSettings.maxZoomFactor, 1.9)
            compare(DockSettings.springStiffness, 170)
            compare(DockSettings.springDamping, 0.60)
            compare(DockSettings.springSpeed, 1.0)
            compare(dock.magnificationMode, 1)
            compare(dock.maxZoomFactor, 1.9)
        }

        function test_badgeUsesLiveDockSettings() {
            const dock = makeDock(1)
            const badge = findChild(dock, "miniDockBadge5")
            const label = findChild(dock, "miniDockBadgeLabel5")
            const box = findChild(dock, "miniDockIconBox5")
            verify(badge && label && box)

            compare(badge.color.toString(), DockSettings.badgeBackgroundColor.toString())
            compare(label.color.toString(), DockSettings.badgeTextColor.toString())
            compare(label.renderType, Text.QtRendering)
            compare(label.font.weight, DockSettings.badgeFontWeight)
            compare(label.font.pixelSize,
                    Math.max(1, Math.round(badge.height * 0.55 * DockSettings.badgeTextSizePercent / 100)))
            compare(badge.width, Math.round(box.width * 0.38))
            compare(badge.x, box.x + box.width - badge.width * 0.8)
            compare(badge.y, box.y - badge.height * 0.2)

            DockSettings.badgeBackgroundColor = "#ff00aaff"
            DockSettings.badgeTextColor = "#ff101010"
            DockSettings.badgeFontWeight = 700
            DockSettings.badgeTextSizePercent = 115
            tryCompare(badge, "color", DockSettings.badgeBackgroundColor)
            tryCompare(label, "color", DockSettings.badgeTextColor)
            tryCompare(label.font, "weight", DockSettings.badgeFontWeight)
            tryCompare(label.font, "pixelSize",
                       Math.max(1, Math.round(badge.height * 0.55 * DockSettings.badgeTextSizePercent / 100)))

            DockSettings.badgeDisplayMode = 1
            tryVerify(() => badge.width === Math.round(box.width * 0.18))
            verify(!label.visible)
            DockSettings.badgeDisplayMode = 2
            tryVerify(() => !badge.visible)
        }

        function test_iconsGrowAwayFromEachDockEdge_data() {
            return [
                { tag: "top", edge: 0, axis: "y", expectedPinned: "near" },
                { tag: "bottom", edge: 1, axis: "y", expectedPinned: "far" },
                { tag: "left", edge: 2, axis: "x", expectedPinned: "near" },
                { tag: "right", edge: 3, axis: "x", expectedPinned: "far" }
            ]
        }

        function test_iconsGrowAwayFromEachDockEdge(data) {
            const dock = makeDock(data.edge)
            dock.hoveredIndex = 2
            tryCompare(dock, "zoomAmount", 1)

            const box = findChild(dock, "miniDockIconBox2")
            const slot = findChild(dock, "miniDockSlot2")
            verify(box && slot)
            verify(box.width > dock.iconPx)

            if (data.axis === "y") {
                if (data.expectedPinned === "near")
                    compare(box.y, 0)
                else
                    compare(box.y + box.height, slot.height)
            } else {
                if (data.expectedPinned === "near")
                    compare(box.x, 0)
                else
                    compare(box.x + box.width, slot.width)
            }

            // The real panel's grown background stays inside its screen-stage
            // bounds, as it does in main.qml's DockView.zoomLayout call.
            const panel = dock.panelItem
            const topLeft = panel.mapToItem(stage, 0, 0)
            const bottomRight = panel.mapToItem(stage, panel.width, panel.height)
            verify(topLeft.x >= -0.01)
            verify(topLeft.y >= -0.01)
            verify(bottomRight.x <= stage.width + 0.01)
            verify(bottomRight.y <= stage.height + 0.01)
        }

        function test_hoverSwitchEnablesPointerZoomAndOffIsStatic() {
            const dock = makeDock(1)
            dock.interactiveHover = false
            const area = findChild(dock, "miniDockHoverArea")
            const icon = findChild(dock, "miniDockIconBox3")
            verify(area && icon)
            const pointer = icon.mapToItem(area, icon.width / 2, icon.height / 2)

            mouseMove(area, pointer.x, pointer.y)
            compare(dock.zoomed, false)
            compare(dock.zoomLayout.scales[3], 1)

            dock.interactiveHover = true
            mouseMove(area, pointer.x, pointer.y)
            tryVerify(() => dock.zoomed)
            tryVerify(() => dock.zoomLayout.scales[3] > 1)

            dock.interactiveHover = false
            tryVerify(() => !dock.zoomed)
            tryVerify(() => dock.zoomLayout.scales[3] === 1)
        }

        function test_zoomTracksLiveSettingsChanges() {
            const dock = makeDock(1)
            dock.hoveredIndex = 3
            tryCompare(dock, "zoomAmount", 1)
            tryVerify(() => Math.abs(dock.zoomLayout.scales[3] - DockSettings.maxZoomFactor) < 0.001)

            DockSettings.maxZoomFactor = 1.3
            tryVerify(() => Math.abs(dock.zoomLayout.scales[3] - 1.3) < 0.001)

            DockSettings.iconSize = 64
            DockSettings.iconSpacing = 21
            tryVerify(() => dock.iconPx === 64)
            tryVerify(() => dock.gapPx === 21)
            tryVerify(() => dock.zoomLayout.scales[3] === 1.3)
        }

        function test_springModeUsesTheSharedZoomGeometryAndUpdatesLive() {
            const dock = makeDock(1)
            const spring = findChild(dock, "miniDockSpringZoomController")
            verify(spring)

            DockSettings.magnificationMode = 1
            dock.hoveredIndex = 2
            tryVerify(() => dock.zoomAmount > 0.95)
            tryVerify(() => dock.zoomLayout.scales[2] > 1.0)
            compare(dock.zoomLayout.scales.length, dock.count)

            DockSettings.springStiffness = 260
            DockSettings.springDamping = 1.1
            DockSettings.springSpeed = 1.7
            DockSettings.maxZoomFactor = 1.4
            tryVerify(() => dock.zoomLayout.scales[2] > 1.35)

            DockSettings.magnificationMode = 0
            tryCompare(dock, "zoomAmount", 1)
            verify(dock.zoomLayout.scales[2] > 1.3)
        }

        function test_springZoomSupportsAllDockEdges() {
            const dock = makeDock(0)
            dock.magnificationMode = 1
            const spring = findChild(dock, "miniDockSpringZoomController")
            verify(spring)

            for (const edge of [0, 1, 2, 3]) {
                dock.edge = edge
                const cursor = dock.vertical ? dock.height / 2 : dock.width / 2
                spring.synchronize(cursor, 0)
                spring.setTarget(cursor, 1, 170, 0.60, 1.0, 0,
                                 dock.vertical ? dock.height : dock.width)
                tryVerify(() => dock.zoomAmount > 0.95)
                verify(dock.zoomLayout.scales.some(scale => scale > 1.0))
                spring.synchronize(cursor, 0)
            }
        }
    }
}
