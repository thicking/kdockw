// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// KDockW 0.10 stored a single ZoomAnimationDuration (applied with OutCubic in
// both directions). Application::migrateLegacySettings() must carry a
// customised value over to the Custom zoom animation preset with the same
// feel, and leave untouched configurations on the Natural default.

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>

#include <KConfig>
#include <KConfigGroup>

#include <QDir>
#include <QFile>
#include <QTemporaryDir>

namespace
{

const QString kGroup = QStringLiteral("General");
const QString kLegacyKey = QStringLiteral("ZoomAnimationDuration");
const QString kPresetKey = QStringLiteral("ZoomAnimationPreset");

constexpr int kNaturalPreset = 0;
constexpr int kQuickPreset = 1;
constexpr int kCustomPreset = 4;
constexpr int kEaseOut = 2;
constexpr int kEaseInOut = 3;

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

    QString kdockwrcPath() const
    {
        return QDir(m_dir.path()).filePath(QStringLiteral("kdockwrc"));
    }

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};

// Writes kdockwrc as an older KDockW release would have left it.
void writeKDockWrc(const ScopedConfigHome &home, const QByteArray &generalEntries)
{
    QFile file(home.kdockwrcPath());
    REQUIRE(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write("[General]\n");
    file.write(generalEntries);
    file.close();
}

// The [General] group as stored on disk, independent of KDockWSettings.
KConfigGroup storedGroup(KConfig &config)
{
    return config.group(kGroup);
}

} // namespace

TEST_CASE("Legacy zoom animation duration migrates to the Custom preset", "[settings][migration]")
{
    const auto [legacy, expected] = GENERATE(table<int, int>({
        {0, 0},
        {400, 400},
        {1000, 1000},
        {5000, 1000}, // hand-edited out-of-range value is clamped
    }));
    INFO("legacy ZoomAnimationDuration=" << legacy);

    const ScopedConfigHome home;
    writeKDockWrc(home, "ZoomAnimationDuration=" + QByteArray::number(legacy) + "\nIconSize=56\n");

    {
        KDockWSettings settings;
        settings.load();
        kdockw::Application::migrateLegacySettings(&settings);

        CHECK(settings.zoomAnimationPreset() == kCustomPreset);
        CHECK(settings.zoomInDuration() == expected);
        CHECK(settings.zoomOutDuration() == expected);
        CHECK(settings.zoomInEasing() == kEaseOut);
        CHECK(settings.zoomOutEasing() == kEaseOut);
        CHECK(settings.iconSize() == 56);
    }

    // The migration is saved: a restarted KDockW sees the Custom preset...
    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.zoomAnimationPreset() == kCustomPreset);
    CHECK(restarted.zoomInDuration() == expected);
    CHECK(restarted.zoomOutDuration() == expected);
    CHECK(restarted.zoomInEasing() == kEaseOut);
    CHECK(restarted.zoomOutEasing() == kEaseOut);
    CHECK(restarted.iconSize() == 56);

    // ...and the legacy key is gone from kdockwrc, so it never migrates twice.
    KConfig stored(home.kdockwrcPath(), KConfig::SimpleConfig);
    CHECK_FALSE(storedGroup(stored).hasKey(kLegacyKey));
    CHECK(storedGroup(stored).readEntry(kPresetKey, -1) == kCustomPreset);
}

TEST_CASE("A stored zoom animation preset wins over the legacy duration", "[settings][migration]")
{
    const ScopedConfigHome home;
    writeKDockWrc(home, "ZoomAnimationDuration=400\nZoomAnimationPreset=1\n");

    {
        KDockWSettings settings;
        settings.load();
        kdockw::Application::migrateLegacySettings(&settings);
        CHECK(settings.zoomAnimationPreset() == kQuickPreset);
        CHECK(settings.zoomInDuration() == settings.defaultZoomInDurationValue());
        CHECK(settings.zoomOutDuration() == settings.defaultZoomOutDurationValue());
    }

    KConfig stored(home.kdockwrcPath(), KConfig::SimpleConfig);
    CHECK_FALSE(storedGroup(stored).hasKey(kLegacyKey));
    CHECK(storedGroup(stored).readEntry(kPresetKey, -1) == kQuickPreset);
    CHECK_FALSE(storedGroup(stored).hasKey(QStringLiteral("ZoomInDuration")));
    CHECK_FALSE(storedGroup(stored).hasKey(QStringLiteral("ZoomOutDuration")));
}

TEST_CASE("Without a legacy key the Natural preset stays the default", "[settings][migration]")
{
    const ScopedConfigHome home;
    writeKDockWrc(home, "IconSize=56\n");

    {
        KDockWSettings settings;
        settings.load();
        kdockw::Application::migrateLegacySettings(&settings);

        CHECK(settings.zoomAnimationPreset() == kNaturalPreset);
        CHECK(settings.zoomInDuration() == 180);
        CHECK(settings.zoomOutDuration() == 240);
        CHECK(settings.zoomInEasing() == kEaseInOut);
        CHECK(settings.zoomOutEasing() == kEaseInOut);
    }

    // Nothing is written for the zoom animation: the defaults keep applying,
    // so a future change of the default reaches this user too.
    KConfig stored(home.kdockwrcPath(), KConfig::SimpleConfig);
    const KConfigGroup group = storedGroup(stored);
    CHECK_FALSE(group.hasKey(kPresetKey));
    CHECK_FALSE(group.hasKey(QStringLiteral("ZoomInDuration")));
    CHECK_FALSE(group.hasKey(QStringLiteral("ZoomOutDuration")));
    CHECK_FALSE(group.hasKey(QStringLiteral("ZoomInEasing")));
    CHECK_FALSE(group.hasKey(QStringLiteral("ZoomOutEasing")));
    CHECK(group.readEntry(QStringLiteral("IconSize"), 0) == 56);
}
