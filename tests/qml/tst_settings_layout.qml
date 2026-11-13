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
        name: "SettingsLayout"
        when: windowShown

        Component {
            id: pageComponent
            Settings.LayoutPage { width: 960 }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function createPage() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page, "LayoutPage failed to load")
            return page
        }

        function findWindowGapSlider(page) {
            const slider = T.findFirst(page, object => object.objectName === "windowGapSlider")
            verify(slider, "window gap slider is missing from Layout & Position")
            return slider
        }

        function test_windowGapSliderIsVisibleForEveryDockMode() {
            const page = createPage()
            compare(page.title, "Layout & Position")
            const slider = findWindowGapSlider(page)

            compare(slider.text, "Gap to maximized windows")
            compare(slider.from, 0)
            compare(slider.to, 20)
            compare(slider.stepSize, 1)
            compare(slider.value, 0)

            for (let edge = 0; edge < 4; ++edge) {
                for (const floating of [false, true]) {
                    for (let visibilityMode = 0; visibilityMode < 3; ++visibilityMode) {
                        DockSettings.edge = edge
                        DockSettings.floating = floating
                        DockSettings.visibilityMode = visibilityMode
                        tryVerify(() => slider.visible && slider.enabled)
                    }
                }
            }
        }

        function test_windowGapSliderWritesTheSetting() {
            const page = createPage()
            const slider = findWindowGapSlider(page)

            DockSettings.windowGap = 10
            tryCompare(slider, "value", 10)
            slider.moved(5)
            compare(DockSettings.windowGap, 5)
        }

        function test_windowGapLabelIsTranslatedInRussian() {
            if (!testRussianLocaleAvailable)
                skip("ru_RU.UTF-8 locale is not installed on this test host")

            const page = createPage()
            compare(page.title, "Расположение и позиция")
            const slider = findWindowGapSlider(page)
            compare(slider.text, "Зазор между доком и окнами")
        }
    }
}
