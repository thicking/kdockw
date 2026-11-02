// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_session.hpp>

#include <QApplication>
#include <QByteArray>
#include <QString>

int main(int argc, char *argv[])
{
    // Catch2 discovery launches each case as its own process. Set locale before
    // QApplication caches QLocale so the desktop-action locale test is stable.
    bool germanDesktopActionCase = false;
    for (int i = 1; i < argc; ++i) {
        germanDesktopActionCase |= QString::fromLocal8Bit(argv[i]).contains(QStringLiteral("localized action names"));
    }
    qputenv("LANGUAGE", germanDesktopActionCase ? QByteArrayLiteral("de") : QByteArrayLiteral("C"));
    qputenv("LC_ALL", germanDesktopActionCase ? QByteArrayLiteral("de_DE.UTF-8") : QByteArrayLiteral("C"));
    qputenv("LANG", germanDesktopActionCase ? QByteArrayLiteral("de_DE.UTF-8") : QByteArrayLiteral("C"));

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kdockw-unit-tests"));
    return Catch::Session().run(argc, argv);
}
