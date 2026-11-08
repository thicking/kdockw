// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "TestUtils.js" as T

Item {
    id: root
    width: 1000
    height: 1400

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "IconsPageMagnification"
        when: windowShown

        Component {
            id: pageComponent
            Settings.IconsPage {
                width: 900
                height: 1300
            }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function makePage() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page, "IconsPage failed to load")
            return page
        }

        function test_switchingModesAndSpringControlsUpdatesSettingsLive() {
            const page = makePage()
            const classic = T.findFirst(page, o => o.objectName === "classicMagnificationCard")
            const spring = T.findFirst(page, o => o.objectName === "springMagnificationCard")
            const stiffness = T.findFirst(page, o => o.objectName === "springStiffnessSlider")
            const damping = T.findFirst(page, o => o.objectName === "springDampingSlider")
            const speed = T.findFirst(page, o => o.objectName === "springSpeedSlider")
            verify(classic && spring && stiffness && damping && speed)

            compare(DockSettings.magnificationMode, 1)
            compare(DockSettings.maxZoomFactor, 1.9)
            compare(DockSettings.springStiffness, 170)
            compare(DockSettings.springDamping, 0.60)
            compare(DockSettings.springSpeed, 1.0)
            compare(classic.checked, false)
            compare(spring.checked, true)
            verify(stiffness.visible && damping.visible && speed.visible)

            classic.activate()
            tryVerify(() => DockSettings.magnificationMode === 0)
            tryVerify(() => classic.checked && !spring.checked)
            verify(!stiffness.visible && !damping.visible && !speed.visible)

            spring.activate()
            tryVerify(() => DockSettings.magnificationMode === 1)
            tryVerify(() => spring.checked && !classic.checked)
            tryVerify(() => stiffness.visible && damping.visible && speed.visible)

            stiffness.moved(240)
            damping.moved(1.1)
            speed.moved(1.7)
            compare(DockSettings.springStiffness, 240)
            compare(DockSettings.springDamping, 1.1)
            compare(DockSettings.springSpeed, 1.7)

            classic.activate()
            tryVerify(() => DockSettings.magnificationMode === 0)
            tryVerify(() => classic.checked && !spring.checked)
            tryVerify(() => !stiffness.visible && !damping.visible && !speed.visible)
        }
    }
}
