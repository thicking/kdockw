// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "dockcontextmenu.h"

#include "desktopactions.h"
#include "dockactions.h"
#include "dockmodel.h"
#include "notificationtracker.h"

#include <taskmanager/abstracttasksmodel.h>
#include <taskmanager/tasksmodel.h>

#include <KLocalizedString>

#include <QApplication>
#include <QCursor>
#include <QIcon>
#include <QMenu>
#include <QPersistentModelIndex>

namespace kdockw
{

QMenu *createContextMenu(const ContextMenuData &data, QObject *context)
{
    auto *menu = new QMenu();
    menu->setAttribute(Qt::WA_DeleteOnClose);

    QAction *header = menu->addAction(data.title);
    header->setEnabled(false);
    QFont boldFont = header->font();
    boldFont.setBold(true);
    header->setFont(boldFont);
    menu->addSeparator();

    for (const ContextMenuAction &item : data.applicationActions) {
        if (item.separator) {
            menu->addSeparator();
            continue;
        }
        QAction *action = menu->addAction(item.icon, item.text);
        if (item.trigger) {
            QObject::connect(action, &QAction::triggered, context, item.trigger);
        }
    }
    if (!data.applicationActions.isEmpty()) {
        menu->addSeparator();
    }

    if (!data.pinText.isEmpty()) {
        QAction *pin = menu->addAction(data.pinIcon, data.pinText);
        QObject::connect(pin, &QAction::triggered, context, data.togglePinned);
    }

    if (data.newInstance) {
        QAction *newInstance = menu->addAction(QIcon::fromTheme(QStringLiteral("list-add")), i18nc("@action:inmenu", "New Instance"));
        QObject::connect(newInstance, &QAction::triggered, context, data.newInstance);
    }

    if (!data.clearNotificationsText.isEmpty() && data.clearNotifications) {
        QAction *clear = menu->addAction(QIcon::fromTheme(QStringLiteral("edit-clear-history")), data.clearNotificationsText);
        QObject::connect(clear, &QAction::triggered, context, data.clearNotifications);
    }

    if (!data.closeText.isEmpty() && data.closeApplication) {
        menu->addSeparator();
        QAction *close = menu->addAction(QIcon::fromTheme(QStringLiteral("window-close")), data.closeText);
        QObject::connect(close, &QAction::triggered, context, data.closeApplication);
    }

    if (!data.windows.isEmpty()) {
        QMenu *windowsMenu = menu->addMenu(QIcon::fromTheme(QStringLiteral("window-list")), i18nc("@action:inmenu", "Close Window"));
        for (const ContextMenuWindowAction &window : data.windows) {
            QAction *closeWindow = windowsMenu->addAction(window.title);
            closeWindow->setToolTip(i18nc("@tooltip", "Close window %1", window.title));
            if (window.close) {
                QObject::connect(closeWindow, &QAction::triggered, context, window.close);
            }
        }
    }

    menu->addSeparator();
    QMenu *dockMenu = menu->addMenu(QIcon::fromTheme(QStringLiteral("application-x-plasma")), i18nc("@action:inmenu", "KDockW"));
    QAction *settings = dockMenu->addAction(QIcon::fromTheme(QStringLiteral("configure")), i18nc("@action:inmenu", "Settings..."));
    settings->setEnabled(static_cast<bool>(data.settings));
    if (data.settings) {
        QObject::connect(settings, &QAction::triggered, context, data.settings);
    }
    QAction *about = dockMenu->addAction(QIcon::fromTheme(QStringLiteral("help-about")), i18nc("@action:inmenu", "About KDockW"));
    about->setEnabled(static_cast<bool>(data.about));
    if (data.about) {
        QObject::connect(about, &QAction::triggered, context, data.about);
    }
    QAction *quit = dockMenu->addAction(QIcon::fromTheme(QStringLiteral("application-exit")), i18nc("@action:inmenu", "Quit KDockW"));
    quit->setEnabled(static_cast<bool>(data.quit));
    if (data.quit) {
        QObject::connect(quit, &QAction::triggered, context, data.quit);
    }
    return menu;
}

DockContextMenu::DockContextMenu(DockModel *model, DockActions *actions, NotificationTracker *tracker, QObject *parent)
    : QObject(parent)
    , m_model(model)
    , m_actions(actions)
    , m_tracker(tracker)
{
}

void DockContextMenu::showForTask(int index)
{
    auto *tasksModel = m_model->tasksModel();
    const QModelIndex idx = tasksModel->index(index, 0);
    if (!idx.isValid()) {
        return;
    }

    const bool isWindow = idx.data(TaskManager::AbstractTasksModel::IsWindow).toBool();
    const bool isGroupParent = idx.data(TaskManager::AbstractTasksModel::IsGroupParent).toBool();
    const QString name = idx.data(Qt::DisplayRole).toString();

    const bool pinned = m_model->isPinned(index);

    ContextMenuData data;
    data.title = name;

    // Desktop entry actions (e.g. "New Private Window"), placed like Plasma's
    // task manager. Group parents report their first window's launcher URL.
    // Each action is captured by value together with its KService, so it
    // launches the right application even if task rows change while the menu
    // is open.
    const QList<KServiceAction> appActions = desktopActions(idx.data(TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon).toUrl());
    for (const KServiceAction &action : appActions) {
        if (action.isSeparator()) {
            data.applicationActions.append({{}, {}, true, {}});
            continue;
        }
        // Desktop files use plain text; '&' is not a mnemonic marker.
        QString text = action.text();
        text.replace(QLatin1Char('&'), QLatin1String("&&"));
        data.applicationActions.append({text, QIcon::fromTheme(action.icon()), false, [action]() {
                                             launchDesktopAction(action);
                                         }});
    }

    // Pin / Unpin
    if (pinned) {
        data.pinText = i18nc("@action:inmenu", "Unpin from Dock");
        data.pinIcon = QIcon::fromTheme(QStringLiteral("window-unpin"));
    } else {
        data.pinText = i18nc("@action:inmenu", "Pin to Dock");
        data.pinIcon = QIcon::fromTheme(QStringLiteral("window-pin"));
    }
    data.togglePinned = [this, index]() { m_actions->togglePinned(index); };

    // New Instance
    data.newInstance = [this, index]() { m_actions->newInstance(index); };

    // Clear Notifications (only when badges are present)
    if (m_tracker != nullptr) {
        const QString appId = m_model->appId(index);
        if (!appId.isEmpty() && m_tracker->unreadCount(appId) > 0) {
            data.clearNotificationsText = i18nc("@action:inmenu", "Clear Notifications");
            data.clearNotifications = [this, appId]() { m_tracker->clearUnreadNotifications(appId); };
        }
    }

    // A grouped dock task represents an application. Its explicitly named
    // application action closes that group; the submenu exposes one-window
    // actions so a window-level intent never closes sibling windows.
    if (isWindow) {
        QPersistentModelIndex persistent(idx);
        if (isGroupParent && tasksModel->rowCount(idx) > 1) {
            QList<QPersistentModelIndex> groupedWindows;
            const int count = tasksModel->rowCount(idx);
            for (int child = 0; child < count; ++child) {
                const QModelIndex childIndex = tasksModel->makeModelIndex(index, child);
                if (!childIndex.isValid() || !childIndex.data(TaskManager::AbstractTasksModel::IsClosable).toBool()) {
                    continue;
                }
                const QPersistentModelIndex childPersistent(childIndex);
                groupedWindows.append(childPersistent);
                data.windows.append({childIndex.data(Qt::DisplayRole).toString(), [tasksModel, childPersistent]() {
                                         if (childPersistent.isValid() && childPersistent.data(TaskManager::AbstractTasksModel::IsClosable).toBool()) {
                                             tasksModel->requestClose(childPersistent);
                                         }
                                     }});
            }
            if (!groupedWindows.isEmpty()) {
                data.closeText = i18nc("@action:inmenu", "Close Application");
                data.closeApplication = [tasksModel, groupedWindows]() {
                    for (const QPersistentModelIndex &window : groupedWindows) {
                        if (window.isValid() && window.data(TaskManager::AbstractTasksModel::IsClosable).toBool()) {
                            tasksModel->requestClose(window);
                        }
                    }
                };
            }
        } else if (idx.data(TaskManager::AbstractTasksModel::IsClosable).toBool()) {
            data.closeText = i18nc("@action:inmenu", "Close Window");
            data.closeApplication = [tasksModel, persistent]() {
                if (persistent.isValid() && persistent.data(TaskManager::AbstractTasksModel::IsClosable).toBool()) {
                    tasksModel->requestClose(persistent);
                }
            };
        }
    }

    data.settings = [this]() { Q_EMIT settingsRequested(); };
    data.about = [this]() { Q_EMIT aboutRequested(); };
    data.quit = []() { qApp->quit(); };
    auto *menu = createContextMenu(data, this);

    // Open before popup(): the popup grab makes QtWayland send the dock a
    // synthetic leave, which QML must already see as part of the menu hold.
    // Also drives the interaction lock (dock stays visible while menu is open).
    setOpen(true);
    connect(menu, &QMenu::aboutToHide, this, [this]() {
        setOpen(false);
    });

    menu->popup(QCursor::pos());
}

bool DockContextMenu::isOpen() const
{
    return m_open;
}

void DockContextMenu::setOpen(bool open)
{
    if (m_open == open) {
        return;
    }
    m_open = open;
    Q_EMIT openChanged();
}

} // namespace kdockw
