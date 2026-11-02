// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "application.h"

#include "kdockw.h"
#include "models/dockactions.h"
#include "models/dockmodel.h"
#include "models/launcherentrytracker.h"
#include "models/notificationtracker.h"
#include "models/taskiconprovider.h"
#include "shell/dockshell.h"
#include "shell/dockview.h"
#include "shell/dockvisibilitycontroller.h"
#include "shell/multidockmanager.h"
#include "shell/outputordermonitor.h"

#include <KAboutData>
#include <KActionCollection>
#include <KConfigGroup>
#include <KCrash>
#include <KDBusService>
#include <KGlobalAccel>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QAction>
#include <QIcon>
#include <QLoggingCategory>
#include <QQuickStyle>
#include <QtQml>

#include <algorithm>

Q_LOGGING_CATEGORY(lcApp, "kdockw.app")

// Static library resources must be explicitly initialized.
// Must be called from global namespace, not inside kdockw namespace.
static void initResources()
{
    Q_INIT_RESOURCE(qml);
}

namespace kdockw
{

Application::Application(int &argc, char **argv)
    : QApplication(argc, argv)
{
}

Application::~Application()
{
    TaskIconProvider::clearRawIcons();
}

KAboutData Application::makeAboutData(bool localized)
{
    const QString displayName = localized ? i18n("KDockW") : QStringLiteral("KDockW");
    const QString description = localized ? i18n("A dock for KDE Plasma 6")
                                          : QStringLiteral("A dock for KDE Plasma 6");
    KAboutData aboutData(QStringLiteral("kdockw"), displayName, QStringLiteral(KDOCKW_VERSION_STRING), description, KAboutLicense::GPL_V3);
    const QString author = localized ? i18n("Byeonghoon Yoo") : QStringLiteral("Byeonghoon Yoo");
    aboutData.addAuthor(author, {}, QStringLiteral("bhyoo@bhyoo.com"));
    aboutData.setOrganizationDomain(QByteArrayLiteral("thicking.com"));
    aboutData.setHomepage(QStringLiteral("https://github.com/thicking/krema"));
    aboutData.setBugAddress(QByteArrayLiteral("https://github.com/thicking/krema/issues"));
    aboutData.setDesktopFileName(QStringLiteral("com.thicking.kdockw"));
    return aboutData;
}

void Application::connectSettingsAutoSave(KDockWSettings *settings, QObject *context)
{
    auto saveSettings = [settings]() {
        settings->save();
    };
    connect(settings, &KDockWSettings::IconSizeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconSpacingChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconOpacityActiveChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconOpacityInactiveChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconOpacityMinimizedChanged, context, saveSettings);
    connect(settings, &KDockWSettings::MaxZoomFactorChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomStyleChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomAnimationPresetChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomInDurationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomOutDurationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomInEasingChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ZoomOutEasingChanged, context, saveSettings);
    connect(settings, &KDockWSettings::CornerRadiusChanged, context, saveSettings);
    connect(settings, &KDockWSettings::FloatingChanged, context, saveSettings);
    connect(settings, &KDockWSettings::FloatingMarginChanged, context, saveSettings);
    connect(settings, &KDockWSettings::BackgroundOpacityChanged, context, saveSettings);
    connect(settings, &KDockWSettings::BackgroundStyleChanged, context, saveSettings);
    connect(settings, &KDockWSettings::TintColorChanged, context, saveSettings);
    connect(settings, &KDockWSettings::VisibilityModeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::EdgeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShowDelayChanged, context, saveSettings);
    connect(settings, &KDockWSettings::HideDelayChanged, context, saveSettings);
    connect(settings, &KDockWSettings::PreviewEnabledChanged, context, saveSettings);
    connect(settings, &KDockWSettings::SingleWindowClickActionChanged, context, saveSettings);
    connect(settings, &KDockWSettings::PreviewThumbnailSizeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::PreviewHoverDelayChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ActivateWindowOnExternalDragChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ExternalDragActivationDelayChanged, context, saveSettings);
    connect(settings, &KDockWSettings::PreviewHideDelayChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowEnabledChanged, context, saveSettings);
    connect(settings, &KDockWSettings::GroupedWindowClickActionChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowLightXChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowLightYChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowLightZChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowLightRadiusChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowColorChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowIntensityChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ShadowElevationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconNormalizationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::AttentionAnimationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::VirtualDesktopModeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::OtherDesktopOpacityChanged, context, saveSettings);
    connect(settings, &KDockWSettings::MonitorModeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::SelectedOutputsChanged, context, saveSettings);
    connect(settings, &KDockWSettings::FollowActiveTriggerChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ScreenTransitionChanged, context, saveSettings);
    connect(settings, &KDockWSettings::IconScaleChanged, context, saveSettings);
    connect(settings, &KDockWSettings::AttentionAnimationDurationChanged, context, saveSettings);
    connect(settings, &KDockWSettings::BadgeDisplayModeChanged, context, saveSettings);
    connect(settings, &KDockWSettings::UseSystemColorChanged, context, saveSettings);
    connect(settings, &KDockWSettings::UseAccentColorChanged, context, saveSettings);
    connect(settings, &KDockWSettings::DodgeActiveOnlyChanged, context, saveSettings);
    connect(settings, &KDockWSettings::ReserveScreenSpaceChanged, context, saveSettings);
    connect(settings, &KDockWSettings::SeparateLaunchersChanged, context, saveSettings);
}

void Application::migrateLegacySettings(KDockWSettings *settings)
{
    // KDockW 0.10 stored a single ZoomAnimationDuration (only when changed from
    // its 100 ms default) applied with an ease-out curve to both directions.
    // Map it to the Custom preset with the same duration and easing, so the
    // upgraded dock keeps exactly the old feel, and drop the obsolete key.
    // "General" is the kdockw.kcfg group holding the zoom entries.
    KConfigGroup group = settings->config()->group(QStringLiteral("General"));
    const QString legacyKey = QStringLiteral("ZoomAnimationDuration");
    if (!group.hasKey(legacyKey)) {
        return;
    }

    if (!group.hasKey(QStringLiteral("ZoomAnimationPreset"))) {
        constexpr int customPreset = 4;
        constexpr int easeOut = 2;
        const int duration = std::clamp(group.readEntry(legacyKey, 100), 0, 1000);
        settings->setZoomAnimationPreset(customPreset);
        settings->setZoomInDuration(duration);
        settings->setZoomOutDuration(duration);
        settings->setZoomInEasing(easeOut);
        settings->setZoomOutEasing(easeOut);
    }

    group.deleteEntry(legacyKey);
    settings->save();
}

int Application::run(const KAboutData &aboutData)
{
    // Ensure Qt Quick Controls use the KDE Plasma style (needed for Kirigami theming)
    if (QQuickStyle::name().isEmpty()) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    // Initialize KDE crash handler (must be called early)
    KCrash::initialize();

    // Set up KDE application metadata (required for KGlobalAccel, D-Bus, etc.);
    // also sets the desktop file name.
    KAboutData::setApplicationData(aboutData);
    setWindowIcon(QIcon::fromTheme(QStringLiteral("com.thicking.kdockw")));

    // Enforce single instance via D-Bus (exits if another instance is already running)
    KDBusService service(KDBusService::Unique);
    connect(&service, &KDBusService::activateRequested, this, [](const QStringList &args, const QString &) {
        qCInfo(lcApp) << "Another instance attempted to start, ignoring. args:" << args;
    });

    // Initialize Qt resources from static library
    initResources();

    // Opt into the layer-shell platform plugin. Equivalent to the deprecated
    // LayerShellQt::Shell::useLayerShell() (it only sets this variable); must
    // happen before the first QWindow is created.
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");

    // Load settings from KConfig (~/.config/kdockwrc)
    m_settings = std::make_unique<KDockWSettings>();
    m_settings->load();
    migrateLegacySettings(m_settings.get());

    // Create data model
    m_dockModel = std::make_unique<DockModel>();
    m_dockModel->setPinnedLaunchers(m_settings->pinnedLaunchers());
    m_dockModel->setSeparateLaunchers(m_settings->separateLaunchers());

    // Create notification trackers (before QML loading)
    m_notificationTracker = std::make_unique<NotificationTracker>();
    m_launcherEntryTracker = std::make_unique<LauncherEntryTracker>();

    // Register global QML singletons (must be before any QML loading)
    // Use qmlRegisterSingletonType (not qmlRegisterSingletonInstance) so multiple
    // QML engines (dock + settings window) can access the same C++ objects.
    auto *model = m_dockModel.get();
    qmlRegisterSingletonType<DockModel>("com.thicking.kdockw", 1, 0, "DockModel", [model](QQmlEngine *, QJSEngine *) -> QObject * {
        QQmlEngine::setObjectOwnership(model, QQmlEngine::CppOwnership);
        return model;
    });
    auto *settings = m_settings.get();
    qmlRegisterSingletonType<KDockWSettings>("com.thicking.kdockw", 1, 0, "DockSettings", [settings](QQmlEngine *, QJSEngine *) -> QObject * {
        QQmlEngine::setObjectOwnership(settings, QQmlEngine::CppOwnership);
        return settings;
    });
    auto *tracker = m_notificationTracker.get();
    qmlRegisterSingletonType<NotificationTracker>("com.thicking.kdockw", 1, 0, "NotificationTracker", [tracker](QQmlEngine *, QJSEngine *) -> QObject * {
        QQmlEngine::setObjectOwnership(tracker, QQmlEngine::CppOwnership);
        return tracker;
    });
    auto *launcherEntries = m_launcherEntryTracker.get();
    qmlRegisterSingletonType<LauncherEntryTracker>("com.thicking.kdockw", 1, 0, "LauncherEntryTracker", [launcherEntries](QQmlEngine *, QJSEngine *) -> QObject * {
        QQmlEngine::setObjectOwnership(launcherEntries, QQmlEngine::CppOwnership);
        return launcherEntries;
    });

    // Create and initialize the multi-dock manager (creates DockShell(s) based on monitor mode).
    // Placement uses the Plasma primary output (kde_output_order_v1); wait for
    // KWin's first order list when the protocol is present so the dock does not
    // briefly land on the wrong (first-announced) output before moving.
    m_dockManager = std::make_unique<MultiDockManager>(m_settings.get(), m_dockModel.get(), m_notificationTracker.get(), this);
    auto *outputOrder = OutputOrderMonitor::instance();
    if (outputOrder->orderReady()) {
        m_dockManager->initialize();
    } else {
        connect(outputOrder, &OutputOrderMonitor::orderReadyChanged, this, [this] {
            m_dockManager->initialize();
        });
    }

    // Apply initial virtual desktop display mode
    m_dockModel->setVirtualDesktopMode(m_settings->virtualDesktopMode());

    // Auto-save pinned launchers when they change on any shell
    connect(m_dockManager.get(), &MultiDockManager::pinnedLaunchersChanged, this, [this]() {
        m_settings->setPinnedLaunchers(m_dockModel->pinnedLaunchers());
        m_settings->save();
    });

    // Auto-save on any setting change
    auto *s = m_settings.get();
    connectSettingsAutoSave(s, this);

    // Virtual desktop mode change
    connect(s, &KDockWSettings::VirtualDesktopModeChanged, this, [this]() {
        m_dockModel->setVirtualDesktopMode(m_settings->virtualDesktopMode());
    });

    // Keep task partitioning in sync with the live settings page.
    connect(s, &KDockWSettings::SeparateLaunchersChanged, this, [this]() {
        m_dockModel->setSeparateLaunchers(m_settings->separateLaunchers());
    });

    // Monitor mode change
    connect(s, &KDockWSettings::MonitorModeChanged, this, [this]() {
        m_dockManager->setMonitorMode(static_cast<MultiDockManager::MonitorMode>(m_settings->monitorMode()));
    });

    // The dock window is now created with layer-shell.
    // Unset the env var so child processes (launched apps) don't inherit it.
    qunsetenv("QT_WAYLAND_SHELL_INTEGRATION");

    // Register global shortcuts (KGlobalAccel)
    registerGlobalShortcuts();

    return exec();
}

void Application::registerGlobalShortcuts()
{
    m_actionCollection = new KActionCollection(this, QStringLiteral("kdockw"));
    auto *kga = KGlobalAccel::self();

    // Toggle dock visibility: Meta+`
    auto *toggleAction = m_actionCollection->addAction(QStringLiteral("toggle-dock"));
    toggleAction->setText(i18nc("@action global shortcut", "Toggle Dock"));
    kga->setDefaultShortcut(toggleAction, {QKeySequence(Qt::META | Qt::Key_QuoteLeft)});
    kga->setShortcut(toggleAction, {QKeySequence(Qt::META | Qt::Key_QuoteLeft)});
    connect(toggleAction, &QAction::triggered, this, [this]() {
        if (auto *shell = m_dockManager->activeShell()) {
            shell->view()->visibilityController()->toggleVisibility();
        }
    });

    // Focus dock for keyboard navigation: Meta+Alt+D (like Plasma's "Move keyboard
    // focus between panels", Meta+Alt+P). No stock Plasma 6 component claims it;
    // the former default Meta+F5 is KWin's "Move Mouse to Focus", which always wins
    // the key and makes kglobalacceld < 6.7 drop it from this action entirely.
    // In multi-monitor mode, focuses the dock on the screen containing the cursor;
    // in Follow Active mode, the dock on the active screen.
    auto *focusDockAction = m_actionCollection->addAction(QStringLiteral("focus-dock"));
    focusDockAction->setText(i18nc("@action global shortcut", "Focus Dock"));
    const QList<QKeySequence> focusDockShortcut{QKeySequence(Qt::META | Qt::ALT | Qt::Key_D)};
    kga->setDefaultShortcut(focusDockAction, focusDockShortcut);
    kga->setShortcut(focusDockAction, focusDockShortcut);
    // Autoloading keeps the stored shortcut. Move users still on the old default
    // (which never reaches kdockw on stock KWin) to the new one.
    if (kga->shortcut(focusDockAction) == QList<QKeySequence>{QKeySequence(Qt::META | Qt::Key_F5)}) {
        kga->setShortcut(focusDockAction, focusDockShortcut, KGlobalAccel::NoAutoloading);
    }
    connect(focusDockAction, &QAction::triggered, this, [this]() {
        if (auto *shell = m_dockManager->shellAtCursor()) {
            shell->focusDock();
        }
    });

    // Meta+1..9: Activate N-th app (targets primary dock)
    for (int i = 1; i <= 9; ++i) {
        auto *activateAction = m_actionCollection->addAction(QStringLiteral("activate-entry-%1").arg(i));
        activateAction->setText(i18nc("@action global shortcut", "Activate Entry %1", i));
        const auto seq = QKeySequence(Qt::META | static_cast<Qt::Key>(Qt::Key_1 + i - 1));
        kga->setDefaultShortcut(activateAction, {seq});
        kga->setShortcut(activateAction, {seq});
        connect(activateAction, &QAction::triggered, this, [this, i]() {
            if (auto *shell = m_dockManager->activeShell()) {
                shell->actions()->activate(i - 1);
            }
        });
    }

    // Meta+Shift+1..9: New instance of N-th app (targets primary dock)
    for (int i = 1; i <= 9; ++i) {
        auto *newInstanceAction = m_actionCollection->addAction(QStringLiteral("new-instance-entry-%1").arg(i));
        newInstanceAction->setText(i18nc("@action global shortcut", "New Instance of Entry %1", i));
        const auto seq = QKeySequence(Qt::META | Qt::SHIFT | static_cast<Qt::Key>(Qt::Key_1 + i - 1));
        kga->setDefaultShortcut(newInstanceAction, {seq});
        kga->setShortcut(newInstanceAction, {seq});
        connect(newInstanceAction, &QAction::triggered, this, [this, i]() {
            if (auto *shell = m_dockManager->activeShell()) {
                shell->actions()->newInstance(i - 1);
            }
        });
    }

    qCDebug(lcApp) << "Global shortcuts registered";
}

} // namespace kdockw
