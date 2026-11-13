// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "dockpresentationmodel.h"

#include <taskmanager/abstracttasksmodel.h>
#include <taskmanager/tasktools.h>

#include <QFileInfo>
#include <QCryptographicHash>
#include <QHash>
#include <QIcon>
#include <QMetaObject>
#include <QLoggingCategory>
#include <QSet>
#include <algorithm>

Q_LOGGING_CATEGORY(lcDockPresentation, "kdockw.presentation")

namespace kdockw
{

DockPresentationModel::DockPresentationModel(QAbstractItemModel *tasksModel, DockEntriesModel *entriesModel, QObject *parent,
                                             bool diagnosticsEnabled)
    : QAbstractListModel(parent)
    , m_tasksModel(tasksModel)
    , m_entriesModel(entriesModel)
    , m_diagnosticsEnabled(diagnosticsEnabled)
{
    connect(m_entriesModel, &DockEntriesModel::entriesChanged, this, &DockPresentationModel::scheduleRebuild);
    // Structural TaskManager signals are emitted after its row indices have
    // changed. Reconcile immediately so delegates never read an old taskIndex
    // against a new row order (the queued version briefly showed other apps'
    // names and icons until the event loop reached the rebuild).
    connect(m_tasksModel, &QAbstractItemModel::rowsInserted, this,
            [this](const QModelIndex &parent, int first, int last) {
                rebuild();
                forwardTaskRowsChanged(parent, first, last);
            });
    connect(m_tasksModel, &QAbstractItemModel::rowsRemoved, this,
            [this](const QModelIndex &parent, int first, int last) {
                rebuild();
                forwardTaskRowsChanged(parent, first, last);
            });
    connect(m_tasksModel, &QAbstractItemModel::rowsMoved, this, [this] { rebuild(); });
    connect(m_tasksModel, &QAbstractItemModel::modelReset, this, [this] { rebuild(); });
    connect(m_tasksModel, &QAbstractItemModel::layoutChanged, this, [this] { rebuild(); });
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
    case IconNameRole:
        return row.iconName;
    case IconUrlRole:
        return row.iconUrl;
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
    names.insert(IconNameRole, "iconName");
    names.insert(IconUrlRole, "iconUrl");
    names.insert(IsPinnedRole, "isPinned");
    return names;
}

int DockPresentationModel::pinnedEntryCount() const
{
    return m_pinnedEntryCount;
}

void DockPresentationModel::setSeparateLaunchers(bool separate)
{
    if (m_separateLaunchers == separate) {
        return;
    }
    m_separateLaunchers = separate;
    rebuild();
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
    QVector<bool> usedTaskRows(m_tasksModel->rowCount(), false);
    const int launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;

    if (!m_separateLaunchers) {
        const QList<DockEntry> entries = m_entriesModel->entries();
        QHash<QString, QList<DockEntry>> foldersBeforeTask;
        QList<DockEntry> pendingFolders;
        for (const DockEntry &entry : entries) {
            if (entry.type == DockEntryType::FolderStack) {
                pendingFolders.append(entry);
            } else {
                foldersBeforeTask.insert(entry.id, pendingFolders);
                pendingFolders.clear();
            }
        }

        QSet<QString> emittedEntryIds;
        const auto appendEntry = [&rows, &emittedEntryIds](const DockEntry &entry, int taskIndex) {
            Row row;
            row.entryId = entry.id;
            row.entryUrl = entry.url;
            row.iconName = entry.iconName;
            row.iconUrl = entry.iconUrl;
            row.pinned = true;
            row.entryType = entry.type == DockEntryType::FolderStack ? QStringLiteral("folderStack") : QStringLiteral("task");
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.taskIndex = taskIndex;
            rows.append(row);
            emittedEntryIds.insert(entry.id);
        };

        for (int taskIndex = 0; taskIndex < m_tasksModel->rowCount(); ++taskIndex) {
            const QUrl launcherUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
            const auto pinnedEntry = std::find_if(entries.cbegin(), entries.cend(), [&launcherUrl, &emittedEntryIds](const DockEntry &entry) {
                return entry.type == DockEntryType::Task && !emittedEntryIds.contains(entry.id)
                    && TaskManager::launcherUrlsMatch(entry.url, launcherUrl, TaskManager::IgnoreQueryItems);
            });
            if (pinnedEntry != entries.cend()) {
                for (const DockEntry &folder : foldersBeforeTask.value(pinnedEntry->id)) {
                    if (!emittedEntryIds.contains(folder.id)) {
                        appendEntry(folder, -1);
                    }
                }
                appendEntry(*pinnedEntry, taskIndex);
                usedTaskRows[taskIndex] = true;
                continue;
            }

            Row row;
            row.taskIndex = taskIndex;
            row.entryType = QStringLiteral("task");
            row.entryUrl = launcherUrl;
            row.entryId = taskKey(taskIndex);
            row.key = QStringLiteral("task:%1").arg(row.entryId);
            rows.append(row);
        }

        // Keep launcher-only rows and stacks whose neighboring launcher is
        // not currently represented by TaskManager visible, in their saved
        // relative order after all live rows.
        for (const DockEntry &entry : entries) {
            if (entry.type == DockEntryType::FolderStack && !emittedEntryIds.contains(entry.id)) {
                appendEntry(entry, -1);
            } else if (entry.type == DockEntryType::Task && !emittedEntryIds.contains(entry.id)) {
                for (const DockEntry &folder : foldersBeforeTask.value(entry.id)) {
                    if (!emittedEntryIds.contains(folder.id)) {
                        appendEntry(folder, -1);
                    }
                }
                appendEntry(entry, -1);
            }
        }
        return rows;
    }

    for (const DockEntry &entry : m_entriesModel->entries()) {
        Row row;
        row.entryId = entry.id;
        row.entryUrl = entry.url;
        row.iconName = entry.iconName;
        row.iconUrl = entry.iconUrl;
        row.pinned = true;
        if (entry.type == DockEntryType::FolderStack) {
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.entryType = QStringLiteral("folderStack");
        } else {
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.entryType = QStringLiteral("task");
            // TaskManager compares launcher URLs without their query metadata
            // (see launcherPosition()/launcherUrlsMatch()). Exact string keys
            // leave an activated pin as an icon-only row when the TaskManager
            // role carries icon/activity query data, then append the same live
            // task again in the unpinned zone.
            for (int taskIndex = 0; taskIndex < usedTaskRows.size(); ++taskIndex) {
                const QUrl launcherUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
                if (launcherUrl.isValid()
                    && TaskManager::launcherUrlsMatch(entry.url, launcherUrl, TaskManager::IgnoreQueryItems)) {
                    row.taskIndex = taskIndex;
                    usedTaskRows[taskIndex] = true;
                    break;
                }
            }
        }
        rows.append(row);
    }

    for (int taskIndex = 0; taskIndex < m_tasksModel->rowCount(); ++taskIndex) {
        if (usedTaskRows.at(taskIndex)) {
            continue;
        }
        Row row;
        row.taskIndex = taskIndex;
        row.entryType = QStringLiteral("task");
        row.entryUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
        // A running task is not a pinned entry. Give it its TaskManager
        // identity so a launcher URL metadata mismatch cannot produce the
        // same stable ID/key as a pinned row.
        row.entryId = taskKey(taskIndex);
        row.key = QStringLiteral("task:%1").arg(row.entryId);
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
    const QVariantList rawWindowIds = index.data(TaskManager::AbstractTasksModel::WinIdList).toList();
    if (!rawWindowIds.isEmpty()) {
        QStringList canonicalIds;
        canonicalIds.reserve(rawWindowIds.size());
        for (const QVariant &windowId : rawWindowIds) {
            canonicalIds.append(windowId.toString());
        }
        std::sort(canonicalIds.begin(), canonicalIds.end());
        return QStringLiteral("running:%1").arg(QString::fromLatin1(QCryptographicHash::hash(
                                                           canonicalIds.join(QLatin1Char('\x1f')).toUtf8(), QCryptographicHash::Sha256)
                                                           .toHex()));
    }
    const QString appId = index.data(TaskManager::AbstractTasksModel::AppId).toString();
    const QUrl launcher = index.data(TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon).toUrl();
    int duplicateOrdinal = 0;
    for (int row = 0; row < taskIndex; ++row) {
        const QModelIndex prior = m_tasksModel->index(row, 0);
        if (prior.data(TaskManager::AbstractTasksModel::WinIdList).toList().isEmpty()
            && prior.data(TaskManager::AbstractTasksModel::AppId).toString() == appId
            && prior.data(TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon).toUrl().toString(QUrl::RemoveQuery)
                == launcher.toString(QUrl::RemoveQuery)) {
            ++duplicateOrdinal;
        }
    }
    const QString identity = appId + QLatin1Char('\x1f') + launcher.toString(QUrl::RemoveQuery)
        + QLatin1Char('\x1f') + QString::number(duplicateOrdinal);
    const QByteArray digest = QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex();
    return QStringLiteral("running:%1:%2").arg(QString::fromLatin1(digest), QString::number(taskIndex));
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

    if (m_diagnosticsEnabled) {
        for (int dockIndex = 0; dockIndex < m_rows.size(); ++dockIndex) {
            const Row &row = m_rows.at(dockIndex);
            const bool hasTask = row.taskIndex >= 0 && row.taskIndex < m_tasksModel->rowCount();
            const QModelIndex taskIndex = hasTask ? m_tasksModel->index(row.taskIndex, 0) : QModelIndex{};
            qCInfo(lcDockPresentation).noquote()
                << "[KDOCKW_DOCK_ROW]"
                << "dockIndex=" << dockIndex
                << "type=" << row.entryType
                << "stableId=" << row.entryId
                << "pinned=" << row.pinned
                << "taskIndex=" << row.taskIndex
                << "desktopId=" << (hasTask ? taskIndex.data(TaskManager::AbstractTasksModel::AppId).toString() : QString{})
                << "launcherUrl=" << (row.entryType == QLatin1String("task") ? row.entryUrl.toString() : QString{})
                << "display=" << (hasTask ? taskIndex.data(Qt::DisplayRole).toString() : QFileInfo(row.entryUrl.toLocalFile()).fileName())
                << "iconName=" << (hasTask ? taskIndex.data(Qt::DecorationRole).value<QIcon>().name() : row.iconName)
                << "isLauncher=" << (hasTask && taskIndex.data(TaskManager::AbstractTasksModel::IsLauncher).toBool())
                << "isWindow=" << (hasTask && taskIndex.data(TaskManager::AbstractTasksModel::IsWindow).toBool())
                << "isGroupParent=" << (hasTask && taskIndex.data(TaskManager::AbstractTasksModel::IsGroupParent).toBool())
                << "taskDataPresent=" << hasTask;
        }
    }
}

void DockPresentationModel::forwardTaskRowsChanged(const QModelIndex &parent, int first, int last)
{
    // TaskManager can replace the launcher/window data at the same root row
    // through rowsRemoved/rowsInserted without a corresponding dataChanged.
    // The presentation Row then keeps the same stable ID and task index, so
    // rebuild() quite correctly sees no structural difference. Notify only
    // the affected presentation rows after reconciliation to refresh their
    // live TaskManager roles and QML bindings.
    if (parent.isValid()) {
        const int dockRow = rowForTaskIndex(parent.row());
        if (dockRow >= 0) {
            Q_EMIT dataChanged(index(dockRow, 0), index(dockRow, 0));
        }
        return;
    }

    const int rowCount = m_tasksModel->rowCount();
    if (rowCount <= 0) {
        return;
    }
    const int firstAffected = std::clamp(first, 0, rowCount - 1);
    const int lastAffected = std::clamp(std::max(first, last), firstAffected, rowCount - 1);
    for (int taskRow = firstAffected; taskRow <= lastAffected; ++taskRow) {
        const int dockRow = rowForTaskIndex(taskRow);
        if (dockRow >= 0) {
            Q_EMIT dataChanged(index(dockRow, 0), index(dockRow, 0));
        }
    }
}

void DockPresentationModel::forwardTaskDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles)
{
    if (!topLeft.isValid() || !bottomRight.isValid() || topLeft.parent() != bottomRight.parent()) {
        return;
    }

    if (topLeft.parent().isValid()) {
        return;
    }

    const int launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;
    const int appNameRole = TaskManager::AbstractTasksModel::AppName;
    const bool presentationMayChange = roles.isEmpty() || roles.contains(Qt::DisplayRole) || roles.contains(appNameRole)
        || roles.contains(TaskManager::AbstractTasksModel::IsLauncher) || roles.contains(TaskManager::AbstractTasksModel::IsWindow)
        || roles.contains(TaskManager::AbstractTasksModel::IsGroupParent) || roles.contains(TaskManager::AbstractTasksModel::WinIdList);
    if (roles.isEmpty() || roles.contains(launcherRole) || roles.contains(TaskManager::AbstractTasksModel::AppId)
        || roles.contains(TaskManager::AbstractTasksModel::WinIdList)
        || roles.contains(TaskManager::AbstractTasksModel::IsLauncher)
        || roles.contains(TaskManager::AbstractTasksModel::IsWindow)
        || roles.contains(TaskManager::AbstractTasksModel::IsGroupParent)) {
        scheduleRebuild();
    }
    QList<int> forwardedRoles = roles;
    if (presentationMayChange && !forwardedRoles.contains(Qt::DisplayRole)) {
        // Qt/KF 6.31 can change a row from launcher to window and update its
        // DisplayRole while omitting DisplayRole from the roles list. QML then
        // keeps the old accessible name even though data() returns the new
        // value. Explicitly notify delegates when task identity/window roles
        // can change the visible name.
        forwardedRoles.append(Qt::DisplayRole);
    }
    for (int taskIndex = topLeft.row(); taskIndex <= bottomRight.row(); ++taskIndex) {
        const int dockIndex = rowForTaskIndex(taskIndex);
        if (m_diagnosticsEnabled && presentationMayChange) {
            qCInfo(lcDockPresentation).noquote()
                << "[KDOCKW_TASK_DATA_TRACE]"
                << "taskRow=" << taskIndex
                << "dockRow=" << dockIndex
                << "incomingRoles=" << roles
                << "forwardedRoles=" << forwardedRoles
                << "display=" << (taskIndex < m_tasksModel->rowCount()
                                      ? m_tasksModel->data(m_tasksModel->index(taskIndex, 0), Qt::DisplayRole).toString()
                                      : QStringLiteral("<invalid>"));
        }
        if (dockIndex >= 0) {
            Q_EMIT dataChanged(index(dockIndex, 0), index(dockIndex, 0), forwardedRoles);
        }
    }
}

} // namespace kdockw
