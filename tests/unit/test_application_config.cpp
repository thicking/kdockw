// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "config/applicationconfig.h"
#include "kdockw.h"

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
    settings.save();

    KDockWSettings restarted;
    restarted.setSharedConfig(kdockw::applicationConfig());
    restarted.load();
    CHECK(restarted.iconSize() == 52);
    CHECK(QFileInfo::exists(configPath));

    ScopedEnvironmentVariable taskDiagnostics("KDOCKW_TASK_DIAGNOSTICS", QByteArrayLiteral("1"));
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
