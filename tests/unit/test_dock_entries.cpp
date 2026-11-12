// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "app/application.h"
#include "kdockw.h"
#include "models/dockentry.h"

#include <catch2/catch_test_macros.hpp>

#include <KConfig>
#include <KConfigGroup>

#include <QTemporaryDir>

namespace
{

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

    [[nodiscard]] QString configFilePath() const
    {
        return m_dir.filePath(QStringLiteral("kdockwrc"));
    }

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};

} // namespace

TEST_CASE("Typed dock entries round-trip in order with explicit types", "[dock-entries]")
{
    const QUrl dolphin(QStringLiteral("applications:org.kde.dolphin.desktop"));
    const QUrl folder = QUrl::fromLocalFile(QStringLiteral("/home/test/Downloads"));
    const QList<kdockw::DockEntry> entries{
        kdockw::DockEntry::task(dolphin),
        kdockw::DockEntry::folderStack(folder),
        kdockw::DockEntry::folderStack(folder),
    };

    const auto decoded = kdockw::DockEntriesCodec::decode(kdockw::DockEntriesCodec::encode(entries));
    REQUIRE(decoded.validDocument);
    REQUIRE(decoded.entries.size() == 3);
    CHECK(decoded.entries.at(0).type == kdockw::DockEntryType::Task);
    CHECK(decoded.entries.at(0).url == dolphin);
    CHECK(decoded.entries.at(0).id == kdockw::DockEntry::task(dolphin).id);
    CHECK(decoded.entries.at(1).type == kdockw::DockEntryType::FolderStack);
    CHECK(decoded.entries.at(1).url == folder);
    CHECK(decoded.entries.at(2).type == kdockw::DockEntryType::FolderStack);
    CHECK(decoded.entries.at(1).id != decoded.entries.at(2).id);
}

TEST_CASE("Typed dock entry decoding rejects unsupported documents and malformed entries", "[dock-entries]")
{
    CHECK_FALSE(kdockw::DockEntriesCodec::decode(QStringLiteral("not-json")).validDocument);
    CHECK_FALSE(kdockw::DockEntriesCodec::decode(QStringLiteral(R"({"version":99,"entries":[]})")).validDocument);

    const QString serialized = QStringLiteral(
        R"({"version":1,"entries":[{"id":"task:wrong","type":"task","url":"applications:org.kde.dolphin.desktop"},{"id":"folder:00000000-0000-0000-0000-000000000001","type":"folderStack","url":"smb://server/share"}]})");
    const auto decoded = kdockw::DockEntriesCodec::decode(serialized);
    REQUIRE(decoded.validDocument);
    CHECK(decoded.entries.isEmpty());
}

TEST_CASE("Folder icon choice persists by stable entry ID and version 1 entries migrate", "[dock-entries][migration]")
{
    const QUrl folder = QUrl::fromLocalFile(QStringLiteral("/home/test/Projects"));
    auto stack = kdockw::DockEntry::folderStack(folder);
    stack.iconName = QStringLiteral("folder-development");
    const auto themeEncoded = kdockw::DockEntriesCodec::encode({stack});
    const auto themeDecoded = kdockw::DockEntriesCodec::decode(themeEncoded);
    REQUIRE(themeDecoded.validDocument);
    REQUIRE(themeDecoded.entries.size() == 1);
    CHECK(themeDecoded.entries.first().id == stack.id);
    CHECK(themeDecoded.entries.first().iconName == QStringLiteral("folder-development"));
    CHECK(themeDecoded.entries.first().iconUrl.isEmpty());

    const QUrl image = QUrl::fromLocalFile(QStringLiteral("/home/test/folder.png"));
    stack = themeDecoded.entries.first();
    stack.iconName.clear();
    stack.iconUrl = image;

    const auto encoded = kdockw::DockEntriesCodec::encode({stack});
    const auto decoded = kdockw::DockEntriesCodec::decode(encoded);
    REQUIRE(decoded.validDocument);
    REQUIRE(decoded.entries.size() == 1);
    CHECK(decoded.entries.first().id == stack.id);
    CHECK(decoded.entries.first().iconUrl == image);
    CHECK(decoded.entries.first().iconName.isEmpty());

    const QString legacy = QStringLiteral(
        R"({"version":1,"entries":[{"id":"folder:00000000-0000-0000-0000-000000000001","type":"folderStack","url":"file:///home/test/Projects"}]})");
    const auto migrated = kdockw::DockEntriesCodec::decode(legacy);
    REQUIRE(migrated.validDocument);
    REQUIRE(migrated.entries.size() == 1);
    CHECK(migrated.entries.first().iconName.isEmpty());
    CHECK(migrated.entries.first().iconUrl.isEmpty());
    CHECK(kdockw::DockEntriesCodec::decode(kdockw::DockEntriesCodec::encode(migrated.entries)).validDocument);
}

TEST_CASE("Legacy launcher migration preserves order and existing launcher settings", "[dock-entries][migration]")
{
    const ScopedConfigHome home;
    const QStringList launchers{
        QStringLiteral("applications:org.kde.dolphin.desktop"),
        QStringLiteral("preferred://browser"),
    };

    KDockWSettings settings;
    settings.load();
    settings.setPinnedLaunchers(launchers);
    settings.save();
    kdockw::Application::migrateLegacySettings(&settings);

    CHECK(settings.pinnedLaunchers() == launchers);
    const auto migrated = kdockw::DockEntriesCodec::decode(settings.dockEntries());
    REQUIRE(migrated.validDocument);
    REQUIRE(migrated.entries.size() == 2);
    CHECK(migrated.entries.at(0).type == kdockw::DockEntryType::Task);
    CHECK(migrated.entries.at(0).url.toString() == launchers.at(0));
    CHECK(migrated.entries.at(1).url.toString() == launchers.at(1));

    KConfig stored(home.configFilePath(), KConfig::SimpleConfig);
    const KConfigGroup group = stored.group(QStringLiteral("General"));
    CHECK(group.hasKey(QStringLiteral("PinnedLaunchers")));
    CHECK(group.hasKey(QStringLiteral("DockEntries")));

    const QString migratedOnce = settings.dockEntries();
    settings.setPinnedLaunchers({QStringLiteral("applications:org.kde.kate.desktop")});
    kdockw::Application::migrateLegacySettings(&settings);
    CHECK(settings.dockEntries() == migratedOnce);
}

TEST_CASE("An existing empty typed list wins over the legacy launcher list", "[dock-entries][migration]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();
    settings.setPinnedLaunchers({QStringLiteral("applications:org.kde.dolphin.desktop")});
    settings.setDockEntries(kdockw::DockEntriesCodec::encode({}));
    settings.save();

    kdockw::Application::migrateLegacySettings(&settings);

    const auto typedEntries = kdockw::DockEntriesCodec::decode(settings.dockEntries());
    REQUIRE(typedEntries.validDocument);
    CHECK(typedEntries.entries.isEmpty());
    CHECK(settings.pinnedLaunchers() == QStringList{QStringLiteral("applications:org.kde.dolphin.desktop")});
}

TEST_CASE("Legacy migration ignores malformed URLs and keeps an empty explicit list", "[dock-entries][migration]")
{
    const auto migrated = kdockw::DockEntriesCodec::fromLegacyLaunchers({
        QStringLiteral("applications:org.kde.dolphin.desktop"),
        QStringLiteral("not a URL"),
        QStringLiteral("applications:org.kde.dolphin.desktop"),
    });
    REQUIRE(migrated.size() == 1);
    CHECK(migrated.first().type == kdockw::DockEntryType::Task);

    const auto empty = kdockw::DockEntriesCodec::decode(kdockw::DockEntriesCodec::encode({}));
    REQUIRE(empty.validDocument);
    CHECK(empty.entries.isEmpty());
}
