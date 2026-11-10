// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of KDockWSettings (KConfigXT). Defaults mirror src/config/kdockw.kcfg.
pragma Singleton
import QtQuick

QtObject {
    property string language: "system"
    property int iconSize: 40
    property int iconSpacing: 10
    property int contentPaddingLeft: 8
    property int contentPaddingRight: 8
    property int contentPaddingTop: 8
    property int contentPaddingBottom: 0
    property int contentAlignment: 1
    property real iconOpacity: 1.0
    property real maxZoomFactor: 1.9
    // 0 = Parabolic (neighbours move aside), 1 = InPlace
    property int zoomStyle: 0
    // 0 = Classic, 1 = Spring.
    property int magnificationMode: 1
    property real springStiffness: 170.0
    property real springDamping: 0.60
    property real springSpeed: 0.9
    // 0 = Natural, 1 = Quick, 2 = Relaxed, 3 = Instant, 4 = Custom
    property int zoomAnimationPreset: 0
    // Custom preset timing (unscaled ms) and easing indices (see ZoomAnimationProfile).
    property int zoomInDuration: 180
    property int zoomOutDuration: 240
    property int zoomInEasing: 3
    property int zoomOutEasing: 3
    // Legacy config keys remain exposed by KConfigXT for compatibility;
    // rendering must not read them.
    property real iconOpacityActive: 1.0
    property real iconOpacityInactive: 1.0
    property real iconOpacityMinimized: 1.0
    property real iconScale: 1.0
    property bool iconNormalization: true
    property int cornerRadius: 17
    property bool floating: true
    property int floatingMargin: 3
    property int visibilityMode: 0
    property bool reserveScreenSpace: true
    property bool dodgeActiveOnly: true
    property int edge: 1
    property int showDelay: 200
    property int hideDelay: 500
    property bool dockShowHideAnimationEnabled: true
    property int dockShowHideAnimationDuration: 220
    property real backgroundOpacity: 0.85
    property int backgroundStyle: 2
    property bool useAccentColor: false
    property bool useSystemColor: false
    property string tintColor: "#4b4144"
    property bool separateLaunchers: true
    property int attentionAnimation: 2
    property int attentionAnimationDuration: 3
    property bool attentionAnimationEnabled: true
    property int attentionAnimationIntensity: 100
    property bool launchBounceEnabled: true
    property int launchBounceIntensity: 150
    property int launchBounceSpeed: 70
    property bool clickBounceEnabled: true
    property int badgeDisplayMode: 0
    property color badgeBackgroundColor: "#ffff3b30"
    property color badgeTextColor: "#ffffffff"
    property int badgeFontWeight: 500
    property int badgeTextSizePercent: 100
    property int runningIndicatorStyle: 0
    property int runningIndicatorPosition: 0
    property int runningIndicatorSize: 4
    property int runningIndicatorColorMode: 1
    property color runningIndicatorColor: "#ffffffff"
    property real otherDesktopOpacity: 0.4
    property bool previewEnabled: true
    property bool cpuOnlyPreviewCapture: false
    property int previewHoverDelay: 500
    property bool activateWindowOnExternalDrag: true
    property int externalDragActivationDelay: 700
    property int singleWindowClickAction: 1
    property int groupedWindowClickAction: 0
    property int previewThumbnailSize: 320
    property int previewMaximumHeight: 200
    property int previewCardPadding: 8
    property int previewDockGap: 2
    property int previewHideDelay: 400
    property int monitorMode: 0
    property int followActiveTrigger: 1
    property int screenTransition: 0
    property int virtualDesktopMode: 1
    property bool shadowEnabled: true
    property int shadowElevation: 1
    property int shadowLightX: 65
    property int shadowLightY: -132
    property int shadowLightZ: 500
    property real shadowLightRadius: 5.5
    property color shadowColor: "#80000000"
    property real shadowIntensity: 0.2

    // Restores every property listed in _resettable to its declared value.
    readonly property var _resettable: ["language", "iconSize", "iconSpacing", "contentPaddingLeft", "contentPaddingRight", "contentPaddingTop", "contentPaddingBottom", "contentAlignment", "iconOpacity", "maxZoomFactor", "zoomStyle", "magnificationMode", "springStiffness", "springDamping", "springSpeed", "zoomAnimationPreset", "zoomInDuration", "zoomOutDuration", "zoomInEasing", "zoomOutEasing", "iconOpacityActive", "iconOpacityInactive", "iconOpacityMinimized", "iconScale", "iconNormalization", "cornerRadius", "floating", "floatingMargin", "visibilityMode", "reserveScreenSpace", "dodgeActiveOnly", "edge", "showDelay", "hideDelay", "dockShowHideAnimationEnabled", "dockShowHideAnimationDuration", "backgroundOpacity", "backgroundStyle", "useAccentColor", "useSystemColor", "tintColor", "separateLaunchers", "attentionAnimation", "attentionAnimationDuration", "attentionAnimationEnabled", "attentionAnimationIntensity", "launchBounceEnabled", "launchBounceIntensity", "launchBounceSpeed", "clickBounceEnabled", "badgeDisplayMode", "badgeBackgroundColor", "badgeTextColor", "badgeFontWeight", "badgeTextSizePercent", "runningIndicatorStyle", "runningIndicatorPosition", "runningIndicatorSize", "runningIndicatorColorMode", "runningIndicatorColor", "otherDesktopOpacity", "previewEnabled", "cpuOnlyPreviewCapture", "previewHoverDelay", "previewHideDelay", "activateWindowOnExternalDrag", "externalDragActivationDelay", "singleWindowClickAction", "groupedWindowClickAction", "previewThumbnailSize", "previewMaximumHeight", "previewCardPadding", "previewDockGap", "monitorMode", "followActiveTrigger", "screenTransition", "virtualDesktopMode", "shadowEnabled", "shadowElevation", "shadowLightX", "shadowLightY", "shadowLightZ", "shadowLightRadius", "shadowColor", "shadowIntensity"]
    property var _defaults: ({})
    Component.onCompleted: {
        for (const k of _resettable) _defaults[k] = this[k]
    }
    function reset() {
        for (const k of _resettable) this[k] = _defaults[k]
    }
}
