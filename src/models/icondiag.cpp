// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "icondiag.h"

#include <QDebug>
#include <QCoreApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QScreen>
#include <QVariant>

#include <algorithm>
#include <optional>

namespace kdockw {

namespace {
bool envIsOne(const char *name) {
  return qEnvironmentVariable(name) == QLatin1String("1");
}

struct DiagnosticSwitches {
  bool debug = false;
  bool taskDiagnostics = false;
  bool testHiDpi = false;
  bool testBadgeLayerOff = false;
  bool testBadgeShadowOff = false;
  bool testBadgeCrisp = false;
  bool testBadgeCrispStable = false;
  bool testBadgeMetrics = false;
  bool testBadgeSeparate = false;
  bool testBadgeOverlay = false;
  bool testBadgeTextQt = false;
  bool testBadgeTextNative = false;
  QString previewClipMode;
  QString previewSourceMode;
  bool previewSceneGraphTrace = false;
  bool previewCaptureMetrics = false;
  QString previewFilterTest;
};

DiagnosticSwitches readDiagnosticSwitches() {
  DiagnosticSwitches switches;
  switches.debug = envIsOne("KDOCKW_ICON_DEBUG");
#ifdef KDOCKW_DIAGNOSTIC_BUILD
  switches.taskDiagnostics = envIsOne("KDOCKW_TASK_DIAGNOSTICS");
#endif
  switches.testHiDpi = switches.debug && envIsOne("KDOCKW_ICON_TEST_HIDPI");
  switches.testBadgeLayerOff =
      switches.debug &&
      qEnvironmentVariable("KDOCKW_ICON_TEST_BADGE_LAYER") == QLatin1String("0");
  switches.testBadgeShadowOff =
      switches.debug &&
      qEnvironmentVariable("KDOCKW_ICON_TEST_BADGE_SHADOW") == QLatin1String("0");
  switches.testBadgeCrisp =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_CRISP");
  switches.testBadgeCrispStable =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_CRISP_STABLE");
  switches.testBadgeMetrics =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_METRICS");
  switches.testBadgeSeparate =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_SEPARATE");
  switches.testBadgeOverlay =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_OVERLAY");
  switches.testBadgeTextQt =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_TEXT_QT");
  switches.testBadgeTextNative =
      switches.debug && envIsOne("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE");
#ifdef KDOCKW_DIAGNOSTIC_BUILD
  const QString previewClipMode = qEnvironmentVariable("KDOCKW_PREVIEW_CLIP_TEST");
  if (previewClipMode == QLatin1String("raw") || previewClipMode == QLatin1String("center50")
      || previewClipMode == QLatin1String("rectangular") || previewClipMode == QLatin1String("rounded")) {
    switches.previewClipMode = previewClipMode == QLatin1String("rectangular")
        ? QStringLiteral("center50") : previewClipMode;
  }
  const QString sourceMode = qEnvironmentVariable("KDOCKW_PREVIEW_SOURCE_TEST");
  if (sourceMode == QLatin1String("pipewire") || sourceMode == QLatin1String("image")) {
    switches.previewSourceMode = sourceMode;
  }
  switches.previewSceneGraphTrace = envIsOne("KDOCKW_PREVIEW_SG_TRACE");
  switches.previewCaptureMetrics = envIsOne("KDOCKW_PREVIEW_METRICS");
  const QString filterTest = qEnvironmentVariable("KDOCKW_PREVIEW_FILTER_TEST");
  if (filterTest == QLatin1String("linear")) {
    switches.previewFilterTest = filterTest;
  }
#endif

  if (switches.testBadgeTextQt && switches.testBadgeTextNative) {
    qWarning() << "Conflicting badge text renderers requested; using the default renderer";
    switches.testBadgeTextQt = false;
    switches.testBadgeTextNative = false;
  }
  return switches;
}

std::optional<DiagnosticSwitches> s_processSwitches;

DiagnosticSwitches switchesForInstance() {
  return s_processSwitches ? *s_processSwitches : readDiagnosticSwitches();
}

void clearDiagnosticSwitchEnvironment() {
  static constexpr const char *names[] = {
      "KDOCKW_ICON_DEBUG",
      "KDOCKW_TASK_DIAGNOSTICS",
      "KDOCKW_ICON_TEST_HIDPI",
      "KDOCKW_ICON_TEST_BADGE_LAYER",
      "KDOCKW_ICON_TEST_BADGE_SHADOW",
      "KDOCKW_ICON_TEST_BADGE_CRISP",
      "KDOCKW_ICON_TEST_BADGE_CRISP_STABLE",
      "KDOCKW_ICON_TEST_BADGE_METRICS",
      "KDOCKW_ICON_TEST_BADGE_SEPARATE",
      "KDOCKW_ICON_TEST_BADGE_OVERLAY",
      "KDOCKW_ICON_TEST_BADGE_TEXT_QT",
      "KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE",
      "KDOCKW_PREVIEW_CLIP_TEST",
      "KDOCKW_PREVIEW_SOURCE_TEST",
      "KDOCKW_PREVIEW_SG_TRACE",
      "KDOCKW_PREVIEW_METRICS",
      "KDOCKW_PREVIEW_FILTER_TEST",
  };
  for (const char *name : names) {
    qunsetenv(name);
  }
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
    : QObject(parent) {
  const DiagnosticSwitches switches = switchesForInstance();
  m_debugEnabled = switches.debug;
  m_taskDiagnosticsEnabled = switches.taskDiagnostics;
  m_testHiDpiEnabled = switches.testHiDpi;
  m_testBadgeLayerOff = switches.testBadgeLayerOff;
  m_testBadgeShadowOff = switches.testBadgeShadowOff;
  m_testBadgeCrisp = switches.testBadgeCrisp;
  m_testBadgeCrispStable = switches.testBadgeCrispStable;
  m_testBadgeMetrics = switches.testBadgeMetrics;
  m_testBadgeSeparate = switches.testBadgeSeparate;
  m_testBadgeOverlay = switches.testBadgeOverlay;
  m_testBadgeTextQt = switches.testBadgeTextQt;
  m_testBadgeTextNative = switches.testBadgeTextNative;
  m_previewClipMode = switches.previewClipMode;
  m_previewSourceMode = switches.previewSourceMode;
  m_previewSceneGraphTrace = switches.previewSceneGraphTrace;
  m_previewCaptureMetrics = switches.previewCaptureMetrics;
  m_previewFilterTest = switches.previewFilterTest;

  if (m_debugEnabled) {
    QJsonObject record{
        {QStringLiteral("event"), QStringLiteral("debug-mode")},
        {QStringLiteral("testHiDpi"), m_testHiDpiEnabled},
        {QStringLiteral("testBadgeLayerOff"), m_testBadgeLayerOff},
        {QStringLiteral("testBadgeShadowOff"), m_testBadgeShadowOff},
        {QStringLiteral("testBadgeCrisp"), m_testBadgeCrisp},
        {QStringLiteral("testBadgeCrispStable"), m_testBadgeCrispStable},
        {QStringLiteral("testBadgeMetrics"), m_testBadgeMetrics},
        {QStringLiteral("testBadgeSeparate"), m_testBadgeSeparate},
        {QStringLiteral("testBadgeOverlay"), m_testBadgeOverlay},
        {QStringLiteral("testBadgeTextQt"), m_testBadgeTextQt},
        {QStringLiteral("testBadgeTextNative"), m_testBadgeTextNative},
        {QStringLiteral("previewClipMode"), m_previewClipMode}};
    record.insert(QStringLiteral("previewSourceMode"), m_previewSourceMode);
    record.insert(QStringLiteral("previewSceneGraphTrace"), m_previewSceneGraphTrace);
    record.insert(QStringLiteral("previewCaptureMetrics"), m_previewCaptureMetrics);
    record.insert(QStringLiteral("previewFilterTest"), m_previewFilterTest);
    emitRecord(record);
  }
}

void IconDiagnostics::prepareProcessEnvironment() {
  if (!s_processSwitches) {
    s_processSwitches = readDiagnosticSwitches();
  }
  if (QCoreApplication::instance()) {
    QCoreApplication::instance()->setProperty("kdockw.taskDiagnosticsEnabled", s_processSwitches->taskDiagnostics);
  }
  clearDiagnosticSwitchEnvironment();
}

bool IconDiagnostics::previewSceneGraphTraceEnabled() {
  return switchesForInstance().previewSceneGraphTrace;
}

bool IconDiagnostics::previewCaptureMetricsEnabled() {
  return switchesForInstance().previewCaptureMetrics;
}

QString IconDiagnostics::previewFilterTestMode() {
  return switchesForInstance().previewFilterTest;
}

QString IconDiagnostics::previewFilterTest() const {
  return m_previewFilterTest;
}

bool IconDiagnostics::debugEnabled() const { return m_debugEnabled; }

bool IconDiagnostics::taskDiagnosticsEnabled() const { return m_taskDiagnosticsEnabled; }

bool IconDiagnostics::testHiDpiEnabled() const { return m_testHiDpiEnabled; }

bool IconDiagnostics::testBadgeLayerOff() const { return m_testBadgeLayerOff; }

bool IconDiagnostics::testBadgeShadowOff() const {
  return m_testBadgeShadowOff;
}

bool IconDiagnostics::testBadgeCrisp() const { return m_testBadgeCrisp; }

bool IconDiagnostics::testBadgeCrispStable() const {
  return m_testBadgeCrispStable;
}

bool IconDiagnostics::testBadgeMetrics() const { return m_testBadgeMetrics; }

bool IconDiagnostics::testBadgeSeparate() const { return m_testBadgeSeparate; }

bool IconDiagnostics::testBadgeOverlay() const { return m_testBadgeOverlay; }

bool IconDiagnostics::testBadgeTextQt() const { return m_testBadgeTextQt; }

bool IconDiagnostics::testBadgeTextNative() const { return m_testBadgeTextNative; }

QString IconDiagnostics::previewClipMode() const { return m_previewClipMode; }

QString IconDiagnostics::previewSourceMode() const { return m_previewSourceMode; }

bool IconDiagnostics::previewSceneGraphTrace() const { return m_previewSceneGraphTrace; }
bool IconDiagnostics::previewCaptureMetrics() const { return m_previewCaptureMetrics; }

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
      {QStringLiteral("iconTheme"), QIcon::themeName()},
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
                               bool shadowEnabled, bool crispPrototypeEnabled,
                               bool crispStablePrototypeEnabled,
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
      {QStringLiteral("shadowEnabled"), shadowEnabled},
      {QStringLiteral("crispPrototypeEnabled"), crispPrototypeEnabled},
      {QStringLiteral("crispStablePrototypeEnabled"),
       crispStablePrototypeEnabled},
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

void IconDiagnostics::logBadgeMetrics(
    const QString &reason, const QString &appId, int count, qreal zoom,
    const QPointF &badgeCenter, const QPointF &labelCenter,
    const QRectF &labelGeometry, qreal implicitWidth, qreal implicitHeight,
    qreal contentWidth, qreal contentHeight, qreal baselineOffset,
    qreal fontPixelSize, qreal minimumPixelSize, qreal counterScale) const {
  if (!m_debugEnabled || !m_testBadgeMetrics) {
    return;
  }

  const QPointF centerDelta = labelCenter - badgeCenter;
  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("badge-metrics")},
      {QStringLiteral("reason"), reason},
      {QStringLiteral("appId"), appId},
      {QStringLiteral("count"), count},
      {QStringLiteral("zoom"), zoom},
      {QStringLiteral("badgeCenterDockLogical"),
       QStringLiteral("%1,%2").arg(badgeCenter.x()).arg(badgeCenter.y())},
      {QStringLiteral("labelCenterDockLogical"),
       QStringLiteral("%1,%2").arg(labelCenter.x()).arg(labelCenter.y())},
      {QStringLiteral("centerDeltaDockLogical"),
       QStringLiteral("%1,%2").arg(centerDelta.x()).arg(centerDelta.y())},
      {QStringLiteral("labelGeometry"), QStringLiteral("%1x%2+%3+%4")
                                            .arg(labelGeometry.width())
                                            .arg(labelGeometry.height())
                                            .arg(labelGeometry.x())
                                            .arg(labelGeometry.y())},
      {QStringLiteral("implicitSize"),
       QStringLiteral("%1x%2").arg(implicitWidth).arg(implicitHeight)},
      {QStringLiteral("contentSize"),
       QStringLiteral("%1x%2").arg(contentWidth).arg(contentHeight)},
      {QStringLiteral("baselineOffset"), baselineOffset},
      {QStringLiteral("fontPixelSize"), fontPixelSize},
      {QStringLiteral("minimumPixelSize"), minimumPixelSize},
      {QStringLiteral("counterScale"), counterScale}};
  emitRecord(record);
}

void IconDiagnostics::logBadgeOverlayRenderMetrics(
    const QString &appId, int count, const QString &renderType, qreal zoom,
    qreal requestedFontPixelSize, qreal fontPixelSize,
    qreal resolvedFontPixelSize, qreal baselineOffset, qreal contentWidth,
    qreal contentHeight, const QRectF &localGeometry,
    const QRectF &rootGeometry, bool textLayerEnabled,
    bool overlayLayerEnabled, qreal textScale, qreal overlayScale,
    qreal windowDpr) const {
  if (!m_debugEnabled || !m_testBadgeMetrics) {
    return;
  }

  QJsonObject record{
      {QStringLiteral("event"), QStringLiteral("badge-overlay-render")},
      {QStringLiteral("appId"), appId},
      {QStringLiteral("count"), count},
      {QStringLiteral("renderType"), renderType},
      {QStringLiteral("zoom"), zoom},
      {QStringLiteral("requestedFontPixelSize"), requestedFontPixelSize},
      {QStringLiteral("fontPixelSize"), fontPixelSize},
      {QStringLiteral("resolvedFontPixelSize"), resolvedFontPixelSize},
      {QStringLiteral("baselineOffset"), baselineOffset},
      {QStringLiteral("contentSize"),
       QStringLiteral("%1x%2").arg(contentWidth).arg(contentHeight)},
      {QStringLiteral("textGeometryLocal"),
       QStringLiteral("%1x%2+%3+%4")
           .arg(localGeometry.width())
           .arg(localGeometry.height())
           .arg(localGeometry.x())
           .arg(localGeometry.y())},
      {QStringLiteral("textGeometryRoot"),
       QStringLiteral("%1x%2+%3+%4")
           .arg(rootGeometry.width())
           .arg(rootGeometry.height())
           .arg(rootGeometry.x())
           .arg(rootGeometry.y())},
      {QStringLiteral("textLayerEnabled"), textLayerEnabled},
      {QStringLiteral("overlayLayerEnabled"), overlayLayerEnabled},
      {QStringLiteral("textScale"), textScale},
      {QStringLiteral("overlayScale"), overlayScale},
      {QStringLiteral("windowDpr"), windowDpr}};
  emitRecord(record);
}

} // namespace kdockw
