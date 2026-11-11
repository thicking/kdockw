// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/dockpresentationmodel.h"

#include <taskmanager/abstracttasksmodel.h>

#include <QStandardItemModel>
#include <QTest>

#include <catch2/catch_test_macros.hpp>

namespace
{
int appendTask(QStandardItemModel &model, const QString &name, const QUrl &launcherUrl)
{
    auto *item = new QStandardItem(name);
    item->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    item->setData(name.toLower(), TaskManager::AbstractTasksModel::AppId);
    model.appendRow(item);
    return model.rowCount() - 1;
}
}

TEST_CASE("Dock presentation model merges pinned entries in stable order and leaves running tasks after them", "[dock-presentation]")
{
    const QUrl appA(QStringLiteral("applications:org.example.A"));
    const QUrl appB(QStringLiteral("applications:org.example.B"));
    const QUrl appC(QStringLiteral("applications:org.example.C"));

    QStandardItemModel tasks;
    const int appBRow = appendTask(tasks, QStringLiteral("App B"), appB);
    const int appARow = appendTask(tasks, QStringLiteral("App A"), appA);
    const int runningRow = appendTask(tasks, QStringLiteral("Running C"), appC);

    kdockw::DockEntriesModel entries;
    const auto taskA = kdockw::DockEntry::task(appA);
    const auto folder = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/stack")));
    const auto taskB = kdockw::DockEntry::task(appB);
    entries.setEntries({taskA, folder, taskB});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 4, 2000);
    CHECK(model.pinnedEntryCount() == 3);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("App A"));
    CHECK(model.data(model.index(1, 0), kdockw::DockPresentationModel::EntryTypeRole).toString() == QStringLiteral("folderStack"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("stack"));
    CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("App B"));
    CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
    CHECK(model.taskIndexForDockIndex(0) == appARow);
    CHECK(model.taskIndexForDockIndex(1) == -1);
    CHECK(model.taskIndexForDockIndex(2) == appBRow);
    CHECK(model.taskIndexForDockIndex(3) == runningRow);
    CHECK(model.dockIndexForTaskIndex(runningRow) == 3);
    CHECK(model.isPinnedDockIndex(1));
    CHECK_FALSE(model.isPinnedDockIndex(3));

    QPersistentModelIndex stableAppA(model.index(0, 0));
    REQUIRE(entries.moveEntryById(folder.id, taskA.id));
    QTRY_COMPARE_WITH_TIMEOUT(model.data(model.index(0, 0), kdockw::DockPresentationModel::EntryTypeRole).toString(),
                              QStringLiteral("folderStack"), 2000);
    CHECK(stableAppA.isValid());
    CHECK(stableAppA.row() == 1);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("stack"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("App A"));

    REQUIRE(entries.moveEntryById(folder.id, taskB.id));
    QTRY_COMPARE_WITH_TIMEOUT(model.data(model.index(2, 0), kdockw::DockPresentationModel::EntryTypeRole).toString(),
                              QStringLiteral("folderStack"), 2000);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("App A"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("App B"));
    CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("stack"));

    appendTask(tasks, QStringLiteral("Running D"), QUrl(QStringLiteral("applications:org.example.D")));
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 5, 2000);
    CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
    CHECK(model.data(model.index(4, 0), Qt::DisplayRole).toString() == QStringLiteral("Running D"));
}
