// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>

#include "utils/springzoomcontroller.h"

#include <cmath>

using Catch::Matchers::WithinAbs;

namespace
{
struct Result {
    qreal cursor;
    qreal amount;
};

Result simulate(int refreshRate, qreal targetCursor, qreal targetAmount, qreal durationSeconds = 1.0)
{
    kdockw::SpringZoomController controller;
    controller.synchronize(150.0, 0.0);
    controller.setTarget(targetCursor, targetAmount, 170.0, 0.60, 1.0, 0.0, 1000.0);
    const int frames = static_cast<int>(durationSeconds * refreshRate);
    const qreal frameTime = 1.0 / refreshRate;
    for (int frame = 0; frame < frames; ++frame) {
        controller.advance(frameTime);
    }
    return {controller.cursor(), controller.amount()};
}
}

TEST_CASE("Spring zoom uses elapsed time rather than a fixed frame count", "[zoom][spring]")
{
    const auto at60 = simulate(60, 720.0, 1.0);
    const auto at120 = simulate(120, 720.0, 1.0);
    const auto at144 = simulate(144, 720.0, 1.0);
    REQUIRE_THAT(at60.cursor, WithinAbs(at120.cursor, 0.15));
    REQUIRE_THAT(at60.cursor, WithinAbs(at144.cursor, 0.15));
    REQUIRE_THAT(at60.amount, WithinAbs(at120.amount, 0.002));
    REQUIRE_THAT(at60.amount, WithinAbs(at144.amount, 0.002));
}

TEST_CASE("Spring zoom follows a sudden cursor move and settles at its target", "[zoom][spring]")
{
    kdockw::SpringZoomController controller;
    controller.synchronize(200.0, 0.0);
    controller.setTarget(850.0, 1.0, 170.0, 0.60, 1.0, 0.0, 1000.0);

    controller.advance(1.0 / 60.0);
    REQUIRE(controller.cursor() > 200.0);
    REQUIRE(controller.cursor() < 850.0);
    REQUIRE(controller.amount() > 0.0);
    REQUIRE(controller.amount() < 1.0);

    for (int frame = 0; frame < 600 && !controller.settled(); ++frame) {
        controller.advance(1.0 / 144.0);
    }
    REQUIRE(controller.settled());
    REQUIRE_THAT(controller.cursor(), WithinAbs(850.0, 0.002));
    REQUIRE_THAT(controller.amount(), WithinAbs(1.0, 0.002));

    controller.setTarget(850.0, 0.0, 170.0, 0.60, 1.0, 0.0, 1000.0);
    for (int frame = 0; frame < 600 && !controller.settled(); ++frame) {
        controller.advance(1.0 / 60.0);
    }
    REQUIRE(controller.settled());
    REQUIRE_THAT(controller.amount(), WithinAbs(0.0, 0.002));
}

TEST_CASE("Spring zoom clamps long stalls and cursor bounds", "[zoom][spring]")
{
    kdockw::SpringZoomController controller;
    controller.synchronize(10.0, 0.0);
    controller.setTarget(500.0, 1.0, 170.0, 0.60, 1.0, 0.0, 250.0);
    controller.advance(5.0); // capped to 100 ms, split into <= 1/240 s substeps
    REQUIRE(controller.cursor() <= 250.0);
    REQUIRE(controller.cursor() >= 0.0);
    REQUIRE(controller.amount() <= 1.0);
    REQUIRE(controller.amount() >= 0.0);
}

TEST_CASE("Spring parameters affect response speed", "[zoom][spring]")
{
    const auto slow = simulate(60, 720.0, 1.0, 0.12);
    kdockw::SpringZoomController fastController;
    fastController.synchronize(150.0, 0.0);
    fastController.setTarget(720.0, 1.0, 260.0, 0.75, 1.8, 0.0, 1000.0);
    for (int frame = 0; frame < 8; ++frame) {
        fastController.advance(1.0 / 60.0);
    }
    REQUIRE(fastController.amount() > slow.amount);
}
