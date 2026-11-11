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

public:
    enum Role {
        EntryIdRole = Qt::UserRole + 1,
        EntryTypeRole,
        EntryUrlRole,
    };
    Q_ENUM(Role)

    explicit DockEntriesModel(QObject *parent = nullptr);

    [[nodiscard]] int count() const;
    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QList<DockEntry> entries() const;
    [[nodiscard]] QStringList taskLauncherUrls() const;
    void setEntries(const QList<DockEntry> &entries);
    void syncTaskOrder(const QStringList &launcherUrls);

    Q_INVOKABLE bool appendFolderStack(const QUrl &url);
    Q_INVOKABLE bool removeFolderStack(const QString &entryId);
    Q_INVOKABLE bool moveEntry(int fromIndex, int toIndex);
    Q_INVOKABLE bool moveEntryById(const QString &entryId, const QString &targetEntryId);

Q_SIGNALS:
    void countChanged();
    void entriesChanged();

private:
    QList<DockEntry> m_entries;
};

} // namespace kdockw
