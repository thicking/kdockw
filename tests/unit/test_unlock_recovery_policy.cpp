// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_test_macros.hpp>

#include "shell/unlockrecoverypolicy.h"

using kdockw::UnlockRecoveryPolicy;
using kdockw::UnlockRecoveryState;

TEST_CASE("Unlock recovery only recreates a changed dock surface", "[shell][unlock]")
{
    const UnlockRecoveryState original{
        .screenIdentity = 1,
        .screenGeometry = QRect(0, 0, 1920, 1080),
        .windowSize = QSize(1920, 147),
        .layerSize = QSize(0, 147),
        .edge = 1,
        .platformEdge = 1,
        .requestedExclusiveZone = 59,
        .windowGap = 0,
        .reserveScreenSpace = true,
        .margin = 0,
        .visibilityMode = 0,
    };

    SECTION("Repeated unlock without a new lock is ignored")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        REQUIRE(policy.consume(original) == UnlockRecoveryPolicy::Decision::Unchanged);
        REQUIRE(policy.consume(original) == UnlockRecoveryPolicy::Decision::NoLockSnapshot);
    }

    SECTION("Screen geometry changes keep the recovery path")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        auto changed = original;
        changed.screenGeometry.setHeight(1200);
        REQUIRE(policy.consume(changed) == UnlockRecoveryPolicy::Decision::Changed);
    }

    SECTION("Exclusive zone changes keep the recovery path")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        auto changed = original;
        changed.requestedExclusiveZone = 64;
        REQUIRE(policy.consume(changed) == UnlockRecoveryPolicy::Decision::Changed);
    }

    SECTION("An unchanged exclusive zone keeps the current surface")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        REQUIRE(policy.consume(original) == UnlockRecoveryPolicy::Decision::Unchanged);
    }

    SECTION("Changing the window gap keeps the recovery path")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        auto changed = original;
        changed.windowGap = 5;
        changed.requestedExclusiveZone += 5;
        REQUIRE(policy.consume(changed) == UnlockRecoveryPolicy::Decision::Changed);
    }

    SECTION("Edge and layer size changes keep the recovery path")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        auto changed = original;
        changed.edge = 2;
        changed.platformEdge = 2;
        changed.layerSize = QSize(147, 0);
        REQUIRE(policy.consume(changed) == UnlockRecoveryPolicy::Decision::Changed);
    }

    SECTION("Window size changes keep the recovery path")
    {
        UnlockRecoveryPolicy policy;
        policy.remember(original);
        auto changed = original;
        changed.windowSize.setHeight(151);
        changed.layerSize.setHeight(151);
        REQUIRE(policy.consume(changed) == UnlockRecoveryPolicy::Decision::Changed);
    }
}
