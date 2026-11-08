// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <catch2/catch_test_macros.hpp>

#include "shell/previewframecache.h"

TEST_CASE("minimized preview frame cache is UUID scoped and process local")
{
    kdockw::PreviewFrameCache cache;
    QImage frame(QSize(320, 200), QImage::Format_ARGB32_Premultiplied);
    frame.fill(QColor(QStringLiteral("#123456")));

    CHECK(cache.imageUrl(QStringLiteral("uuid-a")).isEmpty());
    CHECK(cache.store(QStringLiteral("uuid-a"), frame));
    CHECK(cache.revision() == 1);
    CHECK(cache.contains(QStringLiteral("uuid-a")));
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
}

TEST_CASE("minimized preview frame cache has fixed entry and byte bounds")
{
    kdockw::PreviewFrameCache cache;
    QImage largeFrame(QSize(1200, 900), QImage::Format_ARGB32_Premultiplied);
    largeFrame.fill(Qt::blue);

    for (int i = 0; i < 6; ++i) {
        CHECK(cache.store(QStringLiteral("window-%1").arg(i), largeFrame));
    }

    CHECK(cache.entryCount() == 4);
    CHECK(cache.totalBytes() <= 4 * 1024 * 1024);
    CHECK_FALSE(cache.contains(QStringLiteral("window-0")));
    CHECK_FALSE(cache.contains(QStringLiteral("window-1")));
    CHECK(cache.contains(QStringLiteral("window-2")));
    CHECK(cache.contains(QStringLiteral("window-5")));

    const QImage bounded = cache.imageForKey(cache.imageKey(QStringLiteral("window-5")));
    CHECK(bounded.width() <= 640);
    CHECK(bounded.height() <= 400);
}
