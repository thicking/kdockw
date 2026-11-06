// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/icondiag.h"

#include <catch2/catch_test_macros.hpp>

#include <QProcessEnvironment>
#include <QScopeGuard>
#include <QStringList>
#include <QCoreApplication>
#include <QProcess>

TEST_CASE("Icon rendering experiments require the debug master switch") {
  const QStringList names{
      QStringLiteral("KDOCKW_ICON_DEBUG"),
      QStringLiteral("KDOCKW_ICON_TEST_HIDPI"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_LAYER"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_SHADOW"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_CRISP"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_CRISP_STABLE"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_METRICS"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_SEPARATE"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_OVERLAY"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_TEXT_QT"),
      QStringLiteral("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE"),
      QStringLiteral("KDOCKW_PREVIEW_CLIP_TEST"),
      QStringLiteral("KDOCKW_PREVIEW_SOURCE_TEST"),
      QStringLiteral("KDOCKW_PREVIEW_SG_TRACE"),
      QStringLiteral("KDOCKW_PREVIEW_METRICS"),
      QStringLiteral("KDOCKW_PREVIEW_FILTER_TEST"),
  };
  const QProcessEnvironment previous = QProcessEnvironment::systemEnvironment();
  const auto restoreEnvironment = qScopeGuard([&names, &previous] {
    for (const QString &name : names) {
      const QByteArray encodedName = name.toLocal8Bit();
      if (previous.contains(name)) {
        qputenv(encodedName.constData(), previous.value(name).toLocal8Bit());
      } else {
        qunsetenv(encodedName.constData());
      }
    }
  });
  Q_UNUSED(restoreEnvironment);

  for (const QString &name : names) {
    const QByteArray encodedName = name.toLocal8Bit();
    qunsetenv(encodedName.constData());
  }
  qputenv("KDOCKW_ICON_TEST_HIDPI", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_LAYER", "0");
  qputenv("KDOCKW_ICON_TEST_BADGE_SHADOW", "0");
  qputenv("KDOCKW_ICON_TEST_BADGE_CRISP", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_CRISP_STABLE", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_METRICS", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_SEPARATE", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_OVERLAY", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_TEXT_QT", "1");
  qputenv("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE", "1");
  qputenv("KDOCKW_PREVIEW_CLIP_TEST", "raw");
  qputenv("KDOCKW_PREVIEW_SOURCE_TEST", "image");
  qputenv("KDOCKW_PREVIEW_SG_TRACE", "1");
  qputenv("KDOCKW_PREVIEW_METRICS", "1");
  qputenv("KDOCKW_PREVIEW_FILTER_TEST", "linear");

  const kdockw::IconDiagnostics disabled;
  REQUIRE_FALSE(disabled.debugEnabled());
  REQUIRE_FALSE(disabled.testHiDpiEnabled());
  REQUIRE_FALSE(disabled.testBadgeLayerOff());
  REQUIRE_FALSE(disabled.testBadgeShadowOff());
  REQUIRE_FALSE(disabled.testBadgeCrisp());
  REQUIRE_FALSE(disabled.testBadgeCrispStable());
  REQUIRE_FALSE(disabled.testBadgeMetrics());
  REQUIRE_FALSE(disabled.testBadgeSeparate());
  REQUIRE_FALSE(disabled.testBadgeOverlay());
  REQUIRE_FALSE(disabled.testBadgeTextQt());
  REQUIRE_FALSE(disabled.testBadgeTextNative());
#ifdef KDOCKW_DIAGNOSTIC_BUILD
  REQUIRE(disabled.previewClipMode() == QLatin1String("raw"));
  REQUIRE(disabled.previewSourceMode() == QLatin1String("image"));
  REQUIRE(disabled.previewSceneGraphTrace());
  REQUIRE(disabled.previewCaptureMetrics());
  REQUIRE(disabled.previewFilterTest() == QLatin1String("linear"));
#else
  REQUIRE(disabled.previewClipMode().isEmpty());
  REQUIRE(disabled.previewSourceMode().isEmpty());
  REQUIRE_FALSE(disabled.previewSceneGraphTrace());
  REQUIRE_FALSE(disabled.previewCaptureMetrics());
  REQUIRE(disabled.previewFilterTest().isEmpty());
#endif

  qputenv("KDOCKW_ICON_DEBUG", "1");
  const kdockw::IconDiagnostics enabled;
  REQUIRE(enabled.debugEnabled());
  REQUIRE(enabled.testHiDpiEnabled());
  REQUIRE(enabled.testBadgeLayerOff());
  REQUIRE(enabled.testBadgeShadowOff());
  REQUIRE(enabled.testBadgeCrisp());
  REQUIRE(enabled.testBadgeCrispStable());
  REQUIRE(enabled.testBadgeMetrics());
  REQUIRE(enabled.testBadgeSeparate());
  REQUIRE(enabled.testBadgeOverlay());
  REQUIRE_FALSE(enabled.testBadgeTextQt());
  REQUIRE_FALSE(enabled.testBadgeTextNative());

  qunsetenv("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE");
  const kdockw::IconDiagnostics qtRendering;
  REQUIRE(qtRendering.testBadgeTextQt());
  REQUIRE_FALSE(qtRendering.testBadgeTextNative());

  qunsetenv("KDOCKW_ICON_TEST_BADGE_TEXT_QT");
  qputenv("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE", "1");
  const kdockw::IconDiagnostics nativeRendering;
  REQUIRE_FALSE(nativeRendering.testBadgeTextQt());
  REQUIRE(nativeRendering.testBadgeTextNative());
}

TEST_CASE("Diagnostic rendering switches are consumed before child launches") {
  QProcess process;
  QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
  environment.insert(QStringLiteral("KDOCKW_ICON_DEBUG"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_ICON_TEST_BADGE_OVERLAY"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_ICON_TEST_BADGE_METRICS"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_ICON_TEST_BADGE_TEXT_NATIVE"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_PREVIEW_CLIP_TEST"), QStringLiteral("rounded"));
  environment.insert(QStringLiteral("KDOCKW_PREVIEW_SOURCE_TEST"), QStringLiteral("image"));
  environment.insert(QStringLiteral("KDOCKW_PREVIEW_SG_TRACE"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_PREVIEW_METRICS"), QStringLiteral("1"));
  environment.insert(QStringLiteral("KDOCKW_PREVIEW_FILTER_TEST"), QStringLiteral("linear"));
  environment.remove(QStringLiteral("KDOCKW_ICON_TEST_BADGE_TEXT_QT"));
  process.setProcessEnvironment(environment);
  process.start(QCoreApplication::applicationFilePath(),
                {QStringLiteral("--verify-icon-diagnostic-environment")});
  REQUIRE(process.waitForStarted());
  REQUIRE(process.waitForFinished());
  CHECK(process.exitStatus() == QProcess::NormalExit);
  CHECK(process.exitCode() == 0);
}
