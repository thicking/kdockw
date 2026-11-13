// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>

#include <QIcon>
#include <QList>
#include <QMenu>
#include <QString>

#include <functional>

namespace kdockw
{

class DockModel;
class DockActions;
class NotificationTracker;

struct ContextMenuAction
{
    QString text;
    QIcon icon;
    bool separator = false;
    std::function<void()> trigger;
};

struct ContextMenuWindowAction
{
    QString title;
    std::function<void()> close;
};

struct ContextMenuData
{
    QString title;
    QList<ContextMenuAction> applicationActions;
    QString pinText;
    QIcon pinIcon;
    std::function<void()> togglePinned;
    std::function<void()> newInstance;
    QString clearNotificationsText;
    std::function<void()> clearNotifications;
    QString closeText;
    std::function<void()> closeApplication;
    QList<ContextMenuWindowAction> windows;
    std::function<void()> settings;
    std::function<void()> about;
    std::function<void()> quit;
};

/// Construct one native menu from a task snapshot. Split out so menu state
/// and command routing can be covered without a live Wayland session.
QMenu *createContextMenu(const ContextMenuData &data, QObject *context);

/**
 * Context menu for dock items.
 *
 * Separated from DockModel to isolate UI-level menu construction
 * and its associated signals (settings, about, visibility tracking).
 */
class DockContextMenu : public QObject
{
    Q_OBJECT

    /// True from just before the menu pops up until it starts hiding. QML
    /// holds the dock's hover state while open, so it must already be true
    /// when QtWayland synthesizes the popup-grab leave for the dock window.
    Q_PROPERTY(bool open READ isOpen NOTIFY openChanged)

public:
    explicit DockContextMenu(DockModel *model, DockActions *actions, NotificationTracker *tracker, QObject *parent = nullptr);

    /// Show the native context menu for the task at @p index.
    Q_INVOKABLE void showForTask(int index);

    [[nodiscard]] bool isOpen() const;

Q_SIGNALS:
    void settingsRequested();
    void aboutRequested();
    void openChanged();

private:
    DockModel *m_model;
    DockActions *m_actions;
    NotificationTracker *m_tracker;
    bool m_open = false;

    void setOpen(bool open);
};

} // namespace kdockw
