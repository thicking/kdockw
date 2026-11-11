// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "dockpresentationmodel.h"

#include <taskmanager/abstracttasksmodel.h>

#include <QFileInfo>
#include <QCryptographicHash>
#include <QMetaObject>
#include <QSet>

namespace kdockw
{

DockPresentationModel::DockPresentationModel(QAbstractItemModel *tasksModel, DockEntriesModel *entriesModel, QObject *parent)
    : QAbstractListModel(parent)
    , m_tasksModel(tasksModel)
    , m_entriesModel(entriesModel)
{
    connect(m_entriesModel, &DockEntriesModel::entriesChanged, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::rowsInserted, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::rowsRemoved, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::rowsMoved, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::modelReset, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::layoutChanged, this, &DockPresentationModel::scheduleRebuild);
    connect(m_tasksModel, &QAbstractItemModel::dataChanged, this, &DockPresentationModel::forwardTaskDataChanged);
    scheduleRebuild();
}

int DockPresentationModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant DockPresentationModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.column() != 0 || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }

    const Row &row = m_rows.at(index.row());
    switch (role) {
    case TaskIndexRole:
        return row.taskIndex;
    case EntryIdRole:
        return row.entryId;
    case EntryTypeRole:
        return row.entryType;
    case EntryUrlRole:
        return row.entryUrl;
    case IsPinnedRole:
        return row.pinned;
    default:
        break;
    }

    if (row.entryType == QLatin1String("folderStack")) {
        if (role == Qt::DisplayRole) {
            return QFileInfo(row.entryUrl.toLocalFile()).fileName();
        }
        return {};
    }

    if (row.taskIndex < 0 || row.taskIndex >= m_tasksModel->rowCount()) {
        if (role == Qt::DisplayRole) {
            return QFileInfo(row.entryUrl.path()).completeBaseName();
        }
        return {};
    }
    return m_tasksModel->data(m_tasksModel->index(row.taskIndex, 0), role);
}

QHash<int, QByteArray> DockPresentationModel::roleNames() const
{
    QHash<int, QByteArray> names = m_tasksModel->roleNames();
    names.insert(TaskIndexRole, "taskIndex");
    names.insert(EntryIdRole, "entryId");
    names.insert(EntryTypeRole, "entryType");
    names.insert(EntryUrlRole, "entryUrl");
    names.insert(IsPinnedRole, "isPinned");
    return names;
}

int DockPresentationModel::pinnedEntryCount() const
{
    return m_pinnedEntryCount;
}

int DockPresentationModel::taskIndexForDockIndex(int dockIndex) const
{
    if (dockIndex < 0 || dockIndex >= m_rows.size()) {
        return -1;
    }
    return m_rows.at(dockIndex).taskIndex;
}

int DockPresentationModel::dockIndexForTaskIndex(int taskIndex) const
{
    if (taskIndex < 0 || taskIndex >= m_taskToDock.size()) {
        return -1;
    }
    return m_taskToDock.at(taskIndex);
}

int DockPresentationModel::dockIndexForEntryId(const QString &entryId) const
{
    if (entryId.isEmpty()) {
        return -1;
    }
    for (int row = 0; row < m_rows.size(); ++row) {
        if (m_rows.at(row).entryId == entryId) {
            return row;
        }
    }
    return -1;
}

QString DockPresentationModel::entryIdForDockIndex(int dockIndex) const
{
    if (dockIndex < 0 || dockIndex >= m_rows.size()) {
        return {};
    }
    return m_rows.at(dockIndex).entryId;
}

bool DockPresentationModel::isPinnedDockIndex(int dockIndex) const
{
    return dockIndex >= 0 && dockIndex < m_rows.size() && m_rows.at(dockIndex).pinned;
}

QList<DockPresentationModel::Row> DockPresentationModel::desiredRows() const
{
    QList<Row> rows;
    QSet<int> usedTaskRows;
    QHash<QString, int> taskByLauncher;
    const int launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;

    for (int taskIndex = 0; taskIndex < m_tasksModel->rowCount(); ++taskIndex) {
        const QUrl launcherUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
        if (launcherUrl.isValid()) {
            taskByLauncher.insert(QString::fromLatin1(launcherUrl.toEncoded(QUrl::FullyEncoded)), taskIndex);
        }
    }

    for (const DockEntry &entry : m_entriesModel->entries()) {
        Row row;
        row.entryId = entry.id;
        row.entryUrl = entry.url;
        row.pinned = true;
        if (entry.type == DockEntryType::FolderStack) {
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.entryType = QStringLiteral("folderStack");
        } else {
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.entryType = QStringLiteral("task");
            row.taskIndex = taskByLauncher.value(QString::fromLatin1(entry.url.toEncoded(QUrl::FullyEncoded)), -1);
            if (row.taskIndex >= 0) {
                usedTaskRows.insert(row.taskIndex);
            }
        }
        rows.append(row);
    }

    for (int taskIndex = 0; taskIndex < m_tasksModel->rowCount(); ++taskIndex) {
        if (usedTaskRows.contains(taskIndex)) {
            continue;
        }
        Row row;
        row.taskIndex = taskIndex;
        row.entryType = QStringLiteral("task");
        row.entryUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
        if (row.entryUrl.isValid()) {
            row.entryId = DockEntry::task(row.entryUrl).id;
            row.key = QStringLiteral("entry:%1").arg(row.entryId);
        } else {
            row.key = taskKey(taskIndex);
            row.entryId = row.key;
        }
        row.pinned = false;
        rows.append(row);
    }
    return rows;
}

QString DockPresentationModel::taskKey(int taskIndex, const QString &entryId) const
{
    if (!entryId.isEmpty()) {
        return QStringLiteral("entry:%1").arg(entryId);
    }

    const QModelIndex index = m_tasksModel->index(taskIndex, 0);
    const QString appId = index.data(TaskManager::AbstractTasksModel::AppId).toString();
    if (!appId.isEmpty()) {
        return QStringLiteral("running:%1").arg(appId);
    }
    const QStringList windowIds = index.data(TaskManager::AbstractTasksModel::WinIdList).toStringList();
    if (!windowIds.isEmpty()) {
        return QStringLiteral("windows:%1").arg(QString::fromLatin1(QCryptographicHash::hash(
                                                             windowIds.join(QLatin1Char('\x1f')).toUtf8(), QCryptographicHash::Sha256)
                                                             .toHex()));
    }
    return QStringLiteral("row:%1").arg(taskIndex);
}

int DockPresentationModel::rowForTaskIndex(int taskIndex) const
{
    return dockIndexForTaskIndex(taskIndex);
}

void DockPresentationModel::scheduleRebuild()
{
    if (m_rebuildScheduled) {
        return;
    }
    m_rebuildScheduled = true;
    QMetaObject::invokeMethod(this, [this]() {
        m_rebuildScheduled = false;
        rebuild();
    }, Qt::QueuedConnection);
}

void DockPresentationModel::rebuild()
{
    const QList<Row> desired = desiredRows();
    QSet<QString> wantedKeys;
    for (const Row &row : desired) {
        wantedKeys.insert(row.key);
    }

    const int previousPinnedCount = m_pinnedEntryCount;
    for (int row = m_rows.size() - 1; row >= 0; --row) {
        if (!wantedKeys.contains(m_rows.at(row).key)) {
            beginRemoveRows({}, row, row);
            m_rows.removeAt(row);
            endRemoveRows();
        }
    }

    for (int target = 0; target < desired.size(); ++target) {
        if (target < m_rows.size() && m_rows.at(target).key == desired.at(target).key) {
            continue;
        }
        int current = target + 1;
        while (current < m_rows.size() && m_rows.at(current).key != desired.at(target).key) {
            ++current;
        }
        if (current < m_rows.size()) {
            beginMoveRows({}, current, current, {}, target);
            m_rows.move(current, target);
            endMoveRows();
        } else {
            beginInsertRows({}, target, target);
            m_rows.insert(target, desired.at(target));
            endInsertRows();
        }
    }

    for (int row = 0; row < desired.size(); ++row) {
        if (m_rows.at(row) != desired.at(row)) {
            m_rows[row] = desired.at(row);
            Q_EMIT dataChanged(index(row, 0), index(row, 0));
        }
    }

    m_taskToDock.fill(-1, m_tasksModel->rowCount());
    m_pinnedEntryCount = 0;
    for (int dockIndex = 0; dockIndex < m_rows.size(); ++dockIndex) {
        const Row &row = m_rows.at(dockIndex);
        if (row.pinned) {
            ++m_pinnedEntryCount;
        }
        if (row.taskIndex >= 0 && row.taskIndex < m_taskToDock.size()) {
            m_taskToDock[row.taskIndex] = dockIndex;
        }
    }
    if (previousPinnedCount != m_pinnedEntryCount) {
        Q_EMIT pinnedEntryCountChanged();
    }
}

void DockPresentationModel::forwardTaskDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles)
{
    if (!topLeft.isValid() || topLeft.parent().isValid() || bottomRight.parent().isValid()) {
        return;
    }
    const int launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;
    if (roles.isEmpty() || roles.contains(launcherRole) || roles.contains(TaskManager::AbstractTasksModel::AppId)) {
        scheduleRebuild();
    }
    for (int taskIndex = topLeft.row(); taskIndex <= bottomRight.row(); ++taskIndex) {
        const int dockIndex = rowForTaskIndex(taskIndex);
        if (dockIndex >= 0) {
            Q_EMIT dataChanged(index(dockIndex, 0), index(dockIndex, 0), roles);
        }
    }
}

} // namespace kdockw
