// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>
#include <QPointF>
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
  Q_PROPERTY(bool taskDiagnosticsEnabled READ taskDiagnosticsEnabled CONSTANT)
  Q_PROPERTY(bool testHiDpiEnabled READ testHiDpiEnabled CONSTANT)
  Q_PROPERTY(bool testBadgeLayerOff READ testBadgeLayerOff CONSTANT)
  Q_PROPERTY(bool testBadgeShadowOff READ testBadgeShadowOff CONSTANT)
  Q_PROPERTY(bool testBadgeCrisp READ testBadgeCrisp CONSTANT)
  Q_PROPERTY(bool testBadgeCrispStable READ testBadgeCrispStable CONSTANT)
  Q_PROPERTY(bool testBadgeMetrics READ testBadgeMetrics CONSTANT)
  Q_PROPERTY(bool testBadgeSeparate READ testBadgeSeparate CONSTANT)
  Q_PROPERTY(bool testBadgeOverlay READ testBadgeOverlay CONSTANT)
  Q_PROPERTY(bool testBadgeTextQt READ testBadgeTextQt CONSTANT)
  Q_PROPERTY(bool testBadgeTextNative READ testBadgeTextNative CONSTANT)
  Q_PROPERTY(QString previewClipMode READ previewClipMode CONSTANT)
  Q_PROPERTY(QString previewSourceMode READ previewSourceMode CONSTANT)
  Q_PROPERTY(bool previewSceneGraphTrace READ previewSceneGraphTrace CONSTANT)
  Q_PROPERTY(bool previewCaptureMetrics READ previewCaptureMetrics CONSTANT)
  Q_PROPERTY(QString previewFilterTest READ previewFilterTest CONSTANT)
  Q_PROPERTY(qreal windowDevicePixelRatio READ windowDevicePixelRatio NOTIFY
                 iconDprChanged)

public:
  explicit IconDiagnostics(QObject *parent = nullptr);

  [[nodiscard]] bool debugEnabled() const;
  [[nodiscard]] bool taskDiagnosticsEnabled() const;
  [[nodiscard]] bool testHiDpiEnabled() const;
  [[nodiscard]] bool testBadgeLayerOff() const;
  [[nodiscard]] bool testBadgeShadowOff() const;
  [[nodiscard]] bool testBadgeCrisp() const;
  [[nodiscard]] bool testBadgeCrispStable() const;
  [[nodiscard]] bool testBadgeMetrics() const;
  [[nodiscard]] bool testBadgeSeparate() const;
  [[nodiscard]] bool testBadgeOverlay() const;
  [[nodiscard]] bool testBadgeTextQt() const;
  [[nodiscard]] bool testBadgeTextNative() const;
  [[nodiscard]] QString previewClipMode() const;
  [[nodiscard]] QString previewSourceMode() const;
  [[nodiscard]] bool previewSceneGraphTrace() const;
  [[nodiscard]] bool previewCaptureMetrics() const;
  [[nodiscard]] QString previewFilterTest() const;
  [[nodiscard]] qreal windowDevicePixelRatio() const;

  /// Cache opt-in diagnostic switches, then remove them before launch actions
  /// can pass this process environment to child applications.
  static void prepareProcessEnvironment();
  [[nodiscard]] static bool previewSceneGraphTraceEnabled();
  [[nodiscard]] static bool previewCaptureMetricsEnabled();
  [[nodiscard]] static QString previewFilterTestMode();

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
                            bool layerSmooth, bool shadowEnabled,
                            bool crispPrototypeEnabled,
                            bool crispStablePrototypeEnabled,
                            const QSize &requestedLayerTextureSize) const;
  Q_INVOKABLE void logBadgeMetrics(
      const QString &reason, const QString &appId, int count, qreal zoom,
      const QPointF &badgeCenter, const QPointF &labelCenter,
      const QRectF &labelGeometry, qreal implicitWidth, qreal implicitHeight,
      qreal contentWidth, qreal contentHeight, qreal baselineOffset,
      qreal fontPixelSize, qreal minimumPixelSize, qreal counterScale) const;
  Q_INVOKABLE void logBadgeOverlayRenderMetrics(
      const QString &appId, int count, const QString &renderType, qreal zoom,
      qreal requestedFontPixelSize, qreal fontPixelSize,
      qreal resolvedFontPixelSize, qreal baselineOffset, qreal contentWidth,
      qreal contentHeight, const QRectF &localGeometry,
      const QRectF &rootGeometry, bool textLayerEnabled,
      bool overlayLayerEnabled, qreal textScale, qreal overlayScale,
      qreal windowDpr) const;

Q_SIGNALS:
  void iconDprChanged();

private:
  void refreshWindowDpr();

  QPointer<QQuickWindow> m_window;
  QPointer<QObject> m_screen;
  std::atomic<qreal> m_windowDpr{1.0};
  bool m_debugEnabled = false;
  bool m_taskDiagnosticsEnabled = false;
  bool m_testHiDpiEnabled = false;
  bool m_testBadgeLayerOff = false;
  bool m_testBadgeShadowOff = false;
  bool m_testBadgeCrisp = false;
  bool m_testBadgeCrispStable = false;
  bool m_testBadgeMetrics = false;
  bool m_testBadgeSeparate = false;
  bool m_testBadgeOverlay = false;
  bool m_testBadgeTextQt = false;
  bool m_testBadgeTextNative = false;
  QString m_previewClipMode;
  QString m_previewSourceMode;
  bool m_previewSceneGraphTrace = false;
  bool m_previewCaptureMetrics = false;
  QString m_previewFilterTest;
};

} // namespace kdockw
