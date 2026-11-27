// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of DockModel. Per-index lookups read roles from tasksModel so a test
// only has to populate one place: DockModel.tasksModel.addTask({ ... }).
// Mock-only roles: IconName, IsOnCurrentDesktop; IsLauncher backs isPinned().
pragma Singleton
import QtQuick
import kdockw.test

QtObject {
    readonly property MockMediaPlayerController mediaPlayerController: MockMediaPlayerController {}
    function noteDockDelegateCreated() { }
    function noteDockDelegateDestroyed() { }
    readonly property MockTasksModel tasksModel: MockTasksModel {
        mediaPlayerDisplayMode: DockSettings.mediaPlayerDisplayMode
    }
    readonly property var dockPresentationModel: tasksModel
    readonly property QtObject applicationCatalog: QtObject {
        signal catalogChanged()
        property bool ready: false
        property bool loading: false
        property int _loadGeneration: 0
        property var applications: []
        property var menuTree: []
        function ensureLoaded() {
            if (ready || loading) return
            loading = true
            const generation = ++_loadGeneration
            Qt.callLater(function() {
                if (generation !== _loadGeneration) return
                ready = true
                loading = false
                catalogChanged()
            })
        }
        function resetLoading() { ++_loadGeneration; ready = false; loading = false }
        function refresh() { ++_loadGeneration; ready = true; loading = false; catalogChanged() }
        function search(query) {
            const needle = String(query || "").trim().toLocaleLowerCase()
            if (!needle) return applications
            return applications.filter(app => `${app.name || ""} ${app.genericName || ""} ${app.comment || ""}`
                .toLocaleLowerCase().includes(needle))
        }
        function application(serviceId) {
            return applications.find(app => app.id === serviceId) || ({})
        }
        function launch(serviceId) { return false }
        function launchAction(serviceId, actionName) { return false }
    }
    // Mock of TrashState: tests set `empty` and read recorded calls.
    readonly property QtObject trashState: QtObject {
        property bool empty: true
        property var calls: []
        function _record(name, args) { calls = calls.concat([{ name: name, args: Array.from(args) }]) }
        function callsTo(name) { return calls.filter(c => c.name === name) }
        function open() { _record("open", arguments) }
        function moveToTrash(urls) { _record("moveToTrash", arguments) }
        function emptyTrash() { _record("emptyTrash", arguments) }
        function reset() { empty = true; calls = [] }
    }
    readonly property QtObject applicationLauncherState: QtObject {
        property string style: "launchpad"
        property var pinnedApplicationIds: []
        property var launchpadFolders: []
        property var launchpadItemOrder: []
        property bool startFavoritesImportAttempted: false
        property string startFavoritesImportStatus: "notAttempted"
        function isPinned(serviceId) { return pinnedApplicationIds.includes(serviceId) }
        function togglePinned(serviceId) {
            pinnedApplicationIds = isPinned(serviceId)
                ? pinnedApplicationIds.filter(id => id !== serviceId)
                : pinnedApplicationIds.concat([serviceId])
        }
        function movePinned(fromIndex, toIndex) { return false }
        function setLaunchpadItemOrder(ids) { launchpadItemOrder = ids.slice() }
        function createLaunchpadFolder(name, applicationIds, currentRootOrder) {
            const id = "folder:mock-" + (launchpadFolders.length + 1)
            const order = currentRootOrder.slice()
            let insertAt = order.length
            for (const appId of applicationIds) {
                const index = order.indexOf(appId)
                if (index >= 0) insertAt = Math.min(insertAt, index)
            }
            for (const folder of launchpadFolders)
                folder.applicationIds = folder.applicationIds.filter(appId => !applicationIds.includes(appId))
            for (const appId of applicationIds) {
                const index = order.indexOf(appId)
                if (index >= 0) order.splice(index, 1)
            }
            order.splice(insertAt, 0, id)
            launchpadItemOrder = order
            launchpadFolders = launchpadFolders.concat([{ id, type: "folder", name,
                applicationIds: applicationIds.slice() }])
            return id
        }
        function renameLaunchpadFolder(folderId, name) {
            const updated = launchpadFolders.map(folder => folder.id === folderId
                ? Object.assign({}, folder, { name }) : folder)
            launchpadFolders = updated
            return true
        }
        function addApplicationToLaunchpadFolder(folderId, applicationId) {
            launchpadFolders = launchpadFolders.map(folder => Object.assign({}, folder, {
                applicationIds: folder.id === folderId
                    ? Array.from(new Set(folder.applicationIds.concat([applicationId])))
                    : folder.applicationIds.filter(id => id !== applicationId)
            }))
            launchpadItemOrder = launchpadItemOrder.filter(id => id !== applicationId)
            return true
        }
        function removeApplicationFromLaunchpadFolder(folderId, applicationId) {
            const folder = launchpadFolders.find(item => item.id === folderId)
            if (!folder) return false
            launchpadFolders = launchpadFolders.map(item => item.id === folderId
                ? Object.assign({}, item, {
                    applicationIds: item.applicationIds.filter(id => id !== applicationId)
                }) : item)
            const index = launchpadItemOrder.indexOf(folderId)
            const order = launchpadItemOrder.slice()
            order.splice(index < 0 ? order.length : index + 1, 0, applicationId)
            launchpadItemOrder = order
            return true
        }
        function deleteLaunchpadFolder(folderId) {
            const folder = launchpadFolders.find(item => item.id === folderId)
            if (!folder) return false
            const index = launchpadItemOrder.indexOf(folderId)
            launchpadItemOrder.splice(index < 0 ? launchpadItemOrder.length : index, 1,
                ...folder.applicationIds)
            launchpadFolders = launchpadFolders.filter(item => item.id !== folderId)
            return true
        }
        function importPlasmaFavorites(favoriteIds, availableApplicationIds, sourceAvailable) {
            const retryLegacyPreservedPins = startFavoritesImportAttempted
                && startFavoritesImportStatus === "existingPinsPreserved"
                && pinnedApplicationIds.length > 0
            if (startFavoritesImportAttempted && !retryLegacyPreservedPins) return false
            if (!sourceAvailable) {
                startFavoritesImportStatus = "unavailable"
                return false
            }
            startFavoritesImportAttempted = true
            const valid = new Set(availableApplicationIds)
            const seen = new Set(pinnedApplicationIds)
            const imported = pinnedApplicationIds.slice()
            let added = 0
            for (let id of favoriteIds) {
                id = String(id).replace(/^applications:/, "")
                if (valid.has(id) && !seen.has(id)) {
                    seen.add(id)
                    imported.push(id)
                    added++
                }
            }
            if (added) pinnedApplicationIds = imported
            startFavoritesImportStatus = added
                ? retryLegacyPreservedPins ? "existingPinsPlusPlasmaFavorites" : "imported"
                : pinnedApplicationIds.length
                    ? retryLegacyPreservedPins ? "existingPinsChecked" : "existingPinsPreserved"
                    : favoriteIds.length ? "noMatchingApps" : "noFavorites"
            return added > 0
        }
    }
    readonly property var dockEntriesModel: ListModel {
        id: entries
        property int _nextWidgetId: 0
        readonly property bool hasApplicationLauncher: {
            for (let row = 0; row < count; ++row)
                if (get(row).widgetKind === "applicationLauncher") return true
            return false
        }
        readonly property bool hasTrash: {
            for (let row = 0; row < count; ++row)
                if (get(row).widgetKind === "trash") return true
            return false
        }
        function appendTrash(slot) {
            if (hasTrash) return ""
            const id = "widget:trash:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "trash",
                     placementSlot: slot || "end", widgetSize: 0, widgetVisible: true })
            return id
        }
        function entryIdAt(row) { return row >= 0 && row < count ? get(row).entryId : "" }
        function entryTypeAt(row) { return row >= 0 && row < count ? get(row).entryType : "" }
        function appendSeparator(slot) {
            const id = "widget:separator:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "separator",
                     placementSlot: slot || "center", widgetSize: 0, widgetVisible: true })
            return id
        }
        function appendSpacer(size, slot) {
            const id = "widget:spacer:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "spacer",
                     placementSlot: slot || "center", widgetSize: size, widgetVisible: true })
            return id
        }
        function appendApplicationLauncher(slot) {
            if (hasApplicationLauncher) return ""
            const id = "widget:application-launcher:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "applicationLauncher",
                     iconName: "start-here-kde", iconIsCustom: false,
                     placementSlot: slot || "center", widgetSize: 0, widgetVisible: true })
            return id
        }
        function setBuiltInWidgetIcon(entryId, iconName) {
            for (let row = 0; row < count; ++row) {
                if (get(row).entryId === entryId) {
                    setProperty(row, "iconName", iconName)
                    setProperty(row, "iconIsCustom", true)
                    return true
                }
            }
            return false
        }
        function removeBuiltInWidget(entryId) {
            for (let row = 0; row < count; ++row) {
                if (get(row).entryId === entryId && get(row).entryType === "builtInWidget") {
                    remove(row)
                    return true
                }
            }
            return false
        }
        function setBuiltInWidgetSize(entryId, size) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "widgetSize", size); return true }
            return false
        }
        function setBuiltInWidgetVisible(entryId, visible) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "widgetVisible", visible); return true }
            return false
        }
        function setBuiltInWidgetSlot(entryId, slot) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "placementSlot", slot); return true }
            return false
        }
        function moveEntry(from, to) { if (from < 0 || to < 0 || from >= count || to >= count) return false; move(from, to, 1); return true }
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
    function iconRevision(i) { const v = _role(i, "decoration"); return v === undefined ? "" : String(v) }
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
        trashState.reset()
        currentDesktop = 1
        virtualDesktopMode = 0
        pinnedTaskCount = 0
        folderThemeIconRequests = []
        resetDelegateGeometryRequests()
    }
}
