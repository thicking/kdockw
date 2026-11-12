// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

// Test doubles for the C++-backed QML modules KDockW's QML imports.
//
// Only types that cannot be expressed in plain QML live here:
//  - org.kde.taskmanager AbstractTasksModel (QML needs its role *enum*),
//  - a QAbstractItemModel standing in for DockModel.tasksModel
//    (Repeater model + index()/data()/makeModelIndex()),
//  - org.kde.pipewire PipeWireSourceItem (a QQuickItem),
//  - ZoomLayoutEngine: DockView.zoomLayout() on the production
//    kdockw::computeDockZoom, so the DockView mock lays out zoom exactly as
//    the app does.
// The com.thicking.kdockw singletons are plain QML files under mocks/.

#include <QQuickItem>
#include <QAbstractListModel>
#include <QRectF>
#include <QHash>
#include <QStandardItemModel>
#include <QUrl>
#include <QVariantMap>

namespace KDockWQmlTest
{

class MockFolderStackModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QUrl rootUrl READ rootUrl NOTIFY rootUrlChanged)
    Q_PROPERTY(QUrl currentUrl READ currentUrl NOTIFY currentUrlChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = {}) const override
    {
        Q_UNUSED(parent);
        return m_entries.size();
    }
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override
    {
        if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
            return {};
        const auto &entry = m_entries.at(index.row());
        switch (role) {
        case Qt::DisplayRole:
            return entry.display;
        case Qt::UserRole + 1:
            return entry.iconName;
        case Qt::UserRole + 2:
            return entry.isDirectory;
        default:
            return {};
        }
    }
    QHash<int, QByteArray> roleNames() const override
    {
        return {{Qt::DisplayRole, "display"},
                {Qt::UserRole + 1, "iconName"},
                {Qt::UserRole + 2, "isDirectory"}};
    }
    QUrl rootUrl() const { return m_rootUrl; }
    QUrl currentUrl() const { return m_currentUrl; }
    QString errorMessage() const { return {}; }
    bool loading() const { return false; }
    Q_INVOKABLE bool openFolder(const QUrl &url)
    {
        m_rootUrl = url;
        m_currentUrl = url;
        setRootEntries();
        Q_EMIT rootUrlChanged();
        Q_EMIT currentUrlChanged();
        return true;
    }
    Q_INVOKABLE bool openItem(int row)
    {
        if (row < 0 || row >= m_entries.size())
            return false;
        const auto entry = m_entries.at(row);
        if (entry.isDirectory) {
            m_currentUrl = QUrl::fromLocalFile(m_currentUrl.toLocalFile() + QLatin1Char('/') + entry.display);
            beginResetModel();
            m_entries = {{QStringLiteral("nested.txt"), QStringLiteral("text-plain"), false}};
            endResetModel();
            Q_EMIT currentUrlChanged();
        }
        return true;
    }
    Q_INVOKABLE void goUp()
    {
        if (m_currentUrl == m_rootUrl)
            return;
        m_currentUrl = m_rootUrl;
        setRootEntries();
        Q_EMIT currentUrlChanged();
    }
    Q_INVOKABLE void openCurrentFolder() {}
    Q_INVOKABLE void close() {}

Q_SIGNALS:
    void rootUrlChanged();
    void currentUrlChanged();
    void errorMessageChanged();
    void loadingChanged();

private:
    struct Entry {
        QString display;
        QString iconName;
        bool isDirectory = false;
    };
    void setRootEntries()
    {
        beginResetModel();
        m_entries = {{QStringLiteral("Nested"), QStringLiteral("folder"), true},
                     {QStringLiteral("readme.txt"), QStringLiteral("text-plain"), false}};
        endResetModel();
    }
    QUrl m_rootUrl;
    QUrl m_currentUrl;
    QList<Entry> m_entries;
};

// Mirrors the role names of TaskManager::AbstractTasksModel that KDockW's QML
// reads, plus a few mock-only roles (IconName, IsOnCurrentDesktop) that back
// the per-index DockModel lookups. Values are internal to the test double.
class MockAbstractTasksModel : public QObject
{
    Q_OBJECT
public:
    enum AdditionalRoles {
        AppId = Qt::UserRole + 1,
        IsWindow,
        IsGroupParent,
        IsStartup,
        IsLauncher,
        IsActive,
        IsMinimized,
        IsDemandingAttention,
        ChildCount,
        WinIdList,
        LauncherUrl,
        LauncherUrlWithoutIcon,
        IconName,
        IsOnCurrentDesktop,
        TaskIndex,
        EntryId,
        EntryType,
        EntryUrl,
        IsPinned,
    };
    Q_ENUM(AdditionalRoles)
};

// Stand-in for TaskManager::TasksModel as exposed via DockModel.tasksModel.
// Rows are populated from QML with role-name keyed maps, e.g.
//   tasksModel.addTask({ display: "Dolphin", IsWindow: true, ChildCount: 2 })
class MockTasksModel : public QStandardItemModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int activateRequests READ activateRequests NOTIFY requestsChanged)
    Q_PROPERTY(int closeRequests READ closeRequests NOTIFY requestsChanged)
    Q_PROPERTY(int lastRequestRow READ lastRequestRow NOTIFY requestsChanged)
    Q_PROPERTY(int lastRequestChild READ lastRequestChild NOTIFY requestsChanged)

public:
    explicit MockTasksModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;

    int count() const;
    int activateRequests() const;
    int closeRequests() const;
    int lastRequestRow() const;
    int lastRequestChild() const;

    Q_INVOKABLE int addTask(const QVariantMap &roles);
    Q_INVOKABLE int addChildTask(int parentRow, const QVariantMap &roles);
    Q_INVOKABLE void removeChildTask(int parentRow, int childRow);
    Q_INVOKABLE void setTaskData(int row, const QString &roleName, const QVariant &value);
    Q_INVOKABLE void setChildTaskData(int parentRow, int childRow, const QString &roleName, const QVariant &value);
    Q_INVOKABLE void removeTask(int row);
    Q_INVOKABLE void reset();
    Q_INVOKABLE int taskIndexForDockIndex(int dockIndex) const;
    Q_INVOKABLE int dockIndexForTaskIndex(int taskIndex) const;
    Q_INVOKABLE int dockIndexForEntryId(const QString &entryId) const;
    Q_INVOKABLE QString entryIdForDockIndex(int dockIndex) const;
    Q_INVOKABLE bool isPinnedDockIndex(int dockIndex) const;
    Q_INVOKABLE bool moveByEntryId(const QString &entryId, const QString &targetEntryId);
    // Role lookup by name, used by the QML DockModel mock.
    Q_INVOKABLE QVariant get(int row, const QString &roleName) const;

    // TaskManager::TasksModel API used by KDockW's QML.
    Q_INVOKABLE QModelIndex makeModelIndex(int row, int childRow = -1) const;
    Q_INVOKABLE void requestActivate(const QModelIndex &index);
    Q_INVOKABLE void requestClose(const QModelIndex &index);

Q_SIGNALS:
    void countChanged();
    void requestsChanged();

private:
    int roleForName(const QString &name) const;
    void applyRoles(QStandardItem *item, const QVariantMap &roles) const;
    void recordRequest(const QModelIndex &index);

    QHash<int, QByteArray> m_roleNames;
    int m_activateRequests = 0;
    int m_closeRequests = 0;
    int m_lastRequestRow = -1;
    int m_lastRequestChild = -1;
};

class MockScreencastingRequest : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString uuid READ uuid WRITE setUuid NOTIFY uuidChanged)
    Q_PROPERTY(quint32 nodeId READ nodeId NOTIFY nodeIdChanged)
public:
    using QObject::QObject;
    QString uuid() const
    {
        return m_uuid;
    }
    void setUuid(const QString &uuid);
    quint32 nodeId() const
    {
        return 0;
    }
Q_SIGNALS:
    void uuidChanged();
    void nodeIdChanged();

private:
    QString m_uuid;
};

class MockPipeWireSourceItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(quint32 nodeId MEMBER m_nodeId NOTIFY nodeIdChanged)
    Q_PROPERTY(bool allowDmaBuf MEMBER m_allowDmaBuf NOTIFY allowDmaBufChanged)
    Q_PROPERTY(bool ready MEMBER m_ready NOTIFY readyChanged)
    Q_PROPERTY(int state READ state WRITE setState NOTIFY stateChanged)
    Q_PROPERTY(QSize streamSize MEMBER m_streamSize NOTIFY streamSizeChanged)
    Q_PROPERTY(bool usingDmaBuf READ usingDmaBuf NOTIFY usingDmaBufChanged)
public:
    explicit MockPipeWireSourceItem(QQuickItem *parent = nullptr);
    ~MockPipeWireSourceItem() override;
    bool ready() const { return m_ready; }
    int state() const { return m_state; }
    void setState(int state)
    {
        if (m_state == state) {
            return;
        }
        m_state = state;
        Q_EMIT stateChanged();
    }
    QSize streamSize() const
    {
        return m_streamSize;
    }
    bool usingDmaBuf() const
    {
        return m_allowDmaBuf;
    }
    Q_INVOKABLE QString error() const
    {
        return {};
    }
Q_SIGNALS:
    void nodeIdChanged();
    void allowDmaBufChanged();
    void readyChanged();
    void stateChanged();
    void streamSizeChanged();
    void usingDmaBufChanged();

private:
    quint32 m_nodeId = 0;
    bool m_allowDmaBuf = false;
    bool m_ready = false;
    int m_state = 0;
    QSize m_streamSize;
};

class MockClippedPipeWireSourceItem : public MockPipeWireSourceItem
{
    Q_OBJECT
    Q_PROPERTY(QString clipMode READ clipMode WRITE setClipMode NOTIFY clipModeChanged)
    Q_PROPERTY(QRectF clipViewportRect READ clipViewportRect WRITE setClipViewportRect NOTIFY clipViewportRectChanged)
    Q_PROPERTY(qreal clipRadius READ clipRadius WRITE setClipRadius NOTIFY clipRadiusChanged)
    Q_PROPERTY(bool freezeFrame MEMBER m_freezeFrame NOTIFY freezeFrameChanged)
public:
    using MockPipeWireSourceItem::MockPipeWireSourceItem;
    QString clipMode() const { return m_clipMode; }
    void setClipMode(const QString &mode) { if (m_clipMode != mode) { m_clipMode = mode; Q_EMIT clipModeChanged(); } }
    QRectF clipViewportRect() const { return m_clipViewportRect; }
    void setClipViewportRect(const QRectF &rect) { if (m_clipViewportRect != rect) { m_clipViewportRect = rect; Q_EMIT clipViewportRectChanged(); } }
    qreal clipRadius() const { return m_clipRadius; }
    void setClipRadius(qreal radius) { if (!qFuzzyCompare(m_clipRadius + 1, radius + 1)) { m_clipRadius = radius; Q_EMIT clipRadiusChanged(); } }
Q_SIGNALS:
    void clipModeChanged();
    void clipViewportRectChanged();
    void clipRadiusChanged();
    void freezeFrameChanged();
private:
    QString m_clipMode;
    QRectF m_clipViewportRect;
    qreal m_clipRadius = 0;
    bool m_freezeFrame = false;
};

class MockPipeWireTracker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int activeCount READ activeCount NOTIFY activeCountChanged)
public:
    using QObject::QObject;
    static MockPipeWireTracker *instance();
    int activeCount() const { return m_activeCount; }
    void sourceCreated();
    void sourceDestroyed();
Q_SIGNALS:
    void activeCountChanged();
private:
    int m_activeCount = 0;
};

// Production DockView::zoomLayout() without the window: same arguments, same
// result map (scales, offsets, leadingGrowth, trailingGrowth).
class ZoomLayoutEngine : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QVariantMap zoomLayout(int count,
                                       qreal restStart,
                                       qreal iconSize,
                                       qreal spacing,
                                       int boundary,
                                       qreal boundaryGap,
                                       qreal restBackgroundStart,
                                       qreal restBackgroundEnd,
                                       qreal maxZoomFactor,
                                       int style,
                                       bool active,
                                       qreal cursor,
                                       qreal minEdge,
                                       qreal maxEdge) const;
};

void registerMockTypes();

} // namespace KDockWQmlTest
