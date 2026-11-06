// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Running indicators, badges, attention and accessible state of DockItem,
// driven by task model roles and notification sources.
import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "TestUtils.js" as T
import "../../src/qml/BadgeTextColor.js" as BadgeTextColor

// TestCase is an invisible Item: visual fixtures live under `stage`, a visible
// sibling, so effective visibility, layout and pointer delivery are real.
Item {
    id: root
    width: 800
    height: 200

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "DockItemIndicators"
        when: windowShown

        Component {
            id: rowComponent
            DockItemRow {}
        }

        Component {
            id: badgeThemeBindingComponent
            QtObject {
                property color background: "#ffffff"
                property color preferredForeground: "#ffffff"
                readonly property color chosenForeground:
                    BadgeTextColor.choose(background, preferredForeground)
            }
        }

        function init() {
            KDockWMocks.resetAll()
            IconDiagnostics.debugEnabled = false
            IconDiagnostics.testHiDpiEnabled = false
            IconDiagnostics.testBadgeLayerOff = false
            IconDiagnostics.testBadgeShadowOff = false
            IconDiagnostics.testBadgeCrisp = false
            IconDiagnostics.testBadgeCrispStable = false
            IconDiagnostics.testBadgeMetrics = false
            IconDiagnostics.testBadgeSeparate = false
            IconDiagnostics.testBadgeOverlay = false
        }

        // Unity LauncherEntry state is keyed by the task's launcher URL.
        readonly property string launcherUrl: "applications:org.kde.dolphin.desktop"

        function makeItem(roles) {
            DockModel.tasksModel.addTask(Object.assign({ display: "Dolphin", AppId: "org.kde.dolphin", LauncherUrlWithoutIcon: launcherUrl }, roles))
            let row = createTemporaryObject(rowComponent, stage)
            verify(row)
            tryCompare(row, "count", 1)
            return row.itemAt(0)
        }

        // --- Running indicator dots ---

        function test_dotCountFollowsWindowCount_data() {
            return [
                { tag: "launcher", roles: { IsWindow: false }, dots: 0 },
                { tag: "one-window", roles: { IsWindow: true, ChildCount: 0 }, dots: 1 },
                { tag: "two-windows", roles: { IsWindow: true, ChildCount: 2 }, dots: 2 },
                { tag: "three-windows", roles: { IsWindow: true, ChildCount: 3 }, dots: 3 },
                { tag: "capped-at-three", roles: { IsWindow: true, ChildCount: 7 }, dots: 3 },
            ]
        }

        function test_dotCountFollowsWindowCount(data) {
            let item = makeItem(data.roles)
            tryCompare(T.indicatorDots(item), "length", data.dots)
        }

        function test_dotsUpdateWhenModelRolesChange() {
            let item = makeItem({ IsWindow: false })
            compare(T.indicatorDots(item).length, 0)
            DockModel.tasksModel.setTaskData(0, "IsWindow", true)
            tryVerify(() => T.indicatorDots(item).length === 1)
            DockModel.tasksModel.setTaskData(0, "ChildCount", 2)
            tryVerify(() => T.indicatorDots(item).length === 2)
            DockModel.tasksModel.setTaskData(0, "IsWindow", false)
            tryVerify(() => T.indicatorDots(item).length === 0)
        }

        function test_activeWindowHasLargerDot() {
            let item = makeItem({ IsWindow: true, IsActive: false })
            let dot = T.indicatorDots(item)[0]
            compare(dot.width, 4)
            DockModel.tasksModel.setTaskData(0, "IsActive", true)
            tryCompare(T.indicatorDots(item)[0], "width", 5)
        }

        function test_minimizedWindowDimsDot() {
            let item = makeItem({ IsWindow: true })
            tryCompare(T.indicatorDots(item)[0], "opacity", 0.8)
            DockModel.tasksModel.setTaskData(0, "IsMinimized", true)
            tryCompare(T.indicatorDots(item)[0], "opacity", 0.4)
        }

        function test_configurableStylesAndPositionsStayInsideReservedCell() {
            DockView.edge = 1
            DockSettings.runningIndicatorPosition = 0
            DockSettings.runningIndicatorStyle = 0
            DockSettings.iconSize = 48
            DockSettings.runningIndicatorSize = 8
            let item = makeItem({ IsWindow: true, IsActive: false, ChildCount: 2 })
            const marker = T.indicatorDots(item)[0]

            const expected = [
                { width: 7, height: 7 },
                { width: 16, height: 3 },
                { width: 16, height: 8 },
                { width: 16, height: 8 },
                { width: 22, height: 4 }
            ]
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                for (let position = 0; position < 2; ++position) {
                    DockSettings.runningIndicatorPosition = position
                    for (let style = 0; style < expected.length; ++style) {
                        DockSettings.runningIndicatorStyle = style
                        tryCompare(marker, "width", DockView.isVertical ? expected[style].height : expected[style].width)
                        tryCompare(marker, "height", DockView.isVertical ? expected[style].width : expected[style].height)
                        verify(marker.x >= -0.5 && marker.y >= -0.5, `style ${style}, edge ${edge}, position ${position} starts outside its cell`)
                        verify(marker.x + marker.width <= item.width + 0.5, `style ${style}, edge ${edge}, position ${position} exceeds cell width`)
                        verify(marker.y + marker.height <= item.height + 0.5, `style ${style}, edge ${edge}, position ${position} exceeds cell height`)
                    }
                }
            }
            compare(T.indicatorDots(item).length, 2)
        }

        // --- Badge ---

        function test_noBadgeWithoutNotifications() {
            let item = makeItem({ IsWindow: true })
            compare(item._badgeCount, 0)
            verify(T.badge(item), "badge element not found")
            verify(!T.badge(item).visible)
        }

        function test_badgeShowsUnreadCount_data() {
            return [
                { tag: "1", count: 1, text: "1" },
                { tag: "42", count: 42, text: "42" },
                { tag: "99", count: 99, text: "99" },
                { tag: "overflow", count: 150, text: "99+" },
            ]
        }

        function test_badgeShowsUnreadCount(data) {
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", data.count)
            tryCompare(item, "_badgeCount", data.count)
            verify(T.badge(item).visible)
            compare(T.badgeLabel(item).visible, true)
            compare(T.badgeLabel(item).text, data.text)
        }

        function test_badgeTypographySettingsApplyLiveForEveryWindowState() {
            compare(DockSettings.badgeDisplayMode, 0)
            compare(DockSettings.badgeFontWeight, 500)
            compare(DockSettings.badgeTextSizePercent, 100)
            DockSettings.badgeDisplayMode = 0
            DockSettings.badgeFontWeight = 500
            DockSettings.badgeTextSizePercent = 100
            const states = [
                { IsActive: true, IsMinimized: false },
                { IsActive: false, IsMinimized: false },
                { IsActive: false, IsMinimized: true },
            ]
            const weights = [400, 500, 600, 700]
            const sizes = [75, 100, 125]

            for (let s = 0; s < states.length; ++s) {
                DockSettings.badgeFontWeight = 500
                DockSettings.badgeTextSizePercent = 100
                const item = makeItem(Object.assign({ IsWindow: true }, states[s]))
                NotificationTracker.setUnread("org.kde.dolphin", 42)
                tryCompare(item, "_badgeCount", 42)
                const label = T.badgeLabel(item)
                compare(label.font.weight, 500)
                DockSettings.badgeFontWeight = 700
                compare(label.font.weight, 700)
                for (let w = 0; w < weights.length; ++w) {
                    DockSettings.badgeFontWeight = weights[w]
                    compare(label.font.weight, weights[w])
                    for (let z = 0; z < sizes.length; ++z) {
                        DockSettings.badgeTextSizePercent = sizes[z]
                        const expectedSize = label.parent.height * 0.55 * sizes[z] / 100
                            * item._iconDiagBadgeLabelScale
                        verify(label.font.pixelSize > 0 && label.font.pixelSize <= expectedSize + 0.01,
                               `requested ${expectedSize}, fitted ${label.font.pixelSize}`)
                        verify(label.width > 0 && label.height > 0)
                    }
                }
                DockModel.reset()
                NotificationTracker.reset()
            }
        }

        function test_badgeTypographyFitsStressCountsAcrossZoomAndIconSizes() {
            DockSettings.badgeDisplayMode = 0
            const item = makeItem({ IsWindow: true, IsActive: true })
            NotificationTracker.setUnread("org.kde.dolphin", 999)
            tryCompare(item, "_badgeCount", 999)
            const badge = T.badge(item)
            const label = T.badgeLabel(item)
            const texts = ["1", "42", "999", "999+"]
            const sizes = [24, 40, 64, 96]
            const zooms = [1.0, 1.3, 1.5, 1.7]
            const weights = [400, 500, 600, 700]
            const percentages = [75, 100, 125]

            for (let s = 0; s < sizes.length; ++s) {
                DockSettings.iconSize = sizes[s]
                for (let t = 0; t < texts.length; ++t) {
                    label.text = texts[t]
                    for (let w = 0; w < weights.length; ++w) {
                        DockSettings.badgeFontWeight = weights[w]
                        for (let p = 0; p < percentages.length; ++p) {
                            DockSettings.badgeTextSizePercent = percentages[p]
                            for (let z = 0; z < zooms.length; ++z) {
                                item.zoomScale = zooms[z]
                                verify(label.contentWidth <= label.width + 0.5,
                                       `${texts[t]}, ${sizes[s]} px, ${weights[w]}, ${percentages[p]}%, zoom ${zooms[z]}: content ${label.contentWidth} > box ${label.width}, font ${label.font.pixelSize}`)
                                verify(label.contentHeight <= label.height + 0.5,
                                       `${texts[t]}, ${sizes[s]} px, ${weights[w]}, ${percentages[p]}%, zoom ${zooms[z]}: text height overflow`)
                                const badgeCenter = badge.mapToItem(item, badge.width / 2, badge.height / 2)
                                const labelCenter = label.mapToItem(item, label.width / 2, label.height / 2)
                                verify(Math.abs(badgeCenter.x - labelCenter.x) < 0.02)
                                verify(Math.abs(badgeCenter.y - labelCenter.y) < 0.02)
                            }
                        }
                    }
                }
            }
            label.text = "99+"
            item.zoomScale = 1
        }

        function test_badgeTextUsesQtRenderingAndSeparateCircleShadow() {
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 8)
            tryCompare(item, "_badgeCount", 8)

            const badge = T.badge(item)
            const label = T.badgeLabel(item)
            const shadow = T.findFirst(item, o => o.objectName === "badgeShadowSource")
            verify(shadow, "separate badge shadow source not found")
            compare(label.renderType, Text.QtRendering)
            compare(badge.layer.enabled, false,
                    "badge text and circle must not be baked into a scaled texture")
            verify(shadow.visible, "circle shadow remains enabled in production mode")
            compare(shadow.layer.enabled, true)
            verify(BadgeTextColor.contrastRatio(label.color, badge.color) >= 4.5,
                   "badge text must meet WCAG contrast against the opaque badge fill")
        }

        function test_badgeTextColorPrefersThemeColorWhenReadable() {
            const light = Qt.rgba(1, 1, 1, 1)
            const dark = Qt.rgba(0, 0, 0, 1)
            compare(BadgeTextColor.choose(light, dark), dark)
            compare(BadgeTextColor.choose(dark, light), light)
        }

        function test_badgeTextColorFallbackMeetsContrastAtLuminanceBoundaries_data() {
            return [
                { tag: "black", level: 0.0 },
                { tag: "dark-boundary", level: 0.175 },
                { tag: "wcag-crossover", level: 0.179 },
                { tag: "light-boundary", level: 0.1833 },
                { tag: "mid-gray", level: 0.5 },
                { tag: "white", level: 1.0 },
            ]
        }

        function test_badgeTextColorFallbackMeetsContrastAtLuminanceBoundaries(data) {
            const background = Qt.rgba(data.level, data.level, data.level, 1)
            const preferred = Qt.rgba(1, 1, 1, 1)
            const result = BadgeTextColor.choose(background, preferred)
            const renderedColor = typeof result === "string" ? Qt.color(result) : result
            verify(BadgeTextColor.contrastRatio(renderedColor, background) >= 4.5,
                   `contrast ${BadgeTextColor.contrastRatio(renderedColor, background)} at level ${data.level}`)
        }

        function test_badgeTextColorReactsToThemeChanges() {
            const binding = createTemporaryObject(badgeThemeBindingComponent, tc)
            verify(binding)
            compare(binding.chosenForeground, "#000000",
                    "light badge fill should fall back to a dark foreground")
            binding.background = "#202020"
            tryCompare(binding, "chosenForeground", "#ffffff")
        }

        function test_badgeTextGeometryRemainsCenteredAcrossSizesZoomAndDpr() {
            const iconSizes = [24, 32, 40, 48, 64, 96]
            const zooms = [1.0, 1.125, 1.25, 1.5, 1.7]
            const dprs = [1.0, 1.25, 1.5, 2.0]
            DockSettings.badgeDisplayMode = 0
            const item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 42)
            tryCompare(item, "_badgeCount", 42)
            const badge = T.badge(item)
            const label = T.badgeLabel(item)

            for (let s = 0; s < iconSizes.length; ++s) {
                DockSettings.iconSize = iconSizes[s]
                tryCompare(badge, "width", Math.round(iconSizes[s] * 0.38))
                item.zoomScale = 1
                const expectedCenter = badge.mapToItem(item, badge.width / 2, badge.height / 2)
                const labelCenter = label.mapToItem(item, label.width / 2, label.height / 2)
                verify(Math.abs(labelCenter.x - expectedCenter.x) < 0.01)
                verify(Math.abs(labelCenter.y - expectedCenter.y) < 0.01)

                for (let z = 0; z < zooms.length; ++z) {
                    item.zoomScale = zooms[z]
                    const mappedBadgeCenter = badge.mapToItem(stage, badge.width / 2,
                                                              badge.height / 2)
                    const mappedLabelCenter = label.mapToItem(stage, label.width / 2,
                                                              label.height / 2)
                    verify(Math.abs(mappedLabelCenter.x - mappedBadgeCenter.x) < 0.02)
                    verify(Math.abs(mappedLabelCenter.y - mappedBadgeCenter.y) < 0.02)
                    for (let d = 0; d < dprs.length; ++d) {
                        const physicalXDelta = (mappedLabelCenter.x - mappedBadgeCenter.x) * dprs[d]
                        const physicalYDelta = (mappedLabelCenter.y - mappedBadgeCenter.y) * dprs[d]
                        verify(Math.abs(physicalXDelta) < 0.03)
                        verify(Math.abs(physicalYDelta) < 0.03)
                    }
                }
            }
        }

        function test_stableCrispBadgeKeepsTextCenteredAndMetricsFixed_data() {
            return [
                { tag: "1", count: 1, text: "1" },
                { tag: "8", count: 8, text: "8" },
                { tag: "11", count: 11, text: "11" },
                { tag: "68", count: 68, text: "68" },
                { tag: "99", count: 99, text: "99" },
                { tag: "100-plus", count: 100, text: "99+" },
            ]
        }

        function test_stableCrispBadgeKeepsTextCenteredAndMetricsFixed(data) {
            IconDiagnostics.debugEnabled = true
            IconDiagnostics.testBadgeCrispStable = false
            DockSettings.iconSize = 40
            DockSettings.maxZoomFactor = 1.7
            DockSettings.badgeDisplayMode = 0

            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", data.count)
            tryCompare(item, "_badgeCount", data.count)

            const badge = T.badge(item)
            const label = T.badgeLabel(item)
            compare(label.text, data.text)

            // Record the stock Text.Fit setup, then enable Stable Crisp without
            // changing the glyph size or text box at rest (zoom = 1).
            const stockMetrics = [label.width, label.height, label.implicitWidth,
                                  label.implicitHeight, label.contentWidth,
                                  label.contentHeight, label.baselineOffset,
                                  label.font.pixelSize, label.minimumPixelSize]
            IconDiagnostics.testBadgeCrispStable = true
            tryCompare(item, "_iconDiagCrispBadgeStable", true)
            for (let j = 0; j < stockMetrics.length; ++j) {
                const current = [label.width, label.height, label.implicitWidth,
                                 label.implicitHeight, label.contentWidth,
                                 label.contentHeight, label.baselineOffset,
                                 label.font.pixelSize, label.minimumPixelSize][j]
                verify(Math.abs(current - stockMetrics[j]) < 0.01,
                       `Stable Crisp must match stock text metrics at rest, metric ${j}: ${current} vs ${stockMetrics[j]}`)
            }
            verify(!badge.layer.enabled, "crisp diagnostic must keep text outside the badge texture")

            const zooms = [1.0, 1.125, 1.25, 1.5, 1.7]
            let initial = null
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                const restWidth = item.width
                const restHeight = item.height
                for (let i = 0; i < zooms.length; ++i) {
                    item.zoomScale = zooms[i]
                    tryCompare(item, "currentScale", zooms[i])
                    compare(item.width, restWidth, "zoom must not resize the dock layout cell")
                    compare(item.height, restHeight, "zoom must not resize the dock layout cell")
                    let badgeCenter = badge.mapToItem(item, badge.width / 2, badge.height / 2)
                    let labelCenter = label.mapToItem(item, label.width / 2, label.height / 2)
                    let labelParentCenter = label.mapToItem(badge, label.width / 2, label.height / 2)
                    verify(Math.abs(badgeCenter.x - labelCenter.x) < 0.01,
                           `horizontal center differs at edge ${edge}, zoom ${zooms[i]}: badge=${badgeCenter.x}, label=${labelCenter.x}, label local=${label.x}+${label.width / 2}, parent mapped=${labelParentCenter.x}, badge x/w=${badge.x}/${badge.width}`)
                    verify(Math.abs(badgeCenter.y - labelCenter.y) < 0.01,
                           `vertical center differs at edge ${edge}, zoom ${zooms[i]}: badge=${badgeCenter.y}, label=${labelCenter.y}`)

                    const metrics = [label.width, label.height, label.implicitWidth,
                                     label.implicitHeight, label.contentWidth,
                                     label.contentHeight, label.baselineOffset,
                                     label.font.pixelSize, label.minimumPixelSize]
                    if (initial === null) {
                        initial = metrics
                    } else {
                        for (let j = 0; j < metrics.length; ++j) {
                            verify(Math.abs(metrics[j] - initial[j]) < 0.01,
                                   `text metric ${j} changed at edge ${edge}, zoom ${zooms[i]}: ${metrics[j]} vs ${initial[j]}`)
                        }
                    }
                    const badgeTopLeft = badge.mapToItem(stage, 0, 0)
                    const badgeBottomRight = badge.mapToItem(stage, badge.width, badge.height)
                    verify(Math.abs(Math.abs(badgeBottomRight.x - badgeTopLeft.x)
                                    - badge.width * zooms[i]) < 0.02,
                           `badge width must grow with the icon at edge ${edge}, zoom ${zooms[i]}`)
                    verify(Math.abs(Math.abs(badgeBottomRight.y - badgeTopLeft.y)
                                    - badge.height * zooms[i]) < 0.02,
                           `badge height must grow with the icon at edge ${edge}, zoom ${zooms[i]}`)
                    const labelTopLeft = label.mapToItem(stage, 0, 0)
                    const labelBottomRight = label.mapToItem(stage, label.width, label.height)
                    verify(Math.abs(Math.abs(labelBottomRight.x - labelTopLeft.x)
                                    - label.width * zooms[i]) < 0.02,
                           `text box width must grow with the icon at edge ${edge}, zoom ${zooms[i]}`)
                    verify(Math.abs(Math.abs(labelBottomRight.y - labelTopLeft.y)
                                    - label.height * zooms[i]) < 0.02,
                           `text box height must grow with the icon at edge ${edge}, zoom ${zooms[i]}`)
                }
            }
        }

        function test_crispBadgeSwitchesHaveNoEffectWithoutDebugGate() {
            IconDiagnostics.testBadgeCrispStable = true
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 8)
            tryCompare(item, "_badgeCount", 8)
            compare(item._iconDiagCrispBadgeStable, false)
            compare(T.badge(item).layer.enabled, false,
                    "production badge text is unlayered independently of debug switches")
        }

        function test_badgeOverlayUsesMappedVisualGeometryWithoutResizingCell_data() {
            return [
                { tag: "1", count: 1 },
                { tag: "8", count: 8 },
                { tag: "11", count: 11 },
                { tag: "68", count: 68 },
                { tag: "99", count: 99 },
                { tag: "99-plus", count: 100 },
            ]
        }

        function test_badgeOverlayUsesMappedVisualGeometryWithoutResizingCell(data) {
            IconDiagnostics.debugEnabled = true
            IconDiagnostics.testBadgeOverlay = true
            DockSettings.iconSize = 40
            DockSettings.maxZoomFactor = 1.7
            DockSettings.badgeDisplayMode = 0

            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", data.count)
            tryCompare(item, "_badgeCount", data.count)
            tryCompare(item, "badgeOverlayVisible", true)
            tryCompare(item, "width", 40)
            const badge = T.badge(item)

            // Simulated DPR factors exercise the logical-to-physical invariant;
            // the actual GPU/text rasterization still requires a manual session.
            const dprs = [1.0, 1.25, 1.5, 2.0]
            const zooms = [1.0, 1.125, 1.25, 1.5, 1.7]
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                wait(0)
                const cellWidth = item.width
                const cellHeight = item.height
                for (let i = 0; i < zooms.length; ++i) {
                    item.zoomScale = zooms[i]
                    const mapped = item.badgeOverlayRectIn(stage)
                    const p1 = badge.mapToItem(stage, 0, 0)
                    const p2 = badge.mapToItem(stage, badge.width, badge.height)
                    compare(item.width, cellWidth)
                    compare(item.height, cellHeight)
                    verify(Math.abs(mapped.width - Math.abs(p2.x - p1.x)) < 0.02)
                    verify(Math.abs(mapped.height - Math.abs(p2.y - p1.y)) < 0.02)
                    const mappedCenter = Qt.point(mapped.x + mapped.width / 2,
                                                  mapped.y + mapped.height / 2)
                    const badgeCenter = badge.mapToItem(stage, badge.width / 2,
                                                       badge.height / 2)
                    verify(Math.abs(mappedCenter.x - badgeCenter.x) < 0.02)
                    verify(Math.abs(mappedCenter.y - badgeCenter.y) < 0.02)
                    for (let d = 0; d < dprs.length; ++d) {
                        const physicalCenter = Qt.point(mappedCenter.x * dprs[d],
                                                        mappedCenter.y * dprs[d])
                        verify(Math.abs(physicalCenter.x / dprs[d] - mappedCenter.x) < 0.001)
                        verify(Math.abs(physicalCenter.y / dprs[d] - mappedCenter.y) < 0.001)
                    }
                }
            }
        }

        function test_badgeOnlyForMatchingAppId() {
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.konsole", 3)
            compare(item._badgeCount, 0)
            verify(!T.badge(item).visible)
        }

        function test_badgeDisplayMode_data() {
            return [
                { tag: "number", mode: 0, visible: true, label: true, sizeFactor: 0.38 },
                { tag: "dot", mode: 1, visible: true, label: false, sizeFactor: 0.18 },
                { tag: "off", mode: 2, visible: false, label: false, sizeFactor: 0.18 },
            ]
        }

        function test_badgeDisplayMode(data) {
            DockSettings.badgeDisplayMode = data.mode
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 5)
            tryCompare(item, "_badgeCount", 5)
            let badge = T.badge(item)
            compare(badge.visible, data.visible)
            if (data.visible) {
                compare(T.badgeLabel(item).visible, data.label)
                compare(badge.width, Math.round(DockSettings.iconSize * data.sizeFactor))
                compare(badge.height, badge.width)
            }
        }

        function test_badgeScalesWithIconSize() {
            DockSettings.iconSize = 96
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 2)
            tryCompare(item, "_badgeCount", 2)
            compare(T.badge(item).width, Math.round(96 * 0.38))
        }

        function test_launcherEntryCountTakesPriority() {
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 3)
            tryCompare(item, "_badgeCount", 3)
            LauncherEntryTracker.setEntry(launcherUrl, { count: 7, countVisible: true })
            tryCompare(item, "_badgeCount", 7)
            compare(T.badgeLabel(item).text, "7")
            LauncherEntryTracker.setEntry(launcherUrl, { countVisible: false })
            tryCompare(item, "_badgeCount", 3)
        }

        function test_launcherEntryIsPerApp() {
            let item = makeItem({ IsWindow: true })
            LauncherEntryTracker.setEntry("applications:org.kde.konsole.desktop", { count: 5, countVisible: true, progress: 40, progressVisible: true })
            compare(item._badgeCount, 0)
            verify(!T.badge(item).visible)
            verify(!T.progressBar(item).visible)
        }

        function test_launcherEntryBadgeStaysVisibleDuringDoNotDisturb() {
            NotificationTracker.dndActive = true
            let item = makeItem({ IsWindow: true })
            LauncherEntryTracker.setEntry(launcherUrl, { count: 2, countVisible: true })
            tryCompare(item, "_badgeCount", 2)
            verify(T.badge(item).visible)
        }

        function test_progressBarFollowsLauncherEntry() {
            let item = makeItem({ IsWindow: true })
            let bar = T.progressBar(item)
            verify(bar, "progress bar not found")
            verify(!bar.visible)
            LauncherEntryTracker.setEntry(launcherUrl, { progress: 50, progressVisible: true })
            tryVerify(() => bar.visible)
            let fill = bar.children[0]
            tryCompare(fill, "width", bar.width * 0.5)
            LauncherEntryTracker.setEntry(launcherUrl, { progressVisible: false })
            tryVerify(() => !bar.visible)
        }

        function test_activatingWindowClearsTrackerBadge() {
            let item = makeItem({ IsWindow: true, IsActive: false })
            NotificationTracker.setUnread("org.kde.dolphin", 4)
            tryCompare(item, "_badgeCount", 4)
            DockModel.tasksModel.setTaskData(0, "IsActive", true)
            tryCompare(item, "_badgeCount", 0)
            compare(NotificationTracker.callsTo("clearUnreadNotifications").length, 1)
            compare(NotificationTracker.callsTo("clearUnreadNotifications")[0].args[0], "org.kde.dolphin")
            verify(!T.badge(item).visible)
        }

        // --- Attention ---

        function test_demandingAttentionStartsAnimation() {
            DockSettings.attentionAnimation = 1
            let item = makeItem({ IsWindow: true })
            verify(!item._showAttentionAnim)
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            tryCompare(item, "_showAttentionAnim", true)
        }

        function test_attentionSourcesTrigger_data() {
            return [{ tag: "badge-increase" }, { tag: "sni-needs-attention" }, { tag: "launcher-entry-urgent" }]
        }

        function test_attentionSourcesTrigger(data) {
            DockSettings.attentionAnimation = 3
            let item = makeItem({ IsWindow: true })
            verify(!item._showAttentionAnim)
            if (data.tag === "badge-increase")
                NotificationTracker.setUnread("org.kde.dolphin", 1)
            else if (data.tag === "sni-needs-attention")
                NotificationTracker.setSniAttention("org.kde.dolphin", true)
            else
                LauncherEntryTracker.setEntry(launcherUrl, { urgent: true })
            tryCompare(item, "_showAttentionAnim", true)
        }

        function test_attentionAnimationDisabledBySetting() {
            DockSettings.attentionAnimation = 0
            let item = makeItem({ IsWindow: true })
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            tryCompare(item, "_isDemandingAttention", true)
            verify(!item._showAttentionAnim)
        }

        function test_doNotDisturbSuppressesAnimationButKeepsBadge() {
            DockSettings.attentionAnimation = 1
            NotificationTracker.dndActive = true
            let item = makeItem({ IsWindow: true })
            NotificationTracker.setUnread("org.kde.dolphin", 2)
            tryCompare(item, "_badgeCount", 2)
            verify(T.badge(item).visible)
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            tryCompare(item, "_isDemandingAttention", true)
            verify(!item._showAttentionAnim)
        }

        function test_attentionAnimationStopsAfterDuration() {
            DockSettings.attentionAnimation = 2
            DockSettings.attentionAnimationDuration = 1
            let item = makeItem({ IsWindow: true })
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            tryCompare(item, "_showAttentionAnim", true)
            tryCompare(item, "_showAttentionAnim", false, 3000)
        }

        function test_blinkAnimationRestoresIconOpacity() {
            DockSettings.attentionAnimation = 6
            DockSettings.attentionAnimationDuration = 1
            let item = makeItem({ IsWindow: true, IsActive: true })
            let icon = T.iconImage(item)
            DockModel.tasksModel.setTaskData(0, "IsDemandingAttention", true)
            tryVerify(() => item._blinkOpacity < 1.0, 2000, "blink never dimmed the icon")
            tryCompare(item, "_showAttentionAnim", false, 3000)
            compare(item._blinkOpacity, 1.0)
            tryCompare(icon, "opacity", 1.0)
        }

        // --- Accessibility summary ---

        function test_accessibleDescription_data() {
            return [
                { tag: "none", roles: { IsWindow: true }, unread: 0, expect: "" },
                { tag: "pinned-active", roles: { IsWindow: true, IsLauncher: true, IsActive: true }, unread: 0, expect: "Pinned, Active" },
                { tag: "minimized", roles: { IsWindow: true, IsMinimized: true }, unread: 0, expect: "Minimized" },
                { tag: "windows", roles: { IsWindow: true, ChildCount: 3 }, unread: 0, expect: "3 windows" },
                { tag: "notifications", roles: { IsWindow: true }, unread: 4, expect: "4 notifications" },
                { tag: "attention", roles: { IsWindow: true, IsDemandingAttention: true }, unread: 0, expect: "Attention requested" },
            ]
        }

        function test_accessibleDescription(data) {
            let item = makeItem(data.roles)
            if (data.unread > 0) NotificationTracker.setUnread("org.kde.dolphin", data.unread)
            tryCompare(item, "accessibleDescription", data.expect)
            compare(item.displayName, "Dolphin")
        }
    }
}
