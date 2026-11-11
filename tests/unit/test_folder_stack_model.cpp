// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/folderstackmodel.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include <catch2/catch_test_macros.hpp>

TEST_CASE("Folder stack asynchronously lists and navigates within its root", "[folder-stack]")
{
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    REQUIRE(QDir().mkpath(directory.filePath(QStringLiteral("Nested"))));
    QFile file(directory.filePath(QStringLiteral("readme.txt")));
    REQUIRE(file.open(QIODevice::WriteOnly));
    file.write("contents");
    file.close();

    kdockw::FolderStackModel model;
    REQUIRE(model.openFolder(QUrl::fromLocalFile(directory.path())));
    QTRY_COMPARE_WITH_TIMEOUT(model.loading(), false, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 2, 5000);

    CHECK(model.data(model.index(0, 0), kdockw::FolderStackModel::IsDirectoryRole).toBool());
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == QStringLiteral("Nested"));
    CHECK(model.data(model.index(1, 0), Qt::DisplayRole).toString() == QStringLiteral("readme.txt"));

    QFile createdFile(directory.filePath(QStringLiteral("created.txt")));
    REQUIRE(createdFile.open(QIODevice::WriteOnly));
    createdFile.close();
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 3, 5000);
    REQUIRE(createdFile.remove());
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 2, 5000);

    REQUIRE(model.openItem(0));
    QTRY_COMPARE_WITH_TIMEOUT(model.loading(), false, 5000);
    CHECK(model.currentUrl() == QUrl::fromLocalFile(directory.filePath(QStringLiteral("Nested"))));
    CHECK(model.rowCount() == 0);

    model.goUp();
    QTRY_COMPARE_WITH_TIMEOUT(model.loading(), false, 5000);
    CHECK(model.currentUrl() == QUrl::fromLocalFile(directory.path()));
    model.goUp();
    CHECK(model.currentUrl() == QUrl::fromLocalFile(directory.path()));
}

TEST_CASE("Folder stack rejects non-local locations", "[folder-stack]")
{
    kdockw::FolderStackModel model;

    CHECK_FALSE(model.openFolder(QUrl(QStringLiteral("smb://server/share"))));
    CHECK(model.currentUrl().isEmpty());
    CHECK_FALSE(model.errorMessage().isEmpty());
}
