// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "style/backgroundstyle.h"

#include <catch2/catch_test_macros.hpp>

using kdockw::BackgroundStyleType;

TEST_CASE("Background effect plans match each visual style", "[background][effects]")
{
    const QRegion region(QRect(200, 1020, 1509, 56));

    const auto panel = kdockw::backgroundEffectPlan(BackgroundStyleType::PanelInherit, region);
    CHECK(panel.blurEnabled);
    CHECK(panel.contrastEnabled);
    CHECK(panel.region == region);

    const auto acrylic = kdockw::backgroundEffectPlan(BackgroundStyleType::Acrylic, region);
    CHECK(acrylic.blurEnabled);
    CHECK_FALSE(acrylic.contrastEnabled);
    CHECK(acrylic.region == region);

    for (const auto type : {BackgroundStyleType::Transparent, BackgroundStyleType::Tinted}) {
        const auto direct = kdockw::backgroundEffectPlan(type, region);
        CHECK_FALSE(direct.blurEnabled);
        CHECK_FALSE(direct.contrastEnabled);
    }
}

TEST_CASE("Zoom geometry replaces effect regions without disabling blur", "[background][effects][zoom]")
{
    const QRegion before(QRect(204, 1020, 1509, 56));
    const QRegion during(QRect(200, 1020, 1520, 56));
    const auto previous = kdockw::backgroundEffectPlan(BackgroundStyleType::PanelInherit, before);
    const auto current = kdockw::backgroundEffectPlan(BackgroundStyleType::PanelInherit, during);
    const auto transition = kdockw::backgroundEffectTransition(current, previous);

    CHECK(current.region == during);
    CHECK(transition.setBlurRegion);
    CHECK_FALSE(transition.disableBlur);
    CHECK(transition.setContrastRegion);
    CHECK_FALSE(transition.disableContrast);
}

TEST_CASE("Background style changes disable only effects no longer used", "[background][effects]")
{
    const QRegion region(QRect(200, 1020, 1520, 56));
    const auto panel = kdockw::backgroundEffectPlan(BackgroundStyleType::PanelInherit, region);
    const auto acrylic = kdockw::backgroundEffectPlan(BackgroundStyleType::Acrylic, region);
    const auto tinted = kdockw::backgroundEffectPlan(BackgroundStyleType::Tinted, region);

    const auto toAcrylic = kdockw::backgroundEffectTransition(acrylic, panel);
    CHECK(toAcrylic.setBlurRegion);
    CHECK_FALSE(toAcrylic.disableBlur);
    CHECK_FALSE(toAcrylic.setContrastRegion);
    CHECK(toAcrylic.disableContrast);

    const auto toTinted = kdockw::backgroundEffectTransition(tinted, acrylic);
    CHECK_FALSE(toTinted.setBlurRegion);
    CHECK(toTinted.disableBlur);
    CHECK_FALSE(toTinted.disableContrast);
}
