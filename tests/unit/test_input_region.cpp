// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_test_macros.hpp>

#include "utils/inputregion.h"
#include "utils/layershellpolicy.h"

TEST_CASE("Dock input region computation", "[input-region]")
{
    SECTION("Hidden: only trigger strip")
    {
        kdockw::InputRegionParams p{};
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelX = 800;
        p.panelY = 80;
        p.panelWidth = 320;
        p.panelHeight = 40;
        p.zoomOverflowHeight = 29;
        p.visible = false;
        p.hovered = false;

        QRegion region = kdockw::computeDockInputRegion(p);

        // Should contain only the trigger strip at the bottom
        REQUIRE(region.contains(QPoint(960, 118))); // center bottom
        REQUIRE(region.contains(QPoint(0, 118))); // left bottom
        REQUIRE_FALSE(region.contains(QPoint(960, 90))); // panel area excluded
    }

    SECTION("Visible but not hovered: panel area + trigger strip")
    {
        kdockw::InputRegionParams p{};
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelX = 800;
        p.panelY = 80;
        p.panelWidth = 320;
        p.panelHeight = 40;
        p.zoomOverflowHeight = 29;
        p.visible = true;
        p.hovered = false;

        QRegion region = kdockw::computeDockInputRegion(p);

        // Panel area should be included (with margin)
        REQUIRE(region.contains(QPoint(960, 100))); // panel center
        REQUIRE(region.contains(QPoint(960, 118))); // trigger strip
        // Far outside panel should be excluded
        REQUIRE_FALSE(region.contains(QPoint(100, 90)));
    }

    SECTION("Visible and hovered: includes zoom overflow")
    {
        kdockw::InputRegionParams p{};
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelX = 800;
        p.panelY = 80;
        p.panelWidth = 320;
        p.panelHeight = 40;
        p.zoomOverflowHeight = 29;
        p.visible = true;
        p.hovered = true;

        QRegion region = kdockw::computeDockInputRegion(p);

        // Zoom overflow area above panel should be included
        REQUIRE(region.contains(QPoint(960, 55))); // above panel in zoom area
        REQUIRE(region.contains(QPoint(960, 100))); // panel center
    }

    SECTION("Panel width zero: fallback to empty (accept all input)")
    {
        kdockw::InputRegionParams p{};
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelWidth = 0;
        p.visible = true;
        p.hovered = false;

        QRegion region = kdockw::computeDockInputRegion(p);

        // Empty QRegion = no mask = accept all input
        REQUIRE(region.isEmpty());
    }
}

TEST_CASE("Dock screen rect computation", "[screen-rect]")
{
    SECTION("Bottom edge")
    {
        kdockw::DockScreenRectParams p{};
        p.screenX = 0;
        p.screenY = 0;
        p.screenWidth = 1920;
        p.screenHeight = 1080;
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelX = 800;
        p.panelRefY = 80;
        p.panelWidth = 320;
        p.panelHeight = 40;
        p.edge = 1; // Bottom

        QRect rect = kdockw::computeDockScreenRect(p);

        // Surface top-left: (0, 1080-120) = (0, 960)
        // Panel: (0+800, 960+80, 320, 40) = (800, 1040, 320, 40)
        REQUIRE(rect.x() == 800);
        REQUIRE(rect.y() == 1040);
        REQUIRE(rect.width() == 320);
        REQUIRE(rect.height() == 40);
    }

    SECTION("Top edge")
    {
        kdockw::DockScreenRectParams p{};
        p.screenX = 0;
        p.screenY = 0;
        p.screenWidth = 1920;
        p.screenHeight = 1080;
        p.surfaceWidth = 1920;
        p.surfaceHeight = 120;
        p.panelX = 800;
        p.panelRefY = 0;
        p.panelWidth = 320;
        p.panelHeight = 40;
        p.edge = 0; // Top

        QRect rect = kdockw::computeDockScreenRect(p);

        REQUIRE(rect.x() == 800);
        REQUIRE(rect.y() == 0);
    }
}

TEST_CASE("Preview input region matches the visible popup", "[input-region][preview]")
{
    // 400 px deep preview surface; 300x180 popup.
    kdockw::PreviewInputRegionParams p{};
    p.contentWidth = 300;
    p.contentHeight = 180;

    SECTION("Top edge: popup flush with the top, nothing below it")
    {
        p.surfaceWidth = 1920;
        p.surfaceHeight = 400;
        p.contentX = 800;
        p.edge = 0;

        const QRegion region = kdockw::computePreviewInputRegion(p);

        REQUIRE(region == QRegion(800, 0, 300, 180));
        REQUIRE_FALSE(region.contains(QPoint(950, 180))); // just below the popup
        REQUIRE_FALSE(region.contains(QPoint(950, 399))); // far side of the surface
    }

    SECTION("Bottom edge: popup flush with the bottom, nothing above it")
    {
        p.surfaceWidth = 1920;
        p.surfaceHeight = 400;
        p.contentX = 800;
        p.edge = 1;

        REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(800, 220, 300, 180));
    }

    SECTION("Left edge: popup flush with the left, nothing to its right")
    {
        p.surfaceWidth = 400;
        p.surfaceHeight = 1080;
        p.contentY = 450;
        p.edge = 2;

        REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(0, 450, 300, 180));
    }

    SECTION("Right edge: popup flush with the right, nothing to its left")
    {
        p.surfaceWidth = 400;
        p.surfaceHeight = 1080;
        p.contentY = 450;
        p.edge = 3;

        REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(100, 450, 300, 180));
    }

    SECTION("Fractional popup geometry is fully covered")
    {
        p.surfaceWidth = 1920;
        p.surfaceHeight = 400;
        p.contentX = 800.5;
        p.contentWidth = 300.5;
        p.contentHeight = 180.5;
        p.edge = 0;

        REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(800, 0, 301, 181));
    }

    SECTION("No popup size yet: 1x1 region, never an empty (accept-all) mask")
    {
        p.surfaceWidth = 1920;
        p.surfaceHeight = 400;
        p.contentX = 0;
        p.contentWidth = 0;
        p.contentHeight = 0;
        p.edge = 1;

        const QRegion region = kdockw::computePreviewInputRegion(p);

        REQUIRE_FALSE(region.isEmpty());
        REQUIRE(region == QRegion(0, 0, 1, 1));
    }
}

TEST_CASE("Preview surface margin follows configured visible gap", "[input-region][preview]")
{
    REQUIRE(kdockw::computePreviewSurfaceMargin(32, 56, 4, false) == 92);
    REQUIRE(kdockw::computePreviewSurfaceMargin(32, 56, 0, false) == 88);
    REQUIRE(kdockw::computePreviewSurfaceMargin(32, 56, 4, true) == 60);
    REQUIRE(kdockw::computePreviewSurfaceMargin(32, 56, -4, false) == 88);
}

TEST_CASE("Preview surface margin uses dock-surface coordinates on every edge", "[input-region][preview]")
{
    // Coordinates are local to the dock layer surface; no screen origin or
    // reserved-panel offset is mixed into the layer-shell margin.
    REQUIRE(kdockw::computePreviewSurfaceMarginForIcon(0, 50, 100, 6, 4, 8) == 52);
    REQUIRE(kdockw::computePreviewSurfaceMarginForIcon(1, 80, 100, 6, 4, 8) == 22);
    REQUIRE(kdockw::computePreviewSurfaceMarginForIcon(2, 50, 100, 6, 4, 8) == 52);
    REQUIRE(kdockw::computePreviewSurfaceMarginForIcon(3, 90, 100, 6, 4, 8) == 12);
    REQUIRE(kdockw::computePreviewSurfaceMarginForIcon(99, 20, 100, 0, 4, 8) == 0);
}

TEST_CASE("Bottom-dock preview stays two pixels from zoomed icon on a 1080px output", "[input-region][preview]")
{
    constexpr qreal screenHeight = 1080;
    constexpr qreal dockSurfaceHeight = 120;
    constexpr qreal dockEdgeMargin = 8;
    constexpr qreal iconUpperEdgeInSurface = 50;
    constexpr qreal gap = 2;
    constexpr qreal shadow = 8;
    const int previewMargin = kdockw::computePreviewSurfaceMarginForIcon(
        1, iconUpperEdgeInSurface, dockSurfaceHeight, dockEdgeMargin, gap, shadow);
    REQUIRE(previewMargin == 72);

    const qreal iconRestEdge = screenHeight - dockEdgeMargin
        - (dockSurfaceHeight - iconUpperEdgeInSurface);
    for (const qreal zoomOverflow : {0.0, 24.0}) {
        const qreal iconTop = iconRestEdge - zoomOverflow;
        const qreal cardBodyBottom = screenHeight - previewMargin - zoomOverflow - shadow;
        REQUIRE(iconTop - cardBodyBottom == gap);
    }
}

TEST_CASE("Preview bypasses dock reservation and uses the actual LayerShell margin", "[input-region][preview][layer-shell]")
{
    REQUIRE(kdockw::previewLayerShellExclusiveZone == -1);

    constexpr qreal screenHeight = 1080;
    constexpr qreal dockSurfaceHeight = 136;
    constexpr qreal iconRestEdgeInSurface = 83;
    constexpr qreal actualDockLayerShellMargin = 0;
    constexpr qreal floatingInsetInsideDockSurface = 3;
    constexpr qreal gap = 2;
    constexpr qreal shadowInset = 8;
    const int previewMargin = kdockw::computePreviewSurfaceMarginForIcon(
        1, iconRestEdgeInSurface, dockSurfaceHeight,
        actualDockLayerShellMargin, gap, shadowInset);
    REQUIRE(previewMargin == 47);

    // Floating padding is already represented by the icon's surface-local
    // edge. Adding it as another output margin would add it to the gap twice.
    REQUIRE(floatingInsetInsideDockSurface > actualDockLayerShellMargin);
    for (const qreal zoomOverflow : {0.0, 34.92}) {
        const qreal iconTop = screenHeight - (dockSurfaceHeight - iconRestEdgeInSurface) - zoomOverflow;
        const qreal cardBodyBottom = screenHeight - previewMargin - zoomOverflow - shadowInset;
        REQUIRE(iconTop - cardBodyBottom == gap);
    }
}

TEST_CASE("Preview input region follows the zoomed popup edge inset", "[input-region][preview]")
{
    kdockw::PreviewInputRegionParams p{};
    p.surfaceWidth = 1000;
    p.surfaceHeight = 600;
    p.contentX = 100;
    p.contentY = 150;
    p.contentWidth = 300;
    p.contentHeight = 180;
    p.edgeOffset = 10;

    p.edge = 0;
    REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(100, 10, 300, 180));
    p.edge = 1;
    REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(100, 410, 300, 180));
    p.edge = 2;
    REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(10, 150, 300, 180));
    p.edge = 3;
    REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(690, 150, 300, 180));

    p.edge = 1;
    p.shadowMargin = 8;
    REQUIRE(kdockw::computePreviewInputRegion(p) == QRegion(108, 418, 284, 164));
}
