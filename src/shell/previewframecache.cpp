// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "previewframecache.h"

#include <QCryptographicHash>
#include <QMutexLocker>
#include <QtMath>

#include <algorithm>
#include <cmath>

namespace kdockw
{

PreviewFrameCache::PreviewFrameCache(QObject *parent)
    : QObject(parent)
{
}

quint64 PreviewFrameCache::revision() const
{
    QMutexLocker locker(&m_mutex);
    return m_revision;
}

QString PreviewFrameCache::imageKey(const QString &windowUuid) const
{
    if (windowUuid.isEmpty()) {
        return {};
    }
    return QString::fromLatin1(QCryptographicHash::hash(windowUuid.toUtf8(), QCryptographicHash::Sha256).toHex());
}

QString PreviewFrameCache::imageUrl(const QString &windowUuid) const
{
    const QString key = imageKey(windowUuid);
    if (key.isEmpty() || !contains(windowUuid)) {
        return {};
    }
    return QStringLiteral("image://previewframes/%1?v=%2").arg(key).arg(revision());
}

bool PreviewFrameCache::contains(const QString &windowUuid) const
{
    const QString key = imageKey(windowUuid);
    if (key.isEmpty()) {
        return false;
    }
    QMutexLocker locker(&m_mutex);
    return m_entries.contains(key);
}

QImage PreviewFrameCache::imageForKey(const QString &key) const
{
    QMutexLocker locker(&m_mutex);
    const auto it = m_entries.constFind(key);
    if (it == m_entries.cend()) {
        return {};
    }
    m_lru.removeAll(key);
    m_lru.append(key);
    return it->image;
}

qsizetype PreviewFrameCache::entryCount() const
{
    QMutexLocker locker(&m_mutex);
    return m_entries.size();
}

qsizetype PreviewFrameCache::totalBytes() const
{
    QMutexLocker locker(&m_mutex);
    return m_totalBytes;
}

bool PreviewFrameCache::store(const QString &windowUuid, const QImage &sourceImage)
{
    if (windowUuid.isEmpty() || sourceImage.isNull()) {
        return false;
    }

    QImage image = sourceImage.convertToFormat(QImage::Format_RGBA8888_Premultiplied);
    if (image.width() > MaximumWidth || image.height() > MaximumHeight || image.sizeInBytes() > MaximumImageBytes) {
        const qreal scale = std::min({qreal(MaximumWidth) / image.width(), qreal(MaximumHeight) / image.height(),
                                      std::sqrt(qreal(MaximumImageBytes) / qreal(image.sizeInBytes()))});
        const QSize boundedSize(std::max(1, qFloor(image.width() * scale)), std::max(1, qFloor(image.height() * scale)));
        image = image.scaled(boundedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    const QString key = imageKey(windowUuid);
    const qsizetype bytes = image.sizeInBytes();
    if (image.isNull() || bytes <= 0 || bytes > MaximumImageBytes) {
        return false;
    }

    {
        QMutexLocker locker(&m_mutex);
        const auto existing = m_entries.find(key);
        if (existing != m_entries.end()) {
            m_totalBytes -= existing->bytes;
            m_entries.erase(existing);
            m_lru.removeAll(key);
        }
        while (!m_lru.isEmpty() && (m_entries.size() >= MaximumEntries || m_totalBytes + bytes > MaximumTotalBytes)) {
            const QString evictedKey = m_lru.takeFirst();
            const auto evicted = m_entries.find(evictedKey);
            if (evicted != m_entries.end()) {
                m_totalBytes -= evicted->bytes;
                m_entries.erase(evicted);
            }
        }
        m_entries.insert(key, Entry{std::move(image), bytes});
        m_lru.append(key);
        m_totalBytes += bytes;
        ++m_revision;
    }
    Q_EMIT revisionChanged();
    return true;
}

bool PreviewFrameCache::remove(const QString &windowUuid)
{
    const QString key = imageKey(windowUuid);
    if (key.isEmpty()) {
        return false;
    }
    {
        QMutexLocker locker(&m_mutex);
        const auto it = m_entries.find(key);
        if (it == m_entries.end()) {
            return false;
        }
        m_totalBytes -= it->bytes;
        m_entries.erase(it);
        m_lru.removeAll(key);
        ++m_revision;
    }
    Q_EMIT revisionChanged();
    return true;
}

void PreviewFrameCache::clear()
{
    {
        QMutexLocker locker(&m_mutex);
        if (m_entries.isEmpty()) {
            return;
        }
        m_entries.clear();
        m_lru.clear();
        m_totalBytes = 0;
        ++m_revision;
    }
    Q_EMIT revisionChanged();
}

} // namespace kdockw
