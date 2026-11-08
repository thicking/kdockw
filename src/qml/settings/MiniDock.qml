// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import ".."

// Lifelike miniature of the dock: real theme icons on the panel background,
// drawn at `unit` preview pixels per real pixel. Every look property defaults
// to the live setting and can be overridden (e.g. a picker tile showing one
// option). Hovering the miniature zooms the icons under the pointer like the
// dock; `hoveredIndex` forces the zoom on one icon.
//
// Placed inside a DesktopStage it sits on the stage's screen edge:
//
//     DesktopStage {
//         id: stage
//         MiniDock {
//             unit: stage.unit
//             backdrop: stage.backdrop
//             active: stage.active
//         }
//     }
//
// `focusIcon`, `spacingMarker`, `panelItem` and `floatingMarker` are items
// whose geometry is the measured thing; pass them to DesktopStage's
// measurement overlay.
Item {
    id: dock

    /// Preview pixels per real pixel.
    property real unit: 1.0
    /// 0 Top, 1 Bottom, 2 Left, 3 Right.
    property int edge: DockSettings.edge

    property real iconSize: DockSettings.iconSize
    property real iconSpacing: DockSettings.iconSpacing
    property real contentPaddingLeft: DockSettings.contentPaddingLeft
    property real contentPaddingRight: DockSettings.contentPaddingRight
    property real contentPaddingTop: DockSettings.contentPaddingTop
    property real contentPaddingBottom: DockSettings.contentPaddingBottom
    /// 0 Start, 1 Center, 2 End along the dock's long axis.
    property int contentAlignment: DockSettings.contentAlignment
    property real maxZoomFactor: DockSettings.maxZoomFactor
    /// 0 Classic, 1 Spring.
    property int magnificationMode: DockSettings.magnificationMode
    /// 0 Parabolic, 1 In place.
    property int zoomStyle: DockSettings.zoomStyle
    property real iconScale: DockSettings.iconScale
    property bool iconNormalization: DockSettings.iconNormalization
    property real cornerRadius: DockSettings.cornerRadius
    property bool floating: DockSettings.floating
    property int floatingMargin: DockSettings.floatingMargin
    /// 0 Panel Inherit, 1 Transparent, 2 Tinted, 3 Acrylic.
    property int backgroundStyle: DockSettings.backgroundStyle
    property real backgroundOpacity: DockSettings.backgroundOpacity
    property bool useAccentColor: DockSettings.useAccentColor
    property bool useSystemColor: DockSettings.useSystemColor
    property color tintColor: DockSettings.tintColor
    property real iconOpacity: DockSettings.iconOpacity
    property real otherDesktopOpacity: DockSettings.otherDesktopOpacity
    /// 0 Number, 1 Dot, 2 Off.
    property int badgeDisplayMode: DockSettings.badgeDisplayMode
    property color badgeBackgroundColor: DockSettings.badgeBackgroundColor
    property color badgeTextColor: DockSettings.badgeTextColor
    property int badgeFontWeight: DockSettings.badgeFontWeight
    property int badgeTextSizePercent: DockSettings.badgeTextSizePercent
    property int runningIndicatorStyle: DockSettings.runningIndicatorStyle
    /// 0 Screen edge, 1 Dock interior.
    property int runningIndicatorPosition: DockSettings.runningIndicatorPosition
    property int runningIndicatorSize: DockSettings.runningIndicatorSize
    property int runningIndicatorColorMode: DockSettings.runningIndicatorColorMode
    property color runningIndicatorColor: DockSettings.runningIndicatorColor

    /// Dock entries: icon name, fallback icon, window state ("active",
    /// "inactive", "minimized" or "launcher"), badge count and the simulated
    /// internal padding (icon fill ratio) that icon size normalization removes.
    property var apps: [
        { icon: "org.kde.dolphin", fallback: "system-file-manager", state: "inactive", badge: 0, padding: 1.0 },
        { icon: "org.kde.konsole", fallback: "utilities-terminal", state: "active", badge: 0, padding: 1.0 },
        { icon: "org.kde.kate", fallback: "accessories-text-editor", state: "minimized", badge: 0, padding: 0.82 },
        { icon: "firefox", fallback: "org.kde.falkon", state: "inactive", badge: 0, padding: 1.0 },
        { icon: "systemsettings", fallback: "preferences-system", state: "launcher", badge: 0, padding: 0.88 },
        { icon: "org.kde.discover", fallback: "system-software-install", state: "launcher", badge: 3, padding: 1.0 }
    ]

    /// Item drawn behind the dock (the stage wallpaper), blurred under the
    /// Panel Inherit and Acrylic styles. Must share the dock's parent
    /// coordinates with its origin at the parent's origin.
    property Item backdrop: null
    /// Looping demo animations may run (pause while the window is hidden).
    property bool active: true
    /// Pointer movement over the miniature drives hover zoom when enabled.
    property bool interactiveHover: true
    /// Icon zoomed as if hovered while the pointer is elsewhere (-1: none).
    property int hoveredIndex: -1
    /// Zoom in and out on `focusIndex` in a loop (picker previews).
    property bool pulse: false
    /// Icon not drawn, for a page that draws its own animated copy in its
    /// place (-1: none). Its cell, indicator and badge stay.
    property int hiddenIconIndex: -1

    /// Zoom transition timing: effective milliseconds and Easing.Type values.
    property int zoomInDuration: zoomProfile.effectiveZoomInDuration
    property int zoomOutDuration: zoomProfile.effectiveZoomOutDuration
    property int zoomInEasing: zoomProfile.zoomInEasingType
    property int zoomOutEasing: zoomProfile.zoomOutEasingType

    readonly property bool vertical: edge === 2 || edge === 3
    readonly property int count: apps.length
    readonly property int middleIndex: Math.floor(count / 2)
    /// Icon the measurement markers refer to.
    readonly property int focusIndex: hoveredIndex >= 0 ? Math.min(hoveredIndex, count - 1) : middleIndex
    /// The pointer is over the miniature.
    readonly property bool hovered: hoverArea.containsMouse

    /// Length of the resting dock along its edge in real pixels.
    readonly property real primaryLeadingPadding: vertical ? contentPaddingTop : contentPaddingLeft
    readonly property real primaryTrailingPadding: vertical ? contentPaddingBottom : contentPaddingRight
    readonly property real crossPaddingTotal: vertical
        ? contentPaddingLeft + contentPaddingRight
        : contentPaddingTop + contentPaddingBottom
    readonly property real restContentLengthReal: count * iconSize + Math.max(0, count - 1) * iconSpacing
    readonly property real restLengthReal: Math.max(
        restContentLengthReal + primaryLeadingPadding + primaryTrailingPadding,
        Kirigami.Units.gridUnit * 6)

    /// Bounds of the focus icon at its current zoom.
    readonly property Item focusIcon: {
        // itemAt() is not observable; re-evaluate when delegates change.
        if (repeater.count <= focusIndex) {
            return null
        }
        const slot = repeater.itemAt(focusIndex)
        return slot ? slot.iconBox : null
    }
    /// The gap after the focus icon (before it for the last icon).
    readonly property Item spacingMarker: spacingMarkerItem
    /// The panel background.
    readonly property Item panelItem: background
    /// The gap between the panel and the screen edge (floating).
    readonly property Item floatingMarker: floatingMarkerItem

    // Geometry in preview pixels. Padding and floating margin mirror
    // main.qml (largeSpacing around the icons) and DockView::floatingPadding.
    readonly property real iconPx: iconSize * unit
    readonly property real gapPx: iconSpacing * unit
    readonly property real padPx: crossPaddingTotal * unit
    readonly property real indicatorReservePx: runningIndicatorSize * 2 * unit
    readonly property bool indicatorAfterIcon: {
        const screenSideAfter = edge === 1 || edge === 3
        return runningIndicatorPosition === 0 ? screenSideAfter : !screenSideAfter
    }
    readonly property real floatPx: floating ? floatingMargin * unit : 0
    readonly property real pitch: iconPx + gapPx
    readonly property real thickness: iconPx + padPx + indicatorReservePx
    readonly property real length: restLengthReal * unit
    readonly property real primaryParentExtent: vertical ? (parent ? parent.height : 0)
                                                          : (parent ? parent.width : 0)
    readonly property real primaryDockOrigin: vertical ? y : x
    readonly property real restContentLength: count * iconPx + Math.max(0, count - 1) * gapPx
    readonly property real restStart: {
        const available = Math.max(0, length - (primaryLeadingPadding + primaryTrailingPadding) * unit - restContentLength)
        const alignFactor = contentAlignment === 0 ? 0 : contentAlignment === 2 ? 1 : 0.5
        return primaryLeadingPadding * unit + available * alignFactor
    }
    // How far zoomed icons reach past the panel, away from the edge.
    readonly property real zoomOverflow: iconPx * Math.max(0, maxZoomFactor - 1.0)

    width: vertical ? thickness : length
    height: vertical ? length : thickness
    x: parent ? (vertical ? (edge === 2 ? floatPx : parent.width - width - floatPx) : (parent.width - width) / 2) : 0
    y: parent ? (vertical ? (parent.height - height) / 2 : (edge === 0 ? floatPx : parent.height - height - floatPx)) : 0

    Accessible.ignored: true

    ZoomAnimationProfile {
        id: zoomProfile
    }

    // --- Hover zoom (same layout as the dock's computeDockZoom) ---

    property bool _pulseOn: false
    readonly property bool zoomed: (interactiveHover && hoverArea.containsMouse)
        || hoveredIndex >= 0 || _pulseOn
    readonly property real _staticCursor: focusIndex * pitch + iconPx / 2
    // Cursor in rest-row coordinates (0 = start of the first icon). Kept when
    // the pointer leaves so the zoom collapses where it left, as in the dock.
    property real _mouseCursor: _staticCursor
    // Not readonly: the Behavior intercepts its writes.
    property real cursor: hoverArea.containsMouse ? _mouseCursor : _staticCursor
    Behavior on cursor {
        enabled: !hoverArea.containsMouse
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
    }

    // 0 = rest, 1 = full zoom.
    property real classicZoomAmount: zoomed && maxZoomFactor > 1.0 ? 1.0 : 0.0
    Behavior on classicZoomAmount {
        id: zoomBehavior
        enabled: dock.zoomInDuration > 0 || dock.zoomOutDuration > 0
        NumberAnimation {
            duration: zoomBehavior.targetValue > 0.5 ? dock.zoomInDuration : dock.zoomOutDuration
            easing.type: zoomBehavior.targetValue > 0.5 ? dock.zoomInEasing : dock.zoomOutEasing
        }
    }
    SpringZoomController {
        id: springZoom
        objectName: "miniDockSpringZoomController"
    }
    readonly property real zoomAmount: magnificationMode === 1
        ? springZoom.amount : classicZoomAmount
    readonly property real layoutCursor: magnificationMode === 1
        ? springZoom.cursor : cursor

    function updateSpringTarget() {
        if (magnificationMode !== 1) return
        springZoom.setTarget(cursor, zoomed && maxZoomFactor > 1.0 ? 1.0 : 0.0,
            DockSettings.springStiffness, DockSettings.springDamping,
            DockSettings.springSpeed, 0, vertical ? height : width)
    }
    onCursorChanged: updateSpringTarget()
    onZoomedChanged: updateSpringTarget()
    onWidthChanged: updateSpringTarget()
    onHeightChanged: updateSpringTarget()
    onMaxZoomFactorChanged: updateSpringTarget()
    onEdgeChanged: updateSpringTarget()
    onMagnificationModeChanged: {
        if (magnificationMode === 1) {
            springZoom.synchronize(cursor, classicZoomAmount)
            updateSpringTarget()
        } else {
            springZoom.synchronize(cursor, 0)
        }
    }
    Component.onCompleted: {
        springZoom.synchronize(cursor, classicZoomAmount)
        updateSpringTarget()
    }
    Connections {
        target: DockSettings
        function onSpringStiffnessChanged() { dock.updateSpringTarget() }
        function onSpringDampingChanged() { dock.updateSpringTarget() }
        function onSpringSpeedChanged() { dock.updateSpringTarget() }
    }

    // Scales/offsets/growth from the same computeDockZoom the dock uses
    // (via SettingsWindow.zoomLayout), in the rest frame of the row
    // (0 = leading edge of the first icon; the panel's rest edges are the
    // background bounds). The growth is split between both ends, so far
    // icons and the background edges stay still while the pointer moves.
    readonly property var zoomLayout: SettingsWindow.zoomLayout(
        count, 0,
        iconPx, gapPx,
        -1, 0,
        -restStart, length - restStart,
        1.0 + (maxZoomFactor - 1.0) * zoomAmount,
        zoomStyle,
        zoomAmount > 0,
        layoutCursor,
        -primaryDockOrigin - restStart,
        primaryParentExtent - primaryDockOrigin - restStart)

    SequentialAnimation {
        id: pulseAnimation
        running: dock.pulse && dock.active
        loops: Animation.Infinite
        onRunningChanged: if (!running) dock._pulseOn = false

        PauseAnimation { duration: 500 }
        PropertyAction { target: dock; property: "_pulseOn"; value: true }
        PauseAnimation { duration: dock.zoomInDuration + 700 }
        PropertyAction { target: dock; property: "_pulseOn"; value: false }
        PauseAnimation { duration: dock.zoomOutDuration }
    }
    function _restartPulse() {
        if (pulseAnimation.running) {
            pulseAnimation.restart()
        }
    }
    onZoomInDurationChanged: _restartPulse()
    onZoomOutDurationChanged: _restartPulse()

    // --- Panel background (mirrors computeBackgroundColor()) ---

    Item {
        id: headerColors
        visible: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Header
        Kirigami.Theme.inherit: false
    }

    Item {
        id: accentColors
        visible: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Selection
        Kirigami.Theme.inherit: false
    }

    Item {
        id: background

        readonly property bool blurred: (dock.backgroundStyle === 0 || dock.backgroundStyle === 3) && dock.backdrop !== null
        readonly property color baseColor: dock.backgroundStyle === 2 && !dock.useSystemColor
            ? dock.tintColor
            : (dock.useAccentColor ? accentColors.Kirigami.Theme.backgroundColor
                                   : headerColors.Kirigami.Theme.backgroundColor)
        readonly property color panelColor: Qt.alpha(baseColor, dock.backgroundStyle === 1 ? 0.0 : dock.backgroundOpacity)
        readonly property real radius: Math.min(dock.thickness / 2, dock.cornerRadius * dock.unit)

        // Rests on the panel extent and grows by the zoom layout's growth
        // on each side (Parabolic only; In place never grows it).
        readonly property real leadingGrowth: dock.zoomLayout.leadingGrowth ?? 0
        readonly property real trailingGrowth: dock.zoomLayout.trailingGrowth ?? 0

        x: dock.vertical ? 0 : -leadingGrowth
        y: dock.vertical ? -leadingGrowth : 0
        width: dock.vertical ? dock.thickness : dock.length + leadingGrowth + trailingGrowth
        height: dock.vertical ? dock.length + leadingGrowth + trailingGrowth : dock.thickness
        visible: dock.backgroundStyle !== 1

        ShaderEffectSource {
            id: backdropSource
            visible: false
            sourceItem: background.blurred ? dock.backdrop : null
            sourceRect: Qt.rect(dock.x + background.x, dock.y + background.y, background.width, background.height)
        }

        Rectangle {
            id: backgroundMask
            anchors.fill: parent
            visible: false
            radius: background.radius
            color: Kirigami.Theme.textColor
            layer.enabled: background.blurred
        }

        MultiEffect {
            anchors.fill: parent
            visible: background.blurred
            source: backdropSource
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 32
            maskEnabled: true
            maskSource: backgroundMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle {
            anchors.fill: parent
            visible: dock.backgroundStyle !== 3
            radius: background.radius
            color: background.panelColor
        }

        // Acrylic: the dock's own tint + noise overlay (see main.qml).
        ShaderEffect {
            anchors.fill: parent
            visible: dock.backgroundStyle === 3
            property real tintR: background.panelColor.r
            property real tintG: background.panelColor.g
            property real tintB: background.panelColor.b
            property real tintOpacity: background.panelColor.a
            property real noiseStrength: 0.02
            property real resX: width
            property real resY: height
            property real cornerRadius: background.radius
            fragmentShader: "qrc:/qml/shaders/acrylic_overlay.frag.qsb"
        }
    }

    // --- Icons ---

    // Static rest-position container (rest frame: its primary-axis origin is
    // the leading edge of the first icon). Zoom moves each slot explicitly.
    Item {
        id: row
        x: dock.vertical
            ? dock.contentPaddingLeft * dock.unit + Math.max(0, (dock.width - dock.padPx - dock.iconPx - dock.indicatorReservePx) / 2)
                + (!dock.indicatorAfterIcon ? dock.indicatorReservePx : 0)
            : dock.restStart
        y: dock.vertical
            ? dock.restStart
            : dock.contentPaddingTop * dock.unit + Math.max(0, (dock.height - dock.padPx - dock.iconPx - dock.indicatorReservePx) / 2)
                + (!dock.indicatorAfterIcon ? dock.indicatorReservePx : 0)

        Repeater {
            id: repeater
            model: dock.apps

            Item {
                id: slot
                objectName: "miniDockSlot" + index

                required property var modelData
                required property int index

                readonly property real zoomScale: dock.zoomLayout.scales?.[index] ?? 1.0
                readonly property real zoomOffset: dock.zoomLayout.offsets?.[index] ?? 0.0
                // Parabolic: the slot covers the zoomed icon's positional
                // extent; neighbours are pushed aside through zoomOffset.
                // In place: the slot keeps its rest size and the icon
                // magnifies over its neighbours (offsets are always 0).
                readonly property real slotLength: dock.zoomStyle === 1 ? dock.iconPx : dock.iconPx * zoomScale
                // Slot centre = rest centre + the layout's centre shift.
                readonly property real primaryCenter: index * dock.pitch + dock.iconPx / 2 + zoomOffset
                readonly property string windowState: modelData.state ?? "launcher"
                readonly property Item iconBox: box

                // Preserve the separate virtual-desktop dimming preview.
                // App active/minimized state no longer changes icon opacity.
                opacity: modelData.otherDesktop === true ? dock.otherDesktopOpacity : 1.0

                x: dock.vertical ? 0 : primaryCenter - slotLength / 2
                y: dock.vertical ? primaryCenter - slotLength / 2 : 0
                width: dock.vertical ? dock.iconPx : slotLength
                height: dock.vertical ? slotLength : dock.iconPx
                z: zoomScale

                // Resize the icon directly and pin its cross-axis edge to the
                // dock edge, matching DockItem's Scale origin on all sides.
                Item {
                    id: box
                    width: dock.iconPx * slot.zoomScale
                    height: width
                    x: dock.vertical
                        ? (dock.edge === 2 ? 0 : slot.width - width)
                        : (slot.width - width) / 2
                    y: dock.vertical
                        ? (slot.height - height) / 2
                        : (dock.edge === 0 ? 0 : slot.height - height)
                    objectName: "miniDockIconBox" + slot.index
                }

                // Cell rendered at the maximum zoom size and scaled down to
                // the current zoom, so magnified icons stay crisp.
                Item {
                    readonly property real cellSize: dock.iconPx * Math.max(1.0, dock.maxZoomFactor)
                    x: box.x + (box.width - width) / 2
                    y: box.y + (box.height - height) / 2
                    width: cellSize
                    height: cellSize
                    scale: slot.zoomScale / Math.max(1.0, dock.maxZoomFactor)

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        // Simulated internal padding of padded icons, which
                        // icon size normalization removes in the dock.
                        readonly property real paddingRatio: dock.iconNormalization ? 1.0 : (slot.modelData.padding ?? 1.0)
                        width: parent.width * dock.iconScale * paddingRatio
                        height: width
                        source: slot.modelData.icon
                        fallback: slot.modelData.fallback ?? "application-x-executable"
                        visible: slot.index !== dock.hiddenIconIndex
                        opacity: dock.iconOpacity
                    }
                }

                // Running indicator; the configured position selects the
                // screen-edge or interior side of the icon.
                Rectangle {
                    readonly property int indicatorStyle: dock.runningIndicatorStyle
                    readonly property real markerSize: dock.runningIndicatorSize * dock.unit
                    readonly property real markerThickness: indicatorStyle === 0 ? markerSize
                        : indicatorStyle === 1 ? Math.max(2 * dock.unit, Math.round(markerSize / 3))
                        : indicatorStyle === 2 || indicatorStyle === 3 ? markerSize
                        : Math.max(2 * dock.unit, Math.round(markerSize / 2))
                    readonly property real markerLength: indicatorStyle === 0 ? markerThickness
                        : markerSize * (indicatorStyle === 4 ? 3 : 2)
                    readonly property real gap: Math.max(0, (dock.indicatorReservePx - markerThickness) / 2)
                    visible: slot.windowState !== "launcher"
                    width: dock.vertical ? markerThickness : markerLength
                    height: dock.vertical ? markerLength : markerThickness
                    radius: indicatorStyle === 0 || indicatorStyle === 3 ? Math.max(width, height) / 2
                        : indicatorStyle === 2 ? markerThickness / 2 : Math.min(width, height) / 3
                    x: dock.vertical
                        ? (dock.indicatorAfterIcon ? slot.width + gap : -width - gap)
                        : (slot.width - width) / 2
                    y: dock.vertical
                        ? (slot.height - height) / 2
                        : (dock.indicatorAfterIcon ? slot.height + gap : -height - gap)
                    color: dock.runningIndicatorColorMode === 1 ? dock.runningIndicatorColor : Kirigami.Theme.textColor
                    opacity: slot.windowState === "active" ? 1.0 : slot.windowState === "minimized" ? 0.35 : 0.6

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + Math.max(2, parent.markerSize / 2)
                        height: parent.height + Math.max(2, parent.markerSize / 2)
                        radius: Math.max(width, height) / 2
                        color: parent.color
                        opacity: 0.28
                        visible: parent.indicatorStyle === 3
                        z: -1
                    }
                }

                // Keep the shadow in its own texture so the Qt-rendered
                // label remains sharp, matching DockItem's badge path.
                Rectangle {
                    id: badgeShadow
                    x: box.x + box.width - width * 0.8
                    y: box.y - height * 0.2
                    width: Math.round(box.width * (dock.badgeDisplayMode === 1 ? 0.18 : 0.38))
                    height: width
                    radius: width / 2
                    color: dock.badgeBackgroundColor
                    visible: (slot.modelData.badge ?? 0) > 0 && dock.badgeDisplayMode === 0
                    layer.enabled: visible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.alpha("black", 0.4)
                        shadowBlur: 0.3
                        shadowVerticalOffset: 1
                    }
                }

                // Badge (DockItem.qml): number or dot at the icon's corner.
                Rectangle {
                    id: badge
                    objectName: "miniDockBadge" + slot.index
                    visible: (slot.modelData.badge ?? 0) > 0 && dock.badgeDisplayMode !== 2
                    width: Math.round(box.width * (dock.badgeDisplayMode === 1 ? 0.18 : 0.38))
                    height: width
                    radius: width / 2
                    x: box.x + box.width - width * 0.8
                    y: box.y - height * 0.2
                    color: dock.badgeBackgroundColor

                    QQC2.Label {
                        objectName: "miniDockBadgeLabel" + slot.index
                        visible: dock.badgeDisplayMode === 0
                        x: (parent.width - width) / 2
                        y: (parent.height - height) / 2
                        width: parent.width - 1
                        height: parent.height - 2
                        text: (slot.modelData.badge ?? 0) > 99 ? "99+" : String(slot.modelData.badge ?? 0)
                        color: dock.badgeTextColor
                        renderType: Text.QtRendering
                        font.pixelSize: Math.max(1, parent.height * 0.55 * dock.badgeTextSizePercent / 100)
                        font.weight: dock.badgeFontWeight
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 3 * dock.badgeTextSizePercent / 100
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Accessible.ignored: true
                    }
                }
            }
        }
    }

    // --- Measurement markers (geometry only, never drawn) ---

    Item {
        id: spacingMarkerItem
        readonly property int slotIndex: Math.max(0, Math.min(dock.focusIndex, dock.count - 2))
        readonly property Item slot: {
            if (repeater.count <= slotIndex) {
                return null
            }
            return repeater.itemAt(slotIndex)
        }
        x: row.x + (dock.vertical ? 0 : (slot ? slot.x + slot.width : 0))
        y: row.y + (dock.vertical ? (slot ? slot.y + slot.height : 0) : 0)
        width: dock.vertical ? dock.iconPx : dock.gapPx
        height: dock.vertical ? dock.gapPx : dock.iconPx
    }

    Item {
        id: floatingMarkerItem
        x: dock.vertical ? (dock.edge === 2 ? -dock.floatPx : dock.width) : dock.width / 2
        y: dock.vertical ? dock.height / 2 : (dock.edge === 0 ? -dock.floatPx : dock.height)
        width: dock.vertical ? dock.floatPx : 0
        height: dock.vertical ? 0 : dock.floatPx
    }

    // Pointer tracking over the panel plus the zoom overflow away from the
    // edge, which is the dock's input region while it is hovered.
    MouseArea {
        id: hoverArea
        objectName: "miniDockHoverArea"
        x: dock.edge === 3 ? -dock.zoomOverflow : 0
        y: dock.edge === 1 ? -dock.zoomOverflow : 0
        width: dock.width + (dock.vertical ? dock.zoomOverflow : 0)
        height: dock.height + (dock.vertical ? 0 : dock.zoomOverflow)
        enabled: dock.interactiveHover
        hoverEnabled: dock.interactiveHover
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            dock._mouseCursor = (dock.vertical ? mouse.y + y : mouse.x + x) - dock.restStart
        }
    }
}
