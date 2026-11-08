// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Qt Quick Test runner for KDockW's QML components.
//
// The real QML files under src/qml are loaded unchanged. Their C++ backends
// are replaced by test doubles:
//  - mocks/com/thicking/kdockw/*.qml  — QML singletons for DockModel,
//  DockSettings,
//    DockView, DockVisibility, DockActions, DockContextMenu, PreviewController,
//    NotificationTracker (production registers these as singletons/context
//    properties from C++).
//  - qmltestmocks.cpp            — org.kde.taskmanager / org.kde.pipewire
//  types.
// i18n() is provided by the real KLocalizedContext, exactly as in DockView.

#include "qmltestmocks.h"
#include "utils/springzoomcontroller.h"

#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <QPointF>
#include <QColor>
#include <QQuickImageProvider>
#include <QQmlContext>
#include <QQmlEngine>
#include <QImage>
#include <QRectF>
#include <QSize>
#include <QString>
#include <QVariant>
#include <QtQuickTest>

#include <clocale>

class MockPreviewFrameImageProvider final : public QQuickImageProvider {
public:
  MockPreviewFrameImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

  QImage requestImage(const QString &, QSize *size,
                      const QSize &requestedSize) override {
    const QSize imageSize = requestedSize.isValid() ? requestedSize : QSize(32, 20);
    if (size)
      *size = imageSize;
    QImage image(imageSize, QImage::Format_ARGB32_Premultiplied);
    image.fill(QColor(QStringLiteral("#5277aa")));
    return image;
  }
};

class MockIconDiagnostics : public QObject {
  Q_OBJECT
  Q_PROPERTY(
      bool debugEnabled READ debugEnabled WRITE setDebugEnabled NOTIFY changed)
  Q_PROPERTY(bool testHiDpiEnabled READ testHiDpiEnabled WRITE
                 setTestHiDpiEnabled NOTIFY changed)
  Q_PROPERTY(bool testBadgeLayerOff READ testBadgeLayerOff WRITE
                 setTestBadgeLayerOff NOTIFY changed)
  Q_PROPERTY(bool testBadgeShadowOff READ testBadgeShadowOff WRITE
                 setTestBadgeShadowOff NOTIFY changed)
  Q_PROPERTY(bool testBadgeCrisp READ testBadgeCrisp WRITE setTestBadgeCrisp
                 NOTIFY changed)
  Q_PROPERTY(bool testBadgeCrispStable READ testBadgeCrispStable WRITE
                 setTestBadgeCrispStable NOTIFY changed)
  Q_PROPERTY(bool testBadgeMetrics READ testBadgeMetrics WRITE
                 setTestBadgeMetrics NOTIFY changed)
  Q_PROPERTY(bool testBadgeSeparate READ testBadgeSeparate WRITE
                 setTestBadgeSeparate NOTIFY changed)
  Q_PROPERTY(bool testBadgeOverlay READ testBadgeOverlay WRITE
                 setTestBadgeOverlay NOTIFY changed)
  Q_PROPERTY(bool testBadgeTextQt READ testBadgeTextQt WRITE
                 setTestBadgeTextQt NOTIFY changed)
  Q_PROPERTY(bool testBadgeTextNative READ testBadgeTextNative WRITE
                 setTestBadgeTextNative NOTIFY changed)
  Q_PROPERTY(QString previewClipMode READ previewClipMode WRITE
                 setPreviewClipMode NOTIFY changed)
  Q_PROPERTY(QString previewSourceMode READ previewSourceMode WRITE
                 setPreviewSourceMode NOTIFY changed)
  Q_PROPERTY(bool previewSceneGraphTrace READ previewSceneGraphTrace WRITE
                 setPreviewSceneGraphTrace NOTIFY changed)
  Q_PROPERTY(bool previewCaptureMetrics READ previewCaptureMetrics CONSTANT)
  Q_PROPERTY(qreal windowDevicePixelRatio READ windowDevicePixelRatio NOTIFY
                 changed)

public:
  bool debugEnabled() const { return m_debugEnabled; }
  bool testHiDpiEnabled() const { return m_testHiDpiEnabled; }
  bool testBadgeLayerOff() const { return m_testBadgeLayerOff; }
  bool testBadgeShadowOff() const { return m_testBadgeShadowOff; }
  bool testBadgeCrisp() const { return m_testBadgeCrisp; }
  bool testBadgeCrispStable() const { return m_testBadgeCrispStable; }
  bool testBadgeMetrics() const { return m_testBadgeMetrics; }
  bool testBadgeSeparate() const { return m_testBadgeSeparate; }
  bool testBadgeOverlay() const { return m_testBadgeOverlay; }
  bool testBadgeTextQt() const { return m_testBadgeTextQt; }
  bool testBadgeTextNative() const { return m_testBadgeTextNative; }
  QString previewClipMode() const { return m_previewClipMode; }
  QString previewSourceMode() const { return m_previewSourceMode; }
  bool previewSceneGraphTrace() const { return m_previewSceneGraphTrace; }
  bool previewCaptureMetrics() const { return false; }
  qreal windowDevicePixelRatio() const { return 1.0; }

  void setDebugEnabled(bool value) { assign(m_debugEnabled, value); }
  void setTestHiDpiEnabled(bool value) { assign(m_testHiDpiEnabled, value); }
  void setTestBadgeLayerOff(bool value) { assign(m_testBadgeLayerOff, value); }
  void setTestBadgeShadowOff(bool value) {
    assign(m_testBadgeShadowOff, value);
  }
  void setTestBadgeCrisp(bool value) { assign(m_testBadgeCrisp, value); }
  void setTestBadgeCrispStable(bool value) {
    assign(m_testBadgeCrispStable, value);
  }
  void setTestBadgeMetrics(bool value) { assign(m_testBadgeMetrics, value); }
  void setTestBadgeSeparate(bool value) { assign(m_testBadgeSeparate, value); }
  void setTestBadgeOverlay(bool value) { assign(m_testBadgeOverlay, value); }
  void setTestBadgeTextQt(bool value) { assign(m_testBadgeTextQt, value); }
  void setTestBadgeTextNative(bool value) {
    assign(m_testBadgeTextNative, value);
  }
  void setPreviewClipMode(const QString &value) {
    if (m_previewClipMode == value)
      return;
    m_previewClipMode = value;
    Q_EMIT changed();
  }
  void setPreviewSourceMode(const QString &value) {
    if (m_previewSourceMode == value)
      return;
    m_previewSourceMode = value;
    Q_EMIT changed();
  }
  void setPreviewSceneGraphTrace(bool value) { assign(m_previewSceneGraphTrace, value); }

  Q_INVOKABLE void logQmlImage(const QString &, const QString &,
                               const QString &, const QString &, const QSize &,
                               const QSize &, qreal) const {}
  Q_INVOKABLE void logBadge(const QString &, int, const QString &,
                            const QRectF &, qreal, qreal, bool, bool, bool,
                            bool, bool, const QSize &) const {}
  Q_INVOKABLE void logBadgeMetrics(const QString &, const QString &, int, qreal,
                                   const QPointF &, const QPointF &,
                                   const QRectF &, qreal, qreal, qreal, qreal,
                                   qreal, qreal, qreal, qreal) const {}
  Q_INVOKABLE void logBadgeOverlayRenderMetrics(
      const QString &, int, const QString &, qreal, qreal, qreal, qreal,
      qreal, qreal, qreal, const QRectF &, const QRectF &, bool, bool, qreal,
      qreal, qreal) const {}

Q_SIGNALS:
  void changed();

private:
  void assign(bool &property, bool value) {
    if (property == value)
      return;
    property = value;
    Q_EMIT changed();
  }

  bool m_debugEnabled = false;
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
};

class KDockWQmlTestSetup : public QObject {
  Q_OBJECT

public Q_SLOTS:
  void applicationAvailable() {
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    KLocalizedString::addDomainLocaleDir(QByteArrayLiteral("kdockw"),
                                         QStringLiteral(KDOCKW_DIAGNOSTIC_LOCALE_DIR));
#endif
    if (qEnvironmentVariable("LANGUAGE").startsWith(QStringLiteral("ru"))) {
      KLocalizedString::setLanguages({QStringLiteral("ru")});
      const bool russianLocaleAvailable = std::setlocale(LC_MESSAGES, "ru_RU.UTF-8") != nullptr;
      qputenv("KDOCKW_TEST_RU_LOCALE_AVAILABLE", russianLocaleAvailable ? QByteArrayLiteral("1") : QByteArrayLiteral("0"));
    }
    KDockWQmlTest::registerMockTypes();
    qmlRegisterType<kdockw::SpringZoomController>("com.thicking.kdockw", 1,
                                                  0, "SpringZoomController");
  }

  void qmlEngineAvailable(QQmlEngine *engine) {
    // Prepend so the mock modules shadow any installed real plugins.
    QStringList paths = engine->importPathList();
    paths.prepend(QStringLiteral(KDOCKW_QML_MOCKS_DIR));
    engine->setImportPathList(paths);
    engine->addImageProvider(QStringLiteral("previewframes"),
                             new MockPreviewFrameImageProvider);
    engine->rootContext()->setContextProperty(QStringLiteral("IconDiagnostics"),
                                              &iconDiagnostics);
    engine->rootContext()->setContextProperty(QStringLiteral("SettingsWindow"),
                                              &zoomLayoutEngine);
    engine->rootContext()->setContextProperty(
        QStringLiteral("testRussianLocaleAvailable"),
        qEnvironmentVariableIntValue("KDOCKW_TEST_RU_LOCALE_AVAILABLE") == 1);

    auto *localizedContext = KLocalization::setupLocalizedContext(engine);
    localizedContext->setTranslationDomain(QStringLiteral("kdockw"));
  }

private:
  MockIconDiagnostics iconDiagnostics;
  KDockWQmlTest::ZoomLayoutEngine zoomLayoutEngine;
};

QUICK_TEST_MAIN_WITH_SETUP(kdockw_qml, KDockWQmlTestSetup)

#include "main.moc"
