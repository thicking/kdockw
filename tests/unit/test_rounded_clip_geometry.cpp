// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "scenegraph/roundedclipgeometry.h"

#include <catch2/catch_test_macros.hpp>

#include <cmath>

namespace
{
qreal signedDoubleArea(const QPointF &a, const QPointF &b, const QPointF &c)
{
    return (b.x() - a.x()) * (c.y() - a.y()) - (b.y() - a.y()) * (c.x() - a.x());
}
}

TEST_CASE("Rounded preview clip uses supported triangle topology", "[preview][scenegraph]")
{
    SECTION("Square viewport is four nondegenerate triangles")
    {
        const auto vertices = kdockw::roundedClipTriangleVertices(QRectF(0, 0, 120, 100), 0);
        REQUIRE(vertices.size() == 12);
        for (qsizetype i = 0; i < vertices.size(); i += 3) {
            REQUIRE(signedDoubleArea(vertices[i], vertices[i + 1], vertices[i + 2]) > 0);
        }
    }

    SECTION("Rounded viewport is a finite triangle list inside its bounds")
    {
        const QRectF bounds(0, 0, 120, 100);
        const qreal radius = 24;
        const auto vertices = kdockw::roundedClipTriangleVertices(bounds, radius);
        REQUIRE(vertices.size() == 300);

        for (qsizetype i = 0; i < vertices.size(); i += 3) {
            const auto &a = vertices[i];
            const auto &b = vertices[i + 1];
            const auto &c = vertices[i + 2];
            REQUIRE(signedDoubleArea(a, b, c) > 0);
            for (const auto &point : {a, b, c}) {
                REQUIRE(bounds.contains(point));
                REQUIRE(std::isfinite(point.x()));
                REQUIRE(std::isfinite(point.y()));
                const qreal dx = point.x() - radius;
                const qreal dy = point.y() - radius;
                REQUIRE_FALSE((point.x() < radius && point.y() < radius
                               && dx * dx + dy * dy < radius * radius - 1e-6));
            }
        }
    }

    SECTION("Large radii clamp to half of the shorter dimension")
    {
        const auto clamped = kdockw::roundedClipTriangleVertices(QRectF(0, 0, 120, 100), 80);
        const auto expected = kdockw::roundedClipTriangleVertices(QRectF(0, 0, 120, 100), 50);
        REQUIRE(clamped == expected);
    }
}
