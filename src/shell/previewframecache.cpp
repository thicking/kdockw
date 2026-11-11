// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "previewframecache.h"

#include "models/icondiag.h"

#include <QCryptographicHash>
#include <QLoggingCategory>
#include <QMutexLocker>
#include <QtMath>

#include <algorithm>
#include <cmath>

namespace kdockw
{

Q_LOGGING_CATEGORY(lcPreviewCache, "kdockw.shell.preview.cache")

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

QStringList PreviewFrameCache::windowUuids() const
{
    QMutexLocker locker(&m_mutex);
    QStringList uuids;
    uuids.reserve(m_entries.size());
    for (const Entry &entry : m_entries) {
        uuids.append(entry.windowUuid);
    }
    return uuids;
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
        if (IconDiagnostics::previewCaptureMetricsEnabled()) {
            qCDebug(lcPreviewCache) << "image-read-miss key=" << key << "entries=" << m_entries.size()
                                    << "bytes=" << m_totalBytes;
        }
        return {};
    }
    m_lru.removeAll(key);
    m_lru.append(key);
    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCDebug(lcPreviewCache) << "image-read-hit uuid=" << it->windowUuid << "key=" << key
                                << "size=" << it->image.size() << "bytes=" << it->bytes
                                << "minimized=" << it->minimized << "entries=" << m_entries.size()
                                << "total-bytes=" << m_totalBytes;
    }
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

bool PreviewFrameCache::store(const QString &windowUuid, const QImage &sourceImage, bool minimized)
{
    if (windowUuid.isEmpty() || sourceImage.isNull()) {
        if (IconDiagnostics::previewCaptureMetricsEnabled()) {
            qCDebug(lcPreviewCache) << "store-rejected empty-uuid-or-image uuid=" << windowUuid
                                    << "null=" << sourceImage.isNull();
        }
        return false;
    }

    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCDebug(lcPreviewCache) << "store-request uuid=" << windowUuid << "source-size=" << sourceImage.size()
                                << "source-bytes=" << sourceImage.sizeInBytes();
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
        while (m_entries.size() >= MaximumEntries || m_totalBytes + bytes > MaximumTotalBytes) {
            // The list is oldest first, but minimized frames are retained
            // preferentially. Only evict one when every candidate is already
            // minimized and the hard bounds still require space.
            auto eviction = std::find_if(m_lru.cbegin(), m_lru.cend(), [this](const QString &candidateKey) {
                const auto candidate = m_entries.constFind(candidateKey);
                return candidate != m_entries.cend() && !candidate->minimized;
            });
            if (eviction == m_lru.cend()) {
                eviction = m_lru.cbegin();
            }
            if (eviction == m_lru.cend()) {
                return false;
            }
            const QString evictedKey = *eviction;
            m_lru.removeAt(std::distance(m_lru.cbegin(), eviction));
            const auto evicted = m_entries.find(evictedKey);
            if (evicted != m_entries.end()) {
                if (IconDiagnostics::previewCaptureMetricsEnabled()) {
                    qCDebug(lcPreviewCache) << "evict uuid=" << evicted->windowUuid << "key=" << evictedKey
                                            << "bytes=" << evicted->bytes << "minimized=" << evicted->minimized
                                            << "reason=" << (m_entries.size() >= MaximumEntries ? "entry-limit"
                                                                                              : "byte-limit")
                                            << "incoming-key=" << key << "entries-before=" << m_entries.size()
                                            << "bytes-before=" << m_totalBytes;
                }
                m_totalBytes -= evicted->bytes;
                m_entries.erase(evicted);
            }
        }
        m_entries.insert(key, Entry{std::move(image), bytes, windowUuid, minimized});
        m_lru.append(key);
        m_totalBytes += bytes;
        ++m_revision;
        if (IconDiagnostics::previewCaptureMetricsEnabled()) {
            qCDebug(lcPreviewCache) << "store-committed uuid=" << windowUuid << "key=" << key
                                    << "size=" << m_entries.constFind(key)->image.size() << "bytes=" << bytes
                                    << "entries=" << m_entries.size() << "total-bytes=" << m_totalBytes
                                    << "revision=" << m_revision;
        }
    }
    Q_EMIT revisionChanged();
    return true;
}

bool PreviewFrameCache::setMinimized(const QString &windowUuid, bool minimized)
{
    const QString key = imageKey(windowUuid);
    if (key.isEmpty()) {
        return false;
    }

    QMutexLocker locker(&m_mutex);
    const auto it = m_entries.find(key);
    if (it == m_entries.end() || it->minimized == minimized) {
        return false;
    }
    it->minimized = minimized;
    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCDebug(lcPreviewCache) << "priority-changed uuid=" << it->windowUuid << "key=" << key
                                << "minimized=" << minimized << "entries=" << m_entries.size()
                                << "total-bytes=" << m_totalBytes;
    }
    // Keep recency and priority independent. Priority metadata changes do not
    // change the displayed image, so they must not trigger a QML image reload.
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
            if (IconDiagnostics::previewCaptureMetricsEnabled()) {
                qCDebug(lcPreviewCache) << "remove-miss uuid=" << windowUuid << "key=" << key;
            }
            return false;
        }
        if (IconDiagnostics::previewCaptureMetricsEnabled()) {
            qCDebug(lcPreviewCache) << "remove-hit uuid=" << it->windowUuid << "key=" << key
                                    << "bytes=" << it->bytes << "minimized=" << it->minimized
                                    << "entries-before=" << m_entries.size() << "bytes-before=" << m_totalBytes;
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
        if (IconDiagnostics::previewCaptureMetricsEnabled()) {
            qCDebug(lcPreviewCache) << "clear entries; revision=" << m_revision;
        }
    }
    Q_EMIT revisionChanged();
}

} // namespace kdockw
