// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

Item {
    id: stackItem
    objectName: "folderStackItem"

    required property int index
    required property var model
    required property Item rootItem
    property bool verticalDock: false
    property int dockEdge: 3
    readonly property string displayName: model.display || ""
    readonly property bool popupVisible: stackPopup.visible
    readonly property int popupItemCount: grid.count
    readonly property real iconSize: DockSettings.iconSize

    width: iconSize + DockSettings.iconSpacing
    height: iconSize + DockSettings.iconSpacing

    Accessible.role: Accessible.Button
    Accessible.name: displayName
    Accessible.description: i18n("Folder stack")
    Accessible.focusable: true
    Accessible.onPressAction: stackPopup.openAtRoot()

    function openStack() {
        stackPopup.openAtRoot()
    }

    function openContextMenu() {
        stackContextMenu.popup()
    }

    Image {
        anchors.centerIn: parent
        width: DockSettings.iconSize
        height: DockSettings.iconSize
        source: stackItem.visible ? "image://icon/folder" : ""
        sourceSize: Qt.size(width, height)
        smooth: true
        opacity: DockSettings.iconOpacity
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                stackContextMenu.popup()
            else
                stackPopup.openAtRoot()
        }
    }

    QQC2.Menu {
        id: stackContextMenu
        QQC2.MenuItem {
            text: i18n("Remove folder stack from dock")
            onTriggered: DockModel.dockEntriesModel.removeFolderStack(model.entryId)
        }
    }

    FolderStackModel {
        id: filesModel
    }

    QQC2.Popup {
        id: stackPopup
        parent: stackItem.rootItem
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        padding: Kirigami.Units.largeSpacing
        width: Math.min(rootItem.width - Kirigami.Units.largeSpacing * 2, 560)
        height: Math.min(rootItem.height - Kirigami.Units.largeSpacing * 2, 460)

        function openAtRoot() {
            filesModel.openFolder(model.entryUrl)
            x = Math.max(Kirigami.Units.largeSpacing,
                         Math.min(rootItem.width - width - Kirigami.Units.largeSpacing,
                                  stackItem.mapToItem(rootItem, stackItem.width / 2, 0).x - width / 2))
            const itemTop = stackItem.mapToItem(rootItem, 0, 0).y
            const itemLeft = stackItem.mapToItem(rootItem, 0, 0).x
            if (verticalDock) {
                x = dockEdge === 2 ? itemLeft + stackItem.width : itemLeft - width
                x = Math.max(Kirigami.Units.largeSpacing,
                             Math.min(rootItem.width - width - Kirigami.Units.largeSpacing, x))
                y = Math.max(Kirigami.Units.largeSpacing,
                             Math.min(rootItem.height - height - Kirigami.Units.largeSpacing,
                                      stackItem.mapToItem(rootItem, 0, stackItem.height / 2).y - height / 2))
            } else {
                y = dockEdge === 0 ? itemTop + stackItem.height : itemTop - height
                y = Math.max(Kirigami.Units.largeSpacing,
                             Math.min(rootItem.height - height - Kirigami.Units.largeSpacing, y))
            }
            open()
            grid.forceActiveFocus()
        }

        onClosed: filesModel.close()

        background: Rectangle {
            radius: DockSettings.cornerRadius
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor
        }

        contentItem: Column {
            spacing: Kirigami.Units.smallSpacing

            Row {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                QQC2.ToolButton {
                    text: "‹"
                    Accessible.name: i18n("Go up one folder")
                    enabled: filesModel.currentUrl !== filesModel.rootUrl
                    onClicked: filesModel.goUp()
                }
                QQC2.Label {
                    width: parent.width - openFolderButton.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: filesModel.currentUrl.toString().replace("file://", "")
                    elide: Text.ElideMiddle
                }
                QQC2.ToolButton {
                    id: openFolderButton
                    text: "↗"
                    Accessible.name: i18n("Open folder in Dolphin")
                    onClicked: filesModel.openCurrentFolder()
                }
            }

            QQC2.Label {
                visible: filesModel.loading
                text: i18n("Loading folder contents…")
            }
            QQC2.Label {
                visible: !filesModel.loading && filesModel.errorMessage.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: filesModel.errorMessage
            }
            QQC2.Label {
                visible: !filesModel.loading && filesModel.errorMessage.length === 0 && filesModel.rowCount() === 0
                text: i18n("This folder is empty")
            }
            GridView {
                id: grid
                objectName: "folderStackGrid"
                Accessible.role: Accessible.List
                Accessible.name: i18n("Folder contents")
                clip: true
                width: parent.width
                height: parent.height - y
                cellWidth: 96
                cellHeight: 104
                model: filesModel
                keyNavigationEnabled: true
                reuseItems: true

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
                    Accessible.onPressAction: filesModel.openItem(index)

                    Column {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 40
                            height: 40
                            source: "image://icon/" + (iconName || (isDirectory ? "folder" : "unknown"))
                            sourceSize: Qt.size(width, height)
                        }
                        Text {
                            width: parent.width
                            height: parent.height - 48
                            text: display
                            color: Kirigami.Theme.textColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            grid.currentIndex = index
                            filesModel.openItem(index)
                        }
                    }
                }
            }
        }
    }
}
