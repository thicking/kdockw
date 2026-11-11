// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QList>
#include <QStringList>
#include <QUrl>

namespace kdockw
{

enum class DockEntryType {
    Task,
    FolderStack,
};

/** A persistable item in the dock's pinned order. */
struct DockEntry {
    QString id;
    DockEntryType type = DockEntryType::Task;
    QUrl url;

    [[nodiscard]] static DockEntry task(const QUrl &url);
    [[nodiscard]] static DockEntry folderStack(const QUrl &url);
    [[nodiscard]] bool isValid() const;
    bool operator==(const DockEntry &) const = default;
};

/** Versioned serialization and v0.4.x launcher migration for pinned entries. */
class DockEntriesCodec
{
public:
    struct DecodeResult {
        QList<DockEntry> entries;
        bool validDocument = false;
    };

    [[nodiscard]] static QString encode(const QList<DockEntry> &entries);
    [[nodiscard]] static DecodeResult decode(const QString &serialized);
    [[nodiscard]] static QList<DockEntry> fromLegacyLaunchers(const QStringList &launchers);
};

} // namespace kdockw
