// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_test_macros.hpp>

#include "shell/previewframecache.h"

#include <QTest>

TEST_CASE("minimized preview frame cache is UUID scoped and process local")
{
    kdockw::PreviewFrameCache cache;
    QImage frame(QSize(320, 200), QImage::Format_ARGB32_Premultiplied);
    frame.fill(QColor(QStringLiteral("#123456")));

    CHECK(cache.imageUrl(QStringLiteral("uuid-a")).isEmpty());
    CHECK(cache.store(QStringLiteral("uuid-a"), frame));
    CHECK(cache.revision() == 1);
    CHECK(cache.contains(QStringLiteral("uuid-a")));
    CHECK(cache.windowUuids() == QStringList{QStringLiteral("uuid-a")});
    CHECK_FALSE(cache.contains(QStringLiteral("uuid-b")));

    const QString url = cache.imageUrl(QStringLiteral("uuid-a"));
    CHECK(url.startsWith(QStringLiteral("image://previewframes/")));
    CHECK(url.contains(QStringLiteral("?v=1")));
    const QImage restored = cache.imageForKey(cache.imageKey(QStringLiteral("uuid-a")));
    CHECK(restored.size() == frame.size());
    CHECK(restored.pixelColor(10, 10) == frame.pixelColor(10, 10));

    CHECK(cache.remove(QStringLiteral("uuid-a")));
    CHECK_FALSE(cache.contains(QStringLiteral("uuid-a")));
    CHECK(cache.imageForKey(cache.imageKey(QStringLiteral("uuid-a"))).isNull());
    CHECK(cache.revision() == 2);
    CHECK(cache.windowUuids().isEmpty());
}

TEST_CASE("two windows from the same application keep distinct cached frames")
{
    kdockw::PreviewFrameCache cache;
    QImage first(QSize(32, 24), QImage::Format_RGBA8888_Premultiplied);
    QImage second(QSize(32, 24), QImage::Format_RGBA8888_Premultiplied);
    first.fill(Qt::red);
    second.fill(Qt::blue);

    REQUIRE(cache.store(QStringLiteral("same-app-window-1"), first, true));
    REQUIRE(cache.store(QStringLiteral("same-app-window-2"), second, true));

    const QImage firstCached = cache.imageForKey(cache.imageKey(QStringLiteral("same-app-window-1")));
    const QImage secondCached = cache.imageForKey(cache.imageKey(QStringLiteral("same-app-window-2")));
    CHECK(firstCached.pixelColor(0, 0) == QColor(Qt::red));
    CHECK(secondCached.pixelColor(0, 0) == QColor(Qt::blue));
    CHECK(cache.remove(QStringLiteral("same-app-window-1")));
    CHECK_FALSE(cache.contains(QStringLiteral("same-app-window-1")));
    CHECK(cache.contains(QStringLiteral("same-app-window-2")));
}

TEST_CASE("minimized preview frame cache obeys the 32-frame and 32 MiB bounds")
{
    kdockw::PreviewFrameCache cache;
    QImage largeFrame(QSize(1200, 900), QImage::Format_ARGB32_Premultiplied);
    largeFrame.fill(Qt::blue);

    for (int i = 0; i < 40; ++i) {
        CHECK(cache.store(QStringLiteral("window-%1").arg(i), largeFrame));
    }

    CHECK(cache.entryCount() == 32);
    CHECK(cache.totalBytes() <= 32 * 1024 * 1024);
    CHECK_FALSE(cache.contains(QStringLiteral("window-0")));
    CHECK_FALSE(cache.contains(QStringLiteral("window-7")));
    CHECK(cache.contains(QStringLiteral("window-8")));
    CHECK(cache.contains(QStringLiteral("window-39")));
    CHECK(cache.windowUuids().size() == 32);
    CHECK(cache.windowUuids().contains(QStringLiteral("window-8")));
    CHECK(cache.windowUuids().contains(QStringLiteral("window-39")));

    const QImage bounded = cache.imageForKey(cache.imageKey(QStringLiteral("window-39")));
    CHECK(bounded.width() <= 640);
    CHECK(bounded.height() <= 400);
    CHECK(bounded.format() == QImage::Format_RGBA8888_Premultiplied);
    CHECK(bounded.sizeInBytes() == qsizetype(bounded.bytesPerLine()) * bounded.height());
}

TEST_CASE("cache byte accounting includes the actual RGBA storage at the largest frame size")
{
    kdockw::PreviewFrameCache cache;
    constexpr qsizetype frameBytes = 640 * 400 * 4;
    for (int i = 0; i < 32; ++i) {
        QImage frame(QSize(640, 400), QImage::Format_RGBA8888_Premultiplied);
        frame.fill(QColor(i, 0, 0));
        REQUIRE(cache.store(QStringLiteral("maximum-frame-%1").arg(i), frame, true));
    }

    // 32 maximum-sized frames occupy 31.25 MiB in RGBA. With both the
    // per-frame dimensions and 32-entry cap this is the tightest reachable
    // bound; the explicit 32 MiB byte ceiling remains a defensive invariant.
    CHECK(cache.entryCount() == 32);
    CHECK(cache.totalBytes() == 32 * frameBytes);
    CHECK(cache.totalBytes() <= 32 * 1024 * 1024);
    CHECK(cache.store(QStringLiteral("overflow-frame"), QImage(QSize(640, 400),
                                                               QImage::Format_RGBA8888_Premultiplied), true));
    CHECK(cache.entryCount() == 32);
    CHECK(cache.totalBytes() <= 32 * 1024 * 1024);
}

TEST_CASE("minimized preview cache evicts restored frames before minimized frames")
{
    kdockw::PreviewFrameCache cache;
    QImage frame(QSize(320, 200), QImage::Format_RGBA8888_Premultiplied);
    frame.fill(Qt::green);

    for (int i = 0; i < 32; ++i) {
        CHECK(cache.store(QStringLiteral("window-%1").arg(i), frame));
    }
    CHECK(cache.setMinimized(QStringLiteral("window-0"), true));
    CHECK_FALSE(cache.setMinimized(QStringLiteral("missing-window"), true));
    CHECK_FALSE(cache.setMinimized(QStringLiteral("window-0"), true));
    CHECK(cache.store(QStringLiteral("window-32"), frame));

    CHECK(cache.contains(QStringLiteral("window-0")));
    CHECK_FALSE(cache.contains(QStringLiteral("window-1")));
    CHECK(cache.contains(QStringLiteral("window-2")));
    CHECK(cache.contains(QStringLiteral("window-32")));
}

TEST_CASE("minimized preview cache enforces hard bounds even when every frame is minimized")
{
    kdockw::PreviewFrameCache cache;
    QImage frame(QSize(320, 200), QImage::Format_RGBA8888_Premultiplied);
    frame.fill(Qt::red);

    for (int i = 0; i < 32; ++i) {
        const QString uuid = QStringLiteral("window-%1").arg(i);
        REQUIRE(cache.store(uuid, frame));
        REQUIRE(cache.setMinimized(uuid, true));
    }
    CHECK(cache.store(QStringLiteral("window-32"), frame));

    CHECK(cache.entryCount() == 32);
    CHECK_FALSE(cache.contains(QStringLiteral("window-0")));
    CHECK(cache.contains(QStringLiteral("window-1")));
    CHECK(cache.contains(QStringLiteral("window-32")));
    CHECK(cache.totalBytes() <= 32 * 1024 * 1024);
}

TEST_CASE("minimized preview frames are not removed merely because time passes")
{
    kdockw::PreviewFrameCache cache;
    QImage frame(QSize(320, 200), QImage::Format_RGBA8888_Premultiplied);
    frame.fill(Qt::yellow);

    REQUIRE(cache.store(QStringLiteral("long-lived-window"), frame, true));
    QTest::qWait(25);

    CHECK(cache.contains(QStringLiteral("long-lived-window")));
    CHECK(cache.imageForKey(cache.imageKey(QStringLiteral("long-lived-window"))).size() == frame.size());
}
