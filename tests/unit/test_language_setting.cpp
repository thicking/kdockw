// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <KLocalizedString>
#include <KLocalizedQmlContext>

#include <QDir>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QLocale>
#include <QProcess>
#include <QTemporaryDir>

#include <memory>

namespace
{

class ScopedConfigHome
{
public:
    ScopedConfigHome()
        : m_previous(qgetenv("XDG_CONFIG_HOME"))
        , m_hadPrevious(qEnvironmentVariableIsSet("XDG_CONFIG_HOME"))
    {
        qputenv("XDG_CONFIG_HOME", m_dir.path().toLocal8Bit());
    }
    ~ScopedConfigHome()
    {
        if (m_hadPrevious) {
            qputenv("XDG_CONFIG_HOME", m_previous);
        } else {
            qunsetenv("XDG_CONFIG_HOME");
        }
    }
    ScopedConfigHome(const ScopedConfigHome &) = delete;
    ScopedConfigHome &operator=(const ScopedConfigHome &) = delete;

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};

} // namespace

TEST_CASE("Language preference defaults to the system and persists without resetting other settings", "[settings][language]")
{
    const ScopedConfigHome home;
    const QByteArray originalLanguage = qgetenv("LANGUAGE");
    const QByteArray originalLocale = qgetenv("LC_ALL");
    const QByteArray originalMessagesLocale = qgetenv("LC_MESSAGES");
    const QStringList systemLanguages = KLocalizedString::languages();
    KDockWSettings settings;
    settings.load();

    CHECK(settings.language() == QLatin1String("system"));
    CHECK(settings.iconSize() == 48);

    QObject saveContext;
    kdockw::Application::connectSettingsAutoSave(&settings, &saveContext);
    settings.setIconSize(64);
    settings.setLanguage(QStringLiteral("ru"));
    CHECK(KLocalizedString::languages().value(0).startsWith(QLatin1String("ru")));
    CHECK(qgetenv("LANGUAGE") == originalLanguage);
    CHECK(qgetenv("LC_ALL") == originalLocale);
    CHECK(qgetenv("LC_MESSAGES") == originalMessagesLocale);

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.language() == QLatin1String("ru"));
    CHECK(restarted.iconSize() == 64);

    kdockw::Application::applyLanguagePreference(QStringLiteral("en"));
    settings.setLanguage(QStringLiteral("en"));
    CHECK(KLocalizedString::languages().value(0).startsWith(QLatin1String("en")));
    settings.setLanguage(QStringLiteral("system"));
    CHECK(restarted.language() == QLatin1String("ru")); // The independent instance is not mutated.
    CHECK(KLocalizedString::languages() == systemLanguages);
}

TEST_CASE("KI18n translations update existing QML bindings when the language changes", "[i18n][qml]")
{
    QQmlEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    kdockw::Application::registerQmlEngine(&engine);
    QQmlComponent component(&engine);
    component.setData(QByteArrayLiteral("import QtQml\nQtObject { property string settingsLabel: i18n(\"Settings\"); property string previewLabel: i18n(\"Window Preview\"); property string generalLabel: i18n(\"General\") }"), QUrl());
    REQUIRE(component.isReady());
    std::unique_ptr<QObject> object(component.create());
    REQUIRE(object);

    kdockw::Application::applyLanguagePreference(QStringLiteral("en"));
    CHECK(object->property("settingsLabel").toString() == QLatin1String("Settings"));
    CHECK(object->property("previewLabel").toString() == QLatin1String("Window Preview"));
    CHECK(object->property("generalLabel").toString() == QLatin1String("General"));
    CHECK(i18nc("@action global shortcut", "Toggle Dock") == QLatin1String("Toggle Dock"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("ru"));
    CHECK(object->property("settingsLabel").toString() == QStringLiteral("Параметры"));
    CHECK(object->property("previewLabel").toString() == QStringLiteral("Предпросмотр окон"));
    CHECK(object->property("generalLabel").toString() == QStringLiteral("Общие"));
    CHECK(i18nc("@action global shortcut", "Toggle Dock") == QStringLiteral("Показать или скрыть док"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("system"));
    CHECK(object->property("settingsLabel").toString() == QLatin1String("Settings"));
    CHECK(object->property("previewLabel").toString() == QLatin1String("Window Preview"));
    CHECK(object->property("generalLabel").toString() == QLatin1String("General"));
}

TEST_CASE("The General page saves the selected language when its index changes", "[settings][language][qml]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();
    QObject saveContext;
    kdockw::Application::connectSettingsAutoSave(&settings, &saveContext);

    // Load the actual General page, including its FormCard combo delegate,
    // rather than simulating a settings setter or using a mock ComboBox.
    Q_INIT_RESOURCE(qml);
    QQmlEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    kdockw::Application::registerQmlEngine(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("DockSettings"), &settings);
    QQmlComponent component(&engine, QUrl(QStringLiteral("qrc:/qml/settings/GeneralPage.qml")));
    REQUIRE(component.isReady());
    std::unique_ptr<QObject> page(component.create());
    REQUIRE(page);

    QQmlComponent labelsComponent(&engine);
    labelsComponent.setData(QByteArrayLiteral("import QtQml\nQtObject { property string settingsLabel: i18n(\"Settings\"); property string previewLabel: i18n(\"Window Preview\") }"), QUrl());
    REQUIRE(labelsComponent.isReady());
    std::unique_ptr<QObject> labels(labelsComponent.create());
    REQUIRE(labels);

    QObject *selector = page->findChild<QObject *>(QStringLiteral("languageSelector"));
    REQUIRE(selector);
    CHECK(selector->property("currentIndex").toInt() == 0);

    // FormComboBoxDelegate changes currentIndex before emitting activated.
    // The setting must follow that actual UI property change and be flushed.
    REQUIRE(selector->setProperty("currentIndex", 2));
    CHECK(settings.language() == QLatin1String("en"));
    CHECK(labels->property("settingsLabel").toString() == QLatin1String("Settings"));
    CHECK(labels->property("previewLabel").toString() == QLatin1String("Window Preview"));

    // Page navigation destroys the loaded page; reopening it must read the
    // committed KConfig value instead of returning to its default index.
    page.reset();
    std::unique_ptr<QObject> reopenedPage(component.create());
    REQUIRE(reopenedPage);
    QObject *reopenedSelector = reopenedPage->findChild<QObject *>(QStringLiteral("languageSelector"));
    REQUIRE(reopenedSelector);
    CHECK(reopenedSelector->property("currentIndex").toInt() == 2);

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.language() == QLatin1String("en"));

    QProcess restartedProcess;
    restartedProcess.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--verify-language-preference"), QStringLiteral("en")});
    REQUIRE(restartedProcess.waitForStarted());
    REQUIRE(restartedProcess.waitForFinished());
    CHECK(restartedProcess.exitStatus() == QProcess::NormalExit);
    CHECK(restartedProcess.exitCode() == 0);

    REQUIRE(reopenedSelector->setProperty("currentIndex", 1));
    CHECK(settings.language() == QLatin1String("ru"));
    CHECK(labels->property("settingsLabel").toString() == QStringLiteral("Параметры"));
    CHECK(labels->property("previewLabel").toString() == QStringLiteral("Предпросмотр окон"));
    REQUIRE(reopenedSelector->setProperty("currentIndex", 0));
    CHECK(settings.language() == QLatin1String("system"));
    CHECK(labels->property("settingsLabel").toString() == QLatin1String("Settings"));
}

TEST_CASE("KI18n falls back to the English source string when a translation is missing", "[i18n]")
{
    const auto fallback = ki18n("A source string without a catalog entry")
                              .withLanguages({QStringLiteral("ru")})
                              .toString();
    CHECK(fallback == QLatin1String("A source string without a catalog entry"));
}
