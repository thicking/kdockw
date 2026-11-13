// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <algorithm>
#include <cmath>

namespace kdockw
{

inline int runningIndicatorReserveForSize(int indicatorSize)
{
    return std::max(0, indicatorSize) * 2;
}

/// Extra height above the panel needed for zoomed icons.
inline int zoomOverflowHeight(int iconSize, double maxZoomFactor)
{
    return static_cast<int>(std::ceil(iconSize * (maxZoomFactor - 1.0)));
}

/// Total surface height including dock, zoom overflow / tooltip reserve, and floating padding.
/// Shadow is rendered within available space and naturally clips at surface boundaries.
inline int surfaceHeight(int iconSize,
                         int crossPaddingLeading,
                         int crossPaddingTrailing,
                         int indicatorReserve,
                         double maxZoomFactor,
                         int tooltipReserve,
                         int floatingPadding)
{
    const int dockHeight = iconSize + crossPaddingLeading + crossPaddingTrailing + indicatorReserve;
    const int zoomOverflow = zoomOverflowHeight(iconSize, maxZoomFactor);

    const int topOverflow = std::max(zoomOverflow, tooltipReserve);
    const int bottomOverflow = floatingPadding;

    return dockHeight + topOverflow + bottomOverflow;
}

/// Symmetric-padding overload retained for callers and geometry tests that do
/// not need independent edge values.
inline int surfaceHeight(int iconSize, int padding, double maxZoomFactor, int tooltipReserve, int floatingPadding)
{
    return surfaceHeight(iconSize, padding, padding, 0, maxZoomFactor, tooltipReserve, floatingPadding);
}

inline int surfaceHeight(int iconSize,
                         int crossPaddingLeading,
                         int crossPaddingTrailing,
                         double maxZoomFactor,
                         int tooltipReserve,
                         int floatingPadding)
{
    return surfaceHeight(iconSize,
                         crossPaddingLeading,
                         crossPaddingTrailing,
                         0,
                         maxZoomFactor,
                         tooltipReserve,
                         floatingPadding);
}

/// Height of the visible panel bar (icon + padding + floating gap).
inline int panelBarHeight(int iconSize,
                          int crossPaddingLeading,
                          int crossPaddingTrailing,
                          int indicatorReserve,
                          int floatingPadding)
{
    return iconSize + crossPaddingLeading + crossPaddingTrailing + indicatorReserve + floatingPadding;
}

inline int panelBarHeight(int iconSize, int padding, int floatingPadding)
{
    return panelBarHeight(iconSize, padding, padding, 0, floatingPadding);
}

inline int panelBarHeight(int iconSize, int crossPaddingLeading, int crossPaddingTrailing, int floatingPadding)
{
    return panelBarHeight(iconSize, crossPaddingLeading, crossPaddingTrailing, 0, floatingPadding);
}

/** Layer Shell reservation includes the visible dock and its gap to windows. */
inline int exclusiveZone(int panelBarHeight, int windowGap, bool reserveScreenSpace)
{
    return reserveScreenSpace ? std::max(0, panelBarHeight) + std::max(0, windowGap) : 0;
}

} // namespace kdockw
