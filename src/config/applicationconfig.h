// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <KSharedConfig>

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace kdockw
{

inline QString diagnosticConfigPath()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    static const QString path = [] {
        const QString value = qEnvironmentVariable("KDOCKW_DIAGNOSTIC_CONFIG");
        return !value.isEmpty() && QFileInfo(value).isAbsolute() ? value : QString{};
    }();
    return path;
#endif
    return {};
}

inline bool diagnosticTaskLoggingEnabled()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (const auto *app = QCoreApplication::instance()) {
        return app->property("kdockw.taskDiagnosticsEnabled").toBool();
    }
    return qEnvironmentVariableIntValue("KDOCKW_TASK_DIAGNOSTICS") == 1;
#else
    return false;
#endif
}

inline bool diagnosticReleaseMockModeEnabled()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    static const bool enabled = qEnvironmentVariableIntValue("KDOCKW_DIAGNOSTIC_RELEASE_MOCK") == 1;
    return enabled;
#else
    return false;
#endif
}

inline QUrl diagnosticReleaseMockApiUrl()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    static const QUrl url = [] {
        const QUrl candidate(qEnvironmentVariable("KDOCKW_DIAGNOSTIC_RELEASE_API_URL"), QUrl::StrictMode);
        const bool loopback = candidate.host() == QLatin1String("127.0.0.1") || candidate.host() == QLatin1String("::1");
        if (!candidate.isValid() || candidate.scheme() != QLatin1String("http") || !loopback || candidate.port(-1) < 1
            || !candidate.userInfo().isEmpty() || !candidate.query().isEmpty() || !candidate.fragment().isEmpty()
            || candidate.path() != QLatin1String("/repos/thicking/kdockw/releases")) {
            return QUrl{};
        }
        return candidate;
    }();
    return url;
#else
    return {};
#endif
}

inline QString diagnosticReleaseOpenLogPath()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    static const QString path = [] {
        const QString value = qEnvironmentVariable("KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG");
        return QFileInfo(value).isAbsolute() ? value : QString{};
    }();
    return path;
#else
    return {};
#endif
}

inline void clearDiagnosticLaunchEnvironment()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    // Diagnostic config, logging, and local release-mock options are consumed
    // and cached before models or launch actions are created. Remove them from
    // the process environment so applications started through KIO cannot
    // inherit diagnostic-only settings.
    qunsetenv("KDOCKW_DIAGNOSTIC_CONFIG");
    qunsetenv("KDOCKW_TASK_DIAGNOSTICS");
    qunsetenv("KDOCKW_DIAGNOSTIC_RELEASE_MOCK");
    qunsetenv("KDOCKW_DIAGNOSTIC_RELEASE_API_URL");
    qunsetenv("KDOCKW_DIAGNOSTIC_RELEASE_OPEN_LOG");
#endif
}

/**
 * Open KDockW's settings. Diagnostic builds may redirect only this file via
 * KDOCKW_DIAGNOSTIC_CONFIG; the Plasma/XDG environment remains untouched.
 */
inline KSharedConfig::Ptr applicationConfig()
{
    const QString path = diagnosticConfigPath();
    if (!path.isEmpty()) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        return KSharedConfig::openConfig(path, KConfig::SimpleConfig);
    }
    return KSharedConfig::openConfig(QStringLiteral("kdockwrc"));
}

} // namespace kdockw
