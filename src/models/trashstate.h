// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QList>
#include <QObject>
#include <QUrl>

class KDirWatch;

namespace kdockw
{

/**
 * State and commands for the built-in Trash widget.
 *
 * Full/empty state comes from KIO's trashrc ([Status] Empty), the same key
 * Dolphin reads. The KIO trash worker rewrites that file whenever the trash
 * changes between empty and non-empty, so a file watch is enough to follow it.
 */
class TrashState final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool empty READ isEmpty NOTIFY emptyChanged)

public:
    explicit TrashState(QObject *parent = nullptr);

    [[nodiscard]] bool isEmpty() const;

    /// Opens trash:/ in the default file manager.
    Q_INVOKABLE void open();
    /// Moves @p urls to the trash with KDE's standard confirmation and Undo record.
    Q_INVOKABLE void moveToTrash(const QList<QUrl> &urls);
    /// Empties the trash after KDE's standard confirmation.
    Q_INVOKABLE void emptyTrash();

    /// Re-reads trashrc. Called by the file watch; public for tests.
    void refresh();

Q_SIGNALS:
    void emptyChanged();

private:
    KDirWatch *m_watch = nullptr;
    bool m_empty = true;
};

} // namespace kdockw
