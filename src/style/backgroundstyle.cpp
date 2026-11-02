// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "backgroundstyle.h"

#include <KColorScheme>
#include <KWindowEffects>

namespace kdockw
{

BackgroundEffectPlan backgroundEffectPlan(BackgroundStyleType type, const QRegion &region)
{
    return {
        .blurEnabled = type == BackgroundStyleType::PanelInherit || type == BackgroundStyleType::Acrylic,
        .contrastEnabled = type == BackgroundStyleType::PanelInherit,
        .region = region,
    };
}

BackgroundEffectTransition backgroundEffectTransition(const BackgroundEffectPlan &plan, const BackgroundEffectPlan &previousPlan)
{
    return {
        .setBlurRegion = plan.blurEnabled,
        .disableBlur = !plan.blurEnabled && previousPlan.blurEnabled,
        .setContrastRegion = plan.contrastEnabled,
        .disableContrast = !plan.contrastEnabled && previousPlan.contrastEnabled,
    };
}

void applyBackgroundToWindow(QWindow *window, const BackgroundEffectPlan &plan, const BackgroundEffectPlan &previousPlan)
{
    if (!window) {
        return;
    }

    const BackgroundEffectTransition transition = backgroundEffectTransition(plan, previousPlan);
    if (transition.setBlurRegion && KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind)) {
        // KWindowEffects replaces the previous region when called enabled=true.
        // Keep blur active while zoom changes the panel bounds; toggling it off
        // first creates a visible unblurred frame on every geometry update.
        KWindowEffects::enableBlurBehind(window, true, plan.region);
    } else if (transition.disableBlur) {
        KWindowEffects::enableBlurBehind(window, false);
    }

    if (transition.setContrastRegion && KWindowEffects::isEffectAvailable(KWindowEffects::BackgroundContrast)) {
        KWindowEffects::enableBackgroundContrast(window, true, 1.0, 1.0, 1.0, plan.region);
    } else if (transition.disableContrast) {
        KWindowEffects::enableBackgroundContrast(window, false);
    }
}

void removeBackgroundFromWindow(QWindow *window)
{
    if (!window) {
        return;
    }

    KWindowEffects::enableBlurBehind(window, false);
    KWindowEffects::enableBackgroundContrast(window, false);
}

QColor computeBackgroundColor(BackgroundStyleType type, const QString &tintColorHex, qreal opacity, bool useAccentColor, bool useSystemColor)
{
    if (type == BackgroundStyleType::Transparent) {
        return Qt::transparent;
    }

    QColor color;

    switch (type) {
    case BackgroundStyleType::PanelInherit:
    case BackgroundStyleType::Acrylic: {
        if (useAccentColor) {
            KColorScheme scheme(QPalette::Normal, KColorScheme::Selection);
            color = scheme.background(KColorScheme::NormalBackground).color();
        }
        if (!useAccentColor || !color.isValid()) {
            KColorScheme scheme(QPalette::Normal, KColorScheme::Header);
            color = scheme.background(KColorScheme::NormalBackground).color();
        }
        break;
    }

    case BackgroundStyleType::Tinted: {
        if (useSystemColor) {
            // System color mode: same as PanelInherit/Acrylic (Header or Selection)
            if (useAccentColor) {
                KColorScheme scheme(QPalette::Normal, KColorScheme::Selection);
                color = scheme.background(KColorScheme::NormalBackground).color();
            }
            if (!useAccentColor || !color.isValid()) {
                KColorScheme scheme(QPalette::Normal, KColorScheme::Header);
                color = scheme.background(KColorScheme::NormalBackground).color();
            }
        } else {
            color = QColor::fromString(tintColorHex);
            if (!color.isValid()) {
                KColorScheme scheme(QPalette::Normal, KColorScheme::Header);
                color = scheme.background(KColorScheme::NormalBackground).color();
            }
        }
        break;
    }

    default:
        break;
    }

    color.setAlphaF(static_cast<float>(opacity));
    return color;
}

bool styleUsesBlur(BackgroundStyleType type)
{
    return type == BackgroundStyleType::PanelInherit || type == BackgroundStyleType::Acrylic;
}

bool isStyleAvailable(BackgroundStyleType /* type */)
{
    return true;
}

} // namespace kdockw
