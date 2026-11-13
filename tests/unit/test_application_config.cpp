// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "config/applicationconfig.h"
#include "kdockw.h"
#include "models/icondiag.h"

#include <catch2/catch_test_macros.hpp>

#include <QTemporaryDir>

namespace
{
class ScopedEnvironmentVariable
{
public:
    ScopedEnvironmentVariable(const char *name, const QByteArray &value)
        : m_name(name)
        , m_wasSet(qEnvironmentVariableIsSet(name))
        , m_previous(qgetenv(name))
    {
        qputenv(name, value);
    }
    ~ScopedEnvironmentVariable()
    {
        if (m_wasSet) {
            qputenv(m_name.constData(), m_previous);
        } else {
            qunsetenv(m_name.constData());
        }
    }

private:
    QByteArray m_name;
    bool m_wasSet;
    QByteArray m_previous;
};
}

TEST_CASE("Diagnostic settings use one file without changing the Plasma environment", "[settings][diagnostic]")
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    const QString configPath = directory.filePath(QStringLiteral("isolated/kdockwrc"));
    const QByteArray oldConfigHome = qgetenv("XDG_CONFIG_HOME");
    const bool hadConfigHome = qEnvironmentVariableIsSet("XDG_CONFIG_HOME");
    ScopedEnvironmentVariable diagnosticPath("KDOCKW_DIAGNOSTIC_CONFIG", configPath.toLocal8Bit());

    const auto config = kdockw::applicationConfig();
    REQUIRE(config);
    CHECK(config->name() == configPath);
    CHECK(qgetenv("XDG_CONFIG_HOME") == oldConfigHome);
    CHECK(qEnvironmentVariableIsSet("XDG_CONFIG_HOME") == hadConfigHome);

    KDockWSettings settings;
    settings.setSharedConfig(config);
    settings.load();
    settings.setIconSize(52);
    settings.setReleasesApiETag(QStringLiteral("\"isolated-etag\""));
    settings.setLastSuccessfulUpdateCheck(QStringLiteral("2026-11-07T00:00:00.000Z"));
    settings.setLastAutomaticUpdateAttempt(QStringLiteral("2026-11-07T00:00:01.000Z"));
    settings.setCachedReleaseVersion(QStringLiteral("0.3.1"));
    settings.setCachedReleaseUrl(QStringLiteral("https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.1"));
    settings.setLastNotifiedReleaseVersion(QStringLiteral("0.3.1"));
    settings.setReleaseApiRetryAfter(QStringLiteral("2026-11-07T01:00:00.000Z"));
    settings.save();

    KDockWSettings restarted;
    restarted.setSharedConfig(kdockw::applicationConfig());
    restarted.load();
    CHECK(restarted.iconSize() == 52);
    CHECK(restarted.releasesApiETag() == QLatin1String("\"isolated-etag\""));
    CHECK(restarted.lastSuccessfulUpdateCheck() == QLatin1String("2026-11-07T00:00:00.000Z"));
    CHECK(restarted.lastAutomaticUpdateAttempt() == QLatin1String("2026-11-07T00:00:01.000Z"));
    CHECK(restarted.cachedReleaseVersion() == QLatin1String("0.3.1"));
    CHECK(restarted.lastNotifiedReleaseVersion() == QLatin1String("0.3.1"));
    CHECK(restarted.releaseApiRetryAfter() == QLatin1String("2026-11-07T01:00:00.000Z"));
    CHECK(QFileInfo::exists(configPath));

    ScopedEnvironmentVariable taskDiagnostics("KDOCKW_TASK_DIAGNOSTICS", QByteArrayLiteral("1"));
    kdockw::IconDiagnostics::prepareProcessEnvironment();
    CHECK(kdockw::diagnosticTaskLoggingEnabled());
    kdockw::clearDiagnosticLaunchEnvironment();
    CHECK_FALSE(qEnvironmentVariableIsSet("KDOCKW_DIAGNOSTIC_CONFIG"));
    CHECK_FALSE(qEnvironmentVariableIsSet("KDOCKW_TASK_DIAGNOSTICS"));
    CHECK(kdockw::diagnosticTaskLoggingEnabled());
    CHECK(kdockw::applicationConfig()->name() == configPath);
#else
    SUCCEED("Diagnostic configuration routing is compiled only in diagnostic builds");
#endif
}

TEST_CASE("Production builds ignore diagnostic release API environment overrides", "[settings][diagnostic][updates]")
{
#ifndef KDOCKW_DIAGNOSTIC_BUILD
    ScopedEnvironmentVariable mockMode("KDOCKW_DIAGNOSTIC_RELEASE_MOCK", QByteArrayLiteral("1"));
    ScopedEnvironmentVariable apiUrl("KDOCKW_DIAGNOSTIC_RELEASE_API_URL", QByteArrayLiteral("http://127.0.0.1:43210/repos/thicking/kdockw/releases"));
    ScopedEnvironmentVariable openLog("KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG", QByteArrayLiteral("/tmp/should-not-be-read.log"));
    CHECK_FALSE(kdockw::diagnosticReleaseMockModeEnabled());
    CHECK(kdockw::diagnosticReleaseMockApiUrl().isEmpty());
    CHECK(kdockw::diagnosticReleaseOpenLogPath().isEmpty());
#else
    SUCCEED("Production environment override gate is checked in production builds");
#endif
}

TEST_CASE("Badge colors default to the approved palette and persist independently", "[settings][badges]")
{
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    const QString configPath = directory.filePath(QStringLiteral("kdockwrc"));
    const auto config = KSharedConfig::openConfig(configPath, KConfig::SimpleConfig);

    KDockWSettings settings;
    settings.setSharedConfig(config);
    settings.load();
    CHECK(settings.badgeBackgroundColor() == QStringLiteral("#ffff3b30"));
    CHECK(settings.badgeTextColor() == QStringLiteral("#ffffffff"));

    settings.setBadgeBackgroundColor(QStringLiteral("#ff123456"));
    settings.setBadgeTextColor(QStringLiteral("#ffabcdef"));
    settings.save();

    KDockWSettings restarted;
    restarted.setSharedConfig(KSharedConfig::openConfig(configPath, KConfig::SimpleConfig));
    restarted.load();
    CHECK(restarted.badgeBackgroundColor() == QStringLiteral("#ff123456"));
    CHECK(restarted.badgeTextColor() == QStringLiteral("#ffabcdef"));
}
