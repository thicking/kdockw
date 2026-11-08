// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QHash>
#include <QStringList>

namespace kdockw
{

/**
 * Bounded, process-local cache of the last rendered thumbnail for minimized
 * windows. Images are keyed by the exact TaskManager UUID and never persisted.
 */
class PreviewFrameCache : public QObject
{
    Q_OBJECT
    Q_PROPERTY(quint64 revision READ revision NOTIFY revisionChanged)

public:
    explicit PreviewFrameCache(QObject *parent = nullptr);

    [[nodiscard]] quint64 revision() const;
    [[nodiscard]] QString imageKey(const QString &windowUuid) const;
    [[nodiscard]] QString imageUrl(const QString &windowUuid) const;
    [[nodiscard]] bool contains(const QString &windowUuid) const;
    [[nodiscard]] QImage imageForKey(const QString &key) const;
    [[nodiscard]] qsizetype entryCount() const;
    [[nodiscard]] qsizetype totalBytes() const;

    bool store(const QString &windowUuid, const QImage &image);
    bool remove(const QString &windowUuid);
    void clear();

Q_SIGNALS:
    void revisionChanged();

private:
    struct Entry {
        QImage image;
        qsizetype bytes = 0;
    };

    static constexpr qsizetype MaximumEntries = 4;
    static constexpr qsizetype MaximumImageBytes = 1024 * 1024;
    static constexpr qsizetype MaximumTotalBytes = MaximumEntries * MaximumImageBytes;
    static constexpr int MaximumWidth = 640;
    static constexpr int MaximumHeight = 400;

    mutable QMutex m_mutex;
    QHash<QString, Entry> m_entries;
    mutable QStringList m_lru;
    qsizetype m_totalBytes = 0;
    quint64 m_revision = 0;
};

} // namespace kdockw
