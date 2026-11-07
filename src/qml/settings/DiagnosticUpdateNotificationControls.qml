// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

Column {
    objectName: "diagnosticUpdateNotificationControls"
    width: parent ? parent.width : 0
    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        width: parent.width
        text: i18n("Local notification test")
        font.weight: Font.DemiBold
    }

    QQC2.Label {
        width: parent.width
        text: i18n("Only a loopback mock is used. Opening a release is recorded locally; no browser is started.")
        wrapMode: Text.Wrap
    }

    Column {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            objectName: "testRelease031Button"
            text: i18n("Check mock release 0.3.1")
            width: parent.width
            enabled: !UpdateChecker.checking
            onClicked: {
                UpdateChecker.setDiagnosticReleaseVersion("0.3.1")
                UpdateChecker.checkManually()
            }
        }

        QQC2.Button {
            objectName: "testRelease032Button"
            text: i18n("Check mock release 0.3.2")
            width: parent.width
            enabled: !UpdateChecker.checking
            onClicked: {
                UpdateChecker.setDiagnosticReleaseVersion("0.3.2")
                UpdateChecker.checkManually()
            }
        }
    }

    QQC2.Label {
        width: parent.width
        text: i18n("Release action log: %1", UpdateChecker.diagnosticReleaseOpenLogPath)
        visible: UpdateChecker.diagnosticReleaseOpenLogPath.length > 0
        wrapMode: Text.WrapAnywhere
        font: Kirigami.Theme.smallFont
    }
}
