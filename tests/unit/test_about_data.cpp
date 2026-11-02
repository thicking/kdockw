// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <KAboutData>
#include <KLocalizedString>

#include <QIcon>

TEST_CASE("KAboutData presents KDockW identity, attribution, and installed icon name", "[about][branding]")
{
    const KAboutData aboutData = kdockw::Application::makeAboutData(false);

    CHECK(aboutData.componentName() == QLatin1String("kdockw"));
    CHECK(aboutData.displayName() == QLatin1String("KDockW"));
    CHECK(aboutData.shortDescription() == QLatin1String("KDE Dock for Wayland"));
    CHECK(aboutData.version() == QLatin1String(KDOCKW_VERSION_STRING));
    CHECK(aboutData.homepage() == QLatin1String("https://github.com/thicking/kdockw"));
    CHECK(aboutData.bugAddress() == QLatin1String("https://github.com/thicking/kdockw/issues"));
    CHECK(aboutData.desktopFileName() == QLatin1String("com.thicking.kdockw"));
    CHECK(aboutData.copyrightStatement() == QLatin1String("(C) 2026 Krema Contributors"));
    REQUIRE(aboutData.licenses().size() == 1);
    CHECK(aboutData.licenses().constFirst().key() == KAboutLicense::GPL_V3);
    CHECK(aboutData.licenses().constFirst().spdx().startsWith(QLatin1String("GPL-3.0")));
    CHECK(aboutData.licenses().constFirst().text().contains(QLatin1String("GNU GENERAL PUBLIC LICENSE")));

    const QList<KAboutPerson> authors = aboutData.authors();
    REQUIRE(authors.size() == 2);
    CHECK(authors.at(0).name() == QLatin1String("thicking"));
    CHECK(authors.at(0).task() == QLatin1String("Developer and maintainer; author of KDockW's independent direction"));
    CHECK(authors.at(0).webAddress() == QLatin1String("https://github.com/thicking"));
    CHECK(authors.at(0).emailAddress().isEmpty());
    CHECK(authors.at(1).name() == QLatin1String("Byeonghoon Yoo"));
    CHECK(authors.at(1).task() == QLatin1String("Original author of Krema, the project KDockW is based on"));
    CHECK(authors.at(1).webAddress() == QLatin1String("https://github.com/isac322/krema"));

    CHECK(aboutData.programLogo().canConvert<QIcon>());
}

TEST_CASE("KAboutData identity strings follow KI18n without translating KDE-owned About labels", "[about][i18n]")
{
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
    kdockw::Application::applyLanguagePreference(QStringLiteral("en"));
    const KAboutData english = kdockw::Application::makeAboutData();
    REQUIRE(english.authors().size() == 2);
    CHECK(english.shortDescription() == QLatin1String("KDE Dock for Wayland"));
    CHECK(english.authors().at(0).task() == QLatin1String("Developer and maintainer; author of KDockW's independent direction"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("ru"));
    const KAboutData russian = kdockw::Application::makeAboutData();
    REQUIRE(russian.authors().size() == 2);
    CHECK(russian.shortDescription() == QStringLiteral("Док-панель KDE для Wayland"));
    CHECK(russian.authors().at(0).task() == QStringLiteral("Разработчик и сопровождающий; автор самостоятельного направления KDockW"));
    CHECK(russian.authors().at(1).task() == QStringLiteral("Первоначальный автор Krema, проекта, на котором основан KDockW"));

    kdockw::Application::applyLanguagePreference(QStringLiteral("system"));
}
