// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <KLocalizedString>
#include <KLocalizedQmlContext>

#include <QDir>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QLocale>
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
    component.setData(QByteArrayLiteral("import QtQml\nQtObject { property string label: i18n(\"Settings\") }"), QUrl());
    REQUIRE(component.isReady());
    std::unique_ptr<QObject> object(component.create());
    REQUIRE(object);

    kdockw::Application::applyLanguagePreference(QStringLiteral("en"));
    CHECK(object->property("label").toString() == QLatin1String("Settings"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("ru"));
    CHECK(object->property("label").toString() == QStringLiteral("Параметры"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("system"));
    CHECK(object->property("label").toString() == QLatin1String("Settings"));
}

TEST_CASE("KI18n falls back to the English source string when a translation is missing", "[i18n]")
{
    const auto fallback = ki18n("A source string without a catalog entry")
                              .withLanguages({QStringLiteral("ru")})
                              .toString();
    CHECK(fallback == QLatin1String("A source string without a catalog entry"));
}
