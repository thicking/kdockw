// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Every kdockw.kcfg entry the settings UI can change must reach kdockwrc on
// its own: KConfigSkeleton does not save on destruction, so an entry whose
// change signal is not wired to save() silently reverts on the next start
// unless some other, wired setting happens to change in the same session.

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <QMetaProperty>
#include <QTemporaryDir>

#include <memory>

namespace
{

// Saved by Application::run()'s pinnedLaunchersChanged handler, not by
// connectSettingsAutoSave().
const QString kSeparatelySaved = QStringLiteral("PinnedLaunchers");

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
            if (item->name() != kSeparatelySaved) {
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
    REQUIRE(settings.contentPaddingBottom() == 8);
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
    REQUIRE(settings.runningIndicatorColorMode() == 0);

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
