// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0

Item {
    id: root
    width: 200
    height: 125

    ClippedPipeWireSourceItem {
        id: clippedSource
        objectName: "clippedPipeWireSource"
        width: 320
        height: 200
        clipMode: "rounded"
        clipViewportRect: Qt.rect(60, 37.5, 200, 125)
        clipRadius: 18
    }

    TestCase {
        name: "PipeWireClipGeometry"
        when: windowShown

        function init() {
            clippedSource.clipMode = "rounded"
            clippedSource.clipViewportRect = Qt.rect(60, 37.5, 200, 125)
            clippedSource.clipRadius = 18
        }

        function test_roundedClipUsesSourceLocalViewportCoordinates() {
            compare(clippedSource.width, 320)
            compare(clippedSource.height, 200)
            compare(clippedSource.clipMode, "rounded")
            compare(clippedSource.clipViewportRect, Qt.rect(60, 37.5, 200, 125))
            compare(clippedSource.clipRadius, 18)
        }

        function test_center50ModeSelectsTheCentralHalfOfTheSource() {
            clippedSource.clipMode = "center50"
            compare(clippedSource.clipMode, "center50")
            compare(clippedSource.width / 4, 80)
            compare(clippedSource.height / 4, 50)
        }
    }
}
