// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/dockpresentationmodel.h"

#include <taskmanager/abstracttasksmodel.h>

#include <QFileInfo>
#include <QCoreApplication>
#include <QLoggingCategory>
#include <QStandardItemModel>
#include <QSignalSpy>
#include <QSignalBlocker>
#include <QSet>
#include <QTest>

#include <memory>

#include <catch2/catch_test_macros.hpp>

namespace
{
QStringList capturedQtMessages;

void captureQtMessage(QtMsgType, const QMessageLogContext &, const QString &message)
{
    capturedQtMessages.append(message);
}

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

TEST_CASE("Dock presentation forwards one task notification without entering an update loop",
          "[dock-presentation][dock-widgets][stability]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.example.Editor"));
    QStandardItemModel tasks;
    const int taskRow = appendTask(tasks, QStringLiteral("Editor"), launcherUrl);
    kdockw::DockEntriesModel entries;
    entries.setEntries({kdockw::DockEntry::task(launcherUrl)});
    kdockw::DockPresentationModel presentation(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(presentation.rowCount(), 1, 2000);
    QCoreApplication::processEvents();
    QCoreApplication::processEvents();

    QSignalSpy changed(&presentation, &QAbstractItemModel::dataChanged);
    tasks.item(taskRow)->setText(QStringLiteral("Editor — document"));
    CHECK(changed.count() == 1);

    // Drain queued rebuild work and ensure it settles rather than feeding a
    // new task-model notification back into the presentation model.
    QCoreApplication::processEvents();
    QCoreApplication::processEvents();
    CHECK(changed.count() == 1);
    CHECK(presentation.data(presentation.index(0, 0), Qt::DisplayRole).toString()
          == QStringLiteral("Editor — document"));
}

TEST_CASE("DecorationRole stays narrow while diagnostic traces record icon updates",
          "[dock-presentation][taskmanager-regression]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.example.Editor"));
    QStandardItemModel tasks;
    const int taskRow = appendTask(tasks, QStringLiteral("Editor"), launcherUrl);
    kdockw::DockEntriesModel entries;
    entries.setEntries({kdockw::DockEntry::task(launcherUrl)});
    kdockw::DockPresentationModel presentation(&tasks, &entries, nullptr, true);
    QTRY_COMPARE_WITH_TIMEOUT(presentation.rowCount(), 1, 2000);

    QSignalSpy changed(&presentation, &QAbstractItemModel::dataChanged);
    capturedQtMessages.clear();
    const QtMessageHandler previousHandler = qInstallMessageHandler(captureQtMessage);
    tasks.item(taskRow)->setData(QStringLiteral("icon-update"), Qt::DecorationRole);
    qInstallMessageHandler(previousHandler);

    REQUIRE(changed.count() == 1);
    const QList<int> forwardedRoles = changed.takeFirst().at(2).value<QList<int>>();
    CHECK(forwardedRoles == QList<int>{Qt::DecorationRole});
    CHECK(capturedQtMessages.join(QLatin1Char('\n')).contains(QStringLiteral("incomingRoles= QList(1)")));
}

TEST_CASE("Dock presentation derives grouped window count from live child rows",
          "[dock-presentation][taskmanager-regression][indicators]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.kde.konsole"));
    QStandardItemModel tasks;
    auto group = makeTask(QStringLiteral("Konsole"), launcherUrl, {});
    group->setData(true, TaskManager::AbstractTasksModel::IsWindow);
    group->setData(true, TaskManager::AbstractTasksModel::IsGroupParent);
    // Model this known failure shape: TaskManager's aggregate role is stale,
    // while the child rows used by grouped previews are already current.
    group->setData(3, TaskManager::AbstractTasksModel::ChildCount);
    for (int i = 0; i < 3; ++i) {
        group->appendRow(new QStandardItem(QStringLiteral("Konsole %1").arg(i + 1)));
    }
    tasks.appendRow(group.release());

    kdockw::DockEntriesModel entries;
    kdockw::DockPresentationModel presentation(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(presentation.rowCount(), 1, 2000);
    const QModelIndex dockIndex = presentation.index(0, 0);
    const int childCountRole = TaskManager::AbstractTasksModel::ChildCount;
    QSignalSpy changes(&presentation, &QAbstractItemModel::dataChanged);

    CHECK(presentation.data(dockIndex, childCountRole).toInt() == 3);
    for (int expected = 2; expected >= 0; --expected) {
        REQUIRE(tasks.item(0)->rowCount() > 0);
        tasks.item(0)->removeRow(0);
        QTRY_COMPARE_WITH_TIMEOUT(presentation.data(dockIndex, childCountRole).toInt(), expected, 2000);
        REQUIRE(changes.count() > 0);
        const QList<int> roles = changes.takeLast().at(2).value<QList<int>>();
        CHECK(roles.contains(childCountRole));
    }

    // Exercise the inverse 0 -> 1 -> 2 -> 3 transition without relying on
    // manually mutating the stale ChildCount role.
    for (int expected = 1; expected <= 3; ++expected) {
        tasks.item(0)->appendRow(new QStandardItem(QStringLiteral("Konsole %1").arg(expected)));
        QTRY_COMPARE_WITH_TIMEOUT(presentation.data(dockIndex, childCountRole).toInt(), expected, 2000);
        REQUIRE(changes.count() > 0);
        const QList<int> roles = changes.takeLast().at(2).value<QList<int>>();
        CHECK(roles.contains(childCountRole));
    }
    CHECK(presentation.data(dockIndex, childCountRole).toInt()
          == tasks.rowCount(tasks.index(0, 0)));
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

TEST_CASE("Dock presentation model places built-in widgets in slots without task identity", "[dock-presentation][dock-widgets]")
{
    const QUrl appA(QStringLiteral("applications:org.example.A"));
    const QUrl appB(QStringLiteral("applications:org.example.B"));
    QStandardItemModel tasks;
    appendTask(tasks, QStringLiteral("Pinned A"), appA);
    appendTask(tasks, QStringLiteral("Running B"), appB);

    kdockw::DockEntriesModel entries;
    const auto start = kdockw::DockEntry::separator(kdockw::DockWidgetSlot::Start);
    const auto center = kdockw::DockEntry::separator(kdockw::DockWidgetSlot::Center);
    const auto end = kdockw::DockEntry::separator(kdockw::DockWidgetSlot::End);
    entries.setEntries({kdockw::DockEntry::task(appA), center, start, end});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 5, 2000);
    CHECK(model.entryIdForDockIndex(0) == start.id);
    CHECK(model.data(model.index(0, 0), kdockw::DockPresentationModel::WidgetKindRole).toString()
          == QStringLiteral("separator"));
    CHECK(model.entryIdForDockIndex(2) == center.id);
    CHECK(model.entryIdForDockIndex(4) == end.id);
    CHECK(model.taskIndexForDockIndex(0) == -1);
    CHECK(model.taskIndexForDockIndex(4) == -1);
    CHECK(model.isPinnedDockIndex(0));
    CHECK_FALSE(model.isPinnedDockIndex(3));
    CHECK(entries.moveEntryById(start.id, center.id));
}

TEST_CASE("Application Launcher and compact media participate in dock magnification", "[dock-presentation][dock-widgets][zoom]")
{
    QStandardItemModel tasks;
    kdockw::DockEntriesModel entries;
    const auto separator = kdockw::DockEntry::separator(kdockw::DockWidgetSlot::Start);
    const auto spacer = kdockw::DockEntry::spacer(kdockw::DockWidgetSlot::Center, 32);
    const auto launcher = kdockw::DockEntry::applicationLauncher(kdockw::DockWidgetSlot::End);
    const auto media = kdockw::DockEntry::mediaPlayer(kdockw::DockWidgetSlot::End);
    const auto trash = kdockw::DockEntry::trash(kdockw::DockWidgetSlot::End);
    entries.setEntries({separator, spacer, launcher, media, trash});

    kdockw::DockPresentationModel model(&tasks, &entries);
    model.setMediaPlayerAvailable(true);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 5, 2000);
    const QVariantList specs = model.zoomLayoutSpecs(48);
    REQUIRE(specs.size() == 5);
    for (int row = 0; row < model.rowCount(); ++row) {
        const auto kind = model.data(model.index(row, 0), kdockw::DockPresentationModel::WidgetKindRole).toString();
        const auto spec = specs.at(row).toMap();
        const double expectedSize = kind == QLatin1String("spacer") ? 32.0
            : kind == QLatin1String("mediaPlayer") ? 48.0 : 48.0;
        CHECK(spec.value(QStringLiteral("size")).toDouble() == expectedSize);
        CHECK(spec.value(QStringLiteral("canMagnify")).toBool()
              == (kind == QLatin1String("applicationLauncher") || kind == QLatin1String("mediaPlayer") || kind == QLatin1String("trash")));
    }
    model.setMediaPlayerDisplayMode(1);
    CHECK_FALSE(model.zoomLayoutSpecs(48).at(3).toMap().value(QStringLiteral("canMagnify")).toBool());
    model.setMediaPlayerDisplayMode(2);
    const auto expandedSpecs = model.zoomLayoutSpecs(48);
    CHECK(expandedSpecs.at(3).toMap().value(QStringLiteral("size")).toDouble() == 200.0);
    CHECK_FALSE(expandedSpecs.at(3).toMap().value(QStringLiteral("canMagnify")).toBool());
    model.setMediaPlayerExpandedWidth(203);
    CHECK(model.zoomLayoutSpecs(48).at(3).toMap().value(QStringLiteral("size")).toDouble() == 205.0);
    model.setMediaPlayerExpandedWidth(275);
    CHECK(model.zoomLayoutSpecs(48).at(3).toMap().value(QStringLiteral("size")).toDouble() == 275.0);
    model.setMediaPlayerExpandedWidth(500);
    CHECK(model.zoomLayoutSpecs(48).at(3).toMap().value(QStringLiteral("size")).toDouble() == 300.0);
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

TEST_CASE("Dock presentation keeps a pinned launcher identity through the running-window transition",
          "[dock-presentation][taskmanager-regression]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.example.Writer"));
    QStandardItemModel tasks;
    auto launcher = std::make_unique<QStandardItem>(QStringLiteral("Writer"));
    launcher->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    launcher->setData(QStringLiteral("org.example.writer"), TaskManager::AbstractTasksModel::AppId);
    launcher->setData(true, TaskManager::AbstractTasksModel::IsLauncher);
    launcher->setData(false, TaskManager::AbstractTasksModel::IsWindow);
    launcher->setData(QVariantList{}, TaskManager::AbstractTasksModel::WinIdList);
    tasks.appendRow(launcher.release());

    kdockw::DockEntriesModel entries;
    const auto pinnedEntry = kdockw::DockEntry::task(launcherUrl);
    entries.setEntries({pinnedEntry});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 2000);
    CHECK(model.entryIdForDockIndex(0) == pinnedEntry.id);
    CHECK(model.taskIndexForDockIndex(0) == 0);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Writer"));
    CHECK(model.isPinnedDockIndex(0));

    // TaskManager promotes the launcher's row to a running task. The visual
    // row must keep the saved pin identity while all dynamic presentation
    // roles continue to come from that same, current TaskManager row.
    auto *item = tasks.item(0);
    REQUIRE(item != nullptr);
    {
        // KF 6.31 can update DisplayRole while only announcing the window
        // transition roles. Model this role-list omission explicitly.
        const QSignalBlocker blocker(&tasks);
        item->setData(QStringLiteral("Writer — report.txt"), Qt::DisplayRole);
        item->setData(QVariantList{QStringLiteral("window-42")}, TaskManager::AbstractTasksModel::WinIdList);
        item->setData(false, TaskManager::AbstractTasksModel::IsLauncher);
        item->setData(true, TaskManager::AbstractTasksModel::IsWindow);
        item->setData(true, TaskManager::AbstractTasksModel::IsActive);
        item->setData(QStringLiteral("org.example.writer"), TaskManager::AbstractTasksModel::AppId);
    }
    QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
    tasks.dataChanged(tasks.index(0, 0), tasks.index(0, 0),
                      {TaskManager::AbstractTasksModel::IsLauncher, TaskManager::AbstractTasksModel::IsWindow,
                       TaskManager::AbstractTasksModel::WinIdList, TaskManager::AbstractTasksModel::IsActive});

    CHECK(model.rowCount() == 1);
    CHECK(model.entryIdForDockIndex(0) == pinnedEntry.id);
    CHECK(model.taskIndexForDockIndex(0) == 0);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Writer — report.txt"));
    CHECK(model.data(model.index(0, 0), TaskManager::AbstractTasksModel::WinIdList).toList()
          == QVariantList{QStringLiteral("window-42")});
    CHECK(model.data(model.index(0, 0), TaskManager::AbstractTasksModel::IsWindow).toBool());
    CHECK(model.data(model.index(0, 0), TaskManager::AbstractTasksModel::IsActive).toBool());
    CHECK(model.isPinnedDockIndex(0));
    REQUIRE(changed.count() >= 1);
    CHECK(changed.last().at(2).value<QList<int>>().contains(Qt::DisplayRole));

    tasks.removeRow(0);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 2000);
    CHECK(model.entryIdForDockIndex(0) == pinnedEntry.id);
    CHECK(model.taskIndexForDockIndex(0) == -1);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString()
          == QFileInfo(pinnedEntry.url.path()).completeBaseName());
    CHECK(model.isPinnedDockIndex(0));
}

TEST_CASE("Dock presentation keeps the grouped application title when its active child changes",
          "[dock-presentation][taskmanager-regression][qt611]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.example.Browser"));
    QStandardItemModel tasks;
    auto group = std::make_unique<QStandardItem>(QStringLiteral("Browser"));
    group->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    group->setData(QStringLiteral("org.example.browser"), TaskManager::AbstractTasksModel::AppId);
    group->setData(true, TaskManager::AbstractTasksModel::IsGroupParent);
    group->setData(QStringList{QStringLiteral("window-1"), QStringLiteral("window-2")},
                   TaskManager::AbstractTasksModel::WinIdList);

    auto firstWindow = std::make_unique<QStandardItem>(QStringLiteral("Browser - Docs"));
    firstWindow->setData(false, TaskManager::AbstractTasksModel::IsActive);
    auto secondWindow = std::make_unique<QStandardItem>(QStringLiteral("Browser - Mail"));
    secondWindow->setData(true, TaskManager::AbstractTasksModel::IsActive);
    group->appendRow(firstWindow.release());
    group->appendRow(secondWindow.release());
    tasks.appendRow(group.release());

    kdockw::DockEntriesModel entries;
    const auto pinned = kdockw::DockEntry::task(launcherUrl);
    entries.setEntries({pinned});
    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 2000);

    const QModelIndex dockIndex = model.index(0, 0);
    QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
    CHECK(model.entryIdForDockIndex(0) == pinned.id);
    CHECK(model.taskIndexForDockIndex(0) == 0);
    CHECK(model.data(dockIndex, Qt::DisplayRole).toString() == QStringLiteral("Browser"));

    auto *rootItem = tasks.item(0);
    rootItem->child(1)->setData(false, TaskManager::AbstractTasksModel::IsActive);
    rootItem->child(0)->setData(true, TaskManager::AbstractTasksModel::IsActive);
    rootItem->child(0)->setText(QStringLiteral("Browser - Calendar"));
    CHECK(model.rowCount() == 1);
    CHECK(model.entryIdForDockIndex(0) == pinned.id);
    CHECK(model.data(dockIndex, Qt::DisplayRole).toString() == QStringLiteral("Browser"));
    CHECK(changed.count() == 0);
}

TEST_CASE("Dock presentation refreshes a pinned row when TaskManager replaces it structurally",
          "[dock-presentation][taskmanager-regression][rows]")
{
    const QUrl launcherUrl(QStringLiteral("applications:org.example.Editor"));
    QStandardItemModel tasks;
    auto launcher = std::make_unique<QStandardItem>(QStringLiteral("Editor"));
    launcher->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    launcher->setData(QStringLiteral("org.example.editor"), TaskManager::AbstractTasksModel::AppId);
    launcher->setData(true, TaskManager::AbstractTasksModel::IsLauncher);
    launcher->setData(false, TaskManager::AbstractTasksModel::IsWindow);
    tasks.appendRow(launcher.release());

    kdockw::DockEntriesModel entries;
    const auto pinnedEntry = kdockw::DockEntry::task(launcherUrl);
    const auto folderEntry = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/notes")));
    entries.setEntries({pinnedEntry, folderEntry});

    kdockw::DockPresentationModel model(&tasks, &entries);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 2, 2000);
    const QString stableId = model.entryIdForDockIndex(0);
    CHECK(stableId == pinnedEntry.id);
    CHECK(model.entryIdForDockIndex(1) == folderEntry.id);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Editor"));

    // Some TaskManager implementations remove and insert the root row as a
    // launcher becomes a window, without emitting dataChanged for the
    // surviving pinned presentation row. Keep its stable dock identity and
    // notify the delegate so it reads the replacement TaskManager row.
    tasks.removeRow(0);
    auto running = std::make_unique<QStandardItem>(QStringLiteral("Editor — Draft"));
    running->setData(launcherUrl, TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon);
    running->setData(QStringLiteral("org.example.editor"), TaskManager::AbstractTasksModel::AppId);
    running->setData(false, TaskManager::AbstractTasksModel::IsLauncher);
    running->setData(true, TaskManager::AbstractTasksModel::IsWindow);
    tasks.insertRow(0, running.release());

    CHECK(model.rowCount() == 2);
    CHECK(model.entryIdForDockIndex(0) == stableId);
    CHECK(model.entryIdForDockIndex(1) == folderEntry.id);
    CHECK(model.taskIndexForDockIndex(0) == 0);
    CHECK(model.isPinnedDockIndex(0));
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Editor — Draft"));
}
