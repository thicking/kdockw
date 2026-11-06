// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import "../../src/qml/PreviewBorderColor.js" as PreviewBorderColor

Item {
    TestCase {
        name: "PreviewBorderColor"
        when: windowShown

        function test_opaqueDarkAndLightSurfaces_data() {
            return [
                { tag: "dark", card: "#20242a", theme: "#f5f5f5", lighter: true },
                { tag: "light", card: "#f1eee8", theme: "#181818", lighter: false },
                { tag: "custom-tint", card: "#5b315f", theme: "#f8f8f8", lighter: true },
            ]
        }

        function test_opaqueDarkAndLightSurfaces(data) {
            const card = Qt.color(data.card)
            const theme = Qt.color(data.theme)
            const border = Qt.color(PreviewBorderColor.colorForSurface(card, theme, false))
            const surfaceLuminance = PreviewBorderColor.surfaceLuminance(card, theme)
            const borderLuminance = PreviewBorderColor.relativeLuminance(border)

            compare(border.a, 1, "the outline stays fully opaque over uncertain composition")
            compare(border.r, border.g, "the neutral outline has no color cast")
            compare(border.g, border.b, "the neutral outline has no color cast")
            verify(data.lighter ? borderLuminance > surfaceLuminance
                                : borderLuminance < surfaceLuminance)
            verify(Math.abs(PreviewBorderColor.surfaceContrastRatio(border, card, theme) - 1.7) < 0.02)
        }

        function test_translucentCardUsesKnownKdeSurfaceEstimate() {
            const card = Qt.rgba(0.18, 0.25, 0.35, 0.38)
            const darkTheme = Qt.color("#20252b")
            const lightTheme = Qt.color("#f2f0ec")
            const darkBorder = Qt.color(PreviewBorderColor.colorForSurface(card, darkTheme, false))
            const lightBorder = Qt.color(PreviewBorderColor.colorForSurface(card, lightTheme, false))

            verify(Math.abs(PreviewBorderColor.surfaceContrastRatio(darkBorder, card, darkTheme) - 1.7) < 0.02)
            verify(Math.abs(PreviewBorderColor.surfaceContrastRatio(lightBorder, card, lightTheme) - 1.7) < 0.02)
            verify(PreviewBorderColor.surfaceLuminance(card, darkTheme)
                   !== PreviewBorderColor.surfaceLuminance(card, lightTheme),
                   "theme surface changes must affect translucent-card color resolution")
        }

        function test_hoverStrengthensContrastWithoutTint() {
            const card = Qt.color("#30343a")
            const theme = Qt.color("#f4f4f4")
            const normal = Qt.color(PreviewBorderColor.colorForSurface(card, theme, false))
            const hovered = Qt.color(PreviewBorderColor.colorForSurface(card, theme, true))

            verify(PreviewBorderColor.surfaceContrastRatio(hovered, card, theme)
                   > PreviewBorderColor.surfaceContrastRatio(normal, card, theme))
            compare(hovered.r, hovered.g)
            compare(hovered.g, hovered.b)
        }
    }
}
