// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "dockentriesmodel.h"

#include <QFileInfo>
#include <QSet>

#include <algorithm>
#include <utility>

namespace kdockw
{

DockEntriesModel::DockEntriesModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int DockEntriesModel::count() const
{
    return m_entries.size();
}

bool DockEntriesModel::hasApplicationLauncher() const
{
    return std::any_of(m_entries.cbegin(), m_entries.cend(), [](const DockEntry &entry) {
        return entry.type == DockEntryType::BuiltInWidget
            && entry.widgetKind == QLatin1String("applicationLauncher");
    });
}

bool DockEntriesModel::hasMediaPlayer() const
{
    return std::any_of(m_entries.cbegin(), m_entries.cend(), [](const DockEntry &entry) {
        return entry.type == DockEntryType::BuiltInWidget && entry.widgetKind == QLatin1String("mediaPlayer");
    });
}

bool DockEntriesModel::hasTrash() const
{
    return std::any_of(m_entries.cbegin(), m_entries.cend(), [](const DockEntry &entry) {
        return entry.type == DockEntryType::BuiltInWidget && entry.widgetKind == QLatin1String("trash");
    });
}

int DockEntriesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant DockEntriesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size()) {
        return {};
    }

    const DockEntry &entry = m_entries.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
        return entry.type == DockEntryType::FolderStack ? QFileInfo(entry.url.toLocalFile()).fileName() : entry.url.toString();
    case EntryIdRole:
        return entry.id;
    case EntryTypeRole:
        return entry.type == DockEntryType::FolderStack ? QStringLiteral("folderStack")
            : entry.type == DockEntryType::BuiltInWidget ? QStringLiteral("builtInWidget") : QStringLiteral("task");
    case EntryUrlRole:
        return entry.url;
    case IconNameRole:
        return entry.iconName;
    case IconUrlRole:
        return entry.iconUrl;
    case WidgetKindRole:
        return entry.widgetKind;
    case PlacementSlotRole:
        switch (entry.slot) {
        case DockWidgetSlot::Start: return QStringLiteral("start");
        case DockWidgetSlot::End: return QStringLiteral("end");
        case DockWidgetSlot::Center: return QStringLiteral("center");
        }
        return QStringLiteral("center");
    case WidgetSizeRole:
        return entry.widgetSize;
    case WidgetVisibleRole:
        return entry.widgetVisible;
    case IconIsCustomRole:
        return entry.iconIsCustom;
    default:
        return {};
    }
}

QHash<int, QByteArray> DockEntriesModel::roleNames() const
{
    return {
        {Qt::DisplayRole, "display"},
        {EntryIdRole, "entryId"},
        {EntryTypeRole, "entryType"},
        {EntryUrlRole, "entryUrl"},
        {IconNameRole, "iconName"},
        {IconUrlRole, "iconUrl"},
        {WidgetKindRole, "widgetKind"},
        {PlacementSlotRole, "placementSlot"},
        {WidgetSizeRole, "widgetSize"},
        {WidgetVisibleRole, "widgetVisible"},
        {IconIsCustomRole, "iconIsCustom"},
    };
}

QList<DockEntry> DockEntriesModel::entries() const
{
    return m_entries;
}

QStringList DockEntriesModel::taskLauncherUrls() const
{
    QStringList urls;
    for (const DockEntry &entry : m_entries) {
        if (entry.type == DockEntryType::Task) {
            urls.append(entry.url.toString());
        }
    }
    return urls;
}

void DockEntriesModel::setEntries(const QList<DockEntry> &entries)
{
    QList<DockEntry> validEntries;
    QSet<QString> ids;
    validEntries.reserve(entries.size());
    for (const DockEntry &entry : entries) {
        if (!entry.isValid() || ids.contains(entry.id)) {
            continue;
        }
        ids.insert(entry.id);
        validEntries.append(entry);
    }

    if (m_entries == validEntries) {
        return;
    }

    const int oldCount = m_entries.size();
    beginResetModel();
    m_entries = std::move(validEntries);
    endResetModel();
    if (oldCount != m_entries.size()) {
        Q_EMIT countChanged();
    }
    Q_EMIT entriesChanged();
}

void DockEntriesModel::syncTaskOrder(const QStringList &launcherUrls)
{
    const QList<DockEntry> newTasks = DockEntriesCodec::fromLegacyLaunchers(launcherUrls);
    QList<DockEntry> ordered;
    ordered.reserve(m_entries.size() + newTasks.size());
    qsizetype taskIndex = 0;

    for (const DockEntry &entry : std::as_const(m_entries)) {
        if (entry.type != DockEntryType::Task) {
            ordered.append(entry);
        } else if (taskIndex < newTasks.size()) {
            ordered.append(newTasks.at(taskIndex++));
        }
    }
    while (taskIndex < newTasks.size()) {
        ordered.append(newTasks.at(taskIndex++));
    }
    setEntries(ordered);
}

QString DockEntriesModel::appendSeparator(const QString &slotName)
{
    DockWidgetSlot slot = DockWidgetSlot::Center;
    if (slotName == QLatin1String("start")) {
        slot = DockWidgetSlot::Start;
    } else if (slotName == QLatin1String("end")) {
        slot = DockWidgetSlot::End;
    } else if (slotName != QLatin1String("center")) {
        return {};
    }
    const DockEntry entry = DockEntry::separator(slot);
    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.insert(row, entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return entry.id;
}

QString DockEntriesModel::appendSpacer(int size, const QString &slotName)
{
    if (size < 4 || size > 512) return {};
    DockWidgetSlot slot = DockWidgetSlot::Center;
    if (slotName == QLatin1String("start")) slot = DockWidgetSlot::Start;
    else if (slotName == QLatin1String("end")) slot = DockWidgetSlot::End;
    else if (slotName != QLatin1String("center")) return {};
    const DockEntry entry = DockEntry::spacer(slot, size);
    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.append(entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return entry.id;
}

QString DockEntriesModel::appendApplicationLauncher(const QString &slotName)
{
    if (hasApplicationLauncher()) {
        return {};
    }
    DockWidgetSlot slot = DockWidgetSlot::Center;
    if (slotName == QLatin1String("start")) slot = DockWidgetSlot::Start;
    else if (slotName == QLatin1String("end")) slot = DockWidgetSlot::End;
    else if (slotName != QLatin1String("center")) return {};
    const DockEntry entry = DockEntry::applicationLauncher(slot);
    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.append(entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return entry.id;
}

QString DockEntriesModel::appendMediaPlayer(const QString &slotName)
{
    if (hasMediaPlayer()) return {};
    DockWidgetSlot slot = DockWidgetSlot::End;
    if (slotName == QLatin1String("start")) slot = DockWidgetSlot::Start;
    else if (slotName == QLatin1String("center")) slot = DockWidgetSlot::Center;
    else if (slotName != QLatin1String("end")) return {};
    const DockEntry entry = DockEntry::mediaPlayer(slot);
    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.insert(row, entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return entry.id;
}

QString DockEntriesModel::appendTrash(const QString &slotName)
{
    if (hasTrash())
        return {};
    DockWidgetSlot slot = DockWidgetSlot::End;
    if (slotName == QLatin1String("start"))
        slot = DockWidgetSlot::Start;
    else if (slotName == QLatin1String("center"))
        slot = DockWidgetSlot::Center;
    else if (slotName != QLatin1String("end"))
        return {};
    const DockEntry entry = DockEntry::trash(slot);
    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.insert(row, entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return entry.id;
}

bool DockEntriesModel::setBuiltInWidgetSize(const QString &entryId, int size)
{
    if (size < 4 || size > 512) return false;
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        DockEntry &entry = m_entries[row];
        if (entry.type != DockEntryType::BuiltInWidget || entry.id != entryId) continue;
        if (entry.widgetSize == size) return true;
        entry.widgetSize = size;
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {WidgetSizeRole});
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::setBuiltInWidgetIcon(const QString &entryId, const QString &iconName)
{
    if (iconName.isEmpty()) return false;
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        DockEntry &entry = m_entries[row];
        if (entry.type != DockEntryType::BuiltInWidget || entry.id != entryId
            || entry.widgetKind != QLatin1String("applicationLauncher")) continue;
        if (entry.iconName == iconName && entry.iconIsCustom) return true;
        entry.iconName = iconName;
        entry.iconIsCustom = true;
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {IconNameRole, IconIsCustomRole});
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::setBuiltInWidgetVisible(const QString &entryId, bool visible)
{
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        DockEntry &entry = m_entries[row];
        if (entry.type != DockEntryType::BuiltInWidget || entry.id != entryId) continue;
        if (entry.widgetVisible == visible) return true;
        entry.widgetVisible = visible;
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {WidgetVisibleRole});
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::setBuiltInWidgetSlot(const QString &entryId, const QString &slotName)
{
    DockWidgetSlot slot;
    if (slotName == QLatin1String("start")) slot = DockWidgetSlot::Start;
    else if (slotName == QLatin1String("center")) slot = DockWidgetSlot::Center;
    else if (slotName == QLatin1String("end")) slot = DockWidgetSlot::End;
    else return false;
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        DockEntry &entry = m_entries[row];
        if (entry.type != DockEntryType::BuiltInWidget || entry.id != entryId) continue;
        if (entry.slot == slot) return true;
        entry.slot = slot;
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {PlacementSlotRole});
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::removeBuiltInWidget(const QString &entryId)
{
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        const DockEntry &entry = m_entries.at(row);
        if (entry.type != DockEntryType::BuiltInWidget || entry.id != entryId) {
            continue;
        }
        beginRemoveRows({}, row, row);
        m_entries.removeAt(row);
        endRemoveRows();
        Q_EMIT countChanged();
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::appendFolderStack(const QUrl &url)
{
    const DockEntry entry = DockEntry::folderStack(url);
    if (!entry.isValid()) {
        return false;
    }

    const int row = m_entries.size();
    beginInsertRows({}, row, row);
    m_entries.append(entry);
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT entriesChanged();
    return true;
}

bool DockEntriesModel::removeFolderStack(const QString &entryId)
{
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        const DockEntry &entry = m_entries.at(row);
        if (entry.type != DockEntryType::FolderStack || entry.id != entryId) {
            continue;
        }
        beginRemoveRows({}, row, row);
        m_entries.removeAt(row);
        endRemoveRows();
        Q_EMIT countChanged();
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::setFolderStackIcon(const QString &entryId, const QString &iconName, const QUrl &iconUrl)
{
    if (entryId.isEmpty() || (!iconUrl.isEmpty() && (!iconUrl.isValid() || !iconUrl.isLocalFile()))) {
        return false;
    }
    for (qsizetype row = 0; row < m_entries.size(); ++row) {
        DockEntry &entry = m_entries[row];
        if (entry.type != DockEntryType::FolderStack || entry.id != entryId) {
            continue;
        }
        if (entry.iconName == iconName && entry.iconUrl == iconUrl) {
            return true;
        }
        entry.iconName = iconName;
        entry.iconUrl = iconUrl;
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {IconNameRole, IconUrlRole});
        Q_EMIT entriesChanged();
        return true;
    }
    return false;
}

bool DockEntriesModel::moveEntry(int fromIndex, int toIndex)
{
    if (fromIndex < 0 || fromIndex >= m_entries.size() || toIndex < 0 || toIndex >= m_entries.size() || fromIndex == toIndex) {
        return false;
    }
    const DockWidgetSlot targetSlot = m_entries.at(toIndex).slot;
    const bool movingWidget = m_entries.at(fromIndex).type == DockEntryType::BuiltInWidget;
    const int destinationChild = toIndex > fromIndex ? toIndex + 1 : toIndex;
    if (!beginMoveRows({}, fromIndex, fromIndex, {}, destinationChild)) {
        return false;
    }
    m_entries.move(fromIndex, toIndex);
    endMoveRows();
    if (movingWidget) {
        DockEntry &moved = m_entries[toIndex];
        if (moved.slot != targetSlot) {
            moved.slot = targetSlot;
            Q_EMIT dataChanged(index(toIndex, 0), index(toIndex, 0), {PlacementSlotRole});
        }
    }
    Q_EMIT entriesChanged();
    return true;
}

bool DockEntriesModel::moveEntryById(const QString &entryId, const QString &targetEntryId)
{
    if (entryId.isEmpty() || targetEntryId.isEmpty() || entryId == targetEntryId) {
        return false;
    }
    const auto findEntry = [this](const QString &id) {
        for (qsizetype row = 0; row < m_entries.size(); ++row) {
            if (m_entries.at(row).id == id) {
                return static_cast<int>(row);
            }
        }
        return -1;
    };
    return moveEntry(findEntry(entryId), findEntry(targetEntryId));
}

QString DockEntriesModel::entryIdAt(int row) const
{
    return row >= 0 && row < m_entries.size() ? m_entries.at(row).id : QString{};
}

QString DockEntriesModel::entryTypeAt(int row) const
{
    if (row < 0 || row >= m_entries.size()) return {};
    const DockEntry &entry = m_entries.at(row);
    return entry.type == DockEntryType::BuiltInWidget ? QStringLiteral("builtInWidget")
        : entry.type == DockEntryType::FolderStack ? QStringLiteral("folderStack") : QStringLiteral("task");
}

} // namespace kdockw
