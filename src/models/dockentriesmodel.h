// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include "dockentry.h"

#include <QAbstractListModel>

namespace kdockw
{

/** Ordered model of pinned applications and folder stacks. */
class DockEntriesModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool hasApplicationLauncher READ hasApplicationLauncher NOTIFY entriesChanged)
    Q_PROPERTY(bool hasMediaPlayer READ hasMediaPlayer NOTIFY entriesChanged)
    Q_PROPERTY(bool hasTrash READ hasTrash NOTIFY entriesChanged)

public:
    enum Role {
        EntryIdRole = Qt::UserRole + 1,
        EntryTypeRole,
        EntryUrlRole,
        IconNameRole,
        IconUrlRole,
        WidgetKindRole,
        PlacementSlotRole,
        WidgetSizeRole,
        WidgetVisibleRole,
        IconIsCustomRole,
    };
    Q_ENUM(Role)

    explicit DockEntriesModel(QObject *parent = nullptr);

    [[nodiscard]] int count() const;
    [[nodiscard]] bool hasApplicationLauncher() const;
    [[nodiscard]] bool hasMediaPlayer() const;
    [[nodiscard]] bool hasTrash() const;
    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QList<DockEntry> entries() const;
    [[nodiscard]] QStringList taskLauncherUrls() const;
    void setEntries(const QList<DockEntry> &entries);
    void syncTaskOrder(const QStringList &launcherUrls);

    Q_INVOKABLE bool appendFolderStack(const QUrl &url);
    Q_INVOKABLE QString appendSeparator(const QString &slot = QStringLiteral("center"));
    Q_INVOKABLE QString appendSpacer(int size = 24, const QString &slot = QStringLiteral("center"));
    Q_INVOKABLE QString appendApplicationLauncher(const QString &slot = QStringLiteral("center"));
    Q_INVOKABLE QString appendMediaPlayer(const QString &slot = QStringLiteral("end"));
    Q_INVOKABLE QString appendTrash(const QString &slot = QStringLiteral("end"));
    Q_INVOKABLE bool removeBuiltInWidget(const QString &entryId);
    Q_INVOKABLE bool setBuiltInWidgetSize(const QString &entryId, int size);
    Q_INVOKABLE bool setBuiltInWidgetIcon(const QString &entryId, const QString &iconName);
    Q_INVOKABLE bool setBuiltInWidgetVisible(const QString &entryId, bool visible);
    Q_INVOKABLE bool setBuiltInWidgetSlot(const QString &entryId, const QString &slot);
    Q_INVOKABLE bool removeFolderStack(const QString &entryId);
    Q_INVOKABLE bool setFolderStackIcon(const QString &entryId, const QString &iconName, const QUrl &iconUrl = {});
    Q_INVOKABLE bool moveEntry(int fromIndex, int toIndex);
    Q_INVOKABLE bool moveEntryById(const QString &entryId, const QString &targetEntryId);
    Q_INVOKABLE QString entryIdAt(int row) const;
    Q_INVOKABLE QString entryTypeAt(int row) const;

Q_SIGNALS:
    void countChanged();
    void entriesChanged();

private:
    QList<DockEntry> m_entries;
};

} // namespace kdockw
