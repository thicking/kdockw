// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "dockentry.h"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QUuid>

#include <utility>

namespace kdockw
{
namespace
{

constexpr int kSchemaVersion = 2;

QString taskId(const QUrl &url)
{
    const QByteArray key = url.toString(QUrl::FullyEncoded).toUtf8();
    const QByteArray digest = QCryptographicHash::hash(key, QCryptographicHash::Sha256).toHex();
    return QStringLiteral("task:%1").arg(QString::fromLatin1(digest));
}

bool isLocalDirectoryUrl(const QUrl &url)
{
    return url.isValid() && url.isLocalFile() && url.host().isEmpty() && url.path().startsWith(QLatin1Char('/')) && url.query().isEmpty()
        && url.fragment().isEmpty();
}

QString typeName(DockEntryType type)
{
    switch (type) {
    case DockEntryType::Task:
        return QStringLiteral("task");
    case DockEntryType::FolderStack:
        return QStringLiteral("folderStack");
    }
    return {};
}

bool parseType(const QString &value, DockEntryType *type)
{
    if (value == QLatin1String("task")) {
        *type = DockEntryType::Task;
        return true;
    }
    if (value == QLatin1String("folderStack")) {
        *type = DockEntryType::FolderStack;
        return true;
    }
    return false;
}

} // namespace

DockEntry DockEntry::task(const QUrl &url)
{
    return {taskId(url), DockEntryType::Task, url, {}, {}};
}

DockEntry DockEntry::folderStack(const QUrl &url)
{
    return {QStringLiteral("folder:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces)), DockEntryType::FolderStack, url, {}, {}};
}

bool DockEntry::isValid() const
{
    if (id.isEmpty() || !url.isValid() || url.isEmpty()) {
        return false;
    }

    switch (type) {
    case DockEntryType::Task:
        return !url.scheme().isEmpty() && id == taskId(url) && iconName.isEmpty() && iconUrl.isEmpty();
    case DockEntryType::FolderStack:
        return isLocalDirectoryUrl(url) && id.startsWith(QLatin1String("folder:"))
            && !QUuid(id.mid(QStringLiteral("folder:").size())).isNull()
            && (iconUrl.isEmpty() || (iconUrl.isValid() && iconUrl.isLocalFile()));
    }
    return false;
}

QString DockEntriesCodec::encode(const QList<DockEntry> &entries)
{
    QJsonArray serializedEntries;
    QSet<QString> ids;
    for (const DockEntry &entry : entries) {
        if (!entry.isValid() || ids.contains(entry.id)) {
            continue;
        }
        ids.insert(entry.id);
        QJsonObject item{
            {QStringLiteral("id"), entry.id},
            {QStringLiteral("type"), typeName(entry.type)},
            {QStringLiteral("url"), entry.url.toString(QUrl::FullyEncoded)},
        };
        if (!entry.iconName.isEmpty()) {
            item.insert(QStringLiteral("iconName"), entry.iconName);
        }
        if (!entry.iconUrl.isEmpty()) {
            item.insert(QStringLiteral("iconUrl"), entry.iconUrl.toString(QUrl::FullyEncoded));
        }
        serializedEntries.append(item);
    }

    const QJsonObject document{
        {QStringLiteral("version"), kSchemaVersion},
        {QStringLiteral("entries"), serializedEntries},
    };
    return QString::fromUtf8(QJsonDocument(document).toJson(QJsonDocument::Compact));
}

DockEntriesCodec::DecodeResult DockEntriesCodec::decode(const QString &serialized)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(serialized.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return {};
    }

    const QJsonObject object = document.object();
    const int version = object.value(QStringLiteral("version")).toInt(-1);
    if ((version != 1 && version != kSchemaVersion) || !object.value(QStringLiteral("entries")).isArray()) {
        return {};
    }

    DecodeResult result;
    result.validDocument = true;
    QSet<QString> ids;
    const QJsonArray serializedEntries = object.value(QStringLiteral("entries")).toArray();
    for (const QJsonValue &value : serializedEntries) {
        if (!value.isObject()) {
            continue;
        }
        const QJsonObject item = value.toObject();
        DockEntryType type;
        if (!parseType(item.value(QStringLiteral("type")).toString(), &type)) {
            continue;
        }
        const QUrl url = QUrl::fromEncoded(item.value(QStringLiteral("url")).toString().toUtf8(), QUrl::StrictMode);
        DockEntry entry{item.value(QStringLiteral("id")).toString(), type, url};
        if (version >= 2) {
            entry.iconName = item.value(QStringLiteral("iconName")).toString();
            if (item.contains(QStringLiteral("iconUrl"))) {
                entry.iconUrl = QUrl::fromEncoded(item.value(QStringLiteral("iconUrl")).toString().toUtf8(), QUrl::StrictMode);
            }
        }
        if (!entry.isValid() || ids.contains(entry.id)) {
            continue;
        }
        ids.insert(entry.id);
        result.entries.append(std::move(entry));
    }
    return result;
}

QList<DockEntry> DockEntriesCodec::fromLegacyLaunchers(const QStringList &launchers)
{
    QList<DockEntry> entries;
    QSet<QString> ids;
    entries.reserve(launchers.size());
    for (const QString &launcher : launchers) {
        const QUrl url(launcher, QUrl::StrictMode);
        const DockEntry entry = DockEntry::task(url);
        if (!entry.isValid() || ids.contains(entry.id)) {
            continue;
        }
        ids.insert(entry.id);
        entries.append(entry);
    }
    return entries;
}

} // namespace kdockw
