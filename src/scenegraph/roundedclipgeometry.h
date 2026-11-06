// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QPointF>
#include <QRectF>
#include <QVector>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cmath>

namespace kdockw
{

/**
 * Return a rounded-rectangle clip polygon tessellated as independent
 * triangles, using only primitive topologies supported by Qt 6 QRhi.
 */
[[nodiscard]] inline QVector<QPointF> roundedClipTriangleVertices(const QRectF &rect,
                                                                  qreal requestedRadius,
                                                                  int cornerSegments = 24)
{
    const qreal radius = std::clamp(requestedRadius, qreal(0), std::min(rect.width(), rect.height()) / 2);
    QVector<QPointF> perimeter;

    if (radius <= 0) {
        perimeter = {rect.topLeft(), rect.topRight(), rect.bottomRight(), rect.bottomLeft()};
    } else {
        constexpr qreal pi = 3.14159265358979323846;
        const std::array<QPointF, 4> centers = {
            QPointF(rect.left() + radius, rect.top() + radius),
            QPointF(rect.right() - radius, rect.top() + radius),
            QPointF(rect.right() - radius, rect.bottom() - radius),
            QPointF(rect.left() + radius, rect.bottom() - radius),
        };
        const std::array<qreal, 4> starts = {pi, 1.5 * pi, 0, 0.5 * pi};
        perimeter.reserve(4 * (cornerSegments + 1));

        for (std::size_t corner = 0; corner < centers.size(); ++corner) {
            for (int segment = 0; segment <= cornerSegments; ++segment) {
                const qreal angle = starts[corner] + (0.5 * pi * segment / cornerSegments);
                perimeter.append(QPointF(centers[corner].x() + radius * std::cos(angle),
                                         centers[corner].y() + radius * std::sin(angle)));
            }
        }
    }

    QVector<QPointF> vertices;
    vertices.reserve(perimeter.size() * 3);
    const QPointF center = rect.center();
    for (qsizetype i = 0; i < perimeter.size(); ++i) {
        vertices.append(center);
        vertices.append(perimeter[i]);
        vertices.append(perimeter[(i + 1) % perimeter.size()]);
    }
    return vertices;
}

} // namespace kdockw
