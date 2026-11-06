// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <KSharedConfig>

#include <QDir>
#include <QFileInfo>

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
    static const bool enabled = qEnvironmentVariableIntValue("KDOCKW_TASK_DIAGNOSTICS") == 1;
    return enabled;
#else
    return false;
#endif
}

inline void clearDiagnosticLaunchEnvironment()
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    // The explicit config path and logging opt-in are consumed and cached by
    // KDockW before its models or launch actions are created. Remove them from
    // the process environment so applications started through KIO cannot
    // inherit diagnostic-only settings.
    qunsetenv("KDOCKW_DIAGNOSTIC_CONFIG");
    qunsetenv("KDOCKW_TASK_DIAGNOSTICS");
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
