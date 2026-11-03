// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_session.hpp>

#include "app/application.h"
#include "kdockw.h"

#include <KAboutData>
#include <KLocalizedString>
#include <KLocalizedQmlContext>

#include <QApplication>
#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QProcess>
#include <QString>
#include <QUrl>
#include <memory>

int main(int argc, char *argv[])
{
    if (argc == 3 && QString::fromLocal8Bit(argv[1]) == QLatin1String("--verify-language-preference")) {
        KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
        QCoreApplication app(argc, argv);
        KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
        if (QDir(QStringLiteral(KDOCKW_TEST_LOCALE_DIR)).exists()) {
            KLocalizedString::addDomainLocaleDir(QByteArrayLiteral("kdockw"), QStringLiteral(KDOCKW_TEST_LOCALE_DIR));
        }
        KDockWSettings settings;
        settings.load();
        const QString expectedLanguage = QString::fromLocal8Bit(argv[2]);
        if (settings.language() != expectedLanguage) {
            return 1;
        }
        kdockw::Application::applyLanguagePreference(settings.language());

        const bool russian = expectedLanguage == QLatin1String("ru")
            || (expectedLanguage == QLatin1String("system") && QLocale::system().language() == QLocale::Russian);
        const KAboutData aboutData = kdockw::Application::makeAboutData();
        if (aboutData.shortDescription() != (russian ? QStringLiteral("Док-панель KDE для Wayland") : QStringLiteral("KDE Dock for Wayland"))) {
            return 5;
        }

        QQmlEngine engine;
        KLocalization::setupLocalizedContext(&engine);
        QQmlComponent component(&engine);
        component.setData(QByteArrayLiteral("import QtQml\nQtObject { property string general: i18n(\"General\") }"), QUrl());
        if (!component.isReady()) {
            return 2;
        }
        const std::unique_ptr<QObject> object(component.create());
        if (!object) {
            return 3;
        }
        const QString expectedLabel = russian ? QStringLiteral("Общие") : QStringLiteral("General");
        return object->property("general").toString() == expectedLabel ? 0 : 4;
    }

    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
    // Catch2 discovery launches each case as its own process. Set locale before
    // QApplication caches QLocale so the desktop-action locale test is stable.
    bool germanDesktopActionCase = false;
    for (int i = 1; i < argc; ++i) {
        germanDesktopActionCase |= QString::fromLocal8Bit(argv[i]).contains(QStringLiteral("localized action names"));
    }
    qputenv("LANGUAGE", germanDesktopActionCase ? QByteArrayLiteral("de") : QByteArrayLiteral("C"));
    qputenv("LC_ALL", germanDesktopActionCase ? QByteArrayLiteral("de_DE.UTF-8") : QByteArrayLiteral("C"));
    qputenv("LANG", germanDesktopActionCase ? QByteArrayLiteral("de_DE.UTF-8") : QByteArrayLiteral("C"));

    // Catch2's CMake discovery runs this executable during the build, before
    // CTest can apply the per-test QT_QPA_PLATFORM property. Keep that
    // discovery headless on CI machines without a display server.
    qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("offscreen"));

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kdockw-unit-tests"));
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
    if (QDir(QStringLiteral(KDOCKW_TEST_LOCALE_DIR)).exists()) {
        KLocalizedString::addDomainLocaleDir(QByteArrayLiteral("kdockw"), QStringLiteral(KDOCKW_TEST_LOCALE_DIR));
    }
    return Catch::Session().run(argc, argv);
}
