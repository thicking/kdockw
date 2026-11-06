// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import com.thicking.kdockw 1.0
import "../BadgeTextColor.js" as BadgeTextColor

FormCard.FormCard {
    id: root

    property color secondaryTextColor: Kirigami.Theme.textColor
    readonly property color badgeBackgroundColor: DockSettings.badgeBackgroundColor
    readonly property color badgeTextColor: DockSettings.badgeTextColor
    readonly property var contrast: BadgeTextColor.contrastDescription(
        badgeTextColor, badgeBackgroundColor)

    FormCard.AbstractFormDelegate {
        background: null
        contentItem: RowLayout {
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Badge background color")
            }
            ColorSwatchButton {
                objectName: "badgeBackgroundColorSwatch"
                accessibleName: i18n("Badge background color")
                dialogTitle: i18n("Choose badge background color")
                color: root.badgeBackgroundColor
                onPicked: color => DockSettings.badgeBackgroundColor = color.toString()
            }
        }
    }

    FormCard.FormDelegateSeparator {}

    FormCard.AbstractFormDelegate {
        background: null
        contentItem: RowLayout {
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Badge text color")
            }
            ColorSwatchButton {
                objectName: "badgeTextColorSwatch"
                accessibleName: i18n("Badge text color")
                dialogTitle: i18n("Choose badge text color")
                color: root.badgeTextColor
                onPicked: color => DockSettings.badgeTextColor = color.toString()
            }
        }
    }

    FormCard.AbstractFormDelegate {
        background: null
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                objectName: "badgeColorPreview"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.75
                radius: height / 2
                color: root.badgeBackgroundColor
                border.width: 1
                border.color: Qt.alpha(root.badgeTextColor, 0.5)

                QQC2.Label {
                    anchors.fill: parent
                    text: "8"
                    color: root.badgeTextColor
                    renderType: Text.QtRendering
                    font.pixelSize: parent.height * 0.55
                    font.weight: DockSettings.badgeFontWeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Accessible.ignored: true
                }
            }

            QQC2.Label {
                objectName: "badgeContrastStatus"
                Layout.fillWidth: true
                text: i18nc("@label contrast ratio", "Contrast ratio: %1:1 (%2)",
                             root.contrast.ratio.toFixed(2),
                             root.contrast.meetsRecommended
                                 ? i18n("meets recommended 4.5:1")
                                 : i18n("below recommended 4.5:1"))
                color: root.contrast.meetsRecommended
                    ? root.secondaryTextColor : Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }
        }
    }

    FormCard.FormDelegateSeparator {}

    FormCard.AbstractFormDelegate {
        background: null
        contentItem: RowLayout {
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Restore badge color defaults")
            }
            QQC2.Button {
                objectName: "restoreBadgeColorsButton"
                text: i18n("Restore defaults")
                onClicked: {
                    DockSettings.badgeBackgroundColor = "#ffff3b30"
                    DockSettings.badgeTextColor = "#ffffffff"
                }
            }
        }
    }
}
