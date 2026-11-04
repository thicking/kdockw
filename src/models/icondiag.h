// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>
#include <QPointer>
#include <QRectF>
#include <QSize>
#include <QString>

#include <atomic>

class QQuickWindow;

namespace kdockw {

/** Opt-in, privacy-bounded diagnostics and rendering experiment switches. */
class IconDiagnostics final : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool debugEnabled READ debugEnabled CONSTANT)
  Q_PROPERTY(bool testHiDpiEnabled READ testHiDpiEnabled CONSTANT)
  Q_PROPERTY(bool testBadgeLayerOff READ testBadgeLayerOff CONSTANT)
  Q_PROPERTY(bool testBadgeSeparate READ testBadgeSeparate CONSTANT)

public:
  explicit IconDiagnostics(QObject *parent = nullptr);

  [[nodiscard]] bool debugEnabled() const;
  [[nodiscard]] bool testHiDpiEnabled() const;
  [[nodiscard]] bool testBadgeLayerOff() const;
  [[nodiscard]] bool testBadgeSeparate() const;
  [[nodiscard]] qreal windowDevicePixelRatio() const;

  void attachWindow(QQuickWindow *window);
  void logEnvironment(const QString &reason) const;
  void logIconResource(const QString &appId, const QString &launcherUrl,
                       const QString &iconId, const QString &sourceType,
                       const QString &themeCandidatePath,
                       const QSize &requestedLogicalSize, qreal requestedDpr,
                       const QSize &qiconProbePixelSize, qreal qiconProbeDpr,
                       const QString &qiconAvailableSizes,
                       const QSize &returnedPixelSize, qreal returnedDpr,
                       const QSizeF &returnedLogicalSize,
                       bool normalizationEnabled,
                       const QString &normalizationCache) const;

  Q_INVOKABLE void logQmlImage(const QString &reason, const QString &appId,
                               const QString &launcherUrl,
                               const QString &iconId, const QSize &itemSize,
                               const QSize &sourceSize, qreal zoom) const;
  Q_INVOKABLE void logBadge(const QString &appId, int count,
                            const QString &source, const QRectF &geometry,
                            qreal fontPixelSize, qreal zoom, bool layerEnabled,
                            bool layerSmooth,
                            const QSize &requestedLayerTextureSize) const;

Q_SIGNALS:
  void iconDprChanged();

private:
  void refreshWindowDpr();

  QPointer<QQuickWindow> m_window;
  QPointer<QObject> m_screen;
  std::atomic<qreal> m_windowDpr{1.0};
  bool m_debugEnabled = false;
  bool m_testHiDpiEnabled = false;
  bool m_testBadgeLayerOff = false;
  bool m_testBadgeSeparate = false;
};

} // namespace kdockw
