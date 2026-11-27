// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>
#include <QHash>
#include <QUrl>

#include "dockentriesmodel.h"
#include "dockpresentationmodel.h"
#include "mediaplayercontroller.h"
#include "trashstate.h"

#include <taskmanager/activityinfo.h>
#include <taskmanager/tasksmodel.h>
#include <taskmanager/virtualdesktopinfo.h>

#include <memory>
#ifdef KDOCKW_DIAGNOSTIC_BUILD
#include <QElapsedTimer>
class QTimer;
#endif

class KDockWSettings;

namespace kdockw
{

class ApplicationCatalog;
class ApplicationLauncherState;

/**
 * Central model for the dock's task manager section.
 *
 * Wraps libtaskmanager's TasksModel and configures it for dock usage:
 * grouped by application, with pinned launchers + running windows merged.
 * Exposes the model to QML and provides action methods.
 */
class DockModel : public QObject
{
    Q_OBJECT

    Q_PROPERTY(TaskManager::TasksModel *tasksModel READ tasksModel CONSTANT)
    Q_PROPERTY(DockEntriesModel *dockEntriesModel READ dockEntriesModel CONSTANT)
    Q_PROPERTY(DockPresentationModel *dockPresentationModel READ dockPresentationModel CONSTANT)
    Q_PROPERTY(ApplicationCatalog *applicationCatalog READ applicationCatalog CONSTANT)
    Q_PROPERTY(ApplicationLauncherState *applicationLauncherState READ applicationLauncherState CONSTANT)
    Q_PROPERTY(TrashState *trashState READ trashState CONSTANT)
    Q_PROPERTY(MediaPlayerController *mediaPlayerController READ mediaPlayerController CONSTANT)
    Q_PROPERTY(int pinnedDockEntryCount READ pinnedDockEntryCount NOTIFY pinnedDockEntryCountChanged)
    Q_PROPERTY(bool taskDiagnosticsEnabled READ taskDiagnosticsEnabled CONSTANT)
    Q_PROPERTY(QString dockEntries READ dockEntries NOTIFY dockEntriesChanged)
    Q_PROPERTY(QStringList pinnedLaunchers READ pinnedLaunchers WRITE setPinnedLaunchers NOTIFY pinnedLaunchersChanged)
    Q_PROPERTY(int pinnedTaskCount READ pinnedTaskCount NOTIFY pinnedTaskCountChanged)
    Q_PROPERTY(int virtualDesktopMode READ virtualDesktopMode WRITE setVirtualDesktopMode NOTIFY virtualDesktopModeChanged)
    Q_PROPERTY(QVariant currentDesktop READ currentDesktop NOTIFY currentDesktopChanged)

public:
    explicit DockModel(QObject *parent = nullptr, KDockWSettings *settings = nullptr);
    ~DockModel() override;

    [[nodiscard]] TaskManager::TasksModel *tasksModel() const;
    [[nodiscard]] DockEntriesModel *dockEntriesModel() const;
    [[nodiscard]] DockPresentationModel *dockPresentationModel() const;
    [[nodiscard]] ApplicationCatalog *applicationCatalog() const;
    [[nodiscard]] ApplicationLauncherState *applicationLauncherState() const;
    [[nodiscard]] TrashState *trashState() const;
    [[nodiscard]] MediaPlayerController *mediaPlayerController() const;
    void setMediaPlayerEnabled(bool enabled);
    [[nodiscard]] int pinnedDockEntryCount() const;
    [[nodiscard]] bool taskDiagnosticsEnabled() const;
    [[nodiscard]] QString dockEntries() const;
    void loadDockEntries(const QString &serialized);
    [[nodiscard]] TaskManager::VirtualDesktopInfo *virtualDesktopInfo() const;
    [[nodiscard]] TaskManager::ActivityInfo *activityInfo() const;

    [[nodiscard]] QStringList pinnedLaunchers() const;
    void setPinnedLaunchers(const QStringList &launchers);

    /// Keep pinned applications (including their windows) before unpinned tasks.
    [[nodiscard]] bool separateLaunchers() const;
    void setSeparateLaunchers(bool separate);
    [[nodiscard]] int pinnedTaskCount() const;

    /// Move the task at @p fromIndex to @p toIndex as an explicit user
    /// reorder and save the new launcher order. Returns true on success.
    bool moveTask(int fromIndex, int toIndex);
    Q_INVOKABLE bool moveDockEntry(const QString &entryId, const QString &targetEntryId);

    /// Virtual desktop display mode: 0=ShowAll, 1=DimOtherDesktops, 2=CurrentOnly
    [[nodiscard]] int virtualDesktopMode() const;
    void setVirtualDesktopMode(int mode);

    [[nodiscard]] QVariant currentDesktop() const;

    /// Check if the task at @p index is on the current virtual desktop.
    /// Returns true for launchers, tasks on all desktops, and tasks on current desktop.
    Q_INVOKABLE bool isOnCurrentDesktop(int index) const;

    /// Return the theme name or opaque raw source key for the task icon at @p index.
    Q_INVOKABLE QString iconName(int index) const;
    /// Return the task decoration revision for per-row image URL invalidation.
    Q_INVOKABLE QString iconRevision(int index) const;

    /// Show KDE's installed icon chooser and store the result on this stack ID.
    Q_INVOKABLE bool chooseFolderStackThemeIcon(const QString &entryId, QObject *transientParent = nullptr);
    Q_INVOKABLE bool chooseBuiltInWidgetIcon(const QString &entryId, QObject *transientParent = nullptr);
    /// Show the platform file chooser and store a local image on this stack ID.
    Q_INVOKABLE bool chooseFolderStackImage(const QString &entryId);
    Q_INVOKABLE bool resetFolderStackIcon(const QString &entryId);

    /// Return the launcher URL for the task at @p index.
    Q_INVOKABLE QUrl launcherUrl(int index) const;

    /// Check whether the given URL refers to a .desktop file or applications: scheme.
    Q_INVOKABLE bool isDesktopFile(const QUrl &url) const;

    /// Check whether the URL points to an existing local directory.
    Q_INVOKABLE bool isLocalDirectory(const QUrl &url) const;

    /// Return true if the task at @p index is a pinned launcher.
    Q_INVOKABLE bool isPinned(int index) const;

    /// Return window IDs (UUIDs on Wayland) for the task at @p index.
    Q_INVOKABLE QVariantList windowIds(int index) const;

    /// Return the number of child windows for the task at @p index.
    Q_INVOKABLE int childCount(int index) const;

    /// Return a QModelIndex for use as DelegateModel.rootIndex.
    Q_INVOKABLE QModelIndex taskModelIndex(int index) const;

    /// Publish the delegate geometry for a window task to KWin.
    Q_INVOKABLE void publishDelegateGeometry(int index, QObject *delegate);
    Q_INVOKABLE void noteDockDelegateCreated();
    Q_INVOKABLE void noteDockDelegateDestroyed();

    /// Return the TaskManager/KService desktop-entry or executable identity for
    /// the task at @p index (not necessarily the raw Wayland app_id).
    Q_INVOKABLE QString appId(int index) const;

Q_SIGNALS:
    void dockEntriesChanged();
    void pinnedLaunchersChanged();
    void pinnedTaskCountChanged();
    void pinnedDockEntryCountChanged();
    void virtualDesktopModeChanged();
    void currentDesktopChanged();

private:
    /// Identity of a row in the last settled dock order. A pinned row is
    /// matched by launcher (its launcher or task row), any other row by a
    /// shared window ID, or by AppId when it has no window.
    struct SettledRow {
        QUrl launcherUrl;
        bool isLauncher = false;
        QStringList windowIds;
        QString appId;
    };

    /// A current row, resolved once per launcher-slot pass.
    struct CurrentRow {
        int launcherPosition = -1;
        bool isLauncher = false;
        QStringList windowIds;
        QString appId;
    };

    void scheduleTaskPartition();
    void reconcileTaskPartition();
    bool placeStartedTasksInLauncherSlots();
    [[nodiscard]] static int findRow(const QList<CurrentRow> &rows, const SettledRow &settled, int settledLauncherPosition, int excludedRow);
    void snapshotSettledRows();

    bool m_separateLaunchers = false;
    bool m_partitionPending = false;
    bool m_reconcilingPartition = false;
    int m_pinnedTaskCount = 0;
    int m_virtualDesktopMode = 0;
    QList<SettledRow> m_settledRows;
    std::unique_ptr<DockEntriesModel> m_dockEntriesModel;
    std::unique_ptr<ApplicationCatalog> m_applicationCatalog;
    std::unique_ptr<ApplicationLauncherState> m_applicationLauncherState;
    std::unique_ptr<TrashState> m_trashState;
    std::unique_ptr<MediaPlayerController> m_mediaPlayerController;
    bool m_mediaPlayerEnabled = true;
    std::unique_ptr<TaskManager::TasksModel> m_tasksModel;
    std::unique_ptr<DockPresentationModel> m_dockPresentationModel;
    std::shared_ptr<TaskManager::VirtualDesktopInfo> m_virtualDesktopInfo;
    std::shared_ptr<TaskManager::ActivityInfo> m_activityInfo;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    bool m_performanceDiagnosticsEnabled = false;
    QTimer *m_performanceReportTimer = nullptr;
    QElapsedTimer m_performanceClock;
    quint64 m_partitionRequests = 0;
    quint64 m_partitionCoalesced = 0;
    quint64 m_partitionRuns = 0;
    quint64 m_partitionNanos = 0;
    quint64 m_partitionMaxNanos = 0;
    quint64 m_taskSignals = 0;
    quint64 m_taskDataChangedRows = 0;
    quint64 m_taskDataChangedRanges = 0;
    QHash<QString, quint64> m_taskDataChangedRoleCounts;
    quint64 m_delegateCreated = 0;
    quint64 m_delegateDestroyed = 0;
    quint64 m_delegateLive = 0;
    quint64 m_iconRevisionChangesObserved = 0;
    QHash<QString, QString> m_lastObservedIconRevisions;
#endif
};

} // namespace kdockw
