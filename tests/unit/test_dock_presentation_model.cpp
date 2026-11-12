// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/dockpresentationmodel.h"

#include <taskmanager/abstracttasksmodel.h>

#include <QStandardItemModel>
#include <QSet>
#include <QTest>

#include <memory>

#include <catch2/catch_test_macros.hpp>

namespace
{
int appendTask(QStandardItemModel &model, const QString &name, const QUrl &launcherUrl)
{
    auto *item = new QStandardItem(name);
    item->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    item->setData(name.toLower(), TaskManager::AbstractTasksModel::AppId);
    item->setData(QStringList{name + QStringLiteral("-window")}, TaskManager::AbstractTasksModel::WinIdList);
    model.appendRow(item);
    return model.rowCount() - 1;
}

std::unique_ptr<QStandardItem> makeTask(const QString &name, const QUrl &launcherUrl, const QStringList &windows = {})
{
    auto item = std::make_unique<QStandardItem>(name);
    item->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    item->setData(name.toLower(), TaskManager::AbstractTasksModel::AppId);
    item->setData(windows.isEmpty() ? QStringList{name + QStringLiteral("-window")} : windows,
                  TaskManager::AbstractTasksModel::WinIdList);
    return item;
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
    const QString runningId = model.entryIdForDockIndex(3);
    CHECK_FALSE(runningId.isEmpty());
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

    // Move a specific pinned app around the stack. Stable entry IDs must
    // resolve to the intended row after the preceding mixed-order moves, and
    // unpinned running rows must retain their relative order.
    REQUIRE(entries.moveEntryById(taskB.id, taskA.id));
    QTRY_COMPARE_WITH_TIMEOUT(model.entryIdForDockIndex(0), taskB.id, 2000);
    CHECK(model.entryIdForDockIndex(1) == taskA.id);
    CHECK(model.entryIdForDockIndex(2) == folder.id);
    CHECK(model.entryIdForDockIndex(3) == runningId);

    REQUIRE(entries.moveEntryById(taskA.id, folder.id));
    QTRY_COMPARE_WITH_TIMEOUT(model.entryIdForDockIndex(2), taskA.id, 2000);
    CHECK(model.entryIdForDockIndex(0) == taskB.id);
    CHECK(model.entryIdForDockIndex(1) == folder.id);
    CHECK(model.entryIdForDockIndex(3) == runningId);
    CHECK(model.taskIndexForDockIndex(0) == appBRow);
    CHECK(model.taskIndexForDockIndex(1) == -1);
    CHECK(model.taskIndexForDockIndex(2) == appARow);
    CHECK(model.dockIndexForTaskIndex(runningRow) == 3);

    appendTask(tasks, QStringLiteral("Running D"), QUrl(QStringLiteral("applications:org.example.D")));
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 5, 2000);
    CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
    CHECK(model.data(model.index(4, 0), Qt::DisplayRole).toString() == QStringLiteral("Running D"));
}

TEST_CASE("Dock presentation follows TaskManager order when pinned and running zones are combined", "[dock-presentation][taskmanager-regression]")
{
    const QUrl appA(QStringLiteral("applications:org.example.A"));
    const QUrl appB(QStringLiteral("applications:org.example.B"));
    const QUrl appC(QStringLiteral("applications:org.example.C"));

    QStandardItemModel tasks;
    const int appARow = appendTask(tasks, QStringLiteral("Pinned A"), appA);
    const int runningRow = appendTask(tasks, QStringLiteral("Running C"), appC);
    const int appBRow = appendTask(tasks, QStringLiteral("Pinned B"), appB);

    kdockw::DockEntriesModel entries;
    const auto pinA = kdockw::DockEntry::task(appA);
    const auto folder = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/stack")));
    const auto pinB = kdockw::DockEntry::task(appB);
    entries.setEntries({pinA, folder, pinB});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 4, 2000);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned A"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("stack"));
    CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned B"));
    CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));

    model.setSeparateLaunchers(false);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned A"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
    CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("stack"));
    CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned B"));
    CHECK(model.taskIndexForDockIndex(0) == appARow);
    CHECK(model.taskIndexForDockIndex(1) == runningRow);
    CHECK(model.taskIndexForDockIndex(2) == -1);
    CHECK(model.taskIndexForDockIndex(3) == appBRow);
    CHECK(model.isPinnedDockIndex(0));
    CHECK_FALSE(model.isPinnedDockIndex(1));
    CHECK(model.isPinnedDockIndex(2));
    CHECK(model.isPinnedDockIndex(3));
}

TEST_CASE("Dock presentation matches TaskManager launcher URLs with metadata and survives repeated mixed reorders",
          "[dock-presentation][dock-dnd]")
{
    const QUrl pinnedA(QStringLiteral("applications:org.example.Writer?activity=current"));
    const QUrl taskA(QStringLiteral("applications:org.example.Writer?iconData=encoded"));
    const QUrl pinnedB(QStringLiteral("applications:org.example.Editor"));
    const QUrl taskB(QStringLiteral("applications:org.example.Editor"));
    const QUrl runningUrl(QStringLiteral("applications:org.example.Terminal"));

    QStandardItemModel tasks;
    const int taskARow = appendTask(tasks, QStringLiteral("Writer window"), taskA);
    const int taskBRow = appendTask(tasks, QStringLiteral("Editor window"), taskB);
    const int runningRow = appendTask(tasks, QStringLiteral("Terminal window"), runningUrl);

    kdockw::DockEntriesModel entries;
    const auto writer = kdockw::DockEntry::task(pinnedA);
    const auto stack = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/stack")));
    const auto editor = kdockw::DockEntry::task(pinnedB);
    entries.setEntries({writer, stack, editor});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 4, 2000);
    CHECK(model.pinnedEntryCount() == 3);
    CHECK(model.entryIdForDockIndex(0) == writer.id);
    CHECK(model.entryIdForDockIndex(1) == stack.id);
    CHECK(model.entryIdForDockIndex(2) == editor.id);
    const QString runningId = model.entryIdForDockIndex(3);
    REQUIRE_FALSE(runningId.isEmpty());
    CHECK(model.taskIndexForDockIndex(0) == taskARow);
    CHECK(model.taskIndexForDockIndex(1) == -1);
    CHECK(model.taskIndexForDockIndex(2) == taskBRow);
    CHECK(model.taskIndexForDockIndex(3) == runningRow);

    const QList<QPair<QString, QString>> moves{
        {stack.id, writer.id},
        {editor.id, stack.id},
        {writer.id, editor.id},
        {stack.id, editor.id},
        {writer.id, stack.id},
        {editor.id, writer.id},
        {stack.id, writer.id},
        {writer.id, editor.id},
        {editor.id, stack.id},
        {stack.id, editor.id},
    };
    for (const auto &[sourceId, targetId] : moves) {
        REQUIRE(entries.moveEntryById(sourceId, targetId));
        QTRY_COMPARE_WITH_TIMEOUT(model.entryIdForDockIndex(0), entries.entries().at(0).id, 2000);
        REQUIRE(model.rowCount() == 4);
        QSet<QString> identities;
        for (int row = 0; row < model.rowCount(); ++row) {
            const QString id = model.entryIdForDockIndex(row);
            CHECK_FALSE(id.isEmpty());
            CHECK_FALSE(identities.contains(id));
            identities.insert(id);
        }
        CHECK(model.entryIdForDockIndex(3) == runningId);
        CHECK(model.taskIndexForDockIndex(model.dockIndexForEntryId(writer.id)) == taskARow);
        CHECK(model.taskIndexForDockIndex(model.dockIndexForEntryId(editor.id)) == taskBRow);
        CHECK(model.taskIndexForDockIndex(model.dockIndexForEntryId(stack.id)) == -1);
    }

    const auto restored = kdockw::DockEntriesCodec::decode(kdockw::DockEntriesCodec::encode(entries.entries()));
    REQUIRE(restored.validDocument);
    REQUIRE(restored.entries.size() == entries.entries().size());
    for (int row = 0; row < restored.entries.size(); ++row) {
        CHECK(restored.entries.at(row).id == entries.entries().at(row).id);
        CHECK(restored.entries.at(row).url == entries.entries().at(row).url);
    }
}

TEST_CASE("Dock presentation keeps live TaskManager rows mapped during repeated insertions and removals",
          "[dock-presentation][taskmanager-regression]")
{
    const QUrl appA(QStringLiteral("applications:org.example.A"));
    const QUrl appB(QStringLiteral("applications:org.example.B"));
    const QUrl appC(QStringLiteral("applications:org.example.C"));
    const QUrl duplicate(QStringLiteral("applications:org.example.Shared"));
    QStandardItemModel tasks;
    appendTask(tasks, QStringLiteral("Pinned B"), appB);
    appendTask(tasks, QStringLiteral("Running C"), appC);
    appendTask(tasks, QStringLiteral("Pinned A"), appA);
    appendTask(tasks, QStringLiteral("Running D"), QUrl(QStringLiteral("applications:org.example.D")));

    kdockw::DockEntriesModel entries;
    const auto pinA = kdockw::DockEntry::task(appA);
    const auto folder = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/projects")));
    const auto pinB = kdockw::DockEntry::task(appB);
    entries.setEntries({pinA, folder, pinB});
    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 5, 2000);

    const auto checkRows = [&] {
        CHECK(model.rowCount() == 5);
        CHECK(model.entryIdForDockIndex(0) == pinA.id);
        CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned A"));
        CHECK(model.entryIdForDockIndex(1) == folder.id);
        CHECK(model.entryIdForDockIndex(2) == pinB.id);
        CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned B"));
        CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
        CHECK(model.data(model.index(4, 0), Qt::DisplayRole).toString() == QStringLiteral("Running D"));
        for (int dockIndex = 0; dockIndex < model.rowCount(); ++dockIndex) {
            const int taskIndex = model.taskIndexForDockIndex(dockIndex);
            if (taskIndex >= 0) {
                CHECK(model.data(model.index(dockIndex, 0), TaskManager::AbstractTasksModel::AppId).toString()
                      == tasks.data(tasks.index(taskIndex, 0), TaskManager::AbstractTasksModel::AppId).toString());
            }
        }
    };
    checkRows();

    for (int iteration = 0; iteration < 4; ++iteration) {
        auto *newRow = makeTask(QStringLiteral("Transient %1").arg(iteration), duplicate,
                                {QStringLiteral("shared-window-%1").arg(iteration)}).release();
        newRow->setData(QStringLiteral("shared"), TaskManager::AbstractTasksModel::AppId);
        tasks.insertRow(0, newRow);
        // Structural updates are reconciled synchronously: reading the model
        // before processing the queued event loop must never return a neighbor.
        CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned A"));
        CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned B"));
        CHECK(model.rowCount() == 6);
        const QString insertedId = model.entryIdForDockIndex(3);
        CHECK_FALSE(insertedId.isEmpty());
        CHECK(model.taskIndexForDockIndex(3) == 0);
        CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Transient %1").arg(iteration));
        QSet<QString> ids;
        for (int row = 0; row < model.rowCount(); ++row) {
            const QString id = model.entryIdForDockIndex(row);
            CHECK_FALSE(ids.contains(id));
            ids.insert(id);
        }

        tasks.removeRow(0);
        CHECK(model.rowCount() == 5);
        CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned A"));
        CHECK(model.data(model.index(2, 0), Qt::DisplayRole).toString() == QStringLiteral("Pinned B"));
        CHECK(model.data(model.index(3, 0), Qt::DisplayRole).toString() == QStringLiteral("Running C"));
        CHECK(model.data(model.index(4, 0), Qt::DisplayRole).toString() == QStringLiteral("Running D"));
    }
}
