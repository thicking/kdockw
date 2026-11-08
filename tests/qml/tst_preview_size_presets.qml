// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "../../src/qml/settings/PreviewSizePresets.js" as Presets
import "TestUtils.js" as T

Item {
    width: 760
    height: 500

    Item { id: stage; anchors.fill: parent }

    TestCase {
        name: "PreviewSizePresets"
        when: windowShown

        Component {
            id: pageComponent
            Settings.PreviewPage {
                width: 720
                stage: null
            }
        }

        function init() {
            KDockWMocks.resetAll()
        }

        function makePage() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page)
            return page
        }

        function test_pageMapsSavedSettingsToPresetAndCustom() {
            const page = makePage()
            const selector = T.findFirst(page, item => item.objectName === "thumbnailSizePreset")
            verify(selector)
            compare(selector.currentIndex, 4, "the 320×200 default maps to the large preset")

            DockSettings.previewThumbnailSize = 260
            DockSettings.previewMaximumHeight = 163
            tryCompare(selector, "currentIndex", 3)

            DockSettings.previewThumbnailSize = 240
            DockSettings.previewMaximumHeight = 150
            compare(selector.currentIndex, 0, "a user-defined pair remains custom")
        }

        function test_pageAppliesPresetThroughExistingSettingsImmediately() {
            const page = makePage()
            compare(page.applyThumbnailSizePreset(2), true)
            compare(DockSettings.previewThumbnailSize, 220)
            compare(DockSettings.previewMaximumHeight, 138)
            compare(page.thumbnailPresetIndex(), 2)
            compare(page.applyThumbnailSizePreset(0), false)
            compare(DockSettings.previewThumbnailSize, 220)
            compare(DockSettings.previewMaximumHeight, 138)
        }

        function test_presetDimensionsAndIdentity() {
            const expected = [
                { id: "compact", width: 180, maximumHeight: 113 },
                { id: "standard", width: 220, maximumHeight: 138 },
                { id: "enlarged", width: 260, maximumHeight: 163 },
                { id: "large", width: 320, maximumHeight: 200 },
            ]
            compare(Presets.presets.length, expected.length)
            for (let i = 0; i < expected.length; ++i) {
                compare(Presets.presets[i].id, expected[i].id)
                compare(Presets.presets[i].width, expected[i].width)
                compare(Presets.presets[i].maximumHeight, expected[i].maximumHeight)
                compare(Presets.indexFor(expected[i].width, expected[i].maximumHeight), i)
                compare(Presets.sizeForIndex(i).id, expected[i].id)
            }
        }

        function test_existingCustomDimensionsRemainCustom() {
            compare(Presets.indexFor(200, 180), -1)
            compare(Presets.indexFor(240, 150), -1)
            compare(Presets.sizeForIndex(-1), null)
            compare(Presets.sizeForIndex(Presets.presets.length), null)
        }

        function test_applyingPresetUpdatesOnlyExistingSizeSettings() {
            const settings = {
                previewThumbnailSize: 200,
                previewMaximumHeight: 180,
                untouched: "keep",
            }
            verify(Presets.apply(2, settings))
            compare(settings.previewThumbnailSize, 260)
            compare(settings.previewMaximumHeight, 163)
            compare(settings.untouched, "keep")
            verify(!Presets.apply(-1, settings))
            compare(settings.previewThumbnailSize, 260)
            compare(settings.previewMaximumHeight, 163)
        }
    }
}
