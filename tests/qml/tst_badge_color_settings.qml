// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "../../src/qml/BadgeTextColor.js" as BadgeTextColor
import "TestUtils.js" as T

Item {
    id: root
    width: 720
    height: 300

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "BadgeColorSettings"
        when: windowShown

        Component {
            id: settingsComponent
            Settings.BadgeColorSettings {
                width: 680
            }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function makeSettings() {
            let settings = createTemporaryObject(settingsComponent, stage)
            verify(settings)
            return settings
        }

        function test_defaultsPreviewContrastAndRestore() {
            let settings = makeSettings()
            let backgroundSwatch = T.findFirst(settings, o => o.objectName === "badgeBackgroundColorSwatch")
            let textSwatch = T.findFirst(settings, o => o.objectName === "badgeTextColorSwatch")
            let preview = T.findFirst(settings, o => o.objectName === "badgeColorPreview")
            let restore = T.findFirst(settings, o => o.objectName === "restoreBadgeColorsButton")
            let contrastStatus = T.findFirst(settings, o => o.objectName === "badgeContrastStatus")
            verify(backgroundSwatch && textSwatch && preview && restore && contrastStatus)

            compare(DockSettings.badgeBackgroundColor.toString(), "#ff3b30")
            compare(DockSettings.badgeTextColor.toString(), "#ffffff")
            compare(backgroundSwatch.color.toString(), "#ff3b30")
            compare(textSwatch.color.toString(), "#ffffff")
            compare(preview.color.toString(), "#ff3b30")
            verify(contrastStatus.text.indexOf("3.55:1") >= 0)
            verify(contrastStatus.text.indexOf("below recommended 4.5:1") >= 0)
            compare(BadgeTextColor.contrastRatio(textSwatch.color, backgroundSwatch.color) < 4.5, true)

            DockSettings.badgeBackgroundColor = "#ff000000"
            DockSettings.badgeTextColor = "#ffffffff"
            tryVerify(() => backgroundSwatch.color.toString() === "#000000")
            tryVerify(() => preview.color.toString() === "#000000")
            verify(BadgeTextColor.contrastRatio(textSwatch.color, backgroundSwatch.color) >= 4.5)
            verify(contrastStatus.text.indexOf("meets recommended 4.5:1") >= 0)

            DockSettings.badgeBackgroundColor = "#ff00ff00"
            DockSettings.badgeTextColor = "#ff000000"
            mouseClick(restore)
            tryVerify(() => backgroundSwatch.color.toString() === "#ff3b30")
            tryVerify(() => textSwatch.color.toString() === "#ffffff")
            tryVerify(() => preview.color.toString() === "#ff3b30")
        }
    }
}
