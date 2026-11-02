// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <KLocalizedString>
#include <KLocalizedQmlContext>

#include <QDir>
#include <QFile>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QLocale>
#include <QProcess>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>

#include <algorithm>
#include <memory>
#include <utility>

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

    QString configFilePath() const
    {
        return QDir(m_dir.path()).filePath(QStringLiteral("kdockwrc"));
    }

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};

QByteArray readConfigFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return file.readAll();
}

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
    QCoreApplication::processEvents();
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
    QCoreApplication::processEvents();
    CHECK(object->property("settingsLabel").toString() == QStringLiteral("Параметры"));
    CHECK(object->property("previewLabel").toString() == QStringLiteral("Предпросмотр окон"));
    CHECK(object->property("generalLabel").toString() == QStringLiteral("Общие"));
    CHECK(i18nc("@action global shortcut", "Toggle Dock") == QStringLiteral("Показать или скрыть док"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("system"));
    QCoreApplication::processEvents();
    CHECK(object->property("settingsLabel").toString() == QLatin1String("Settings"));
    CHECK(object->property("previewLabel").toString() == QLatin1String("Window Preview"));
    CHECK(object->property("generalLabel").toString() == QLatin1String("General"));
}

TEST_CASE("The General page saves the selected language on user activation", "[settings][language][qml]")
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
    int languageChangedCount = 0;
    QObject::connect(&settings, &KDockWSettings::LanguageChanged, &saveContext, [&languageChangedCount]() {
        ++languageChangedCount;
    });

    // A visual/index change by itself is not a user preference. The setting is
    // committed only by the control's user activation signal.
    REQUIRE(selector->setProperty("currentIndex", 2));
    QCoreApplication::processEvents();
    CHECK(settings.language() == QLatin1String("system"));
    CHECK(languageChangedCount == 0);
    QFile configFile(home.configFilePath());
    if (configFile.exists()) {
        REQUIRE(configFile.open(QIODevice::ReadOnly));
        CHECK_FALSE(configFile.readAll().contains("Language="));
        configFile.close();
    }

    REQUIRE(QMetaObject::invokeMethod(selector, "activated", Q_ARG(int, 2)));
    QCoreApplication::processEvents();
    CHECK(settings.language() == QLatin1String("en"));
    CHECK(languageChangedCount == 1);
    REQUIRE(configFile.open(QIODevice::ReadOnly));
    CHECK(configFile.readAll().contains("[General]"));
    configFile.close();
    CHECK(readConfigFile(home.configFilePath()).contains("Language=en"));
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

    REQUIRE(QMetaObject::invokeMethod(reopenedSelector, "activated", Q_ARG(int, 1)));
    QCoreApplication::processEvents();
    CHECK(settings.language() == QLatin1String("ru"));
    CHECK(readConfigFile(home.configFilePath()).contains("Language=ru"));
    CHECK(labels->property("settingsLabel").toString() == QStringLiteral("Параметры"));
    CHECK(labels->property("previewLabel").toString() == QStringLiteral("Предпросмотр окон"));
    QProcess russianRestartedProcess;
    russianRestartedProcess.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--verify-language-preference"), QStringLiteral("ru")});
    REQUIRE(russianRestartedProcess.waitForStarted());
    REQUIRE(russianRestartedProcess.waitForFinished());
    CHECK(russianRestartedProcess.exitStatus() == QProcess::NormalExit);
    CHECK(russianRestartedProcess.exitCode() == 0);
    REQUIRE(QMetaObject::invokeMethod(reopenedSelector, "activated", Q_ARG(int, 0)));
    QCoreApplication::processEvents();
    CHECK(settings.language() == QLatin1String("system"));
    const QByteArray systemConfig = readConfigFile(home.configFilePath());
    CHECK((systemConfig.contains("Language=system") || !systemConfig.contains("Language=")));
    KDockWSettings systemReloaded;
    systemReloaded.load();
    CHECK(systemReloaded.language() == QLatin1String("system"));
    CHECK(labels->property("settingsLabel").toString() == QLatin1String("Settings"));
    QProcess systemRestartedProcess;
    systemRestartedProcess.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--verify-language-preference"), QStringLiteral("system")});
    REQUIRE(systemRestartedProcess.waitForStarted());
    REQUIRE(systemRestartedProcess.waitForFinished());
    CHECK(systemRestartedProcess.exitStatus() == QProcess::NormalExit);
    CHECK(systemRestartedProcess.exitCode() == 0);
}

TEST_CASE("The settings window language selector shows real options and retranslates the settings UI", "[settings][language][qml][regression]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();
    QObject saveContext;
    kdockw::Application::connectSettingsAutoSave(&settings, &saveContext);
    settings.setIconSize(64);

    const QLocale systemLocale = QLocale::system();
    const QString russianDescription = QStringLiteral(
        "Выберите язык KDockW. Системный режим использует настройки локали KDE и Qt.");
    const QString englishDescription = QStringLiteral(
        "Choose the language used by KDockW. System default follows the KDE and Qt locale settings.");
    kdockw::Application::applyLanguagePreference(QStringLiteral("ru"));

    Q_INIT_RESOURCE(qml);
    QQmlEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("DockSettings"), &settings);
    QQmlComponent component(&engine, QUrl(QStringLiteral("qrc:/qml/SettingsDialog.qml")));
    REQUIRE(component.isReady());
    QObject *dialogObject = component.createWithInitialProperties({{QStringLiteral("defaultModule"), QStringLiteral("general")}});
    REQUIRE(dialogObject);
    auto *window = qobject_cast<QQuickWindow *>(dialogObject);
    REQUIRE(window);
    window->show();
    QCoreApplication::processEvents();

    auto *pageLoader = window->findChild<QObject *>(QStringLiteral("settingsPageLoader"));
    REQUIRE(pageLoader);
    QObject *page = pageLoader->property("item").value<QObject *>();
    REQUIRE(page);
    CHECK(page->property("title").toString() == QStringLiteral("Общие"));
    CHECK(page->property("subtitle").toString() == QStringLiteral("Основные настройки и язык приложения"));
    CHECK(window->property("title").toString() == QStringLiteral("Параметры"));
    QObject *sectionHeader = page->findChild<QObject *>(QStringLiteral("languageSectionHeader"));
    REQUIRE(sectionHeader);
    CHECK(sectionHeader->property("title").toString() == QStringLiteral("Язык"));

    QObject *selector = page->findChild<QObject *>(QStringLiteral("languageSelector"));
    REQUIRE(selector);
    CHECK(selector->property("currentIndex").toInt() == 0);
    CHECK(selector->property("displayText").toString() == QStringLiteral("Автоматически (системный язык)"));
    CHECK(selector->property("text").toString() == QStringLiteral("Язык"));
    CHECK(selector->property("description").toString() == russianDescription);

    QVariantList modules = window->property("modules").toList();
    auto generalModule = std::find_if(modules.cbegin(), modules.cend(), [](const QVariant &module) {
        return module.toMap().value(QStringLiteral("moduleId")).toString() == QLatin1String("general");
    });
    REQUIRE(generalModule != modules.cend());
    CHECK(generalModule->toMap().value(QStringLiteral("text")).toString() == QStringLiteral("Общие"));

    // Open the actual FormCard ComboBox popup and inspect its three rendered
    // delegate labels instead of setting currentIndex directly.
    QObject *comboBox = nullptr;
    for (QObject *child : selector->findChildren<QObject *>()) {
        if (child->property("popup").isValid()) {
            comboBox = child;
            break;
        }
    }
    REQUIRE(comboBox);
    QObject *popup = comboBox->property("popup").value<QObject *>();
    REQUIRE(popup);
    REQUIRE(QMetaObject::invokeMethod(selector, "clicked"));
    QCoreApplication::processEvents();
    CHECK(popup->property("visible").toBool());
    QObject *popupList = nullptr;
    for (QObject *child : popup->findChildren<QObject *>()) {
        if (child->property("count").toInt() == 3 && QByteArray(child->metaObject()->className()).contains("ListView")) {
            popupList = child;
            break;
        }
    }
    REQUIRE(popupList);

    QStringList optionLabels;
    QList<QQuickItem *> optionItems;
    for (int i = 0; i < 3; ++i) {
        QQuickItem *item = nullptr;
        REQUIRE(QMetaObject::invokeMethod(popupList, "itemAtIndex", Q_RETURN_ARG(QQuickItem *, item), Q_ARG(int, i)));
        REQUIRE(item);
        optionItems.append(item);
        optionLabels.append(item->property("text").toString());
        CHECK(item->isVisible());
    }
    CHECK(optionLabels.contains(QStringLiteral("Автоматически (системный язык)")));
    CHECK(optionLabels.contains(QStringLiteral("Русский")));
    CHECK(optionLabels.contains(QStringLiteral("English")));

    // Invoke the actual rendered option delegate's clicked signal.
    QObject *englishOption = nullptr;
    for (QQuickItem *item : std::as_const(optionItems)) {
        if (item->property("text").toString() == QLatin1String("English") && item->isVisible()) {
            englishOption = item;
            break;
        }
    }
    REQUIRE(englishOption);
    REQUIRE(QMetaObject::invokeMethod(englishOption, "clicked"));
    QCoreApplication::processEvents();

    CHECK(settings.language() == QLatin1String("en"));
    CHECK(readConfigFile(home.configFilePath()).contains("[General]"));
    CHECK(readConfigFile(home.configFilePath()).contains("Language=en"));
    CHECK(readConfigFile(home.configFilePath()).contains("IconSize=64"));
    CHECK(selector->property("displayText").toString() == QLatin1String("English"));
    CHECK(page->property("title").toString() == QLatin1String("General"));
    CHECK(page->property("subtitle").toString() == QLatin1String("General settings and application language"));
    CHECK(window->property("title").toString() == QLatin1String("Settings"));
    CHECK(sectionHeader->property("title").toString() == QLatin1String("Language"));
    CHECK(selector->property("text").toString() == QLatin1String("Language"));
    CHECK(selector->property("description").toString() == englishDescription);
    modules = window->property("modules").toList();
    generalModule = std::find_if(modules.cbegin(), modules.cend(), [](const QVariant &module) {
        return module.toMap().value(QStringLiteral("moduleId")).toString() == QLatin1String("general");
    });
    REQUIRE(generalModule != modules.cend());
    CHECK(generalModule->toMap().value(QStringLiteral("text")).toString() == QLatin1String("General"));
    CHECK(QLocale::system() == systemLocale);
    CHECK(i18nc("@action global shortcut", "Toggle Dock") == QLatin1String("Toggle Dock"));

    QProcess restartedProcess;
    restartedProcess.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--verify-language-preference"), QStringLiteral("en")});
    REQUIRE(restartedProcess.waitForStarted());
    REQUIRE(restartedProcess.waitForFinished());
    CHECK(restartedProcess.exitStatus() == QProcess::NormalExit);
    CHECK(restartedProcess.exitCode() == 0);

    auto activateOption = [&](int index) {
        REQUIRE(QMetaObject::invokeMethod(selector, "clicked"));
        QCoreApplication::processEvents();
        QObject *openPopup = comboBox->property("popup").value<QObject *>();
        REQUIRE(openPopup);
        REQUIRE(openPopup->property("visible").toBool());
        QObject *openList = nullptr;
        for (QObject *child : openPopup->findChildren<QObject *>()) {
            if (child->property("count").toInt() == 3 && QByteArray(child->metaObject()->className()).contains("ListView")) {
                openList = child;
                break;
            }
        }
        REQUIRE(openList);
        QQuickItem *item = nullptr;
        REQUIRE(QMetaObject::invokeMethod(openList, "itemAtIndex", Q_RETURN_ARG(QQuickItem *, item), Q_ARG(int, index)));
        REQUIRE(item);
        REQUIRE(QMetaObject::invokeMethod(item, "clicked"));
        QCoreApplication::processEvents();
    };

    activateOption(1);
    CHECK(settings.language() == QLatin1String("ru"));
    CHECK(readConfigFile(home.configFilePath()).contains("Language=ru"));
    CHECK(selector->property("displayText").toString() == QStringLiteral("Русский"));
    CHECK(page->property("title").toString() == QStringLiteral("Общие"));
    CHECK(page->property("subtitle").toString() == QStringLiteral("Основные настройки и язык приложения"));
    CHECK(window->property("title").toString() == QStringLiteral("Параметры"));
    CHECK(sectionHeader->property("title").toString() == QStringLiteral("Язык"));
    CHECK(selector->property("text").toString() == QStringLiteral("Язык"));
    CHECK(selector->property("description").toString() == russianDescription);
    modules = window->property("modules").toList();
    generalModule = std::find_if(modules.cbegin(), modules.cend(), [](const QVariant &module) {
        return module.toMap().value(QStringLiteral("moduleId")).toString() == QLatin1String("general");
    });
    REQUIRE(generalModule != modules.cend());
    CHECK(generalModule->toMap().value(QStringLiteral("text")).toString() == QStringLiteral("Общие"));
    CHECK(i18nc("@action global shortcut", "Toggle Dock") == QStringLiteral("Показать или скрыть док"));

    activateOption(0);
    CHECK(settings.language() == QLatin1String("system"));
    const QByteArray systemConfig = readConfigFile(home.configFilePath());
    CHECK((systemConfig.contains("Language=system") || !systemConfig.contains("Language=")));
    KDockWSettings systemReloaded;
    systemReloaded.load();
    CHECK(systemReloaded.language() == QLatin1String("system"));
    CHECK(selector->property("displayText").toString() == QLatin1String("System default"));
    CHECK(page->property("title").toString() == QLatin1String("General"));
    activateOption(2);
    CHECK(settings.language() == QLatin1String("en"));
    CHECK(readConfigFile(home.configFilePath()).contains("Language=en"));
    CHECK(page->property("title").toString() == QLatin1String("General"));

    // Recreate the page after navigation and verify persistence and language
    // state in the actual SettingsDialog rather than in an isolated control.
    REQUIRE(QMetaObject::invokeMethod(window, "openModule", Q_ARG(QVariant, QVariant(QStringLiteral("about")))));
    QCoreApplication::processEvents();
    CHECK(window->property("currentModule").toString() == QLatin1String("about"));
    REQUIRE(pageLoader->property("item").value<QObject *>());
    REQUIRE(QMetaObject::invokeMethod(window, "openModule", Q_ARG(QVariant, QVariant(QStringLiteral("general")))));
    QCoreApplication::processEvents();
    CHECK(window->property("currentModule").toString() == QLatin1String("general"));
    page = pageLoader->property("item").value<QObject *>();
    REQUIRE(page);
    selector = page->findChild<QObject *>(QStringLiteral("languageSelector"));
    REQUIRE(selector);
    CHECK(selector->property("currentIndex").toInt() == 2);
    CHECK(selector->property("displayText").toString() == QLatin1String("English"));
    CHECK(page->property("title").toString() == QLatin1String("General"));

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.language() == QLatin1String("en"));
    CHECK(restarted.iconSize() == 64);

    window->close();
    delete window;
    dialogObject = component.createWithInitialProperties({{QStringLiteral("defaultModule"), QStringLiteral("general")}});
    REQUIRE(dialogObject);
    window = qobject_cast<QQuickWindow *>(dialogObject);
    REQUIRE(window);
    window->show();
    QCoreApplication::processEvents();
    pageLoader = window->findChild<QObject *>(QStringLiteral("settingsPageLoader"));
    REQUIRE(pageLoader);
    page = pageLoader->property("item").value<QObject *>();
    REQUIRE(page);
    selector = page->findChild<QObject *>(QStringLiteral("languageSelector"));
    REQUIRE(selector);
    CHECK(selector->property("currentIndex").toInt() == 2);
    CHECK(selector->property("displayText").toString() == QLatin1String("English"));
    CHECK(page->property("title").toString() == QLatin1String("General"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("ru"));
    QCoreApplication::processEvents();
    CHECK(page->property("title").toString() == QStringLiteral("Общие"));
    CHECK(selector->property("text").toString() == QStringLiteral("Язык"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("system"));
    QCoreApplication::processEvents();
    CHECK(QLocale::system() == systemLocale);
    window->close();
    delete window;
}

TEST_CASE("KI18n falls back to the English source string when a translation is missing", "[i18n]")
{
    const auto fallback = ki18n("A source string without a catalog entry")
                              .withLanguages({QStringLiteral("ru")})
                              .toString();
    CHECK(fallback == QLatin1String("A source string without a catalog entry"));
}
