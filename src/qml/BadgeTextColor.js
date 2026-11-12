// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

.pragma library

// The badge background is an opaque Kirigami.Theme.highlightColor. Composite
// translucent foreground colors over it before measuring their effective
// contrast, as rendered by Qt Quick.
function _linearChannel(channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function _luminance(color) {
    return 0.2126 * _linearChannel(color.r)
         + 0.7152 * _linearChannel(color.g)
         + 0.0722 * _linearChannel(color.b)
}

function contrastRatio(foreground, background) {
    const alpha = foreground.a === undefined ? 1 : foreground.a
    const effectiveForeground = {
        r: foreground.r * alpha + background.r * (1 - alpha),
        g: foreground.g * alpha + background.g * (1 - alpha),
        b: foreground.b * alpha + background.b * (1 - alpha)
    }
    const foregroundLuminance = _luminance(effectiveForeground)
    const backgroundLuminance = _luminance(background)
    return (Math.max(foregroundLuminance, backgroundLuminance) + 0.05)
         / (Math.min(foregroundLuminance, backgroundLuminance) + 0.05)
}

function choose(background, preferredForeground) {
    if (contrastRatio(preferredForeground, background) >= 4.5)
        return preferredForeground

    const black = { r: 0, g: 0, b: 0, a: 1 }
    const white = { r: 1, g: 1, b: 1, a: 1 }
    return contrastRatio(black, background) >= contrastRatio(white, background)
        ? "#000000" : "#ffffff"
}

function composite(foreground, background) {
    const alpha = foreground.a === undefined ? 1 : foreground.a
    return Qt.rgba(foreground.r * alpha + background.r * (1 - alpha),
                   foreground.g * alpha + background.g * (1 - alpha),
                   foreground.b * alpha + background.b * (1 - alpha), 1)
}

function contrastDescription(foreground, background) {
    const ratio = contrastRatio(foreground, background)
    return {
        ratio: ratio,
        meetsRecommended: ratio >= 4.5
    }
}
