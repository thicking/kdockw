// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QColor>
#include <QRegion>
#include <QWindow>

namespace kdockw
{

enum class BackgroundStyleType : int {
    PanelInherit = 0,
    Transparent = 1,
    Tinted = 2, // UseSystemColor → Header color; otherwise user tint
    Acrylic = 3,
};

/// The compositor effects that must remain enabled while a style's region moves.
struct BackgroundEffectPlan {
    bool blurEnabled = false;
    bool contrastEnabled = false;
    QRegion region;
};

struct BackgroundEffectTransition {
    bool setBlurRegion = false;
    bool disableBlur = false;
    bool setContrastRegion = false;
    bool disableContrast = false;
};

/// Describe the compositor state for a style and its current visible region.
BackgroundEffectPlan backgroundEffectPlan(BackgroundStyleType type, const QRegion &region);

/// Describe the effect calls needed to transition from one plan to another.
BackgroundEffectTransition backgroundEffectTransition(const BackgroundEffectPlan &plan,
                                                       const BackgroundEffectPlan &previousPlan);

/// Apply compositor effects (blur, contrast) to @p window for the current plan.
/// Updates the current effects in place; an active effect is never disabled as
/// an intermediate step when only its region changes.
/// @param plan The desired effects and region. An empty region means whole window (avoid!).
void applyBackgroundToWindow(QWindow *window,
                             const BackgroundEffectPlan &plan,
                             const BackgroundEffectPlan &previousPlan);

/// Remove all compositor effects (blur, contrast) from @p window.
void removeBackgroundFromWindow(QWindow *window);

/// Compute the background color for a QML Rectangle.
/// @param tintColorHex Tinted style user color (hex, e.g. "#1e3a5f")
/// @param opacity Base opacity (0.0–1.0)
/// @param useAccentColor If true, use Selection (accent) color instead of Header color
/// @param useSystemColor If true (Tinted), use system Header color instead of tintColorHex
QColor computeBackgroundColor(BackgroundStyleType type, const QString &tintColorHex, qreal opacity, bool useAccentColor = false, bool useSystemColor = false);

/// Whether the given style uses blur behind.
bool styleUsesBlur(BackgroundStyleType type);

/// Whether the given style is available on this system.
bool isStyleAvailable(BackgroundStyleType type);

} // namespace kdockw
