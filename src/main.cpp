// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "app/application.h"
#include "config/applicationconfig.h"
#include "models/icondiag.h"

#include <KAboutData>
#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QStringList>

int main(int argc, char *argv[])
{
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));

    // QApplication cannot be created before headless --help/--version checks.
    // Keep this parser metadata untranslated until the real application exists.
    KAboutData aboutData = kdockw::Application::makeAboutData(false);
    // QCommandLineParser builds --version's output and its error prefix from
    // these; set them directly because no QApplication exists yet
    // (Application::run() installs the KAboutData itself).
    QCoreApplication::setApplicationName(aboutData.componentName());
    QCoreApplication::setApplicationVersion(aboutData.version());
    QCommandLineParser parser;
    // setupCommandLine adds --help, --author, --license and --desktopfile, but
    // the version option only once an instance exists.
    const QCommandLineOption versionOption = parser.addVersionOption();
    aboutData.setupCommandLine(&parser);

    // Pass 1, before QApplication: its constructor aborts without a display,
    // yet --help/--version/--author/--license must work headless (package
    // smoke checks) and before KDBusService hands the call to a running
    // instance. Tolerant: Qt's own options are still in argv here, and are
    // read as words so that e.g. -reverse is not taken for -v.
    QStringList arguments;
    arguments.reserve(argc);
    for (int i = 0; i < argc; ++i) {
        arguments.append(QString::fromLocal8Bit(argv[i]));
    }
    parser.setSingleDashWordOptionMode(QCommandLineParser::ParseAsLongOptions);
    (void)parser.parse(arguments); // unknown options are reported by pass 2
    if (parser.isSet(QStringLiteral("help"))) {
        parser.showHelp();
    }
    if (parser.isSet(versionOption)) {
        parser.showVersion();
    }
    // --author/--license print and exit. Only these: processCommandLine also
    // applies --desktopfile through setApplicationData, which needs the
    // instance and is left to pass 2.
    if (parser.isSet(QStringLiteral("author")) || parser.isSet(QStringLiteral("license"))) {
        aboutData.processCommandLine(&parser);
    }

    kdockw::Application app(argc, argv);
    // Let KI18n hook the Q*Application instance for runtime language-change
    // notifications; the earlier call also supports headless metadata setup.
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
    // Now KI18n has a Q*Application instance and can load catalogs reliably.
    // KI18n installs catalogs under the system locale directory. Also expose
    // the build-tree catalog so `build/release/bin/kdockw` can run directly.
    const QDir appDir(QCoreApplication::applicationDirPath());
    const QString buildLocaleDir = appDir.filePath(QStringLiteral("../src/locale"));
    if (QDir(buildLocaleDir).exists()) {
        KLocalizedString::addDomainLocaleDir(QByteArrayLiteral("kdockw"), buildLocaleDir);
    }
    const KConfigGroup general(kdockw::applicationConfig(), QStringLiteral("General"));
    kdockw::Application::applyLanguagePreference(general.readEntry(QStringLiteral("Language"), QStringLiteral("system")));
    (void)kdockw::diagnosticTaskLoggingEnabled();
    kdockw::IconDiagnostics::prepareProcessEnvironment();
    kdockw::clearDiagnosticLaunchEnvironment();
    aboutData = kdockw::Application::makeAboutData();
    // Pass 2: QApplication has removed its own options; anything left that
    // the parser does not know is an error.
    parser.setSingleDashWordOptionMode(QCommandLineParser::ParseAsCompactedShortOptions);
    parser.process(app);
    aboutData.processCommandLine(&parser); // applies --desktopfile to aboutData
    return app.run(aboutData);
}
