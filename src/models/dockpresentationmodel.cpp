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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
#include <QElapsedTimer>
#include <QTimer>
#endif
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    m_performanceDiagnosticsEnabled = qEnvironmentVariable("KDOCKW_PERF_DIAGNOSTICS") == QLatin1String("1");
    if (m_performanceDiagnosticsEnabled) {
        m_performanceClock.start();
        m_performanceReportTimer = new QTimer(this);
        m_performanceReportTimer->setInterval(5000);
        connect(m_performanceReportTimer, &QTimer::timeout, this, [this] {
            const qint64 elapsedMs = m_performanceClock.restart();
            qCInfo(lcDockPresentation).noquote()
                << "[KDOCKW_PERF_DOCK_PRESENTATION]"
                << "intervalMs=" << elapsedMs
                << "taskDataChanged=" << m_sourceDataChanges
                << "rowsInserted=" << m_sourceRowsInserted
                << "rowsRemoved=" << m_sourceRowsRemoved
                << "rowsMoved=" << m_sourceRowsMoved
                << "layoutChanged=" << m_sourceLayoutChanges
                << "modelReset=" << m_sourceModelResets
                << "rebuilds=" << m_rebuilds
                << "rebuildTotalMs=" << (m_rebuildNanos / 1000000.0)
                << "rebuildMaxMs=" << (m_rebuildMaxNanos / 1000000.0)
                << "dataHandlerTotalMs=" << (m_dataHandlerNanos / 1000000.0)
                << "dataHandlerMaxMs=" << (m_dataHandlerMaxNanos / 1000000.0)
                << "forwardedRows=" << m_forwardedRows
                << "launcherRoleChanges=" << m_launcherRoleChanges
                << "identityRoleChanges=" << m_identityRoleChanges
                << "decorationRoleChanges=" << m_decorationRoleChanges
                << "attentionRoleChanges=" << m_attentionRoleChanges
                << "otherRoleChanges=" << m_otherRoleChanges
                << "visibleRows=" << m_rows.size()
                << "taskRows=" << (m_tasksModel ? m_tasksModel->rowCount() : 0);
            m_sourceDataChanges = 0;
            m_sourceRowsInserted = 0;
            m_sourceRowsRemoved = 0;
            m_sourceRowsMoved = 0;
            m_sourceLayoutChanges = 0;
            m_sourceModelResets = 0;
            m_rebuilds = 0;
            m_rebuildNanos = 0;
            m_rebuildMaxNanos = 0;
            m_forwardedRows = 0;
            m_dataHandlerNanos = 0;
            m_dataHandlerMaxNanos = 0;
            m_launcherRoleChanges = 0;
            m_identityRoleChanges = 0;
            m_decorationRoleChanges = 0;
            m_attentionRoleChanges = 0;
            m_otherRoleChanges = 0;
        });
        m_performanceReportTimer->start();
    }
#endif
    connect(m_entriesModel, &DockEntriesModel::entriesChanged, this, &DockPresentationModel::scheduleRebuild);
    // Structural TaskManager signals are emitted after its row indices have
    // changed. Reconcile immediately so delegates never read an old taskIndex
    // against a new row order (the queued version briefly showed other apps'
    // names and icons until the event loop reached the rebuild).
    connect(m_tasksModel, &QAbstractItemModel::rowsInserted, this,
            [this](const QModelIndex &parent, int first, int last) {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
                if (m_performanceDiagnosticsEnabled) ++m_sourceRowsInserted;
#endif
                rebuild();
                forwardTaskRowsChanged(parent, first, last);
            });
    connect(m_tasksModel, &QAbstractItemModel::rowsRemoved, this,
            [this](const QModelIndex &parent, int first, int last) {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
                if (m_performanceDiagnosticsEnabled) ++m_sourceRowsRemoved;
#endif
                rebuild();
                forwardTaskRowsChanged(parent, first, last);
            });
    connect(m_tasksModel, &QAbstractItemModel::rowsMoved, this, [this] {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        if (m_performanceDiagnosticsEnabled) ++m_sourceRowsMoved;
#endif
        rebuild();
    });
    connect(m_tasksModel, &QAbstractItemModel::modelReset, this, [this] {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        if (m_performanceDiagnosticsEnabled) ++m_sourceModelResets;
#endif
        rebuild();
    });
    connect(m_tasksModel, &QAbstractItemModel::layoutChanged, this, [this] {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        if (m_performanceDiagnosticsEnabled) ++m_sourceLayoutChanges;
#endif
        rebuild();
    });
    connect(m_tasksModel, &QAbstractItemModel::dataChanged, this, [this](const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles) {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        QElapsedTimer timer;
        if (m_performanceDiagnosticsEnabled) {
            timer.start();
            m_sourceDataChanges += static_cast<quint64>(std::max(1, bottomRight.row() - topLeft.row() + 1));
            if (roles.isEmpty()) {
                ++m_otherRoleChanges;
            } else {
                for (const int role : roles) {
                    if (role == TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon
                        || role == TaskManager::AbstractTasksModel::LauncherUrl) {
                        ++m_launcherRoleChanges;
                    } else if (role == TaskManager::AbstractTasksModel::AppId
                               || role == TaskManager::AbstractTasksModel::IsLauncher
                               || role == TaskManager::AbstractTasksModel::IsWindow
                               || role == TaskManager::AbstractTasksModel::IsGroupParent
                               || role == TaskManager::AbstractTasksModel::WinIdList) {
                        ++m_identityRoleChanges;
                    } else if (role == Qt::DecorationRole) {
                        ++m_decorationRoleChanges;
                    } else if (role == TaskManager::AbstractTasksModel::IsDemandingAttention) {
                        ++m_attentionRoleChanges;
                    } else {
                        ++m_otherRoleChanges;
                    }
                }
            }
        }
#endif
        forwardTaskDataChanged(topLeft, bottomRight, roles);
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        if (m_performanceDiagnosticsEnabled) {
            const quint64 nanos = static_cast<quint64>(timer.nsecsElapsed());
            m_dataHandlerNanos += nanos;
            m_dataHandlerMaxNanos = std::max(m_dataHandlerMaxNanos, nanos);
        }
#endif
    });
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
    case WidgetKindRole:
        return row.widgetKind;
    case PlacementSlotRole:
        return row.placementSlot;
    case IsPinnedRole:
        return row.pinned;
    case WidgetSizeRole:
        return row.widgetSize;
    case WidgetVisibleRole:
        return row.widgetVisible;
    case IconIsCustomRole:
        return row.iconIsCustom;
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

    // ChildCount can lag the tree structure during TaskManager's group
    // collapse/expand notifications. The preview already uses rowCount() as
    // the authoritative window count; expose the same event-driven value to
    // QML so its indicator delegates cannot retain a stale aggregate role.
    if (role == TaskManager::AbstractTasksModel::ChildCount) {
        return m_tasksModel->rowCount(m_tasksModel->index(row.taskIndex, 0));
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
    names.insert(WidgetKindRole, "widgetKind");
    names.insert(PlacementSlotRole, "placementSlot");
    names.insert(IsPinnedRole, "isPinned");
    names.insert(WidgetSizeRole, "widgetSize");
    names.insert(WidgetVisibleRole, "widgetVisible");
    names.insert(IconIsCustomRole, "iconIsCustom");
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

void DockPresentationModel::setMediaPlayerAvailable(bool available)
{
    if (m_mediaPlayerAvailable == available) return;
    m_mediaPlayerAvailable = available;
    scheduleRebuild();
}

void DockPresentationModel::setMediaPlayerDisplayMode(int mode)
{
    mode = std::clamp(mode, 0, 2);
    if (m_mediaPlayerDisplayMode == mode) return;
    m_mediaPlayerDisplayMode = mode;
    scheduleRebuild();
}

void DockPresentationModel::setMediaPlayerExpandedWidth(int width)
{
    width = std::clamp(200 + ((width - 200 + 2) / 5) * 5, 200, 300);
    if (m_mediaPlayerExpandedWidth == width) return;
    m_mediaPlayerExpandedWidth = width;
    scheduleRebuild();
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

QVariantList DockPresentationModel::zoomLayoutSpecs(int iconSize) const
{
    QVariantList specs;
    specs.reserve(m_rows.size());
    for (const Row &row : m_rows) {
        const bool widget = row.entryType == QLatin1String("builtInWidget");
        const bool launcher = widget && row.widgetKind == QLatin1String("applicationLauncher");
        const bool media = widget && row.widgetKind == QLatin1String("mediaPlayer");
        const bool trash = widget && row.widgetKind == QLatin1String("trash");
        const double size = media && m_mediaPlayerDisplayMode == 2 ? m_mediaPlayerExpandedWidth
            : media && m_mediaPlayerDisplayMode == 1 ? std::max(96, iconSize)
            : widget && row.widgetSize > 0 ? std::max(4, row.widgetSize) : std::max(1, iconSize);
        specs.append(QVariantMap{{QStringLiteral("size"), size},
                                 {QStringLiteral("canMagnify"), !widget || launcher || trash || (media && m_mediaPlayerDisplayMode == 0)}});
    }
    return specs;
}

QList<DockPresentationModel::Row> DockPresentationModel::desiredRows() const
{
    QList<Row> rows;
    const auto appendBuiltIn = [this, &rows](const DockEntry &entry) {
        if (!entry.widgetVisible) return;
        if (entry.widgetKind == QLatin1String("mediaPlayer") && !m_mediaPlayerAvailable) return;
        Row row;
        row.entryId = entry.id;
        row.entryType = QStringLiteral("builtInWidget");
        row.widgetKind = entry.widgetKind;
        row.iconName = entry.iconName;
        row.iconUrl = entry.iconUrl;
        row.widgetSize = entry.widgetSize;
        if (entry.widgetKind == QLatin1String("mediaPlayer") && m_mediaPlayerDisplayMode == 2) {
            row.widgetSize = m_mediaPlayerExpandedWidth;
        }
        row.widgetVisible = entry.widgetVisible;
        row.iconIsCustom = entry.iconIsCustom;
        row.placementSlot = entry.slot == DockWidgetSlot::Start ? QStringLiteral("start")
            : entry.slot == DockWidgetSlot::End ? QStringLiteral("end") : QStringLiteral("center");
        row.key = QStringLiteral("entry:%1").arg(entry.id);
        row.pinned = true;
        rows.append(row);
    };
    const auto sortSlots = [&rows]() {
        const auto rank = [](const Row &row) {
            if (row.placementSlot == QLatin1String("start")) return 0;
            if (row.placementSlot == QLatin1String("end")) return 2;
            return 1;
        };
        std::stable_sort(rows.begin(), rows.end(), [&rank](const Row &left, const Row &right) {
            return rank(left) < rank(right);
        });
        return rows;
    };
    QVector<bool> usedTaskRows(m_tasksModel->rowCount(), false);
    const int launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;

    if (!m_separateLaunchers) {
        const QList<DockEntry> entries = m_entriesModel->entries();
        QHash<QString, QList<DockEntry>> entriesBeforeTask;
        QList<DockEntry> pendingEntries;
        QSet<QString> emittedEntryIds;
        for (const DockEntry &entry : entries) {
            if (entry.type == DockEntryType::BuiltInWidget) {
                if (entry.slot == DockWidgetSlot::Center) {
                    pendingEntries.append(entry);
                } else {
                    appendBuiltIn(entry);
                    emittedEntryIds.insert(entry.id);
                }
            } else if (entry.type == DockEntryType::FolderStack) {
                pendingEntries.append(entry);
            } else {
                entriesBeforeTask.insert(entry.id, pendingEntries);
                pendingEntries.clear();
            }
        }

        const auto appendEntry = [&rows, &emittedEntryIds](const DockEntry &entry, int taskIndex) {
            Row row;
            row.entryId = entry.id;
            row.entryUrl = entry.url;
            row.iconName = entry.iconName;
            row.iconUrl = entry.iconUrl;
            row.pinned = true;
            row.entryType = entry.type == DockEntryType::FolderStack
                ? QStringLiteral("folderStack")
                : QStringLiteral("task");
            row.key = QStringLiteral("entry:%1").arg(entry.id);
            row.taskIndex = taskIndex;
            rows.append(row);
            emittedEntryIds.insert(entry.id);
        };

        for (int taskIndex = 0; taskIndex < m_tasksModel->rowCount(); ++taskIndex) {
            const QUrl launcherUrl = m_tasksModel->data(m_tasksModel->index(taskIndex, 0), launcherRole).toUrl();
            const auto pinnedEntry = std::find_if(
                entries.cbegin(), entries.cend(), [&launcherUrl, &emittedEntryIds](const DockEntry &entry) {
                    return entry.type == DockEntryType::Task && !emittedEntryIds.contains(entry.id)
                        && TaskManager::launcherUrlsMatch(entry.url, launcherUrl, TaskManager::IgnoreQueryItems);
                });
            if (pinnedEntry != entries.cend()) {
                for (const DockEntry &before : entriesBeforeTask.value(pinnedEntry->id)) {
                    if (!emittedEntryIds.contains(before.id)) {
                        if (before.type == DockEntryType::BuiltInWidget) {
                            appendBuiltIn(before);
                            emittedEntryIds.insert(before.id);
                        } else {
                            appendEntry(before, -1);
                        }
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
            if (entry.type == DockEntryType::BuiltInWidget && !emittedEntryIds.contains(entry.id)) {
                appendBuiltIn(entry);
                emittedEntryIds.insert(entry.id);
            } else if (entry.type == DockEntryType::FolderStack && !emittedEntryIds.contains(entry.id)) {
                appendEntry(entry, -1);
            } else if (entry.type == DockEntryType::Task && !emittedEntryIds.contains(entry.id)) {
                for (const DockEntry &before : entriesBeforeTask.value(entry.id)) {
                    if (!emittedEntryIds.contains(before.id)) {
                        if (before.type == DockEntryType::BuiltInWidget) {
                            appendBuiltIn(before);
                            emittedEntryIds.insert(before.id);
                        } else {
                            appendEntry(before, -1);
                        }
                    }
                }
                appendEntry(entry, -1);
            }
        }
        return sortSlots();
    }

    for (const DockEntry &entry : m_entriesModel->entries()) {
        if (entry.type == DockEntryType::BuiltInWidget) {
            appendBuiltIn(entry);
            continue;
        }
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
    return sortSlots();
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    QElapsedTimer perfTimer;
    if (m_performanceDiagnosticsEnabled) perfTimer.start();
#endif
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (m_performanceDiagnosticsEnabled) {
        const quint64 nanos = static_cast<quint64>(perfTimer.nsecsElapsed());
        ++m_rebuilds;
        m_rebuildNanos += nanos;
        m_rebuildMaxNanos = std::max(m_rebuildMaxNanos, nanos);
    }
#endif
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            if (m_performanceDiagnosticsEnabled) ++m_forwardedRows;
#endif
            QList<int> changedRoles = m_tasksModel->roleNames().keys();
            if (!changedRoles.contains(TaskManager::AbstractTasksModel::ChildCount)) {
                changedRoles.append(TaskManager::AbstractTasksModel::ChildCount);
            }
            Q_EMIT dataChanged(index(dockRow, 0), index(dockRow, 0), changedRoles);
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            if (m_performanceDiagnosticsEnabled) ++m_forwardedRows;
#endif
            Q_EMIT dataChanged(index(dockRow, 0), index(dockRow, 0));
        }
    }
}

void DockPresentationModel::forwardTaskDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles)
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (qEnvironmentVariable("KDOCKW_EXPERIMENT_SUPPRESS_TASK_MODEL_FORWARDING") == QLatin1String("1")) {
        return;
    }
#endif
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
    // DecorationRole is relevant to icon updates, but it must not participate
    // in presentationMayChange: that flag also adds DisplayRole to the
    // forwarded signal. Keep the runtime notification narrow and widen only
    // the diagnostic trace gate.
    const bool diagnosticTraceMayChange = presentationMayChange || roles.contains(Qt::DecorationRole);
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
        if (m_diagnosticsEnabled && diagnosticTraceMayChange) {
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
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            if (m_performanceDiagnosticsEnabled) ++m_forwardedRows;
#endif
            Q_EMIT dataChanged(index(dockIndex, 0), index(dockIndex, 0), forwardedRoles);
        }
    }
}

} // namespace kdockw
