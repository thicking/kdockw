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

constexpr int kSchemaVersion = 5;

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
    case DockEntryType::BuiltInWidget:
        return QStringLiteral("builtInWidget");
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
    if (value == QLatin1String("builtInWidget")) {
        *type = DockEntryType::BuiltInWidget;
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

DockEntry DockEntry::separator(DockWidgetSlot slot)
{
    const QString id = QStringLiteral("widget:separator:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    DockEntry entry{id, DockEntryType::BuiltInWidget};
    entry.widgetKind = QStringLiteral("separator");
    entry.slot = slot;
    return entry;
}

DockEntry DockEntry::spacer(DockWidgetSlot slot, int size)
{
    const QString id = QStringLiteral("widget:spacer:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    DockEntry entry{id, DockEntryType::BuiltInWidget};
    entry.widgetKind = QStringLiteral("spacer");
    entry.slot = slot;
    entry.widgetSize = size;
    return entry;
}

DockEntry DockEntry::applicationLauncher(DockWidgetSlot slot)
{
    const QString id = QStringLiteral("widget:application-launcher:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    DockEntry entry{id, DockEntryType::BuiltInWidget};
    entry.widgetKind = QStringLiteral("applicationLauncher");
    entry.iconName = QStringLiteral("start-here-kde");
    entry.slot = slot;
    return entry;
}

DockEntry DockEntry::mediaPlayer(DockWidgetSlot slot)
{
    const QString id = QStringLiteral("widget:media-player:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    DockEntry entry{id, DockEntryType::BuiltInWidget};
    entry.widgetKind = QStringLiteral("mediaPlayer");
    entry.slot = slot;
    return entry;
}

DockEntry DockEntry::trash(DockWidgetSlot slot)
{
    const QString id = QStringLiteral("widget:trash:%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    DockEntry entry{id, DockEntryType::BuiltInWidget};
    entry.widgetKind = QStringLiteral("trash");
    entry.slot = slot;
    return entry;
}

bool DockEntry::isValid() const
{
    if (id.isEmpty()) {
        return false;
    }

    switch (type) {
    case DockEntryType::Task:
        return !url.scheme().isEmpty() && id == taskId(url) && iconName.isEmpty() && iconUrl.isEmpty();
    case DockEntryType::FolderStack:
        return isLocalDirectoryUrl(url) && id.startsWith(QLatin1String("folder:"))
            && !QUuid(id.mid(QStringLiteral("folder:").size())).isNull()
            && (iconUrl.isEmpty() || (iconUrl.isValid() && iconUrl.isLocalFile()));
    case DockEntryType::BuiltInWidget:
        return !url.isValid() && url.isEmpty() && iconUrl.isEmpty()
            && ((widgetKind == QLatin1String("separator") && id.startsWith(QLatin1String("widget:separator:")) && iconName.isEmpty() && widgetSize >= 0
                 && widgetSize <= 512)
                || (widgetKind == QLatin1String("spacer") && id.startsWith(QLatin1String("widget:spacer:")) && iconName.isEmpty() && widgetSize >= 4
                    && widgetSize <= 512)
                || (widgetKind == QLatin1String("applicationLauncher") && id.startsWith(QLatin1String("widget:application-launcher:")) && !iconName.isEmpty()
                    && widgetSize == 0)
                || (widgetKind == QLatin1String("mediaPlayer") && id.startsWith(QLatin1String("widget:media-player:")) && iconName.isEmpty() && widgetSize == 0)
                || (widgetKind == QLatin1String("trash") && id.startsWith(QLatin1String("widget:trash:")) && iconName.isEmpty() && widgetSize == 0));
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
        if (entry.type == DockEntryType::BuiltInWidget) {
            item.insert(QStringLiteral("widgetKind"), entry.widgetKind);
            item.insert(QStringLiteral("slot"), entry.slot == DockWidgetSlot::Start ? QStringLiteral("start")
                : entry.slot == DockWidgetSlot::End ? QStringLiteral("end") : QStringLiteral("center"));
            item.insert(QStringLiteral("size"), entry.widgetSize);
            item.insert(QStringLiteral("visible"), entry.widgetVisible);
            if (entry.widgetKind == QLatin1String("applicationLauncher")) {
                item.insert(QStringLiteral("iconIsCustom"), entry.iconIsCustom);
            }
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
    if ((version < 1 || version > kSchemaVersion) || !object.value(QStringLiteral("entries")).isArray()) {
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
        const QUrl url = item.contains(QStringLiteral("url"))
            ? QUrl::fromEncoded(item.value(QStringLiteral("url")).toString().toUtf8(), QUrl::StrictMode) : QUrl{};
        DockEntry entry{item.value(QStringLiteral("id")).toString(), type, url};
        if (version >= 2) {
            entry.iconName = item.value(QStringLiteral("iconName")).toString();
            if (item.contains(QStringLiteral("iconUrl"))) {
                entry.iconUrl = QUrl::fromEncoded(item.value(QStringLiteral("iconUrl")).toString().toUtf8(), QUrl::StrictMode);
            }
        }
        if (version >= 3 && type == DockEntryType::BuiltInWidget) {
            entry.widgetKind = item.value(QStringLiteral("widgetKind")).toString();
            const QString slot = item.value(QStringLiteral("slot")).toString();
            entry.slot = slot == QLatin1String("start") ? DockWidgetSlot::Start
                : slot == QLatin1String("end") ? DockWidgetSlot::End : DockWidgetSlot::Center;
            if (version >= 4) {
                entry.widgetSize = item.value(QStringLiteral("size")).toInt();
                entry.widgetVisible = item.value(QStringLiteral("visible")).toBool(true);
            }
            if (entry.widgetKind == QLatin1String("applicationLauncher")) {
                entry.iconIsCustom = version >= 5
                    ? item.value(QStringLiteral("iconIsCustom")).toBool()
                    : entry.iconName != QLatin1String("start-here-kde");
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
