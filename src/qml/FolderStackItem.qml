// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

Item {
    id: stackItem
    objectName: "folderStackItem"

    required property int index
    required property var model
    required property Item rootItem
    property bool verticalDock: false
    property int dockEdge: 3
    property real maxZoomFactor: 1.6
    readonly property string displayName: model.display || ""
    property string iconName: "folder"
    property url iconUrl: ""
    readonly property bool popupVisible: stackPopup.visible
    readonly property int popupItemCount: grid.count
    readonly property real iconSize: DockSettings.iconSize
    readonly property var popupControl: stackPopup
    readonly property var contextMenuControl: stackContextMenu
    readonly property real popupX: stackPopup.x
    readonly property real popupY: stackPopup.y
    readonly property real popupScreenX: stackPopup.screenX
    readonly property real popupScreenY: stackPopup.screenY
    readonly property rect popupAnchorRect: stackPopup.anchorRect
    readonly property rect popupAnchorScreenRect: stackPopup.anchorScreenRect
    readonly property point popupAnchorCenter: stackPopup.anchorCenter
    readonly property real popupWidth: stackPopup.width
    readonly property real popupHeight: stackPopup.height
    readonly property real popupContentWidth: stackPopup.contentItem ? stackPopup.contentItem.width : 0
    readonly property real popupContentHeight: stackPopup.contentItem ? stackPopup.contentItem.height : 0
    readonly property bool popupContentVisible:
        stackPopup.contentItem && stackPopup.contentItem.visible && stackPopup.contentItem.opacity > 0
    readonly property int popupModelCount: grid.count
    readonly property real popupGridHeight: grid.height
    readonly property real popupGridWidth: grid.width
    readonly property bool popupGridVisible: grid.visible && grid.opacity > 0
    readonly property bool popupFirstDelegateVisible:
        grid.count > 0 && grid.itemAtIndex(0) !== null
            && grid.itemAtIndex(0).visible && grid.itemAtIndex(0).opacity > 0
    readonly property string popupCurrentUrl: filesModel.currentUrl.toString()
    readonly property size folderIconSourceSize: folderIcon.sourceSize
    readonly property bool popupPendingOpen: stackPopup.pendingOpen
    readonly property rect popupTransformedAnchorRect: stackPopup.transformedAnchorRect
    readonly property color popupCardColor: stackPopup.surfaceColor
    readonly property real popupCardPadding: stackPopup.cardPadding
    readonly property real popupShadowMargin: stackPopup.shadowMargin

    width: iconSize + DockSettings.iconSpacing
    height: iconSize + DockSettings.iconSpacing

    Accessible.role: Accessible.Button
    Accessible.name: displayName
    Accessible.description: i18n("Folder stack")
    Accessible.focusable: true
    Accessible.onPressAction: openStack()

    function openStack() {
        if (typeof rootItem.suppressDockTooltip === "function")
            rootItem.suppressDockTooltip()
        if (stackPopup.visible) {
            stackPopup.close()
        } else if (stackPopup.pendingOpen) {
            stackPopup.pendingOpen = false
            filesModel.close()
        } else {
            stackPopup.openAtRoot()
        }
    }

    function openContextMenu() {
        if (typeof rootItem.suppressDockTooltip === "function")
            rootItem.suppressDockTooltip()
        stackContextMenu.popup()
    }

    function chooseThemeIconFromMenu() {
        const entryId = model.entryId
        stackContextMenu.close()
        // Let the native Qt.Popup surface release its Wayland input grab
        // before opening the QWidget-based KDE icon chooser.
        Qt.callLater(function() {
            DockModel.chooseFolderStackThemeIcon(entryId, stackItem.Window.window)
        })
    }

    function closeContextMenuForWindowDeactivation(active) {
        if (!active && stackContextMenu.visible)
            stackContextMenu.close()
    }

    function activateGridItem(itemIndex, isDirectory) {
        filesModel.openItem(itemIndex)
        if (!isDirectory)
            stackPopup.close()
    }

    function closeForWindowDeactivation(active) {
        if (!active && stackPopup.visible)
            stackPopup.close()
    }

    // Match the image-provider path used by neighboring app icons. Request the
    // maximum Spring Magnification frame up front so the outer transform does
    // not enlarge a rest-size texture.
    Image {
        id: folderIcon
        anchors.centerIn: parent
        width: DockSettings.iconSize
        height: DockSettings.iconSize
        source: {
            if (!stackItem.visible) return ""
            if (stackItem.iconUrl.toString().length > 0) return stackItem.iconUrl
            return "image://icon/" + encodeURIComponent(stackItem.iconName || "folder")
                + "?v=" + DockView.iconCacheVersion
        }
        sourceSize: Qt.size(Math.ceil(width * stackItem.maxZoomFactor * Screen.devicePixelRatio),
                            Math.ceil(height * stackItem.maxZoomFactor * Screen.devicePixelRatio))
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: DockSettings.iconOpacity
        Accessible.ignored: true
    }

    QQC2.Menu {
        id: stackContextMenu
        objectName: "folderStackContextMenu"
        popupType: QQC2.Popup.Window
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        QQC2.Menu {
            title: i18n("Change icon…")
            QQC2.MenuItem {
                objectName: "folderStackChooseThemeIcon"
                text: i18n("Choose an icon from the theme…")
                onTriggered: stackItem.chooseThemeIconFromMenu()
            }
            QQC2.MenuItem {
                text: i18n("Choose an image from disk…")
                onTriggered: DockModel.chooseFolderStackImage(model.entryId)
            }
            QQC2.MenuItem {
                text: i18n("Restore default icon")
                onTriggered: DockModel.resetFolderStackIcon(model.entryId)
            }
        }
        QQC2.MenuItem {
            text: i18n("Remove from dock")
            onTriggered: DockModel.dockEntriesModel.removeFolderStack(model.entryId)
        }

        Connections {
            target: stackContextMenu.contentItem ? stackContextMenu.contentItem.Window.window : null
            function onActiveChanged() {
                const menuWindow = stackContextMenu.contentItem
                    ? stackContextMenu.contentItem.Window.window : null
                if (menuWindow)
                    stackItem.closeContextMenuForWindowDeactivation(menuWindow.active)
            }
        }
    }

    FolderStackModel {
        id: filesModel
    }

    QQC2.Popup {
        id: stackPopup
        objectName: "folderStackPopup"
        parent: stackItem.rootItem
        popupType: QQC2.Popup.Window
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        property bool sawActivePopupWindow: false
        property bool pendingOpen: false
        property real screenX: 0
        property real screenY: 0
        property rect anchorRect: Qt.rect(0, 0, 0, 0)
        property rect transformedAnchorRect: Qt.rect(0, 0, 0, 0)
        property rect anchorScreenRect: Qt.rect(0, 0, 0, 0)
        property point anchorCenter: Qt.point(0, 0)
        readonly property bool usesSeparateWindow: popupType === QQC2.Popup.Window
        readonly property bool closeOnOutsideEnabled:
            (closePolicy & QQC2.Popup.CloseOnPressOutside) !== 0
        property real requestedPopupWidth: Math.max(1, Math.min(560,
            rootItem.width - Kirigami.Units.largeSpacing * 2))
        property real requestedPopupHeight: Math.max(1, Math.min(460,
            rootItem.height - Kirigami.Units.largeSpacing * 2))
        readonly property real cardPadding: DockSettings.previewCardPadding
        readonly property real shadowMargin: Kirigami.Units.smallSpacing * 2
        readonly property real configuredDockGap: DockSettings.previewDockGap
        readonly property real springOverflow:
            DockSettings.iconSize * Math.max(0, DockSettings.maxZoomFactor - 1)
        readonly property real previewDockClearance: configuredDockGap + springOverflow
        readonly property color surfaceColor: DockView.backgroundColor.a > 0
            ? BadgeTextColor.composite(DockView.backgroundColor, Kirigami.Theme.backgroundColor)
            : BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.backgroundColor,
                                                   DockSettings.backgroundOpacity),
                                       Kirigami.Theme.backgroundColor)
        readonly property color foregroundColor: BadgeTextColor.choose(
            surfaceColor, Kirigami.Theme.textColor)
        readonly property color outlineColor: Qt.alpha(foregroundColor, 0.27)
        readonly property real gridHoverTintOpacity: 0.08
        readonly property real gridSelectionTintOpacity: 0.16
        readonly property color gridHoverSurfaceColor: BadgeTextColor.composite(
            Qt.alpha(Kirigami.Theme.highlightColor, gridHoverTintOpacity), surfaceColor)
        readonly property color gridSelectionSurfaceColor: BadgeTextColor.composite(
            Qt.alpha(Kirigami.Theme.highlightColor, gridSelectionTintOpacity), surfaceColor)
        readonly property color gridHoverForegroundColor: BadgeTextColor.choose(
            gridHoverSurfaceColor, Kirigami.Theme.textColor)
        readonly property color gridSelectionForegroundColor: BadgeTextColor.choose(
            gridSelectionSurfaceColor, Kirigami.Theme.textColor)
        readonly property color gridSelectionBorderColor: Qt.alpha(Kirigami.Theme.highlightColor, 0.52)
        readonly property real gridCellRadius: Math.min(12, Math.max(10, Kirigami.Units.cornerRadius * 2))
        readonly property real gridCellInset: Math.max(6, Kirigami.Units.smallSpacing * 2)
        width: requestedPopupWidth
        height: requestedPopupHeight
        padding: cardPadding + shadowMargin

        function clamp(value, low, high) {
            return Math.max(low, Math.min(high, value))
        }

        function openAtRoot() {
            if (pendingOpen || visible)
                return
            pendingOpen = true
            logPopupGeometry("before-open")
            filesModel.openFolder(model.entryUrl)
            // KDirLister completes asynchronously. Creating the native popup
            // only after its model settles lets the xdg_popup positioner see
            // the final content geometry in the initial surface commit.
            if (!filesModel.loading)
                Qt.callLater(openWhenContentReady)
        }

        function openWhenContentReady() {
            if (!pendingOpen || filesModel.loading)
                return
            pendingOpen = false
            openPreparedPopup()
        }

        Connections {
            target: filesModel
            function onLoadingChanged() {
                if (!filesModel.loading && stackPopup.pendingOpen)
                    stackPopup.openWhenContentReady()
            }
        }

        function openPreparedPopup() {

            const inset = Kirigami.Units.largeSpacing
            // Match PreviewPopup.qml: the card edge clears the resting icon by
            // the configured preview gap plus maximum Spring overflow.
            const gap = previewDockClearance
            const shadow = shadowMargin
            const surfaceWindow = stackItem.Window.window
            const surfaceWidth = surfaceWindow ? surfaceWindow.width : rootItem.width
            const surfaceHeight = surfaceWindow ? surfaceWindow.height : rootItem.height
            const surfaceContentItem = surfaceWindow ? surfaceWindow.contentItem : null
            const rootOrigin = surfaceContentItem
                ? rootItem.mapToItem(surfaceContentItem, 0, 0) : Qt.point(0, 0)
            const corners = [
                stackItem.mapToItem(rootItem, 0, 0),
                stackItem.mapToItem(rootItem, stackItem.width, 0),
                stackItem.mapToItem(rootItem, 0, stackItem.height),
                stackItem.mapToItem(rootItem, stackItem.width, stackItem.height)
            ]
            let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
            for (const corner of corners) {
                minX = Math.min(minX, corner.x)
                maxX = Math.max(maxX, corner.x)
                minY = Math.min(minY, corner.y)
                maxY = Math.max(maxY, corner.y)
            }
            const transformedAnchor = Qt.rect(minX, minY, maxX - minX, maxY - minY)
            transformedAnchorRect = transformedAnchor
            const restGeometryItem = stackItem.parent && stackItem.parent.delegateGeometryTarget
                ? stackItem.parent.delegateGeometryTarget : null
            let mappedAnchor = transformedAnchor
            if (restGeometryItem) {
                const restOrigin = restGeometryItem.mapToItem(rootItem, 0, 0)
                const restInsetX = Math.max(0, (restGeometryItem.width - stackItem.iconSize) / 2)
                const restInsetY = Math.max(0, (restGeometryItem.height - stackItem.iconSize) / 2)
                mappedAnchor = Qt.rect(restOrigin.x + restInsetX, restOrigin.y + restInsetY,
                                       stackItem.iconSize, stackItem.iconSize)
            }
            const mappedCenter = Qt.point(mappedAnchor.x + mappedAnchor.width / 2,
                                          mappedAnchor.y + mappedAnchor.height / 2)
            anchorRect = mappedAnchor
            anchorCenter = mappedCenter
            const reportedScreen = DockView.screenGeometry
            const screen = reportedScreen.width > 0 && reportedScreen.height > 0
                ? reportedScreen : Qt.rect(0, 0, surfaceWidth, surfaceHeight)
            const surfaceX = screen.x + (verticalDock && dockEdge === 3
                ? screen.width - surfaceWidth : 0)
            const surfaceY = screen.y + (!verticalDock && dockEdge === 1
                ? screen.height - surfaceHeight : 0)
            const rootSurfaceX = surfaceX + rootOrigin.x
            const rootSurfaceY = surfaceY + rootOrigin.y
            const itemX = rootSurfaceX + mappedAnchor.x
            const itemY = rootSurfaceY + mappedAnchor.y
            const itemRight = rootSurfaceX + mappedAnchor.x + mappedAnchor.width
            const itemBottom = rootSurfaceY + mappedAnchor.y + mappedAnchor.height
            const itemCenterX = rootSurfaceX + mappedCenter.x
            const itemCenterY = rootSurfaceY + mappedCenter.y
            anchorScreenRect = Qt.rect(itemX, itemY, mappedAnchor.width, mappedAnchor.height)
            const screenRight = screen.x + screen.width
            const screenBottom = screen.y + screen.height
            const maxWidth = Math.max(1, screen.width - inset * 2)
            const maxHeight = Math.max(1, screen.height - inset * 2)

            if (verticalDock) {
                const rightSpace = Math.max(0, screenRight - itemRight - gap + shadow - inset)
                const leftSpace = Math.max(0, itemX - gap + shadow - screen.x - inset)
                const preferRight = dockEdge === 2
                const preferred = preferRight ? rightSpace : leftSpace
                const alternate = preferRight ? leftSpace : rightSpace
                const usePreferred = preferred >= Math.min(240, maxWidth) || preferred >= alternate
                const useRight = preferRight ? usePreferred : !usePreferred
                requestedPopupWidth = Math.max(1, Math.min(560, useRight ? rightSpace : leftSpace, maxWidth))
                requestedPopupHeight = Math.max(1, Math.min(460, maxHeight))
                const globalX = useRight ? itemRight + gap - shadow
                    : itemX - gap + shadow - width
                const globalY = clamp(itemCenterY - height / 2,
                    screen.y + inset, Math.max(screen.y + inset, screenBottom - height - inset))
                screenX = globalX
                screenY = globalY
                x = globalX - rootSurfaceX
                y = globalY - rootSurfaceY
            } else {
                const belowSpace = Math.max(0, screenBottom - itemBottom - gap + shadow - inset)
                const aboveSpace = Math.max(0, itemY - gap + shadow - screen.y - inset)
                const preferBelow = dockEdge === 0
                const preferred = preferBelow ? belowSpace : aboveSpace
                const alternate = preferBelow ? aboveSpace : belowSpace
                const usePreferred = preferred >= Math.min(220, maxHeight) || preferred >= alternate
                const useBelow = preferBelow ? usePreferred : !usePreferred
                requestedPopupWidth = Math.max(1, Math.min(560, maxWidth))
                requestedPopupHeight = Math.max(1, Math.min(460, useBelow ? belowSpace : aboveSpace, maxHeight))
                const globalX = clamp(itemCenterX - width / 2,
                    screen.x + inset, Math.max(screen.x + inset, screenRight - width - inset))
                const globalY = useBelow ? itemBottom + gap - shadow
                    : itemY - gap + shadow - height
                screenX = globalX
                screenY = globalY
                x = globalX - rootSurfaceX
                y = globalY - rootSurfaceY
            }

            logPopupGeometry("content-ready")
            sawActivePopupWindow = false
            open()
        }

        onOpened: {
            grid.forceLayout()
            grid.forceActiveFocus()
            logPopupGeometry("opened")
            Qt.callLater(() => logPopupGeometry("content-ready"))
        }

        onWidthChanged: {
            if (visible)
                logPopupGeometry("geometry-changed")
        }

        onHeightChanged: {
            if (visible)
                logPopupGeometry("geometry-changed")
        }

        function logPopupGeometry(phase) {
            if (!DockModel.taskDiagnosticsEnabled) return
            const popupWindow = contentItem ? contentItem.Window.window : null
            const dockWindow = stackItem.Window.window
            const surfaceContentItem = dockWindow ? dockWindow.contentItem : null
            const rootOrigin = surfaceContentItem
                ? rootItem.mapToItem(surfaceContentItem, 0, 0) : Qt.point(0, 0)
            const screen = DockView.screenGeometry
            const dockWidth = dockWindow ? dockWindow.width : rootItem.width
            const dockHeight = dockWindow ? dockWindow.height : rootItem.height
            const parentOriginScreen = Qt.point(
                screen.x + (verticalDock && dockEdge === 3 ? screen.width - dockWidth : 0) + rootOrigin.x,
                screen.y + (!verticalDock && dockEdge === 1 ? screen.height - dockHeight : 0) + rootOrigin.y)
            console.info("[KDOCKW_POPUP_TRACE] " + JSON.stringify({
                phase: phase,
                entryId: stackItem.model.entryId || "",
                coordinateSpace: "logical screen / popup-parent item",
                dockEdge: dockEdge,
                verticalDock: verticalDock,
                scale: stackItem.parent && stackItem.parent.currentScale !== undefined
                    ? stackItem.parent.currentScale : 1,
                primaryTranslate: stackItem.parent && stackItem.parent.primaryTranslate !== undefined
                    ? stackItem.parent.primaryTranslate : 0,
                anchorRectInParent: { x: anchorRect.x, y: anchorRect.y,
                                      width: anchorRect.width, height: anchorRect.height },
                transformedAnchorRectInParent: {
                    x: transformedAnchorRect.x, y: transformedAnchorRect.y,
                    width: transformedAnchorRect.width, height: transformedAnchorRect.height
                },
                anchorCenterInParent: { x: anchorCenter.x, y: anchorCenter.y },
                popupRequestedInParent: { x: x, y: y, width: width, height: height },
                requestedPopupSize: { width: requestedPopupWidth, height: requestedPopupHeight },
                requestedScreen: { x: screenX, y: screenY },
                dockWindow: dockWindow
                    ? { x: dockWindow.x, y: dockWindow.y, width: dockWindow.width,
                        height: dockWindow.height, visible: dockWindow.visible }
                    : null,
                inferredParentOriginScreen: {
                    x: parentOriginScreen.x, y: parentOriginScreen.y
                },
                popupContent: contentItem
                    ? { x: contentItem.x, y: contentItem.y, width: contentItem.width,
                        height: contentItem.height, visible: contentItem.visible,
                        opacity: contentItem.opacity, z: contentItem.z }
                    : null,
                popupWindow: popupWindow
                    ? { x: popupWindow.x, y: popupWindow.y, width: popupWindow.width,
                        height: popupWindow.height, visible: popupWindow.visible,
                        active: popupWindow.active,
                        transientForDock: popupWindow.transientParent === dockWindow }
                    : null,
                modelCount: grid.count,
                firstDelegate: grid.itemAtIndex(0)
                    ? { x: grid.itemAtIndex(0).x, y: grid.itemAtIndex(0).y,
                        width: grid.itemAtIndex(0).width, height: grid.itemAtIndex(0).height,
                        visible: grid.itemAtIndex(0).visible,
                        opacity: grid.itemAtIndex(0).opacity }
                    : null
            }))
        }

        onClosed: {
            logPopupGeometry("closed")
            pendingOpen = false
            filesModel.close()
            if (typeof rootItem.folderStackPopupClosed === "function")
                rootItem.folderStackPopupClosed()
        }

        Connections {
            target: stackPopup.contentItem ? stackPopup.contentItem.Window.window : null
            function onXChanged() {
                stackPopup.logPopupGeometry("window-position-updated")
            }
            function onYChanged() {
                stackPopup.logPopupGeometry("window-position-updated")
            }
            function onWidthChanged() {
                stackPopup.logPopupGeometry("geometry-changed")
            }
            function onHeightChanged() {
                stackPopup.logPopupGeometry("geometry-changed")
            }
            function onActiveChanged() {
                if (target.active) {
                    stackPopup.sawActivePopupWindow = true
                } else if (stackPopup.sawActivePopupWindow) {
                    stackItem.closeForWindowDeactivation(false)
                }
            }
        }

        Connections {
            target: stackItem.Window.window
            function onXChanged() {
                if (stackPopup.visible || stackPopup.pendingOpen)
                    stackPopup.logPopupGeometry("geometry-changed")
            }
            function onYChanged() {
                if (stackPopup.visible || stackPopup.pendingOpen)
                    stackPopup.logPopupGeometry("geometry-changed")
            }
            function onWidthChanged() {
                if (stackPopup.visible || stackPopup.pendingOpen)
                    stackPopup.logPopupGeometry("geometry-changed")
            }
            function onHeightChanged() {
                if (stackPopup.visible || stackPopup.pendingOpen)
                    stackPopup.logPopupGeometry("geometry-changed")
            }
        }

        background: Item {
            Kirigami.ShadowedRectangle {
                anchors.fill: parent
                anchors.margins: stackPopup.shadowMargin
                radius: Math.min(DockSettings.cornerRadius, width / 2, height / 2)
                color: stackPopup.surfaceColor
                border.width: 1
                border.color: stackPopup.outlineColor
                shadow.size: DockSettings.shadowEnabled ? DockSettings.shadowLightRadius * 2 : 0
                shadow.xOffset: -DockSettings.shadowLightX * DockSettings.shadowElevation
                    / Math.max(1, DockSettings.shadowLightZ)
                shadow.yOffset: -DockSettings.shadowLightY * DockSettings.shadowElevation
                    / Math.max(1, DockSettings.shadowLightZ)
                shadow.color: Qt.alpha(DockSettings.shadowColor, DockSettings.shadowIntensity)

                Kirigami.Theme.colorSet: Kirigami.Theme.Window
                Kirigami.Theme.inherit: false
            }
        }

        contentItem: Item {
            id: popupContent
            // Popup.Window can otherwise fall back to the content's initial
            // implicit size during native surface creation, before the first
            // GridView layout. Pin the content's preferred size to the final
            // requested popup size so the first xdg_popup commit uses matching
            // dimensions and coordinates.
            implicitWidth: Math.max(1,
                stackPopup.requestedPopupWidth - stackPopup.leftPadding - stackPopup.rightPadding)
            implicitHeight: Math.max(1,
                stackPopup.requestedPopupHeight - stackPopup.topPadding - stackPopup.bottomPadding)

            ColumnLayout {
                id: contentLayout
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    id: pathHeader
                    objectName: "folderStackHeader"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: "folder"
                        color: stackPopup.foregroundColor
                        Accessible.ignored: true
                    }
                    QQC2.ToolButton {
                        id: goUpButton
                        objectName: "folderStackGoUpButton"
                        icon.name: "go-up"
                        display: QQC2.AbstractButton.IconOnly
                        Accessible.name: i18n("Go up one folder")
                        enabled: filesModel.currentUrl !== filesModel.rootUrl
                        Layout.alignment: Qt.AlignVCenter
                        flat: true
                        onClicked: filesModel.goUp()
                    }
                    QQC2.Label {
                        objectName: "folderStackPath"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: filesModel.currentUrl.toString().replace("file://", "")
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                        color: stackPopup.foregroundColor
                        font.weight: Font.DemiBold
                    }
                    QQC2.ToolButton {
                        id: openFolderButton
                        icon.name: "document-open"
                        display: QQC2.AbstractButton.IconOnly
                        Accessible.name: i18n("Open folder in Dolphin")
                        Layout.alignment: Qt.AlignVCenter
                        flat: true
                        onClicked: {
                            filesModel.openCurrentFolder()
                            stackPopup.close()
                        }
                    }
                }

                QQC2.Label {
                    visible: filesModel.loading
                    text: i18n("Loading folder contents…")
                    color: stackPopup.foregroundColor
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight : 0
                }
                QQC2.Label {
                    visible: !filesModel.loading && filesModel.errorMessage.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    wrapMode: Text.Wrap
                    text: filesModel.errorMessage
                    color: stackPopup.foregroundColor
                }
                QQC2.Label {
                    visible: !filesModel.loading && filesModel.errorMessage.length === 0 && grid.count === 0
                    text: i18n("This folder is empty")
                    color: stackPopup.foregroundColor
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight : 0
                }
                GridView {
                    id: grid
                    objectName: "folderStackGrid"
                    Accessible.role: Accessible.List
                    Accessible.name: i18n("Folder contents")
                    clip: true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 1
                    Layout.minimumHeight: 80
                    Layout.preferredHeight: 260
                    readonly property int columnCount: Math.max(1, Math.floor(width / 112))
                    cellWidth: Math.max(1, Math.floor(width / columnCount))
                    cellHeight: 104
                    model: filesModel
                    keyNavigationEnabled: true
                    focus: true
                    property int hoveredIndex: -1
                    property bool keyboardSelectionActive: false
                    reuseItems: true

                    onCountChanged: {
                        if (count > 0 && currentIndex < 0)
                            currentIndex = 0
                        if (count === 0) {
                            hoveredIndex = -1
                            keyboardSelectionActive = false
                        }
                    }

                    Keys.onPressed: function(event) {
                        if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].indexOf(event.key) !== -1) {
                            keyboardSelectionActive = true
                            hoveredIndex = -1
                            let nextIndex = currentIndex < 0 ? 0 : currentIndex
                            if (event.key === Qt.Key_Left)
                                nextIndex = Math.max(0, nextIndex - 1)
                            else if (event.key === Qt.Key_Right)
                                nextIndex = Math.min(count - 1, nextIndex + 1)
                            else if (event.key === Qt.Key_Up)
                                nextIndex = Math.max(0, nextIndex - columnCount)
                            else if (event.key === Qt.Key_Down)
                                nextIndex = Math.min(count - 1, nextIndex + columnCount)
                            if (count > 0)
                                currentIndex = nextIndex
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            keyboardSelectionActive = true
                            hoveredIndex = -1
                            const delegate = itemAtIndex(currentIndex)
                            if (delegate)
                                stackItem.activateGridItem(currentIndex, delegate.isDirectory)
                            event.accepted = true
                        }
                    }

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        id: folderScrollBar
                        objectName: "folderStackScrollBar"
                        policy: QQC2.ScrollBar.AsNeeded
                        width: Kirigami.Units.smallSpacing
                        padding: 0
                        background: Rectangle {
                            color: Qt.alpha(stackPopup.foregroundColor, 0.06)
                            radius: width / 2
                            visible: folderScrollBar.size < 1
                        }
                        contentItem: Rectangle {
                            implicitWidth: Kirigami.Units.smallSpacing
                            implicitHeight: Kirigami.Units.gridUnit * 2
                            radius: width / 2
                            color: folderScrollBar.pressed
                                ? Qt.alpha(stackPopup.foregroundColor, 0.65)
                                : Qt.alpha(stackPopup.foregroundColor,
                                    folderScrollBar.hovered ? 0.45 : 0.28)
                        }
                    }

                    delegate: Item {
                        required property int index
                        required property string display
                        required property string iconName
                        required property bool isDirectory
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Accessible.role: Accessible.Button
                        Accessible.name: display
                        Accessible.description: isDirectory ? i18n("Folder") : i18n("File")
                        Accessible.focusable: true
                        Accessible.onPressAction: stackItem.activateGridItem(index, isDirectory)

                        Column {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 40
                                source: iconName || (isDirectory ? "folder" : "application-octet-stream")
                                Accessible.ignored: true
                            }
                            QQC2.Label {
                                objectName: "folderStackFilename"
                                width: parent.width
                                height: parent.height - 48
                                text: display
                                color: grid.hoveredIndex === index
                                    ? stackPopup.gridHoverForegroundColor
                                    : grid.keyboardSelectionActive && grid.currentIndex === index
                                        ? stackPopup.gridSelectionForegroundColor
                                        : stackPopup.foregroundColor
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            objectName: "folderStackCellHighlight"
                            readonly property bool hoverActive: grid.hoveredIndex === index
                            readonly property bool keyboardActive:
                                !hoverActive && grid.keyboardSelectionActive && grid.currentIndex === index
                            anchors.fill: parent
                            anchors.margins: stackPopup.gridCellInset
                            radius: stackPopup.gridCellRadius
                            color: hoverActive ? stackPopup.gridHoverSurfaceColor
                                : stackPopup.gridSelectionSurfaceColor
                            border.width: keyboardActive ? 1 : 0
                            border.color: stackPopup.gridSelectionBorderColor
                            visible: hoverActive || keyboardActive
                            z: -1
                        }
                        MouseArea {
                            id: fileMouseArea
                            objectName: "folderStackCellMouseArea"
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                grid.hoveredIndex = index
                                grid.keyboardSelectionActive = false
                                grid.currentIndex = index
                            }
                            onPositionChanged: {
                                grid.hoveredIndex = index
                                grid.keyboardSelectionActive = false
                                grid.currentIndex = index
                            }
                            onExited: {
                                if (grid.hoveredIndex === index)
                                    grid.hoveredIndex = -1
                            }
                            onClicked: {
                                grid.hoveredIndex = index
                                grid.keyboardSelectionActive = false
                                grid.currentIndex = index
                                stackItem.activateGridItem(index, isDirectory)
                            }
                        }
                    }
                }
            }
        }
    }
}
