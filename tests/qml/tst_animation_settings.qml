// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "TestUtils.js" as T

Item {
    width: 1000
    height: 1200

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "AnimationSettings"
        when: windowShown

        Component {
            id: pageComponent
            Settings.AnimationsPage { width: 960 }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function test_controlsReflectAndUpdateAnimationSettings() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page, "AnimationsPage failed to load")

            const launchSwitch = T.findFirst(page, o => o.objectName === "launchBounceEnabledSwitch")
            const launchIntensity = T.findFirst(page, o => o.objectName === "launchBounceIntensityControl")
            const launchSpeed = T.findFirst(page, o => o.objectName === "launchBounceSpeedControl")
            const clickBounceSwitch = T.findFirst(page, o => o.objectName === "clickBounceEnabledSwitch")
            const attentionSwitch = T.findFirst(page, o => o.objectName === "attentionAnimationEnabledSwitch")
            const attentionIntensity = T.findFirst(page, o => o.objectName === "attentionAnimationIntensityControl")
            const attentionDuration = T.findFirst(page, o => o.objectName === "attentionAnimationDurationControl")
            const attentionPicker = T.findFirst(page, o => o.objectName === "attentionAnimationPicker")
            verify(launchSwitch && launchIntensity && launchSpeed && clickBounceSwitch
                   && attentionSwitch && attentionIntensity && attentionDuration && attentionPicker)

            compare(launchSwitch.checked, true)
            compare(launchIntensity.value, 150)
            compare(launchIntensity.from, 50)
            compare(launchIntensity.to, 200)
            compare(clickBounceSwitch.checked, true)
            compare(launchSpeed.value, 100)
            compare(attentionSwitch.checked, true)
            compare(attentionIntensity.value, 100)
            compare(attentionDuration.value, 3)

            DockSettings.launchBounceIntensity = 130
            DockSettings.launchBounceSpeed = 80
            DockSettings.attentionAnimationIntensity = 120
            DockSettings.attentionAnimationDuration = 8
            tryCompare(launchIntensity, "value", 130)
            tryCompare(launchSpeed, "value", 80)
            tryCompare(attentionIntensity, "value", 120)
            tryCompare(attentionDuration, "value", 8)

            mouseClick(launchSwitch, launchSwitch.width / 2, launchSwitch.height / 2)
            tryCompare(DockSettings, "launchBounceEnabled", false)
            tryCompare(launchIntensity, "visible", false)

            mouseClick(attentionSwitch, attentionSwitch.width / 2, attentionSwitch.height / 2)
            tryCompare(DockSettings, "attentionAnimationEnabled", false)
            tryCompare(attentionPicker, "enabled", false)

            mouseClick(clickBounceSwitch, clickBounceSwitch.width / 2, clickBounceSwitch.height / 2)
            tryCompare(DockSettings, "clickBounceEnabled", false)
        }

    }
}
