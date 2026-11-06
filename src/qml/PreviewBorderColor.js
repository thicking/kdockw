// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

.pragma library

// Resolve the preview surface against KDE's known window color. This is a
// stable estimate for translucent surfaces; it is not the compositor's actual
// wallpaper/blur result.
function _linearChannel(channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function _srgbChannel(channel) {
    const clamped = Math.max(0, Math.min(1, channel))
    return clamped <= 0.0031308
        ? clamped * 12.92
        : 1.055 * Math.pow(clamped, 1 / 2.4) - 0.055
}

function relativeLuminance(color) {
    return 0.2126 * _linearChannel(color.r)
         + 0.7152 * _linearChannel(color.g)
         + 0.0722 * _linearChannel(color.b)
}

function surfaceLuminance(cardColor, themeBackground) {
    const alpha = cardColor.a === undefined ? 1 : cardColor.a
    const backgroundAlpha = themeBackground.a === undefined ? 1 : themeBackground.a
    const outAlpha = alpha + backgroundAlpha * (1 - alpha)
    if (outAlpha <= 0)
        return relativeLuminance({ r: 0.5, g: 0.5, b: 0.5 })

    const red = (cardColor.r * alpha
        + themeBackground.r * backgroundAlpha * (1 - alpha)) / outAlpha
    const green = (cardColor.g * alpha
        + themeBackground.g * backgroundAlpha * (1 - alpha)) / outAlpha
    const blue = (cardColor.b * alpha
        + themeBackground.b * backgroundAlpha * (1 - alpha)) / outAlpha
    return relativeLuminance({ r: red, g: green, b: blue })
}

function contrastRatio(first, second) {
    const firstAlpha = first.a === undefined ? 1 : first.a
    const red = first.r * firstAlpha + second.r * (1 - firstAlpha)
    const green = first.g * firstAlpha + second.g * (1 - firstAlpha)
    const blue = first.b * firstAlpha + second.b * (1 - firstAlpha)
    const firstLuminance = relativeLuminance({ r: red, g: green, b: blue })
    const secondLuminance = relativeLuminance(second)
    return (Math.max(firstLuminance, secondLuminance) + 0.05)
         / (Math.min(firstLuminance, secondLuminance) + 0.05)
}

function surfaceContrastRatio(foreground, cardColor, themeBackground) {
    const firstLuminance = relativeLuminance(foreground)
    const secondLuminance = surfaceLuminance(cardColor, themeBackground)
    return (Math.max(firstLuminance, secondLuminance) + 0.05)
         / (Math.min(firstLuminance, secondLuminance) + 0.05)
}

function _hexByte(channel) {
    const value = Math.round(Math.max(0, Math.min(1, channel)) * 255)
    return value.toString(16).padStart(2, "0")
}

function colorForSurface(cardColor, themeBackground, hovered) {
    const backgroundLuminance = surfaceLuminance(cardColor, themeBackground)
    const targetRatio = hovered ? 1.9 : 1.7
    const borderLuminance = backgroundLuminance < 0.5
        ? (backgroundLuminance + 0.05) * targetRatio - 0.05
        : (backgroundLuminance + 0.05) / targetRatio - 0.05
    const gray = _srgbChannel(borderLuminance)
    const byte = _hexByte(gray)
    return "#ff" + byte + byte + byte
}
