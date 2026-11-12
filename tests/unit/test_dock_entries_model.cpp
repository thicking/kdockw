// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/dockentriesmodel.h"

#include <catch2/catch_test_macros.hpp>

TEST_CASE("Dock entries model exposes typed roles and retains mixed order", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const QUrl dolphin(QStringLiteral("applications:org.kde.dolphin.desktop"));
    const QUrl folder = QUrl::fromLocalFile(QStringLiteral("/tmp/Downloads"));
    const auto stack = kdockw::DockEntry::folderStack(folder);
    model.setEntries({kdockw::DockEntry::task(dolphin), stack});

    REQUIRE(model.rowCount() == 2);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == dolphin.toString());
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::EntryTypeRole).toString() == QStringLiteral("task"));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryTypeRole).toString() == QStringLiteral("folderStack"));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryIdRole).toString() == stack.id);
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryUrlRole).toUrl() == folder);
    CHECK(model.roleNames().value(kdockw::DockEntriesModel::EntryUrlRole) == QByteArray("entryUrl"));
}

TEST_CASE("Dock entries model syncs task order while preserving folder slots", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const QUrl first(QStringLiteral("applications:org.kde.dolphin.desktop"));
    const QUrl second(QStringLiteral("applications:org.kde.kate.desktop"));
    const QUrl third(QStringLiteral("applications:org.kde.konsole.desktop"));
    const auto firstStack = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/one")));
    const auto secondStack = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/two")));
    model.setEntries({kdockw::DockEntry::task(first), firstStack, kdockw::DockEntry::task(second), secondStack});

    model.syncTaskOrder({third.toString(), first.toString()});

    const auto entries = model.entries();
    REQUIRE(entries.size() == 4);
    CHECK(entries.at(0).url == third);
    CHECK(entries.at(1).id == firstStack.id);
    CHECK(entries.at(2).url == first);
    CHECK(entries.at(3).id == secondStack.id);
}

TEST_CASE("Dock entries model appends, moves, and removes only folder stacks", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const auto task = kdockw::DockEntry::task(QUrl(QStringLiteral("applications:org.kde.dolphin.desktop")));
    model.setEntries({task});

    CHECK_FALSE(model.appendFolderStack(QUrl(QStringLiteral("smb://server/share"))));
    REQUIRE(model.appendFolderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/Downloads"))));
    REQUIRE(model.appendFolderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/Pictures"))));

    const QString firstId = model.entries().at(1).id;
    REQUIRE(model.setFolderStackIcon(firstId, QStringLiteral("folder-development")));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::IconNameRole).toString()
          == QStringLiteral("folder-development"));
    REQUIRE(model.moveEntryById(firstId, model.entries().last().id));
    CHECK(model.entries().last().id == firstId);
    CHECK(model.data(model.index(2, 0), kdockw::DockEntriesModel::IconNameRole).toString()
          == QStringLiteral("folder-development"));
    REQUIRE(model.setFolderStackIcon(firstId, {}, QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg"))));
    CHECK(model.data(model.index(2, 0), kdockw::DockEntriesModel::IconUrlRole).toUrl()
          == QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg")));
    CHECK_FALSE(model.setFolderStackIcon(firstId, {}, QUrl(QStringLiteral("https://example.test/icon.png"))));
    CHECK(model.entries().last().iconUrl == QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg")));
    CHECK(model.rowCount() == 3);

    CHECK(model.moveEntry(2, 0));
    CHECK(model.entries().at(0).type == kdockw::DockEntryType::FolderStack);
    CHECK_FALSE(model.moveEntry(0, 0));
    CHECK_FALSE(model.removeFolderStack(task.id));
    CHECK(model.removeFolderStack(model.entries().at(0).id));
    CHECK(model.rowCount() == 2);
    CHECK(model.entries().at(1).type == kdockw::DockEntryType::FolderStack);
}
