// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Selected-monitor placement regression (issue #18).
//
// This test deliberately writes MonitorMode=3 and SelectedOutputs through the
// generic KConfig API instead of referring to the new generated settings
// accessors or enum names.  It therefore compiles against the frozen baseline
// too, where the observable failure is an incorrect dock subset rather than a
// missing symbol.
//
// Must run under run-with-kwin.sh with KDOCKW_TEST_OUTPUT_COUNT=3.

#include "app/application.h"
#include "kdockw.h"
#include "models/dockmodel.h"
#include "models/launcherentrytracker.h"
#include "models/notificationtracker.h"
#include "outputordermonitortestaccess.h"
#include "shell/dockshell.h"
#include "shell/dockview.h"
#include "shell/multidockmanager.h"
#include "shell/outputordermonitor.h"
#include "../dockqmltypes.h"

#include <catch2/catch_session.hpp>
#include <catch2/catch_test_macros.hpp>

#include <KAboutData>
#include <KConfigGroup>
#include <KSharedConfig>
#include <LayerShellQt/Window>

#include <QApplication>
#include <QCursor>
#include <QPointer>
#include <QProcess>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QScreen>
#include <QSet>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTimer>
#include <QTest>
#include <QtQml>

#include <memory>

// Static library resources must be initialized from the global namespace.
static void initResources()
{
    Q_INIT_RESOURCE(qml);
}

namespace
{

constexpr int kTimeoutMs = 15000;

struct App {
    std::unique_ptr<KDockWSettings> settings;
    std::unique_ptr<kdockw::DockModel> model;
    std::unique_ptr<kdockw::NotificationTracker> tracker;
    std::unique_ptr<kdockw::LauncherEntryTracker> launcherEntries;
};

App &app()
{
    static App *instance = [] {
        auto *a = new App;
        a->settings = std::make_unique<KDockWSettings>();
        a->settings->load();
        a->model = std::make_unique<kdockw::DockModel>();
        a->model->setPinnedLaunchers(a->settings->pinnedLaunchers());
        a->tracker = std::make_unique<kdockw::NotificationTracker>();
        a->launcherEntries = std::make_unique<kdockw::LauncherEntryTracker>();

        auto *model = a->model.get();
        qmlRegisterSingletonType<kdockw::DockModel>("com.thicking.kdockw", 1, 0, "DockModel", [model](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(model, QQmlEngine::CppOwnership);
            return model;
        });
        auto *settings = a->settings.get();
        qmlRegisterSingletonType<KDockWSettings>("com.thicking.kdockw", 1, 0, "DockSettings", [settings](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(settings, QQmlEngine::CppOwnership);
            return settings;
        });
        auto *tracker = a->tracker.get();
        qmlRegisterSingletonType<kdockw::NotificationTracker>("com.thicking.kdockw", 1, 0, "NotificationTracker", [tracker](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(tracker, QQmlEngine::CppOwnership);
            return tracker;
        });
        auto *launcherEntries = a->launcherEntries.get();
        qmlRegisterSingletonType<kdockw::LauncherEntryTracker>("com.thicking.kdockw",
                                                              1,
                                                              0,
                                                              "LauncherEntryTracker",
                                                              [launcherEntries](QQmlEngine *, QJSEngine *) -> QObject * {
                                                                  QQmlEngine::setObjectOwnership(launcherEntries, QQmlEngine::CppOwnership);
                                                                  return launcherEntries;
                                                              });
        registerDockQmlTypes();
        return a;
    }();
    return *instance;
}

QStringList screenNames()
{
    QStringList names;
    for (auto *screen : QGuiApplication::screens()) {
        names.append(screen->name());
    }
    return names;
}

bool waitForStableScreenTopology()
{
    // KWin publishes the new primary and QtWayland updates screen geometry in
    // separate asynchronous events. MultiDockManager debounces those changes
    // for 300 ms; wait for a 350 ms quiet period before taking a saved-output
    // snapshot so an earlier output transaction cannot rewrite the fixture
    // after its first exposure check.
    QTimer quiet;
    quiet.setSingleShot(true);
    quiet.setInterval(350);
    const auto markDirty = [&quiet] {
        quiet.start();
    };
    const auto watchScreen = [&quiet, &markDirty](QScreen *screen) {
        QObject::connect(screen, &QScreen::geometryChanged, &quiet, markDirty);
        QObject::connect(screen, &QScreen::availableGeometryChanged, &quiet, markDirty);
        QObject::connect(screen, &QScreen::virtualGeometryChanged, &quiet, markDirty);
    };
    for (auto *screen : QGuiApplication::screens()) {
        watchScreen(screen);
    }
    QObject::connect(qApp, &QGuiApplication::screenAdded, &quiet, [&](QScreen *screen) {
        watchScreen(screen);
        markDirty();
    });
    QObject::connect(qApp, &QGuiApplication::screenRemoved, &quiet, markDirty);
    auto *order = kdockw::OutputOrderMonitor::instance();
    QObject::connect(order, &kdockw::OutputOrderMonitor::primaryOutputChanged, &quiet, markDirty);
    QObject::connect(order, &kdockw::OutputOrderMonitor::orderReadyChanged, &quiet, markDirty);

    QSignalSpy settled(&quiet, &QTimer::timeout);
    quiet.start();
    return settled.wait(3000);
}

void writeSelectedMonitorConfig(const QStringList &selectedOutputs)
{
    const auto config = KSharedConfig::openConfig(QStringLiteral("kdockwrc"));
    auto general = config->group(QStringLiteral("General"));
    general.writeEntry(QStringLiteral("MonitorMode"), 3);
    general.writeEntry(QStringLiteral("SelectedOutputs"), selectedOutputs);
    config->sync();
}

QSet<QString> dockedScreenNames(const kdockw::MultiDockManager &manager)
{
    QSet<QString> names;
    for (auto *shell : manager.shells()) {
        if (!shell || !shell->view()) {
            continue;
        }
        auto *view = shell->view();
        auto *layer = LayerShellQt::Window::get(view);
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
        if (layer && layer->screenConfiguration() == LayerShellQt::Window::ScreenFromQWindow && view->screen()) {
            names.insert(view->screen()->name());
        }
#else
        if (layer && layer->screen()) {
            names.insert(layer->screen()->name());
        }
#endif
    }
    return names;
}

QScreen *screenNamed(const QString &name)
{
    for (auto *screen : QGuiApplication::screens()) {
        if (screen->name() == name) {
            return screen;
        }
    }
    return nullptr;
}

kdockw::DockShell *shellNamed(const kdockw::MultiDockManager &manager, const QString &name)
{
    for (auto *shell : manager.shells()) {
        if (shell->view()->dockScreen() && shell->view()->dockScreen()->name() == name) {
            return shell;
        }
    }
    return nullptr;
}

std::unique_ptr<kdockw::MultiDockManager> makeSelectedManager(const QStringList &selected)
{
    REQUIRE(waitForStableScreenTopology());
    auto *order = kdockw::OutputOrderMonitor::instance();
    REQUIRE(QTest::qWaitFor(
        [order] {
            return order->orderReady();
        },
        kTimeoutMs));
    writeSelectedMonitorConfig(selected);
    auto &a = app();
    a.settings->load();
    auto manager = std::make_unique<kdockw::MultiDockManager>(a.settings.get(), a.model.get(), a.tracker.get());
    kdockw::Application::connectSettingsAutoSave(a.settings.get(), manager.get());
    manager->initialize();
    return manager;
}

void requireDocksOn(const kdockw::MultiDockManager &manager, const QStringList &names)
{
    const QSet<QString> expected(names.cbegin(), names.cend());
    const bool ready = QTest::qWaitFor(
        [&] {
            const auto shells = manager.shells();
            if (shells.size() != expected.size() || dockedScreenNames(manager) != expected) {
                return false;
            }
            return std::all_of(shells.cbegin(), shells.cend(), [](kdockw::DockShell *shell) {
                return shell && shell->view() && shell->view()->dockScreen() && shell->view()->isExposed();
            });
        },
        kTimeoutMs);
    if (!ready) {
        qWarning() << "Selected-output fixture did not settle. Expected:" << names << "screens:" << screenNames() << "docks:"
                   << manager.shells().size() << dockedScreenNames(manager);
        for (auto *shell : manager.shells()) {
            auto *view = shell ? shell->view() : nullptr;
            auto *layer = view ? LayerShellQt::Window::get(view) : nullptr;
            QString layerName = QStringLiteral("<no layer screen>");
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
            if (layer && layer->screenConfiguration() == LayerShellQt::Window::ScreenFromQWindow && view && view->screen()) {
                layerName = view->screen()->name();
            }
#else
            if (layer && layer->screen()) {
                layerName = layer->screen()->name();
            }
#endif
            qWarning() << "dock state: assigned=" << (view && view->dockScreen() ? view->dockScreen()->name() : QStringLiteral("<no screen>"))
                       << "QWindow=" << (view && view->screen() ? view->screen()->name() : QStringLiteral("<no screen>"))
                       << "exposed:" << (view && view->isExposed()) << "visible:" << (view && view->isVisible())
                       << "layer screen:" << layerName;
        }
    }
    REQUIRE(ready);
    for (auto *shell : manager.shells()) {
        REQUIRE(shell->view()->dockScreen());
        CHECK(shell->view()->isVisible());
        auto *layer = LayerShellQt::Window::get(shell->view());
        REQUIRE(layer);
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
        CHECK(layer->screenConfiguration() == LayerShellQt::Window::ScreenFromQWindow);
#else
        CHECK(layer->screen() == shell->view()->dockScreen());
#endif
        INFO("output " << shell->view()->dockScreen()->name().toStdString() << " screen geometry "
                       << shell->view()->dockScreen()->geometry().x() << "," << shell->view()->dockScreen()->geometry().y() << " "
                       << shell->view()->dockScreen()->geometry().width() << "x" << shell->view()->dockScreen()->geometry().height()
                       << " window geometry " << shell->view()->geometry().x() << "," << shell->view()->geometry().y() << " "
                       << shell->view()->geometry().width() << "x" << shell->view()->geometry().height());
    }
}

QStringList savedSelection()
{
    return KSharedConfig::openConfig(QStringLiteral("kdockwrc"))->group(QStringLiteral("General")).readEntry(QStringLiteral("SelectedOutputs"), QStringList());
}

bool runKscreenDoctor(const QStringList &args)
{
    const auto tool = QStandardPaths::findExecutable(QStringLiteral("kscreen-doctor"));
    if (tool.isEmpty()) {
        return false;
    }
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"));
    QProcess process;
    process.setProcessEnvironment(env);
    process.start(tool, args);
    // Keep Qt GUI event dispatch alive while the compositor command runs.
    if (!QTest::qWaitFor(
            [&] {
                return process.state() == QProcess::NotRunning;
            },
            kTimeoutMs)
        || process.error() == QProcess::FailedToStart) {
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        qWarning("kscreen-doctor %s failed: %s",
                 qUtf8Printable(args.join(QLatin1Char(' '))),
                 qUtf8Printable(QString::fromUtf8(process.readAllStandardError())));
        return false;
    }
    return true;
}

bool makePrimary(const QString &name)
{
    // A lone priority.1 command can normalize the existing ranks without
    // changing the primary when another output already has rank 0. Demote
    // the current incumbent and promote an alternate in one compositor
    // transaction first, then promote the requested output.
    auto *order = kdockw::OutputOrderMonitor::instance();
    auto *currentPrimary = order->primaryScreen();
    if (!currentPrimary) {
        return false;
    }
    const QStringList names = screenNames();
    if (names.size() < 2) {
        return false;
    }
    const QString incumbent = currentPrimary->name();
    QString other;
    for (const auto &candidate : names) {
        if (candidate != name) {
            other = candidate;
            break;
        }
    }
    if (other.isEmpty()) {
        return false;
    }

    QStringList transition;
    if (incumbent == other) {
        transition = {QStringLiteral("output.%1.priority.1").arg(other)};
    } else {
        transition = {
            QStringLiteral("output.%1.priority.%2").arg(incumbent).arg(names.size()),
            QStringLiteral("output.%1.priority.1").arg(other),
        };
    }
    if (!runKscreenDoctor(transition)) {
        return false;
    }
    // Process exit does not mean this client has adopted the new primary.
    if (!QTest::qWaitFor(
            [&] {
                return order->primaryScreen() && order->primaryScreen()->name() == other;
            },
            kTimeoutMs)) {
        return false;
    }
    if (!runKscreenDoctor({QStringLiteral("output.%1.priority.1").arg(name)})) {
        return false;
    }
    return QTest::qWaitFor(
        [&] {
            return order->primaryScreen() && order->primaryScreen()->name() == name;
        },
        kTimeoutMs);
}

void requirePrimary(const QString &name)
{
    auto *order = kdockw::OutputOrderMonitor::instance();
    // A primary signal needs a real transition. Complete a different primary
    // first when the requested output is already current.
    if (order->primaryScreen() && order->primaryScreen()->name() == name) {
        for (const auto &other : screenNames()) {
            if (other != name) {
                requirePrimary(other);
                break;
            }
        }
    }
    QSignalSpy changed(order, &kdockw::OutputOrderMonitor::primaryOutputChanged);
    REQUIRE(makePrimary(name));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return !changed.isEmpty() && order->primaryScreen() && order->primaryScreen()->name() == name;
        },
        kTimeoutMs));
}

QSet<QString> surfaceOutputNames(const char *scope)
{
    QSet<QString> result;
    for (auto *window : QGuiApplication::topLevelWindows()) {
        auto *layer = LayerShellQt::Window::get(window);
        if (!layer || layer->scope() != QLatin1String(scope)) {
            continue;
        }
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
        if (layer->screenConfiguration() == LayerShellQt::Window::ScreenFromQWindow && window->screen()) {
            result.insert(window->screen()->name());
        }
#else
        if (layer->screen()) {
            result.insert(layer->screen()->name());
        }
#endif
    }
    return result;
}

void requireRetained(const QPointer<kdockw::DockShell> &shell, const QString &name)
{
    REQUIRE(shell);
    REQUIRE(shell->view()->dockScreen());
    CHECK(shell->view()->dockScreen()->name() == name);
}

} // namespace

TEST_CASE("Selected monitors create docks only on the saved outputs", "[selected-output]")
{
    REQUIRE(QGuiApplication::screens().size() == 3);

    auto *outputOrder = kdockw::OutputOrderMonitor::instance();
    REQUIRE(QTest::qWaitFor(
        [outputOrder] {
            return outputOrder->orderReady();
        },
        kTimeoutMs));
    auto *primary = outputOrder->primaryScreen();
    REQUIRE(primary);

    const QStringList allOutputs = screenNames();
    REQUIRE(allOutputs.size() == 3);

    // Deliberately exclude the Plasma primary: the selected mode must honor
    // the saved subset rather than implicitly adding the primary output.
    QStringList selectedOutputs;
    for (const auto &name : allOutputs) {
        if (name != primary->name()) {
            selectedOutputs.append(name);
        }
    }
    REQUIRE(selectedOutputs.size() == 2);

    // This is the compatibility seam: the test compiles on the unfixed
    // branch, while its shell-subset assertion fails there (mode 3 is not
    // implemented and falls through to the old mode behavior).
    writeSelectedMonitorConfig(selectedOutputs);

    auto &a = app();
    a.settings->load();
    auto manager = std::make_unique<kdockw::MultiDockManager>(a.settings.get(), a.model.get(), a.tracker.get());
    manager->initialize();

    REQUIRE(QTest::qWaitFor(
        [&] {
            return manager->shells().size() == selectedOutputs.size();
        },
        kTimeoutMs));

    const QSet<QString> expected(selectedOutputs.cbegin(), selectedOutputs.cend());
    REQUIRE(QTest::qWaitFor(
        [&] {
            return dockedScreenNames(*manager) == expected;
        },
        kTimeoutMs));

    for (auto *shell : manager->shells()) {
        REQUIRE(shell);
        auto *view = shell->view();
        REQUIRE(view);
        REQUIRE(QTest::qWaitFor(
            [&] {
                return view->isExposed();
            },
            kTimeoutMs));
        QQuickView *previewView = nullptr;
        REQUIRE(QTest::qWaitFor(
            [&] {
                for (auto *window : QGuiApplication::topLevelWindows()) {
                    auto *quickView = qobject_cast<QQuickView *>(window);
                    auto *layer = LayerShellQt::Window::get(window);
                    if (quickView && layer && layer->scope() == QLatin1String("tooltip") && quickView->engine() == view->engine()) {
                        previewView = quickView;
                        return previewView->isExposed();
                    }
                }
                return false;
            },
            kTimeoutMs));
        REQUIRE(previewView);
        REQUIRE(previewView->screen());
        auto *layer = LayerShellQt::Window::get(previewView);
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
        CHECK(layer->screenConfiguration() == LayerShellQt::Window::ScreenFromQWindow);
#else
        CHECK(layer->screen() == view->dockScreen());
#endif
        REQUIRE(view->dockScreen());
        CHECK(expected.contains(view->dockScreen()->name()));
        CHECK(view->isVisible());
    }
}

TEST_CASE(
    "Unavailable selected monitors use one temporary primary dock "
    "without changing the saved selection",
    "[selected-output][fallback]")
{
    REQUIRE(QGuiApplication::screens().size() == 3);
    QStringList selected;
    SECTION("empty selection")
    {
        selected = {};
    }
    SECTION("only disconnected names")
    {
        selected = {QStringLiteral("missing-HDMI-A-9"), QStringLiteral("missing-DP-8")};
    }

    auto manager = makeSelectedManager(selected);
    auto *order = kdockw::OutputOrderMonitor::instance();
    const auto originalPrimary = order->primaryScreen()->name();
    const auto restorePrimary = qScopeGuard([&] {
        makePrimary(originalPrimary);
    });
    requireDocksOn(*manager, {originalPrimary});
    CHECK(savedSelection() == selected);

    const auto names = screenNames();
    const auto newPrimary = names.first() == originalPrimary ? names.last() : names.first();
    requirePrimary(newPrimary);
    requireDocksOn(*manager, {newPrimary});
    CHECK(savedSelection() == selected);
}

TEST_CASE(
    "Removing and returning the last selected output replaces only the "
    "temporary fallback",
    "[selected-output][hotplug]")
{
    REQUIRE(QGuiApplication::screens().size() == 3);
    auto *order = kdockw::OutputOrderMonitor::instance();
    REQUIRE(QTest::qWaitFor(
        [order] {
            return order->orderReady();
        },
        kTimeoutMs));
    const auto originalPrimary = order->primaryScreen()->name();
    const auto names = screenNames();
    const auto selected = names.first() == originalPrimary ? names.last() : names.first();
    auto manager = makeSelectedManager({selected});
    requireDocksOn(*manager, {selected});
    QPointer<kdockw::DockShell> removed = manager->shells().first();
    const auto restoreOutput = qScopeGuard([&] {
        runKscreenDoctor({QStringLiteral("output.%1.enable").arg(selected)});
        makePrimary(originalPrimary);
    });

    REQUIRE(runKscreenDoctor({QStringLiteral("output.%1.disable").arg(selected)}));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return screenNamed(selected) == nullptr;
        },
        kTimeoutMs));
    REQUIRE(QTest::qWaitFor(
        [&] {
            auto *primary = order->primaryScreen();
            return primary && manager->shells().size() == 1 && dockedScreenNames(*manager) == QSet<QString>{primary->name()};
        },
        kTimeoutMs));
    CHECK_FALSE(removed);
    CHECK(savedSelection() == QStringList{selected});
    QPointer<kdockw::DockShell> fallback = manager->shells().first();

    REQUIRE(runKscreenDoctor({QStringLiteral("output.%1.enable").arg(selected)}));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return screenNamed(selected) != nullptr;
        },
        kTimeoutMs));
    requireDocksOn(*manager, {selected});
    CHECK_FALSE(fallback);
    CHECK(savedSelection() == QStringList{selected});
}

TEST_CASE(
    "Primary changes and unselected hotplug retain selected dock and "
    "preview surfaces",
    "[selected-output][identity]")
{
    REQUIRE(QGuiApplication::screens().size() == 3);
    auto *order = kdockw::OutputOrderMonitor::instance();
    REQUIRE(QTest::qWaitFor(
        [order] {
            return order->orderReady();
        },
        kTimeoutMs));
    const auto originalPrimary = order->primaryScreen()->name();
    QStringList selected = screenNames();
    selected.removeAll(originalPrimary);
    REQUIRE(selected.size() == 2);
    auto manager = makeSelectedManager(selected);
    requireDocksOn(*manager, selected);
    QPointer<kdockw::DockShell> first = shellNamed(*manager, selected.first());
    QPointer<kdockw::DockShell> second = shellNamed(*manager, selected.last());
    REQUIRE(first);
    REQUIRE(second);
    QSignalSpy firstDestroyed(first, &QObject::destroyed);
    QSignalSpy secondDestroyed(second, &QObject::destroyed);
    const auto restoreOutput = qScopeGuard([&] {
        runKscreenDoctor({QStringLiteral("output.%1.enable").arg(originalPrimary)});
        makePrimary(originalPrimary);
    });

    requirePrimary(selected.first());
    // A bounded destroyed-signal observation includes the topology debounce.
    // No fixed sleep or source-level implementation assertion is required.
    CHECK_FALSE(firstDestroyed.wait(1000));
    CHECK_FALSE(secondDestroyed.wait(1000));
    requireRetained(first, selected.first());
    requireRetained(second, selected.last());
    requireDocksOn(*manager, selected);

    REQUIRE(runKscreenDoctor({QStringLiteral("output.%1.disable").arg(originalPrimary)}));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return screenNamed(originalPrimary) == nullptr;
        },
        kTimeoutMs));
    CHECK_FALSE(firstDestroyed.wait(1000));
    CHECK_FALSE(secondDestroyed.wait(1000));
    requireRetained(first, selected.first());
    requireRetained(second, selected.last());

    REQUIRE(runKscreenDoctor({QStringLiteral("output.%1.enable").arg(originalPrimary)}));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return screenNamed(originalPrimary) != nullptr;
        },
        kTimeoutMs));
    CHECK_FALSE(firstDestroyed.wait(1000));
    CHECK_FALSE(secondDestroyed.wait(1000));
    requireDocksOn(*manager, selected);
    requireRetained(first, selected.first());
    requireRetained(second, selected.last());

    const QSet<QString> expected(selected.cbegin(), selected.cend());
    CHECK(surfaceOutputNames("dock") == expected);
    CHECK(surfaceOutputNames("tooltip") == expected);
}

TEST_CASE(
    "Selected-mode shortcuts resolve through primary adopted order and "
    "saved selection order",
    "[selected-output][shortcuts]")
{
    REQUIRE(QGuiApplication::screens().size() == 3);
    auto *order = kdockw::OutputOrderMonitor::instance();
    REQUIRE(QTest::qWaitFor(
        [order] {
            return order->orderReady();
        },
        kTimeoutMs));
    auto *unselected = QGuiApplication::primaryScreen();
    REQUIRE(unselected);
    // Finish a real compositor transaction before injecting completed orders,
    // so late priority replies from an earlier test cannot overwrite the seam.
    requirePrimary(unselected->name());
    REQUIRE(waitForStableScreenTopology());
    const auto originalOrder = order->outputOrder();
    const auto restoreOrder = qScopeGuard([&] {
        kdockw::OutputOrderMonitorTestAccess::deliverOrder(order, originalOrder);
    });
    QStringList selected = screenNames();
    selected.removeAll(unselected->name());
    REQUIRE(selected.size() == 2);
    selected.swapItemsAt(0, 1);
    auto manager = makeSelectedManager(selected);
    requireDocksOn(*manager, selected);
    INFO("requested selected order: " << selected.join(QLatin1Char(',')).toStdString() << "; current screens: "
                                        << screenNames().join(QLatin1Char(',')).toStdString());
    QStringList managerScreens;
    for (auto *shell : manager->shells()) {
        managerScreens.append(shell && shell->view() && shell->view()->dockScreen() ? shell->view()->dockScreen()->name() : QStringLiteral("<none>"));
    }
    INFO("manager shell screens: " << managerScreens.join(QLatin1Char(',')).toStdString());
    auto *first = shellNamed(*manager, selected.first());
    auto *second = shellNamed(*manager, selected.last());
    REQUIRE(first);
    REQUIRE(second);

    // A selected primary wins even when the saved selection puts it last.
    kdockw::OutputOrderMonitorTestAccess::deliverOrder(order, {selected.last(), unselected->name(), selected.first()});
    CHECK(manager->primaryShell() == second);
    CHECK(manager->activeShell() == second);

    // With an unselected primary, use the first live selected output in the
    // compositor's adopted order, not unordered-map iteration or saved order.
    kdockw::OutputOrderMonitorTestAccess::deliverOrder(order, {unselected->name(), selected.last(), selected.first()});
    CHECK(manager->primaryShell() == second);
    CHECK(manager->activeShell() == second);

    // An incomplete (pending) list must not change the shortcut target.
    kdockw::OutputOrderMonitorTestAccess::deliverOrder(order, {QStringLiteral("not-yet-connected"), selected.first(), selected.last()});
    CHECK(manager->activeShell() == second);

    // No adopted order: the Qt primary is unselected, so saved-name order wins.
    kdockw::OutputOrderMonitorTestAccess::deliverOrder(order, {});
    CHECK(manager->primaryShell() == first);
    CHECK(manager->activeShell() == first);

    // The existing Focus Dock route falls back deterministically when the
    // cursor is on an output with no dock. A client surface there makes its
    // global pointer coordinates observable to QtWayland.
    QQuickWindow pointerSurface;
    pointerSurface.setScreen(unselected);
    pointerSurface.setGeometry(QRect(unselected->geometry().topLeft(), QSize(120, 80)));
    auto *layer = LayerShellQt::Window::get(&pointerSurface);
    REQUIRE(layer);
    layer->setScope(QStringLiteral("selected-output-pointer-test"));
#ifndef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
    layer->setScreen(unselected);
#endif
    pointerSurface.show();
    REQUIRE(QTest::qWaitFor(
        [&] {
            return pointerSurface.isExposed();
        },
        kTimeoutMs));
    QTest::mouseMove(&pointerSurface, QPoint(40, 30));
    REQUIRE(QTest::qWaitFor(
        [&] {
            return QGuiApplication::screenAt(QCursor::pos()) == unselected;
        },
        kTimeoutMs));
    CHECK(manager->shellAtCursor() == first);
    manager->shellAtCursor()->focusDock();
    // Navigation starts synchronously; wait for KWin and QML keyboard focus
    // before sending Escape.
    REQUIRE(QTest::qWaitFor(
        [&] {
            return first->view()->isActive() && first->view()->rootObject()->hasActiveFocus()
                && first->view()->rootObject()->property("keyboardNavigating").toBool();
        },
        kTimeoutMs));
    CHECK_FALSE(second->view()->rootObject()->property("keyboardNavigating").toBool());
    QTest::keyClick(first->view(), Qt::Key_Escape);
    REQUIRE(QTest::qWaitFor(
        [&] {
            return !first->view()->rootObject()->property("keyboardNavigating").toBool();
        },
        kTimeoutMs));
}

int main(int argc, char *argv[])
{
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");

    QApplication application(argc, argv);
    if (QQuickStyle::name().isEmpty()) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }
    KAboutData aboutData(QStringLiteral("kdockw"), QStringLiteral("KDockW"), QStringLiteral("test"));
    KAboutData::setApplicationData(aboutData);
    initResources();

    return Catch::Session().run(argc, argv);
}
