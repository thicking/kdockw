// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "icondiag.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QScreen>
#include <QVariant>

#include <algorithm>

namespace kdockw {

namespace {
bool envIsOne(const char *name) {
  return qEnvironmentVariable(name) == QLatin1String("1");
}

QString graphicsApiName(QSGRendererInterface::GraphicsApi api) {
  switch (api) {
  case QSGRendererInterface::Unknown:
    return QStringLiteral("unknown");
  case QSGRendererInterface::Software:
    return QStringLiteral("software");
  case QSGRendererInterface::OpenVG:
    return QStringLiteral("OpenVG");
  case QSGRendererInterface::OpenGL:
    return QStringLiteral("OpenGL");
  case QSGRendererInterface::Direct3D11:
    return QStringLiteral("Direct3D11");
  case QSGRendererInterface::Vulkan:
    return QStringLiteral("Vulkan");
  case QSGRendererInterface::Metal:
    return QStringLiteral("Metal");
  case QSGRendererInterface::Null:
    return QStringLiteral("null");
  case QSGRendererInterface::Direct3D12:
    return QStringLiteral("Direct3D12");
  }
  return QStringLiteral("unrecognized");
}

void emitRecord(QJsonObject object) {
  qInfo().noquote().nospace()
      << "[KDOCKW_ICON_DEBUG] "
      << QJsonDocument(object).toJson(QJsonDocument::Compact);
}
} // namespace

IconDiagnostics::IconDiagnostics(QObject *parent)
    : QObject(parent), m_debugEnabled(envIsOne("KDOCKW_ICON_DEBUG")),
      m_testHiDpiEnabled(m_debugEnabled && envIsOne("KDOCKW_ICON_TEST_HIDPI")),
      m_testBadgeLayerOff(
          m_debugEnabled &&
          qEnvironmentVariable("KDOCKW_ICON_TEST_BADGE_LAYER") ==
              QLatin1String("0")),
      m_testBadgeSeparate(m_debugEnabled &&
                          envIsOne("KDOCKW_ICON_TEST_BADGE_SEPARATE")) {
  if (m_debugEnabled) {
    QJsonObject record{
        {QStringLiteral("event"), QStringLiteral("debug-mode")},
        {QStringLiteral("testHiDpi"), m_testHiDpiEnabled},
        {QStringLiteral("testBadgeLayerOff"), m_testBadgeLayerOff},
        {QStringLiteral("testBadgeSeparate"), m_testBadgeSeparate}};
    emitRecord(record);
  }
}

bool IconDiagnostics::debugEnabled() const { return m_debugEnabled; }

bool IconDiagnostics::testHiDpiEnabled() const { return m_testHiDpiEnabled; }

bool IconDiagnostics::testBadgeLayerOff() const { return m_testBadgeLayerOff; }

bool IconDiagnostics::testBadgeSeparate() const { return m_testBadgeSeparate; }

qreal IconDiagnostics::windowDevicePixelRatio() const {
  return m_windowDpr.load(std::memory_order_relaxed);
}

void IconDiagnostics::refreshWindowDpr() {
  if (!m_window) {
    return;
  }
  const qreal current = std::max<qreal>(1.0, m_window->devicePixelRatio());
  const qreal previous =
      m_windowDpr.exchange(current, std::memory_order_relaxed);
  if (!qFuzzyCompare(previous + 1.0, current + 1.0)) {
    Q_EMIT iconDprChanged();
  }
}

void IconDiagnostics::attachWindow(QQuickWindow *window) {
  if (m_window == window) {
    return;
  }

  m_window = window;
  if (!m_debugEnabled || !m_window) {
    return;
  }
  refreshWindowDpr();

  connect(m_window, &QWindow::screenChanged, this, [this](QScreen *screen) {
    if (m_screen) {
      disconnect(m_screen, nullptr, this, nullptr);
    }
    m_screen = screen;
    if (screen) {
      connect(screen, &QScreen::physicalDotsPerInchChanged, this, [this] {
        refreshWindowDpr();
        logEnvironment(QStringLiteral("screen-dpr-changed"));
      });
    }
    refreshWindowDpr();
    logEnvironment(QStringLiteral("screen-changed"));
  });

  // screenChanged is not guaranteed to fire for the window's initial screen.
  if (m_window->screen()) {
    m_screen = m_window->screen();
    connect(m_window->screen(), &QScreen::physicalDotsPerInchChanged, this,
            [this] {
              refreshWindowDpr();
              logEnvironment(QStringLiteral("screen-dpr-changed"));
            });
  }

  connect(
      m_window, &QQuickWindow::sceneGraphInitialized, this,
      [this] {
        refreshWindowDpr();
        logEnvironment(QStringLiteral("scene-graph-initialized"));
      },
      Qt::QueuedConnection);
}

void IconDiagnostics::logEnvironment(const QString &reason) const {
  if (!m_debugEnabled) {
    return;
  }

  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("environment")},
      {QStringLiteral("reason"), reason},
      {QStringLiteral("qtVersion"), QString::fromLatin1(qVersion())},
      {QStringLiteral("windowDpr"), windowDevicePixelRatio()},
      {QStringLiteral("qtQuickBackend"), QQuickWindow::sceneGraphBackend()}};
  if (m_window) {
    record.insert(
        QStringLiteral("windowGeometryLogical"),
        QStringLiteral("%1x%2").arg(m_window->width()).arg(m_window->height()));
    if (const auto *renderer = m_window->rendererInterface()) {
      record.insert(QStringLiteral("graphicsApi"),
                    graphicsApiName(renderer->graphicsApi()));
    } else {
      record.insert(QStringLiteral("graphicsApi"),
                    QStringLiteral("unavailable"));
    }
    if (const QScreen *screen = m_window->screen()) {
      record.insert(QStringLiteral("screenName"), screen->name());
      record.insert(QStringLiteral("screenGeometryLogical"),
                    QStringLiteral("%1x%2+%3+%4")
                        .arg(screen->geometry().width())
                        .arg(screen->geometry().height())
                        .arg(screen->geometry().x())
                        .arg(screen->geometry().y()));
      record.insert(QStringLiteral("screenDpr"), screen->devicePixelRatio());
      record.insert(QStringLiteral("refreshRateHz"), screen->refreshRate());
    } else {
      record.insert(QStringLiteral("screenName"),
                    QStringLiteral("unavailable"));
    }
  } else {
    record.insert(QStringLiteral("screenName"), QStringLiteral("unavailable"));
    record.insert(QStringLiteral("graphicsApi"), QStringLiteral("unavailable"));
  }
  emitRecord(record);
}

void IconDiagnostics::logIconResource(
    const QString &appId, const QString &launcherUrl, const QString &iconId,
    const QString &sourceType, const QString &themeCandidatePath,
    const QSize &requestedLogicalSize, qreal requestedDpr,
    const QSize &qiconProbePixelSize, qreal qiconProbeDpr,
    const QString &qiconAvailableSizes, const QSize &returnedPixelSize,
    qreal returnedDpr, const QSizeF &returnedLogicalSize,
    bool normalizationEnabled, const QString &normalizationCache) const {
  if (!m_debugEnabled) {
    return;
  }

  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("icon-resource")},
      {QStringLiteral("appId"), appId},
      {QStringLiteral("launcherUrl"), launcherUrl},
      {QStringLiteral("iconId"), iconId},
      {QStringLiteral("sourceType"), sourceType},
      {QStringLiteral("themeLookupCandidatePath"),
       themeCandidatePath.isEmpty() ? QJsonValue(QJsonValue::Null)
                                    : QJsonValue(themeCandidatePath)},
      {QStringLiteral("requestedLogicalSize"),
       QStringLiteral("%1x%2")
           .arg(requestedLogicalSize.width())
           .arg(requestedLogicalSize.height())},
      {QStringLiteral("requestedDpr"), requestedDpr},
      {QStringLiteral("qiconProbePixelSize"),
       QStringLiteral("%1x%2")
           .arg(qiconProbePixelSize.width())
           .arg(qiconProbePixelSize.height())},
      {QStringLiteral("qiconProbeDpr"), qiconProbeDpr},
      {QStringLiteral("qiconAvailableLogicalSizes"), qiconAvailableSizes},
      {QStringLiteral("returnedPixelSize"),
       QStringLiteral("%1x%2")
           .arg(returnedPixelSize.width())
           .arg(returnedPixelSize.height())},
      {QStringLiteral("returnedDpr"), returnedDpr},
      {QStringLiteral("returnedLogicalSize"),
       QStringLiteral("%1x%2")
           .arg(returnedLogicalSize.width())
           .arg(returnedLogicalSize.height())},
      {QStringLiteral("normalizationEnabled"), normalizationEnabled},
      {QStringLiteral("normalizationCache"), normalizationCache},
      {QStringLiteral("qmlImageCache"),
       QStringLiteral(
           "provider-callback; cache hit state is not exposed by Qt Quick")}};
  emitRecord(record);
}

void IconDiagnostics::logQmlImage(const QString &reason, const QString &appId,
                                  const QString &launcherUrl,
                                  const QString &iconId, const QSize &itemSize,
                                  const QSize &sourceSize, qreal zoom) const {
  if (!m_debugEnabled) {
    return;
  }

  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("qml-image")},
      {QStringLiteral("reason"), reason},
      {QStringLiteral("appId"), appId},
      {QStringLiteral("launcherUrl"), launcherUrl},
      {QStringLiteral("iconId"), iconId},
      {QStringLiteral("itemLogicalSize"),
       QStringLiteral("%1x%2").arg(itemSize.width()).arg(itemSize.height())},
      {QStringLiteral("sourceSizePixels"), QStringLiteral("%1x%2")
                                               .arg(sourceSize.width())
                                               .arg(sourceSize.height())},
      {QStringLiteral("currentZoom"), zoom},
      {QStringLiteral("windowDpr"), windowDevicePixelRatio()}};
  emitRecord(record);
}

void IconDiagnostics::logBadge(const QString &appId, int count,
                               const QString &source, const QRectF &geometry,
                               qreal fontPixelSize, qreal zoom,
                               bool layerEnabled, bool layerSmooth,
                               const QSize &requestedLayerTextureSize) const {
  if (!m_debugEnabled) {
    return;
  }

  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("badge")},
      {QStringLiteral("appId"), appId},
      {QStringLiteral("count"), count},
      {QStringLiteral("countSource"), source},
      {QStringLiteral("geometryLogical"), QStringLiteral("%1x%2+%3+%4")
                                              .arg(geometry.width())
                                              .arg(geometry.height())
                                              .arg(geometry.x())
                                              .arg(geometry.y())},
      {QStringLiteral("fontPixelSizeBeforeFit"), fontPixelSize},
      {QStringLiteral("zoom"), zoom},
      {QStringLiteral("layerEnabled"), layerEnabled},
      {QStringLiteral("layerSmooth"), layerSmooth},
      {QStringLiteral("requestedLayerTextureSize"),
       requestedLayerTextureSize.isEmpty()
           ? QJsonValue(QStringLiteral("implicit"))
           : QJsonValue(QStringLiteral("%1x%2")
                            .arg(requestedLayerTextureSize.width())
                            .arg(requestedLayerTextureSize.height()))},
      {QStringLiteral("actualLayerTexturePixels"),
       QStringLiteral("unavailable via public QML API")}};
  emitRecord(record);
}

} // namespace kdockw
