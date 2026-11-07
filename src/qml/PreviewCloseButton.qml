// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

/**
 * The approved red preview close control, shared by single and grouped windows.
 * Its caller supplies the accessible window title and handles clicked().
 */
QQC2.ToolButton {
    id: root

    objectName: "previewCloseButton"
    property string windowTitle: ""

    width: 22
    height: 22
    Layout.preferredWidth: 22
    Layout.preferredHeight: 22
    Layout.minimumWidth: 22
    Layout.maximumWidth: 22
    Layout.minimumHeight: 22
    Layout.maximumHeight: 22
    padding: 0
    hoverEnabled: true

    contentItem: Text {
        objectName: "previewCloseCross"
        text: "×"
        color: "#351010"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.QtRendering
        visible: root.hovered || root.down
    }

    Accessible.name: i18n("Close %1", root.windowTitle)

    background: Rectangle {
        radius: width / 2
        color: root.down ? "#E6534D" : "#FF5F57"
    }
}
