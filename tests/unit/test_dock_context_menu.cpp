// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/dockcontextmenu.h"

#include <catch2/catch_test_macros.hpp>

#include <QAction>
#include <QCoreApplication>
#include <QMenu>

namespace
{

QAction *actionWithText(QMenu *menu, const QString &text)
{
    for (QAction *action : menu->actions()) {
        if (action->text() == text) {
            return action;
        }
    }
    return nullptr;
}

QMenu *submenuWithText(QMenu *menu, const QString &text)
{
    for (QAction *action : menu->actions()) {
        if (action->menu() != nullptr && action->text() == text) {
            return action->menu();
        }
    }
    return nullptr;
}

kdockw::ContextMenuData baseData()
{
    kdockw::ContextMenuData data;
    data.title = QStringLiteral("Claude");
    data.pinText = QStringLiteral("Unpin from Dock");
    data.togglePinned = []() {};
    data.newInstance = []() {};
    data.settings = []() {};
    data.about = []() {};
    data.quit = []() {};
    return data;
}

} // namespace

TEST_CASE("context menu preserves desktop action order and routes dock commands separately", "[contextmenu]")
{
    int appActionCalls = 0;
    int pinCalls = 0;
    int newInstanceCalls = 0;
    auto data = baseData();
    data.togglePinned = [&pinCalls]() { ++pinCalls; };
    data.newInstance = [&newInstanceCalls]() { ++newInstanceCalls; };
    data.applicationActions = {
        {QStringLiteral("New chat"), {}, false, [&appActionCalls]() { ++appActionCalls; }},
        {{}, {}, true, {}},
        {QStringLiteral("Continue Claude Code session"), {}, false, [&appActionCalls]() { ++appActionCalls; }},
    };

    QMenu *menu = kdockw::createContextMenu(data, QCoreApplication::instance());
    REQUIRE(menu != nullptr);
    REQUIRE(menu->actions().at(0)->text() == QStringLiteral("Claude"));
    REQUIRE(menu->actions().at(2)->text() == QStringLiteral("New chat"));
    REQUIRE(menu->actions().at(3)->isSeparator());
    REQUIRE(menu->actions().at(4)->text() == QStringLiteral("Continue Claude Code session"));
    REQUIRE(menu->actions().at(6)->text() == QStringLiteral("Unpin from Dock"));
    REQUIRE(menu->actions().at(7)->text() == QStringLiteral("New Instance"));

    menu->actions().at(2)->trigger();
    REQUIRE(appActionCalls == 1);
    menu->actions().at(6)->trigger();
    menu->actions().at(7)->trigger();
    REQUIRE(pinCalls == 1);
    REQUIRE(newInstanceCalls == 1);

    QMenu *dockMenu = submenuWithText(menu, QStringLiteral("KDockW"));
    REQUIRE(dockMenu != nullptr);
    REQUIRE(dockMenu->actions().size() == 3);
    REQUIRE(dockMenu->actions().at(0)->text() == QStringLiteral("Settings..."));
    REQUIRE(dockMenu->actions().at(1)->text() == QStringLiteral("About KDockW"));
    REQUIRE(dockMenu->actions().at(2)->text() == QStringLiteral("Quit KDockW"));
    REQUIRE(actionWithText(menu, QStringLiteral("Quit")) == nullptr);
    delete menu;
}

TEST_CASE("context menu offers only window-level close for one running window", "[contextmenu]")
{
    int closeCalls = 0;
    auto data = baseData();
    data.pinText = QStringLiteral("Pin to Dock");
    data.closeText = QStringLiteral("Close Window");
    data.closeApplication = [&closeCalls]() { ++closeCalls; };

    QMenu *menu = kdockw::createContextMenu(data, QCoreApplication::instance());
    QAction *close = actionWithText(menu, QStringLiteral("Close Window"));
    REQUIRE(close != nullptr);
    close->trigger();
    REQUIRE(closeCalls == 1);
    REQUIRE(actionWithText(menu, QStringLiteral("Close Application")) == nullptr);
    REQUIRE(actionWithText(menu, QStringLiteral("Unpin from Dock")) == nullptr);
    REQUIRE(actionWithText(menu, QStringLiteral("Pin to Dock")) != nullptr);
    delete menu;
}

TEST_CASE("context menu grouped close distinguishes the app from each window", "[contextmenu]")
{
    int appCloseCalls = 0;
    int firstWindowCloseCalls = 0;
    int secondWindowCloseCalls = 0;
    auto data = baseData();
    data.closeText = QStringLiteral("Close Application");
    data.closeApplication = [&appCloseCalls, &firstWindowCloseCalls, &secondWindowCloseCalls]() {
        ++appCloseCalls;
        ++firstWindowCloseCalls;
        ++secondWindowCloseCalls;
    };
    data.windows = {
        {QStringLiteral("Claude — Conversation 1"), [&firstWindowCloseCalls]() { ++firstWindowCloseCalls; }},
        {QStringLiteral("Claude — Conversation 2"), [&secondWindowCloseCalls]() { ++secondWindowCloseCalls; }},
    };

    QMenu *menu = kdockw::createContextMenu(data, QCoreApplication::instance());
    REQUIRE(actionWithText(menu, QStringLiteral("Close Application")) != nullptr);
    QMenu *windowsMenu = submenuWithText(menu, QStringLiteral("Close Window"));
    REQUIRE(windowsMenu != nullptr);
    REQUIRE(windowsMenu->actions().size() == 2);

    windowsMenu->actions().at(0)->trigger();
    REQUIRE(firstWindowCloseCalls == 1);
    REQUIRE(secondWindowCloseCalls == 0);
    REQUIRE(appCloseCalls == 0);

    actionWithText(menu, QStringLiteral("Close Application"))->trigger();
    REQUIRE(appCloseCalls == 1);
    REQUIRE(firstWindowCloseCalls == 2);
    REQUIRE(secondWindowCloseCalls == 1);
    delete menu;
}

TEST_CASE("context menu launcher-only state has no close command", "[contextmenu]")
{
    auto data = baseData();
    data.pinText = QStringLiteral("Unpin from Dock");
    QMenu *menu = kdockw::createContextMenu(data, QCoreApplication::instance());
    REQUIRE(actionWithText(menu, QStringLiteral("Close Application")) == nullptr);
    REQUIRE(actionWithText(menu, QStringLiteral("Close Window")) == nullptr);
    REQUIRE(submenuWithText(menu, QStringLiteral("KDockW")) != nullptr);
    delete menu;
}

TEST_CASE("context menu settings and about handlers do not quit KDockW", "[contextmenu]")
{
    int settingsCalls = 0;
    int aboutCalls = 0;
    int quitCalls = 0;
    auto data = baseData();
    data.settings = [&settingsCalls]() { ++settingsCalls; };
    data.about = [&aboutCalls]() { ++aboutCalls; };
    data.quit = [&quitCalls]() { ++quitCalls; };

    QMenu *menu = kdockw::createContextMenu(data, QCoreApplication::instance());
    QMenu *dockMenu = submenuWithText(menu, QStringLiteral("KDockW"));
    REQUIRE(dockMenu != nullptr);
    dockMenu->actions().at(0)->trigger();
    dockMenu->actions().at(1)->trigger();
    REQUIRE(settingsCalls == 1);
    REQUIRE(aboutCalls == 1);
    REQUIRE(quitCalls == 0);
    dockMenu->actions().at(2)->trigger();
    REQUIRE(quitCalls == 1);
    delete menu;
}
