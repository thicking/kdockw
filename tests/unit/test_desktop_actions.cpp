// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/desktopactions.h"

#include <catch2/catch_test_macros.hpp>

#include <KService>
#include <KServiceAction>

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>

namespace
{

QString writeDesktopFile(const QString &directory, const QString &fileName, const QByteArray &contents)
{
    REQUIRE(QDir().mkpath(directory));
    const QString path = directory + QLatin1Char('/') + fileName;
    QFile file(path);
    REQUIRE(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    REQUIRE(file.write(contents) == contents.size());
    file.close();
    return path;
}

QStringList actionNames(const QList<KServiceAction> &actions)
{
    QStringList names;
    for (const KServiceAction &action : actions) {
        names << (action.isSeparator() ? QStringLiteral("|") : action.name());
    }
    return names;
}

// Actions are listed out of alphabetical and group order on purpose: the menu
// must follow the Actions= key, the order the desktop file declares.
const QByteArray browserEntry =
    "[Desktop Entry]\n"
    "Type=Application\n"
    "Name=KDockW Fixture Browser\n"
    "Exec=kdockw-fixture-browser %u\n"
    "Icon=kdockw-fixture-browser\n"
    "Actions=new-window;hidden;new-private-window;\n"
    "\n"
    "[Desktop Action new-private-window]\n"
    "Name=New Private Window\n"
    "Name[de]=Neues privates Fenster\n"
    "Exec=kdockw-fixture-browser --private-window %u\n"
    "\n"
    "[Desktop Action hidden]\n"
    "Name=Hidden Action\n"
    "Exec=kdockw-fixture-browser --hidden\n"
    "NoDisplay=true\n"
    "\n"
    "[Desktop Action new-window]\n"
    "Name=New Window\n"
    "Name[de]=Neues Fenster\n"
    "Icon=window-new\n"
    "Exec=kdockw-fixture-browser --new-window %u\n";

} // namespace

TEST_CASE("Desktop actions follow the declared order and skip hidden ones", "[desktopactions]")
{
    // The fixture also has German names: pin the untranslated locale, the
    // same way the i18n case below selects German, so the English labels
    // hold whatever locale the developer runs ctest in.
    qunsetenv("LANGUAGE");
    qputenv("LC_ALL", "C");
    qputenv("LANG", "C");

    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    // An absolute path outside every XDG applications directory, like a
    // launcher pinned from an arbitrary location.
    const QString path = writeDesktopFile(dir.path(), QStringLiteral("kdockw-fixture-browser.desktop"), browserEntry);

    const QList<KServiceAction> actions = kdockw::desktopActions(QUrl::fromLocalFile(path));

    REQUIRE(actionNames(actions) == QStringList{QStringLiteral("new-window"), QStringLiteral("new-private-window")});
    REQUIRE(actions.at(0).text() == QStringLiteral("New Window"));
    REQUIRE(actions.at(0).icon() == QStringLiteral("window-new"));
    REQUIRE(actions.at(0).exec() == QStringLiteral("kdockw-fixture-browser --new-window %u"));
    // An action without an Icon key is still offered.
    REQUIRE(actions.at(1).text() == QStringLiteral("New Private Window"));
    REQUIRE(actions.at(1).icon().isEmpty());
    // Each action keeps its application, so launching it does not depend on
    // the task row that opened the menu.
    REQUIRE(actions.at(1).service());
    REQUIRE(actions.at(1).service()->entryPath() == path);
}

TEST_CASE("Desktop actions use the localized action names", "[desktopactions][i18n]")
{
    // KConfig picks the desktop-file locale from the environment on first use.
    qputenv("LANGUAGE", "de");
    qputenv("LC_ALL", "de_DE.UTF-8");
    qputenv("LANG", "de_DE.UTF-8");

    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const QString path = writeDesktopFile(dir.path(), QStringLiteral("kdockw-fixture-browser.desktop"), browserEntry);

    const QList<KServiceAction> actions = kdockw::desktopActions(QUrl::fromLocalFile(path));

    REQUIRE(actions.size() == 2);
    REQUIRE(actions.at(0).text() == QStringLiteral("Neues Fenster"));
    REQUIRE(actions.at(1).text() == QStringLiteral("Neues privates Fenster"));
}

TEST_CASE("Desktop actions keep inner separators only", "[desktopactions]")
{
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const QString path = writeDesktopFile(dir.path(),
                                          QStringLiteral("kdockw-fixture-separators.desktop"),
                                          "[Desktop Entry]\n"
                                          "Type=Application\n"
                                          "Name=KDockW Fixture Separators\n"
                                          "Exec=kdockw-fixture-separators\n"
                                          "Actions=_SEPARATOR_;first;hidden;_SEPARATOR_;_SEPARATOR_;second;_SEPARATOR_;\n"
                                          "\n"
                                          "[Desktop Action first]\n"
                                          "Name=First\n"
                                          "Exec=kdockw-fixture-separators --first\n"
                                          "\n"
                                          "[Desktop Action hidden]\n"
                                          "Name=Hidden\n"
                                          "Exec=kdockw-fixture-separators --hidden\n"
                                          "NoDisplay=true\n"
                                          "\n"
                                          "[Desktop Action second]\n"
                                          "Name=Second\n"
                                          "Exec=kdockw-fixture-separators --second\n");

    const QList<KServiceAction> actions = kdockw::desktopActions(QUrl::fromLocalFile(path));

    REQUIRE(actionNames(actions) == QStringList{QStringLiteral("first"), QStringLiteral("|"), QStringLiteral("second")});
}

TEST_CASE("Desktop actions are empty when the entry offers none", "[desktopactions]")
{
    QTemporaryDir dir;
    REQUIRE(dir.isValid());

    const QString plain = writeDesktopFile(dir.path(),
                                           QStringLiteral("kdockw-fixture-plain.desktop"),
                                           "[Desktop Entry]\n"
                                           "Type=Application\n"
                                           "Name=KDockW Fixture Plain\n"
                                           "Exec=kdockw-fixture-plain\n");
    REQUIRE(kdockw::desktopActions(QUrl::fromLocalFile(plain)).isEmpty());

    // Only hidden actions and separators: nothing to show.
    const QString hiddenOnly = writeDesktopFile(dir.path(),
                                                QStringLiteral("kdockw-fixture-hidden.desktop"),
                                                "[Desktop Entry]\n"
                                                "Type=Application\n"
                                                "Name=KDockW Fixture Hidden\n"
                                                "Exec=kdockw-fixture-hidden\n"
                                                "Actions=hidden;_SEPARATOR_;\n"
                                                "\n"
                                                "[Desktop Action hidden]\n"
                                                "Name=Hidden\n"
                                                "Exec=kdockw-fixture-hidden --hidden\n"
                                                "NoDisplay=true\n");
    REQUIRE(kdockw::desktopActions(QUrl::fromLocalFile(hiddenOnly)).isEmpty());

    // Launchers that do not resolve to an application.
    REQUIRE(kdockw::desktopActions(QUrl()).isEmpty());
    REQUIRE(kdockw::desktopActions(QUrl::fromLocalFile(dir.path() + QStringLiteral("/missing.desktop"))).isEmpty());
    REQUIRE(kdockw::desktopActions(QUrl::fromLocalFile(dir.path() + QStringLiteral("/kdockw-fixture-plain.txt"))).isEmpty());
    REQUIRE(kdockw::desktopActions(QUrl(QStringLiteral("applications:kdockw-fixture-not-installed.desktop"))).isEmpty());
    REQUIRE(kdockw::desktopActions(QUrl(QStringLiteral("https://example.org/app.desktop"))).isEmpty());
}

TEST_CASE("Desktop actions resolve installed and user-local applications", "[desktopactions][sycoca]")
{
    // A private XDG tree: KSycoca builds its database from it on first use.
    QTemporaryDir root;
    REQUIRE(root.isValid());
    const QString dataHome = root.path() + QStringLiteral("/data-home");
    const QString dataDir = root.path() + QStringLiteral("/data-dir");
    REQUIRE(QDir().mkpath(root.path() + QStringLiteral("/cache")));
    qputenv("XDG_DATA_HOME", dataHome.toLocal8Bit());
    qputenv("XDG_DATA_DIRS", dataDir.toLocal8Bit());
    qputenv("XDG_CACHE_HOME", (root.path() + QStringLiteral("/cache")).toLocal8Bit());
    qputenv("XDG_CONFIG_HOME", (root.path() + QStringLiteral("/config")).toLocal8Bit());

    // System-wide (XDG_DATA_DIRS) and user-local (~/.local/share/applications).
    const QString installed = writeDesktopFile(dataDir + QStringLiteral("/applications"), QStringLiteral("kdockw-fixture-browser.desktop"), browserEntry);
    const QString local = writeDesktopFile(dataHome + QStringLiteral("/applications"),
                                           QStringLiteral("kdockw-fixture-local.desktop"),
                                           "[Desktop Entry]\n"
                                           "Type=Application\n"
                                           "Name=KDockW Fixture Local\n"
                                           "Exec=kdockw-fixture-local\n"
                                           "Actions=compose;\n"
                                           "\n"
                                           "[Desktop Action compose]\n"
                                           "Name=Compose\n"
                                           "Icon=mail-message-new\n"
                                           "Exec=kdockw-fixture-local --compose\n");

    // TaskManager reports installed applications as applications: URLs and
    // others as file URLs; both must resolve.
    const QList<KServiceAction> byMenuId = kdockw::desktopActions(QUrl(QStringLiteral("applications:kdockw-fixture-browser.desktop")));
    REQUIRE(actionNames(byMenuId) == QStringList{QStringLiteral("new-window"), QStringLiteral("new-private-window")});
    REQUIRE(byMenuId.at(0).service()->entryPath() == installed);

    const QList<KServiceAction> byPath = kdockw::desktopActions(QUrl::fromLocalFile(installed));
    REQUIRE(actionNames(byPath) == QStringList{QStringLiteral("new-window"), QStringLiteral("new-private-window")});

    const QList<KServiceAction> userLocal = kdockw::desktopActions(QUrl(QStringLiteral("applications:kdockw-fixture-local.desktop")));
    REQUIRE(actionNames(userLocal) == QStringList{QStringLiteral("compose")});
    REQUIRE(userLocal.at(0).icon() == QStringLiteral("mail-message-new"));
    REQUIRE(userLocal.at(0).service()->entryPath() == local);
    REQUIRE(actionNames(kdockw::desktopActions(QUrl::fromLocalFile(local))) == QStringList{QStringLiteral("compose")});
}
