// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "platform/dockplatform.h"
#include "shell/dockvisibilitycontroller.h"

#include <catch2/catch_test_macros.hpp>

#include <QGuiApplication>
#include <QSignalSpy>
#include <QWindow>
#include <QTest>

namespace
{
class CountingDockPlatform final : public kdockw::DockPlatform
{
public:
    void setupWindow(QWindow *) override { }
    void setScreen(QScreen *) override { }
    void setEdge(Edge edge) override { m_edge = edge; }
    void setExclusiveZone(int) override { }
    void setMargin(int) override { }
    [[nodiscard]] int margin() const override { return currentMargin; }
    void setVisibilityMode(VisibilityMode) override { }
    void setSize(const QSize &) override { }
    void setInputRegion(const QRegion &region) override
    {
        ++inputRegionUpdates;
        lastInputRegion = region;
    }
    [[nodiscard]] Edge edge() const override { return m_edge; }
    void setKeyboardInteractivity(bool) override { }

    int inputRegionUpdates = 0;
    int currentMargin = 0;
    QRegion lastInputRegion;

private:
    Edge m_edge = Edge::Bottom;
};
}

TEST_CASE("panel geometry emits only when its integer geometry changes", "[visibility][geometry]")
{
    CountingDockPlatform platform;
    QWindow window;
    window.resize(1920, 1080);
    kdockw::DockVisibilityController controller(&platform, nullptr, nullptr, nullptr, &window, QGuiApplication::primaryScreen());
    QSignalSpy changed(&controller, &kdockw::DockVisibilityController::panelRectChanged);

    controller.setPanelRect(12.2, 36.2, 300.8, 64.7);
    controller.setPanelRect(12.9, 36.9, 300.1, 64.1);
    CHECK(changed.count() == 1);
    CHECK(controller.panelRect() == QRect(12, 36, 300, 64));

    controller.setPanelRect(12.9, 37.1, 300.1, 64.1);
    CHECK(changed.count() == 2);
    CHECK(controller.panelRect() == QRect(12, 37, 300, 64));
}

TEST_CASE("unchanged interaction geometry does not rebuild the input region", "[visibility][geometry]")
{
    CountingDockPlatform platform;
    QWindow window;
    window.resize(1920, 1080);
    kdockw::DockVisibilityController controller(&platform, nullptr, nullptr, nullptr, &window, QGuiApplication::primaryScreen());

    controller.setInteractionRect(20.2, 40.2, 100.8, 50.7);
    REQUIRE(platform.inputRegionUpdates == 1);
    controller.setInteractionRect(20.9, 40.9, 100.1, 50.1);
    CHECK(platform.inputRegionUpdates == 1);

    controller.setInteractionRect(20.9, 41.1, 100.1, 50.1);
    CHECK(platform.inputRegionUpdates == 2);
}

TEST_CASE("dock auto-hide delay remains a live independent timer", "[visibility][timer]")
{
    CountingDockPlatform platform;
    QWindow window;
    window.resize(800, 600);
    kdockw::DockVisibilityController controller(&platform, nullptr, nullptr, nullptr, &window, QGuiApplication::primaryScreen());

    controller.setMode(kdockw::DockPlatform::VisibilityMode::AutoHide);
    CHECK_FALSE(controller.isDockVisible());
    controller.setShowDelay(10);
    controller.setHovered(true);
    REQUIRE(QTest::qWaitFor([&controller] { return controller.isDockVisible(); }, 1000));

    controller.setHideDelay(80);
    controller.setHovered(false);
    QTest::qWait(25);
    CHECK(controller.isDockVisible());
    CHECK(QTest::qWaitFor([&controller] { return !controller.isDockVisible(); }, 1000));
}
