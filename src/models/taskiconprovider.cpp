// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "taskiconprovider.h"
#include "icondiag.h"

#include <QImage>
#include <QMutexLocker>
#include <QPainter>
#include <QUrl>
#include <QUrlQuery>
#include <QStringList>

#include <algorithm>
#include <cmath>

namespace kdockw
{

QMutex TaskIconProvider::s_rawIconsMutex;
QCache<QString, QIcon> TaskIconProvider::s_rawIcons{TaskIconProvider::kRawIconCacheCapacity};

TaskIconProvider::TaskIconProvider(bool normalizationEnabled, IconDiagnostics *diagnostics)
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
    , m_normalizationEnabled(normalizationEnabled)
    , m_diagnostics(diagnostics)
{
}

void TaskIconProvider::registerRawIcon(const QString &key, const QIcon &icon)
{
    if (key.isEmpty() || icon.isNull()) {
        return;
    }
    // QCache owns the copy and deletes the replaced value. This gives raw
    // artwork explicit replacement and bounded lifetime semantics while
    // allowing every DockView provider to resolve the same opaque source.
    const QMutexLocker locker(&s_rawIconsMutex);
    s_rawIcons.insert(key, new QIcon(icon));
}

void TaskIconProvider::clearRawIcons()
{
    const QMutexLocker locker(&s_rawIconsMutex);
    s_rawIcons.clear();
}

QPixmap TaskIconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    // Parse "org.kde.dolphin?v=0" → iconName = "org.kde.dolphin"
    const int queryIdx = id.indexOf(QLatin1Char('?'));
    const QString iconName = (queryIdx >= 0) ? id.left(queryIdx) : id;
    QString appId;
    QString launcherUrl;
    if (m_diagnostics && m_diagnostics->debugEnabled() && queryIdx >= 0) {
        const QUrlQuery query(QUrl(QStringLiteral("image://icon/") + id));
        appId = query.queryItemValue(QStringLiteral("diag-app"), QUrl::FullyDecoded);
        launcherUrl = query.queryItemValue(QStringLiteral("diag-launcher"), QUrl::FullyDecoded);
    }

    const int width = requestedSize.width() > 0 ? requestedSize.width() : 48;
    const int height = requestedSize.height() > 0 ? requestedSize.height() : 48;
    const int targetSize = std::max(width, height);
    const qreal dpr = m_diagnostics && m_diagnostics->testHiDpiEnabled()
        ? std::max<qreal>(1.0, m_diagnostics->windowDevicePixelRatio())
        : 1.0;
    const int targetPixels = static_cast<int>(std::ceil(targetSize * dpr));

    // Nameless task decorations are registered under opaque keys by
    // DockModel. Theme names remain the first-class path for named icons.
    QIcon icon;
    QString sourceType;
    {
        const QMutexLocker locker(&s_rawIconsMutex);
        if (const QIcon *rawIcon = s_rawIcons.object(iconName)) {
            icon = *rawIcon;
            sourceType = QStringLiteral("taskmanager-decoration");
        }
    }
    if (icon.isNull()) {
        icon = QIcon::fromTheme(iconName);
        if (!icon.isNull()) {
            sourceType = QStringLiteral("theme-name");
        }
    }
    if (icon.isNull()) {
        icon = QIcon(iconName);
        if (!icon.isNull()) {
            sourceType = QStringLiteral("file-or-icon-name");
        }
    }
    if (icon.isNull()) {
        icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        sourceType = QStringLiteral("fallback-theme-icon");
    }

    bool normalizationEnabled;
    qreal iconScale;
    {
        const QMutexLocker locker(&m_mutex);
        normalizationEnabled = m_normalizationEnabled;
        iconScale = m_iconScale;
    }

    QPixmap result;
    bool normalizationCacheHit = false;

    // Fast path: normalization disabled
    if (!normalizationEnabled) {
        result = icon.pixmap(QSize(targetSize, targetSize), dpr);
        if (result.isNull()) {
            result = QPixmap(targetPixels, targetPixels);
            result.fill(Qt::transparent);
        }
    } else {
        // Analyze icon padding (cached)
        auto info = analyzeIcon(iconName, icon, &normalizationCacheHit);

        // Shape correction only applies when there's actual padding to reclaim.
        // If the bounding box already fills the canvas (contentRatio > 0.95), scaling up
        // would clip the icon edges — so skip normalization entirely.
        // For icons WITH padding, use effective ratio that penalizes round shapes
        // (a circle's visual mass is ~sqrt(π/4) ≈ 89% of same-bbox square).
        const bool hasSignificantPadding = info.contentRatio < 0.95;
        const qreal effectiveRatio = hasSignificantPadding ? info.contentRatio * std::sqrt(info.fillRatio) : info.contentRatio;

        // If content fills most of the icon (accounting for shape), skip normalization.
        // Shrink so that content fills exactly kEdgeToEdgeFill of the canvas,
        // matching the target fill used by normalizePixmap for square icons.
        if (effectiveRatio >= kMinContentRatio) {
            const qreal shrinkFactor = (info.contentRatio > kEdgeToEdgeFill) ? kEdgeToEdgeFill / info.contentRatio : 1.0;
            result = shrinkPixmap(icon, targetPixels, shrinkFactor, dpr);
        } else {
            // Normalize: crop padding and rescale
            result = normalizePixmap(icon, targetPixels, info, dpr);
        }
    }

    // Apply uniform icon scale (adds equal padding around all icons)
    if (iconScale < 1.0) {
        int shrunkSize = static_cast<int>(std::round(targetPixels * iconScale));
        QImage scaled = result.toImage().scaled(shrunkSize, shrunkSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        result = QPixmap(targetPixels, targetPixels);
        result.fill(Qt::transparent);
        QPainter painter(&result);
        painter.drawImage((targetPixels - scaled.width()) / 2, (targetPixels - scaled.height()) / 2, scaled);
        painter.end();
    }

    result.setDevicePixelRatio(dpr);

    if (size) {
        *size = QSize(static_cast<int>(std::ceil(result.width() / dpr)),
                      static_cast<int>(std::ceil(result.height() / dpr)));
    }
    if (m_diagnostics && m_diagnostics->debugEnabled()) {
        const QPixmap qiconProbe = icon.pixmap(QSize(width, height), dpr);
        QStringList availableSizes;
        for (const QSize &available : icon.availableSizes()) {
            availableSizes.append(QStringLiteral("%1x%2").arg(available.width()).arg(available.height()));
        }
        const QSize logicalSize(static_cast<int>(std::ceil(result.width() / dpr)),
                                static_cast<int>(std::ceil(result.height() / dpr)));
        m_diagnostics->logIconResource(appId,
                                       launcherUrl,
                                       iconName,
                                       sourceType,
                                       QString(),
                                       QSize(width, height),
                                       dpr,
                                       qiconProbe.size(),
                                       qiconProbe.devicePixelRatio(),
                                       availableSizes.join(QLatin1Char(',')),
                                       result.size(),
                                       result.devicePixelRatio(),
                                       QSizeF(logicalSize),
                                       normalizationEnabled,
                                       normalizationEnabled ? (normalizationCacheHit ? QStringLiteral("hit") : QStringLiteral("miss")) : QStringLiteral("disabled"));
    }
    return result;
}

void TaskIconProvider::setNormalizationEnabled(bool enabled)
{
    const QMutexLocker locker(&m_mutex);
    m_normalizationEnabled = enabled;
}

void TaskIconProvider::setIconScale(qreal scale)
{
    const QMutexLocker locker(&m_mutex);
    m_iconScale = std::clamp(scale, 0.5, 1.0);
}

void TaskIconProvider::clearCache()
{
    const QMutexLocker locker(&m_mutex);
    m_cache.clear();
    ++m_cacheGeneration;
}

QRect TaskIconProvider::findContentBounds(const QImage &image, int threshold)
{
    const int w = image.width();
    const int h = image.height();

    if (w == 0 || h == 0) {
        return {};
    }

    int top = h, bottom = -1, left = w, right = -1;

    for (int y = 0; y < h; ++y) {
        const auto *scanline = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            if (qAlpha(scanline[x]) > threshold) {
                if (y < top)
                    top = y;
                if (y > bottom)
                    bottom = y;
                if (x < left)
                    left = x;
                if (x > right)
                    right = x;
            }
        }
    }

    if (bottom < 0) {
        return {};
    }

    return QRect(left, top, right - left + 1, bottom - top + 1);
}

IconNormalizationInfo TaskIconProvider::analyzeIcon(const QString &iconName, const QIcon &icon, bool *cacheHit)
{
    // QIcon::cacheKey changes when the artwork is replaced. Include it in
    // the normalization key so geometry cannot outlive the pixels it describes.
    const QString cacheKey = iconName + QLatin1Char('\x1f')
        + QString::number(static_cast<qulonglong>(icon.cacheKey()), 16);
    quint64 cacheGeneration;
    {
        const QMutexLocker locker(&m_mutex);
        const auto it = m_cache.constFind(cacheKey);
        if (it != m_cache.constEnd()) {
            if (cacheHit) {
                *cacheHit = true;
            }
            return it.value();
        }
        cacheGeneration = m_cacheGeneration;
    }
    if (cacheHit) {
        *cacheHit = false;
    }

    // Determine probe size: use the largest available raster, or 256 for SVG
    const auto sizes = icon.availableSizes();
    int probeSize = 256;
    if (!sizes.isEmpty()) {
        // Find the largest available size
        for (const auto &s : sizes) {
            int maxDim = std::max(s.width(), s.height());
            if (maxDim > probeSize) {
                probeSize = maxDim;
            }
        }
    }
    // For SVG icons, availableSizes() is empty; 256 is a good probe size

    QImage probeImage = icon.pixmap(QSize(probeSize, probeSize), 1.0).toImage();
    if (probeImage.isNull() || probeImage.format() != QImage::Format_ARGB32_Premultiplied) {
        probeImage = probeImage.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    }

    QRect bounds = findContentBounds(probeImage, kAlphaThreshold);

    IconNormalizationInfo info;
    info.probeSize = probeSize;

    if (bounds.isEmpty()) {
        // Fully transparent icon — treat as no padding
        info.contentRatio = 1.0;
        info.fillRatio = 1.0;
        info.contentBounds = QRect(0, 0, probeSize, probeSize);
    } else {
        int contentDim = std::max(bounds.width(), bounds.height());
        info.contentRatio = static_cast<qreal>(contentDim) / probeSize;
        info.contentBounds = bounds;

        // Count non-transparent pixels within content bounds to measure shape fill.
        // Square icon fills ~100% of bbox, circle fills ~π/4 ≈ 78.5%.
        int contentPixels = 0;
        for (int y = bounds.top(); y <= bounds.bottom(); ++y) {
            const auto *scanline = reinterpret_cast<const QRgb *>(probeImage.constScanLine(y));
            for (int x = bounds.left(); x <= bounds.right(); ++x) {
                if (qAlpha(scanline[x]) > kAlphaThreshold) {
                    ++contentPixels;
                }
            }
        }
        const qreal bboxArea = static_cast<qreal>(bounds.width()) * bounds.height();
        info.fillRatio = (bboxArea > 0) ? contentPixels / bboxArea : 1.0;
    }

    {
        const QMutexLocker locker(&m_mutex);
        // Do not repopulate a cache cleared while the probe was rendering.
        if (cacheGeneration == m_cacheGeneration) {
            m_cache.insert(cacheKey, info);
        }
    }
    return info;
}

QPixmap TaskIconProvider::normalizePixmap(const QIcon &icon, int targetSize, const IconNormalizationInfo &info, qreal dpr)
{
    // Adaptive margin: circular icons (low fillRatio) have inherent visual spacing
    // in their transparent corners, so they need less explicit margin.
    // Square (fill≈1.0) → full margin (4%), Circle (fill≈0.785) → minimal margin (1%).
    const qreal margin = (info.fillRatio < 0.95) ? 0.01 : kMinMarginRatio;
    const qreal maxFill = 1.0 - margin * 2;

    const qreal effectiveRatio = info.contentRatio * std::sqrt(info.fillRatio);
    qreal targetFill = std::min(effectiveRatio * kMaxEffectiveScale, maxFill);
    int targetContentPx = static_cast<int>(std::round(targetSize * targetFill));

    // How large we need to load the icon so that its content region is >= targetContentPx
    int requiredLoadSize = static_cast<int>(std::ceil(static_cast<qreal>(targetContentPx) / info.contentRatio / dpr));

    // Determine actual load size
    const auto sizes = icon.availableSizes();
    int loadSize = requiredLoadSize;

    if (!sizes.isEmpty()) {
        // Raster icon: find smallest available size >= requiredLoadSize
        int bestSize = 0;
        int largestAvailable = 0;
        for (const auto &s : sizes) {
            int maxDim = std::max(s.width(), s.height());
            if (maxDim >= requiredLoadSize && (bestSize == 0 || maxDim < bestSize)) {
                bestSize = maxDim;
            }
            if (maxDim > largestAvailable) {
                largestAvailable = maxDim;
            }
        }
        loadSize = (bestSize > 0) ? bestSize : largestAvailable;
    }
    // SVG: loadSize = requiredLoadSize (exact render)

    // Load icon at the determined size
    QImage loadedImage = icon.pixmap(QSize(loadSize, loadSize), dpr).toImage();
    if (loadedImage.isNull()) {
        QPixmap fallback(targetSize, targetSize);
        fallback.fill(Qt::transparent);
        fallback.setDevicePixelRatio(dpr);
        return fallback;
    }
    if (loadedImage.format() != QImage::Format_ARGB32_Premultiplied) {
        loadedImage = loadedImage.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    }

    // Find actual content bounds in the loaded image
    QRect bounds = findContentBounds(loadedImage, kAlphaThreshold);
    if (bounds.isEmpty()) {
        return icon.pixmap(QSize(static_cast<int>(std::ceil(targetSize / dpr)), static_cast<int>(std::ceil(targetSize / dpr))), dpr);
    }

    // Expand to square, centered on the content center
    int contentDim = std::max(bounds.width(), bounds.height());
    int cx = bounds.center().x();
    int cy = bounds.center().y();
    int half = contentDim / 2;

    QRect squareBounds(cx - half, cy - half, contentDim, contentDim);

    // Clamp to image bounds
    squareBounds = squareBounds.intersected(loadedImage.rect());

    // Crop the content
    QImage cropped = loadedImage.copy(squareBounds);

    // Scale the cropped content to targetContentPx
    QImage scaled = cropped.scaled(targetContentPx, targetContentPx, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    // Place centered on the target canvas
    QPixmap result(targetSize, targetSize);
    result.fill(Qt::transparent);
    QPainter painter(&result);
    int offsetX = (targetSize - scaled.width()) / 2;
    int offsetY = (targetSize - scaled.height()) / 2;
    painter.drawImage(offsetX, offsetY, scaled);
    painter.end();
    result.setDevicePixelRatio(dpr);

    return result;
}

QPixmap TaskIconProvider::shrinkPixmap(const QIcon &icon, int targetSize, qreal shrinkFactor, qreal dpr)
{
    const int logicalTargetSize = static_cast<int>(std::ceil(targetSize / dpr));
    QPixmap original = icon.pixmap(QSize(logicalTargetSize, logicalTargetSize), dpr);
    if (original.isNull()) {
        original = QPixmap(targetSize, targetSize);
        original.fill(Qt::transparent);
        original.setDevicePixelRatio(dpr);
        return original;
    }

    int shrunkSize = static_cast<int>(std::round(targetSize * shrinkFactor));
    QImage scaled = original.toImage().scaled(shrunkSize, shrunkSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    QPixmap result(targetSize, targetSize);
    result.fill(Qt::transparent);
    QPainter painter(&result);
    int offsetX = (targetSize - scaled.width()) / 2;
    int offsetY = (targetSize - scaled.height()) / 2;
    painter.drawImage(offsetX, offsetY, scaled);
    painter.end();
    result.setDevicePixelRatio(dpr);

    return result;
}

} // namespace kdockw
