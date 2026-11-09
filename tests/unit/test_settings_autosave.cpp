// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Every kdockw.kcfg entry the settings UI can change must reach kdockwrc on
// its own: KConfigSkeleton does not save on destruction, so an entry whose
// change signal is not wired to save() silently reverts on the next start
// unless some other, wired setting happens to change in the same session.

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QMetaProperty>
#include <QSet>
#include <QTemporaryDir>

#include <memory>

namespace
{

// Saved by Application::run()'s pinnedLaunchersChanged handler, not by
// connectSettingsAutoSave().
const QString kSeparatelySaved = QStringLiteral("PinnedLaunchers");
// Internal update-check cache fields are written in batches by
// ReleaseUpdateChecker::save(), not individually through the settings UI.
const QSet<QString> kCheckerCacheSettings{
    QStringLiteral("LastSuccessfulUpdateCheck"),
    QStringLiteral("LastAutomaticUpdateAttempt"),
    QStringLiteral("ReleasesApiETag"),
    QStringLiteral("CachedReleaseVersion"),
    QStringLiteral("CachedReleaseUrl"),
    QStringLiteral("LastNotifiedReleaseVersion"),
    QStringLiteral("ReleaseApiRetryAfter"),
};

QMetaProperty propertyFor(const KDockWSettings &settings, const QString &itemName)
{
    QString name = itemName;
    name[0] = name[0].toLower();
    const auto *meta = settings.metaObject();
    return meta->property(meta->indexOfProperty(name.toLatin1().constData()));
}

// A valid value different from the entry's default.
QVariant changedValue(const KConfigSkeletonItem &item, const QVariant &current)
{
    const QVariant min = item.minValue();
    const QVariant max = item.maxValue();
    switch (current.typeId()) {
    case QMetaType::Bool:
        return !current.toBool();
    case QMetaType::Int:
        if (max.isValid() && max != current) {
            return max;
        }
        if (min.isValid() && min != current) {
            return min;
        }
        return current.toInt() + 1;
    case QMetaType::Double:
        if (max.isValid() && max != current) {
            return max;
        }
        if (min.isValid() && min != current) {
            return min;
        }
        return current.toDouble() + 1.0;
    case QMetaType::QString:
        return QStringLiteral("#123456");
    case QMetaType::QStringList:
        return QStringList{QStringLiteral("HDMI-A-2"), QStringLiteral("eDP-1"), QStringLiteral("unavailable-output")};
    default:
        return {};
    }
}

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

TEST_CASE("Changing any single setting persists it across a restart", "[settings]")
{
    // Item names come from the schema, so entries added to kdockw.kcfg later
    // are covered too.
    QStringList itemNames;
    {
        const ScopedConfigHome home;
        KDockWSettings settings;
        const auto items = settings.items();
        for (const auto *item : items) {
            if (item->name() != kSeparatelySaved && !kCheckerCacheSettings.contains(item->name())) {
                itemNames.append(item->name());
            }
        }
    }
    REQUIRE(itemNames.size() > 1);

    QStringList notPersisted;
    for (const QString &name : std::as_const(itemNames)) {
        const ScopedConfigHome home;
        QVariant written;
        {
            // Session 1: the settings UI changes only this entry, then KDockW quits.
            auto settings = std::make_unique<KDockWSettings>();
            settings->load();
            QObject context;
            kdockw::Application::connectSettingsAutoSave(settings.get(), &context);

            const auto *item = settings->findItem(name);
            REQUIRE(item);
            const QMetaProperty property = propertyFor(*settings, name);
            INFO("kcfg entry: " << name.toStdString());
            REQUIRE(property.isValid());
            written = changedValue(*item, property.read(settings.get()));
            REQUIRE(written.isValid());
            REQUIRE(property.write(settings.get(), written));
            REQUIRE(property.read(settings.get()) == written);
        }

        // Session 2: KDockW starts again and loads kdockwrc.
        KDockWSettings restarted;
        restarted.load();
        if (propertyFor(restarted, name).read(&restarted) != written) {
            notPersisted.append(name);
        }
    }

    INFO("reverted after restart: " << notPersisted.join(QStringLiteral(", ")).toStdString());
    CHECK(notPersisted.isEmpty());
}

TEST_CASE("Content padding and alignment persist independently", "[settings][content-layout]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();

    REQUIRE(settings.contentPaddingLeft() == 8);
    REQUIRE(settings.contentPaddingRight() == 8);
    REQUIRE(settings.contentPaddingTop() == 8);
    REQUIRE(settings.contentPaddingBottom() == 0);
    REQUIRE(settings.contentAlignment() == 1);

    QObject context;
    kdockw::Application::connectSettingsAutoSave(&settings, &context);
    settings.setContentPaddingLeft(1);
    settings.setContentPaddingRight(17);
    settings.setContentPaddingTop(33);
    settings.setContentPaddingBottom(64);
    settings.setContentAlignment(2);

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.contentPaddingLeft() == 1);
    CHECK(restarted.contentPaddingRight() == 17);
    CHECK(restarted.contentPaddingTop() == 33);
    CHECK(restarted.contentPaddingBottom() == 64);
    CHECK(restarted.contentAlignment() == 2);
    CHECK(restarted.iconSize() == settings.iconSize());
    CHECK(restarted.iconSpacing() == settings.iconSpacing());
}

TEST_CASE("Running indicator preferences persist independently", "[settings][running-indicator]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();

    REQUIRE(settings.runningIndicatorStyle() == 0);
    REQUIRE(settings.runningIndicatorPosition() == 0);
    REQUIRE(settings.runningIndicatorSize() == 4);
    REQUIRE(settings.runningIndicatorColorMode() == 1);

    QObject context;
    kdockw::Application::connectSettingsAutoSave(&settings, &context);
    settings.setRunningIndicatorStyle(4);
    settings.setRunningIndicatorPosition(1);
    settings.setRunningIndicatorSize(12);
    settings.setRunningIndicatorColorMode(1);
    settings.setRunningIndicatorColor(QStringLiteral("#ff336699"));

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.runningIndicatorStyle() == 4);
    CHECK(restarted.runningIndicatorPosition() == 1);
    CHECK(restarted.runningIndicatorSize() == 12);
    CHECK(restarted.runningIndicatorColorMode() == 1);
    CHECK(restarted.runningIndicatorColor() == QStringLiteral("#ff336699"));
    CHECK(restarted.iconSize() == settings.iconSize());
    CHECK(restarted.contentPaddingLeft() == settings.contentPaddingLeft());
}

TEST_CASE("Badge typography defaults and preferences persist independently", "[settings][badge]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.load();

    REQUIRE(settings.badgeFontWeight() == 500);
    REQUIRE(settings.badgeTextSizePercent() == 100);
    REQUIRE(settings.badgeDisplayMode() == 0);

    QObject context;
    kdockw::Application::connectSettingsAutoSave(&settings, &context);
    // A user-selected value that matches the old factory default must survive
    // an application update that changes the new-install default to Medium.
    settings.setBadgeFontWeight(700);
    settings.setBadgeTextSizePercent(115);

    KDockWSettings restarted;
    restarted.load();
    CHECK(restarted.badgeFontWeight() == 700);
    CHECK(restarted.badgeTextSizePercent() == 115);
    CHECK(restarted.iconSize() == settings.iconSize());
    CHECK(restarted.badgeDisplayMode() == settings.badgeDisplayMode());
}

TEST_CASE("First-run settings match the validated KDockW appearance", "[settings][defaults]")
{
    const ScopedConfigHome home;
    KDockWSettings settings;
    settings.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    settings.load();

    CHECK(settings.language() == QStringLiteral("system"));
    CHECK(settings.iconSize() == 40);
    CHECK(settings.iconSpacing() == 10);
    CHECK(settings.contentPaddingLeft() == 8);
    CHECK(settings.contentPaddingRight() == 8);
    CHECK(settings.contentPaddingTop() == 8);
    CHECK(settings.contentPaddingBottom() == 0);
    CHECK(settings.contentAlignment() == 1);
    CHECK(settings.iconOpacity() == 1.0);
    CHECK(settings.iconOpacityActive() == 1.0);
    CHECK(settings.iconOpacityInactive() == 1.0);
    CHECK(settings.iconOpacityMinimized() == 1.0);
    CHECK(settings.maxZoomFactor() == Catch::Approx(1.9));
    CHECK(settings.zoomStyle() == 0);
    CHECK(settings.magnificationMode() == 1);
    CHECK(settings.springStiffness() == Catch::Approx(170.0));
    CHECK(settings.springDamping() == Catch::Approx(0.60));
    CHECK(settings.springSpeed() == Catch::Approx(1.0));
    CHECK(settings.cornerRadius() == 17);
    CHECK(settings.floating());
    CHECK(settings.floatingMargin() == 3);
    CHECK(settings.visibilityMode() == 0);
    CHECK(settings.dodgeActiveOnly());
    CHECK(settings.reserveScreenSpace());
    CHECK(settings.edge() == 1);
    CHECK(settings.backgroundStyle() == 2);
    CHECK(settings.backgroundOpacity() == 0.85);
    CHECK_FALSE(settings.useSystemColor());
    CHECK_FALSE(settings.useAccentColor());
    CHECK(settings.tintColor() == QStringLiteral("#4b4144"));
    CHECK(settings.shadowEnabled());
    CHECK(settings.shadowLightX() == 65);
    CHECK(settings.shadowLightY() == -132);
    CHECK(settings.shadowLightZ() == 500);
    CHECK(settings.shadowLightRadius() == 5.5);
    CHECK(settings.shadowIntensity() == Catch::Approx(0.2));
    CHECK(settings.previewEnabled());
    CHECK_FALSE(settings.cpuOnlyPreviewCapture());
    CHECK(settings.attentionAnimation() == 2);
    CHECK(settings.attentionAnimationEnabled());
    CHECK(settings.attentionAnimationIntensity() == 100);
    CHECK(settings.launchBounceEnabled());
    CHECK(settings.launchBounceIntensity() == 150);
    CHECK(settings.launchBounceSpeed() == 100);
    CHECK(settings.clickBounceEnabled());
    CHECK(settings.hideDelay() == 500);
    CHECK(settings.previewHideDelay() == 400);
    CHECK(settings.previewThumbnailSize() == 320);
    CHECK(settings.previewMaximumHeight() == 200);
    CHECK(settings.singleWindowClickAction() == 0);
    CHECK(settings.shadowElevation() == 1);
    CHECK(settings.runningIndicatorStyle() == 0);
    CHECK(settings.runningIndicatorPosition() == 0);
    CHECK(settings.runningIndicatorSize() == 4);
    CHECK(settings.runningIndicatorColorMode() == 1);
    CHECK(settings.runningIndicatorColor() == QStringLiteral("#ffffffff"));
    CHECK(settings.separateLaunchers());
}

TEST_CASE("Explicit user preferences override the new factory defaults", "[settings][defaults]")
{
    const ScopedConfigHome home;
    {
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        auto general = config.group(QStringLiteral("General"));
        general.writeEntry(QStringLiteral("IconSize"), 72);
        general.writeEntry(QStringLiteral("BackgroundStyle"), 3);
        general.writeEntry(QStringLiteral("RunningIndicatorSize"), 9);
        general.writeEntry(QStringLiteral("IconSpacing"), 12);
        general.writeEntry(QStringLiteral("MaxZoomFactor"), 1.8);
        general.writeEntry(QStringLiteral("PreviewHideDelay"), 640);
        general.writeEntry(QStringLiteral("PreviewThumbnailSize"), 260);
        general.writeEntry(QStringLiteral("SingleWindowClickAction"), 1);
        config.sync();
    }

    KDockWSettings settings;
    settings.load();
    CHECK(settings.iconSize() == 72);
    CHECK(settings.backgroundStyle() == 3);
    CHECK(settings.runningIndicatorSize() == 9);
    CHECK(settings.iconSpacing() == 12);
    CHECK(settings.maxZoomFactor() == Catch::Approx(1.8));
    CHECK(settings.previewHideDelay() == 640);
    CHECK(settings.previewThumbnailSize() == 260);
    CHECK(settings.singleWindowClickAction() == 1);
    CHECK(settings.contentPaddingBottom() == 0);
}

TEST_CASE("Dock and preview visibility defaults preserve explicit user timing", "[settings][visibility][defaults][migration]")
{
    const ScopedConfigHome home;

    KDockWSettings defaults;
    defaults.load();
    CHECK(defaults.hideDelay() == 500);
    CHECK(defaults.dockShowHideAnimationEnabled());
    CHECK(defaults.dockShowHideAnimationDuration() == 220);
    CHECK(defaults.previewHideDelay() == 400);

    {
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        auto general = config.group(QStringLiteral("General"));
        general.writeEntry(QStringLiteral("HideDelay"), 750);
        general.writeEntry(QStringLiteral("DockShowHideAnimationEnabled"), false);
        general.writeEntry(QStringLiteral("DockShowHideAnimationDuration"), 360);
        general.writeEntry(QStringLiteral("PreviewHideDelay"), 650);
        config.sync();
    }

    KDockWSettings saved;
    saved.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    saved.load();
    CHECK(saved.hideDelay() == 750);
    CHECK_FALSE(saved.dockShowHideAnimationEnabled());
    CHECK(saved.dockShowHideAnimationDuration() == 360);
    CHECK(saved.previewHideDelay() == 650);
}

TEST_CASE("Launch and attention animation settings preserve old and explicit preferences", "[settings][animation][defaults][migration]")
{
    const ScopedConfigHome home;

    // Existing configurations without an explicitly saved duration inherit
    // the current first-run default.
    KDockWSettings defaults;
    defaults.load();
    CHECK(defaults.attentionAnimationDuration() == 3);

    // Configurations created before these controls existed have no new keys;
    // KConfigXT supplies their defaults without changing existing preferences.
    {
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        auto general = config.group(QStringLiteral("General"));
        general.writeEntry(QStringLiteral("AttentionAnimation"), 3);
        general.writeEntry(QStringLiteral("AttentionAnimationDuration"), 12);
        general.writeEntry(QStringLiteral("IconSize"), 64);
        config.sync();
    }

    KDockWSettings migrated;
    migrated.load();
    CHECK(migrated.attentionAnimation() == 3);
    CHECK(migrated.attentionAnimationDuration() == 12);
    CHECK(migrated.iconSize() == 64);
    CHECK(migrated.attentionAnimationEnabled());
    CHECK(migrated.attentionAnimationIntensity() == 100);
    CHECK(migrated.launchBounceEnabled());
    CHECK(migrated.launchBounceIntensity() == 150);
    CHECK(migrated.launchBounceSpeed() == 100);
    CHECK(migrated.clickBounceEnabled());

    migrated.setAttentionAnimationEnabled(false);
    migrated.setAttentionAnimationIntensity(130);
    migrated.setLaunchBounceEnabled(false);
    migrated.setLaunchBounceIntensity(80);
    migrated.setLaunchBounceSpeed(120);
    migrated.save();

    KDockWSettings reloaded;
    reloaded.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    reloaded.load();
    CHECK_FALSE(reloaded.attentionAnimationEnabled());
    CHECK(reloaded.attentionAnimationIntensity() == 130);
    CHECK_FALSE(reloaded.launchBounceEnabled());
    CHECK(reloaded.launchBounceIntensity() == 80);
    CHECK(reloaded.launchBounceSpeed() == 120);
    CHECK(reloaded.attentionAnimation() == 3);
    CHECK(reloaded.attentionAnimationDuration() == 12);
}

TEST_CASE("Existing magnification settings migrate without overwriting saved values", "[settings][migration][zoom]")
{
    const ScopedConfigHome home;
    {
        // Older configurations have zoom preferences but no Spring settings.
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        auto general = config.group(QStringLiteral("General"));
        general.writeEntry(QStringLiteral("IconSize"), 72);
        general.writeEntry(QStringLiteral("MaxZoomFactor"), 1.7);
        config.sync();
    }

    KDockWSettings settings;
    settings.load();
    CHECK(settings.iconSize() == 72);
    CHECK(settings.maxZoomFactor() == Catch::Approx(1.7));
    CHECK(settings.magnificationMode() == 1);
    CHECK(settings.springStiffness() == Catch::Approx(170.0));
    CHECK(settings.springDamping() == Catch::Approx(0.60));
    CHECK(settings.springSpeed() == Catch::Approx(1.0));
}

TEST_CASE("Explicit Classic mode and Spring tuning survive updated defaults", "[settings][migration][zoom]")
{
    const ScopedConfigHome home;
    {
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        auto general = config.group(QStringLiteral("General"));
        general.writeEntry(QStringLiteral("MagnificationMode"), 0);
        general.writeEntry(QStringLiteral("MaxZoomFactor"), 1.6);
        general.writeEntry(QStringLiteral("SpringStiffness"), 230.0);
        general.writeEntry(QStringLiteral("SpringDamping"), 0.85);
        general.writeEntry(QStringLiteral("SpringSpeed"), 1.4);
        config.sync();
    }

    KDockWSettings settings;
    settings.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    settings.load();
    CHECK(settings.magnificationMode() == 0);
    CHECK(settings.maxZoomFactor() == Catch::Approx(1.6));
    CHECK(settings.springStiffness() == Catch::Approx(230.0));
    CHECK(settings.springDamping() == Catch::Approx(0.85));
    CHECK(settings.springSpeed() == Catch::Approx(1.4));

    settings.save();
    KDockWSettings restarted;
    restarted.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    restarted.load();
    CHECK(restarted.magnificationMode() == 0);
    CHECK(restarted.maxZoomFactor() == Catch::Approx(1.6));
    CHECK(restarted.springStiffness() == Catch::Approx(230.0));
    CHECK(restarted.springDamping() == Catch::Approx(0.85));
    CHECK(restarted.springSpeed() == Catch::Approx(1.4));
}

TEST_CASE("Preview redesign defaults preserve existing thumbnail preferences", "[settings][preview][migration]")
{
    const ScopedConfigHome home;
    {
        // This represents an existing config file written before the new
        // layout settings existed. Its configured width must remain intact.
        KConfig config(home.configFilePath(), KConfig::SimpleConfig);
        config.group(QStringLiteral("General")).writeEntry(QStringLiteral("PreviewThumbnailSize"), 260);
        config.sync();
    }

    KDockWSettings settings;
    settings.load();
    CHECK(settings.previewThumbnailSize() == 260);
    CHECK(settings.previewMaximumHeight() == 200);
    CHECK(settings.previewCardPadding() == 8);
    CHECK(settings.previewDockGap() == 2);

    settings.setPreviewMaximumHeight(240);
    settings.setPreviewCardPadding(12);
    settings.setPreviewDockGap(16);
    settings.save();

    KDockWSettings restarted;
    restarted.setConfig(std::make_unique<KConfig>(home.configFilePath(), KConfig::SimpleConfig));
    restarted.load();
    CHECK(restarted.previewThumbnailSize() == 260);
    CHECK(restarted.previewMaximumHeight() == 240);
    CHECK(restarted.previewCardPadding() == 12);
    CHECK(restarted.previewDockGap() == 16);
}
