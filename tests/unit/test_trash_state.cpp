// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/trashstate.h"

#include <catch2/catch_test_macros.hpp>

#include <KConfig>
#include <KConfigGroup>

#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

namespace
{

/// Points XDG_CONFIG_HOME at a temporary directory so trashrc is a test file.
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

/// Writes trashrc the way the KIO trash worker does.
void writeTrashStatus(bool empty)
{
    KConfig config(QStringLiteral("trashrc"), KConfig::SimpleConfig);
    config.group(QStringLiteral("Status")).writeEntry("Empty", empty);
    config.sync();
}

} // namespace

TEST_CASE("Trash state is empty when trashrc does not exist yet", "[trash][dock-widgets]")
{
    const ScopedConfigHome home;
    const kdockw::TrashState trash;
    CHECK(trash.isEmpty());
}

TEST_CASE("Trash state reads and follows KIO's trashrc status", "[trash][dock-widgets]")
{
    const ScopedConfigHome home;
    writeTrashStatus(false);

    kdockw::TrashState trash;
    CHECK_FALSE(trash.isEmpty());

    QSignalSpy changed(&trash, &kdockw::TrashState::emptyChanged);
    writeTrashStatus(true);
    trash.refresh();
    CHECK(trash.isEmpty());
    CHECK(changed.count() == 1);

    trash.refresh();
    CHECK(changed.count() == 1); // no signal when the status did not change
}

TEST_CASE("Trash state notices trashrc rewrites without a manual refresh", "[trash][dock-widgets]")
{
    const ScopedConfigHome home;
    kdockw::TrashState trash;
    REQUIRE(trash.isEmpty());

    // trashrc is created by the first trash operation, then rewritten.
    writeTrashStatus(false);
    QTRY_VERIFY_WITH_TIMEOUT(!trash.isEmpty(), 5000);
    writeTrashStatus(true);
    QTRY_VERIFY_WITH_TIMEOUT(trash.isEmpty(), 5000);
}
