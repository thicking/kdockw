// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

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
        name: "AnimationSettingsRussian"
        when: windowShown

        Component {
            id: pageComponent
            Settings.AnimationsPage { width: 960 }
        }
        Component {
            id: behaviorPageComponent
            Settings.BehaviorPage { width: 960 }
        }
        Component {
            id: previewPageComponent
            Settings.PreviewPage { width: 960 }
        }

        function init() {
            KDockWMocks.resetAll()
            DockSettings.visibilityMode = 1
            DockSettings.previewEnabled = true
        }

        function test_translationCatalogIsLoaded() {
            if (!testRussianLocaleAvailable) {
                skip("ru_RU.UTF-8 locale is not installed on this test host")
            }
            const page = createTemporaryObject(pageComponent, stage)
            verify(page, "AnimationsPage failed to load")
            compare(page.title, "Анимация и индикаторы")
            const heightControl = T.findFirst(page, o => o.objectName === "launchBounceIntensityControl")
            verify(heightControl)
            compare(heightControl.label, "Высота подпрыгивания (% от размера значка)")
            const clickSwitch = T.findFirst(page, o => o.objectName === "clickBounceEnabledSwitch")
            verify(clickSwitch)
            compare(clickSwitch.text, "Подпрыгивание при активации открытого приложения")

            const behaviorPage = createTemporaryObject(behaviorPageComponent, stage)
            verify(behaviorPage, "BehaviorPage failed to load")
            const showHideSwitch = T.findFirst(behaviorPage, o => o.objectName === "dockShowHideAnimationSwitch")
            verify(showHideSwitch)
            compare(showHideSwitch.text, "Анимировать появление и скрытие дока")
            compare(showHideSwitch.description, "Плавно выдвигать док при изменении его видимости")
            const showDelay = T.findFirst(behaviorPage, o => o.text === "Задержка показа (мс)")
            const dockHideDelay = T.findFirst(behaviorPage, o => o.text === "Задержка скрытия (мс)")
            const animationDuration = T.findFirst(behaviorPage, o => o.text === "Длительность анимации дока (мс)")
            verify(showDelay)
            verify(dockHideDelay)
            verify(animationDuration)

            const previewPage = createTemporaryObject(previewPageComponent, stage)
            verify(previewPage, "PreviewPage failed to load")
            compare(previewPage.title, "Предпросмотр окон")
            const previewHideDelay = T.findFirst(previewPage, o => o.objectName === "previewHideDelaySlider")
            verify(previewHideDelay)
            compare(previewHideDelay.text, "Задержка скрытия (мс)")
        }
    }
}
