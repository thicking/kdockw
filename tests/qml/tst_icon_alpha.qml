// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import QtQuick.Window

Item {
    id: root
    width: 240
    height: 240

    TestCase {
        id: tc
        name: "IconAlphaSceneGraph"
        when: windowShown

        function init() {
            if (root.Window.window)
                root.Window.window.color = "#102030"
        }

        function containsCompositedColor(image, red, green, blue) {
            for (let y = 0; y < image.height; ++y) {
                for (let x = 0; x < image.width; ++x) {
                    if (Math.abs(image.red(x, y) - red) <= 2
                            && Math.abs(image.green(x, y) - green) <= 2
                            && Math.abs(image.blue(x, y) - blue) <= 2)
                        return true
                }
            }
            return false
        }

        Component {
            id: imageProbeComponent
            Item {
                id: probe
                width: 240
                height: 240
                property real zoom: 1.0
                property real imageOpacity: 1.0
                property int baseSize: 40
                property url imageSource
                property alias imageItem: iconImage

                Item {
                    anchors.centerIn: parent
                    width: probe.baseSize
                    height: probe.baseSize
                    transform: Scale {
                        origin.x: probe.baseSize / 2
                        origin.y: probe.baseSize / 2
                        xScale: probe.zoom
                        yScale: probe.zoom
                    }

                    Image {
                        id: iconImage
                        anchors.fill: parent
                        source: probe.imageSource
                        smooth: true
                        opacity: probe.imageOpacity
                    }
                }
            }
        }

        function test_sceneGraphPreservesIconAlphaAtZoomAndOpacity_data() {
            const rows = []
            for (const format of ["svg", "png"]) {
                for (const size of [24, 48, 72, 96]) {
                    rows.push({
                        tag: `${format}-${size}px`,
                        path: `fixtures/icon-alpha.${format}`,
                        size: size
                    })
                }
            }
            return rows
        }

        function test_sceneGraphPreservesIconAlphaAtZoomAndOpacity(data) {
            const probe = createTemporaryObject(imageProbeComponent, root, {
                imageSource: Qt.resolvedUrl(data.path),
                baseSize: data.size
            })
            verify(probe)
            tryCompare(probe.imageItem, "status", Image.Ready)

            const zooms = [1.0, 1.3, 1.5, 1.7]
            const opacities = [1.0, 0.75, 0.5]
            for (const opacity of opacities) {
                probe.imageOpacity = opacity
                for (const zoom of zooms) {
                    probe.zoom = zoom
                    wait(30)
                    tryCompare(probe.imageItem, "opacity", opacity)
                    const snapshot = grabImage(probe)
                    const expectedRed = Math.round(56 * opacity + 16 * (1 - opacity))
                    const expectedGreen = Math.round(153 * opacity + 32 * (1 - opacity))
                    const expectedBlue = Math.round(232 * opacity + 48 * (1 - opacity))
                    verify(containsCompositedColor(snapshot, expectedRed, expectedGreen, expectedBlue),
                           `${data.tag} has no pixel near expected composited RGB ${expectedRed},${expectedGreen},${expectedBlue} at zoom=${zoom}, opacity=${opacity}`)
                }
            }
        }
    }
}
