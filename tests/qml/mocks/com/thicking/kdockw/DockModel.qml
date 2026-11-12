// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of DockModel. Per-index lookups read roles from tasksModel so a test
// only has to populate one place: DockModel.tasksModel.addTask({ ... }).
// Mock-only roles: IconName, IsOnCurrentDesktop; IsLauncher backs isPinned().
pragma Singleton
import QtQuick
import kdockw.test

QtObject {
    readonly property MockTasksModel tasksModel: MockTasksModel {}
    readonly property var dockPresentationModel: tasksModel
    readonly property var dockEntriesModel: ListModel {
        id: entries
        function removeFolderStack(entryId) {
            for (let row = 0; row < count; ++row) {
                if (get(row).entryId === entryId) {
                    remove(row)
                    return true
                }
            }
            return false
        }
    }
    property int currentDesktop: 1
    // 0=ShowAll, 1=DimOtherDesktops, 2=CurrentOnly
    property int virtualDesktopMode: 0
    // Fixtures supply prepartitioned task rows and their pinned boundary;
    // production DockModel's sorting is exercised by the model/native suites.
    property int pinnedTaskCount: 0
    readonly property int pinnedDockEntryCount: pinnedTaskCount + entries.count
    property var delegateGeometryRequests: []
    property var folderThemeIconRequests: []

    function _role(i, name) { return tasksModel.get(i, name) }
    function isPinned(i) { return !!_role(i, "IsLauncher") }
    function appId(i) { return _role(i, "AppId") || "" }
    function iconName(i) { return _role(i, "IconName") || "" }
    function launcherUrl(i) { return _role(i, "LauncherUrl") || "" }
    function isOnCurrentDesktop(i) { let v = _role(i, "IsOnCurrentDesktop"); return v === undefined ? true : !!v }
    function childCount(i) { return tasksModel.rowCount(tasksModel.index(i, 0)) }
    function isDesktopFile(url) { return url.toString().endsWith(".desktop") }
    function isLocalDirectory(url) { return url.toString() === "file:///tmp" || url.toString().endsWith("/") }
    function moveDockEntry(fromId, toId) { return tasksModel.moveByEntryId(fromId, toId) }
    function chooseFolderStackThemeIcon(entryId, transientParent) {
        folderThemeIconRequests = folderThemeIconRequests.concat([{
            entryId: entryId,
            hasTransientParent: !!transientParent,
        }])
        return true
    }

    function publishDelegateGeometry(i, delegate) {
        delegateGeometryRequests = delegateGeometryRequests.concat([{
            index: i,
            isWindow: !!_role(i, "IsWindow"),
            isGroupParent: !!_role(i, "IsGroupParent"),
            childCount: _role(i, "ChildCount") || 0,
            geometry: {
                x: delegate.x,
                y: delegate.y,
                width: delegate.width,
                height: delegate.height,
            },
        }])
    }

    function resetDelegateGeometryRequests() {
        delegateGeometryRequests = []
    }

    function reset() {
        tasksModel.reset()
        entries.clear()
        currentDesktop = 1
        virtualDesktopMode = 0
        pinnedTaskCount = 0
        folderThemeIconRequests = []
        resetDelegateGeometryRequests()
    }
}
