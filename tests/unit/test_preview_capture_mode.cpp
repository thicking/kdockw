// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "shell/previewcontroller.h"
#include "shell/previewcapturepolicy.h"

#include "app/application.h"
#include "kdockw.h"

#include <catch2/catch_test_macros.hpp>

#include <QByteArray>
#include <QCoreApplication>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSignalSpy>
#include <QTemporaryDir>

#include <KConfig>

#include <memory>

namespace
{
class CaptureModeEnvironment
{
public:
    CaptureModeEnvironment()
        : m_wasSet(qEnvironmentVariableIsSet("KDOCKW_PREVIEW_CAPTURE_MODE"))
        , m_previous(qgetenv("KDOCKW_PREVIEW_CAPTURE_MODE"))
    {
    }

    ~CaptureModeEnvironment()
    {
        if (m_wasSet) {
            qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", m_previous);
        } else {
            qunsetenv("KDOCKW_PREVIEW_CAPTURE_MODE");
        }
    }

private:
    bool m_wasSet;
    QByteArray m_previous;
};

class ScopedConfigHome
{
public:
    ScopedConfigHome()
        : m_previous(qgetenv("XDG_CONFIG_HOME"))
        , m_hadPrevious(qEnvironmentVariableIsSet("XDG_CONFIG_HOME"))
    {
        qputenv("XDG_CONFIG_HOME", m_dir.path().toLocal8Bit());
    }

    ~ScopedConfigHome()
    {
        if (m_hadPrevious) {
            qputenv("XDG_CONFIG_HOME", m_previous);
        } else {
            qunsetenv("XDG_CONFIG_HOME");
        }
    }

    QString path() const { return m_dir.path(); }

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};
}

TEST_CASE("Software renderers use CPU-readable PipeWire capture without changing user preferences", "[preview]")
{
    CHECK(kdockw::previewcapturepolicy::isSoftwareRenderer("llvmpipe (LLVM 19.1.7, 256 bits)"));
    CHECK(kdockw::previewcapturepolicy::isSoftwareRenderer("Mesa X11 swrast"));
    CHECK(kdockw::previewcapturepolicy::isSoftwareRenderer("SwiftShader Device (Subzero)"));
    CHECK_FALSE(kdockw::previewcapturepolicy::isSoftwareRenderer("AMD Radeon RX 7800 XT"));

    CHECK(kdockw::previewcapturepolicy::cpuCaptureOnly(true, false, true, false, false));
    CHECK(kdockw::previewcapturepolicy::cpuCaptureOnly(false, true, true, false, false));
    CHECK_FALSE(kdockw::previewcapturepolicy::cpuCaptureOnly(false, false, true, false, true));
    CHECK(kdockw::previewcapturepolicy::cpuCaptureOnly(false, false, false, false, true));
    CHECK_FALSE(kdockw::previewcapturepolicy::cpuCaptureOnly(false, false, false, false, false));
}

TEST_CASE("Preview capture mode is selected per process environment", "[preview]")
{
    CaptureModeEnvironment restoreEnvironment;

    SECTION("Unset and auto select the normal DMA-BUF-preferred path")
    {
        qunsetenv("KDOCKW_PREVIEW_CAPTURE_MODE");
        kdockw::PreviewController controller(nullptr, nullptr, nullptr);
        REQUIRE_FALSE(controller.cpuCaptureOnly());

        qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "auto");
        kdockw::PreviewController autoController(nullptr, nullptr, nullptr);
        REQUIRE_FALSE(autoController.cpuCaptureOnly());
    }

    SECTION("cpu-only selects CPU-readable buffers from item creation")
    {
        qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "cpu-only");
        kdockw::PreviewController controller(nullptr, nullptr, nullptr);
        REQUIRE(controller.cpuCaptureOnly());
    }

    SECTION("Unknown values safely fall back to auto")
    {
        qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "invalid");
        kdockw::PreviewController controller(nullptr, nullptr, nullptr);
        REQUIRE_FALSE(controller.cpuCaptureOnly());
    }
}

TEST_CASE("Saved capture mode applies live and environment overrides take precedence", "[preview][settings]")
{
    ScopedConfigHome configHome;
    CaptureModeEnvironment restoreEnvironment;
    qunsetenv("KDOCKW_PREVIEW_CAPTURE_MODE");

    KDockWSettings settings;
    settings.setConfig(std::make_unique<KConfig>(configHome.path() + QStringLiteral("/kdockwrc"), KConfig::SimpleConfig));
    settings.load();
    REQUIRE_FALSE(settings.cpuOnlyPreviewCapture());

    QObject saveContext;
    kdockw::Application::connectSettingsAutoSave(&settings, &saveContext);
    kdockw::PreviewController controller(nullptr, nullptr, &settings);
    QSignalSpy modeChanged(&controller, &kdockw::PreviewController::captureModeChanged);

    settings.setCpuOnlyPreviewCapture(true);
    CHECK(controller.cpuCaptureOnly());
    CHECK(modeChanged.count() == 1);
    {
        KDockWSettings restarted;
        restarted.setConfig(std::make_unique<KConfig>(configHome.path() + QStringLiteral("/kdockwrc"), KConfig::SimpleConfig));
        restarted.load();
        CHECK(restarted.cpuOnlyPreviewCapture());
    }
    {
        QProcess process;
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("XDG_CONFIG_HOME"), configHome.path());
        environment.remove(QStringLiteral("KDOCKW_PREVIEW_CAPTURE_MODE"));
        process.setProcessEnvironment(environment);
        process.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--verify-preview-capture-mode"), QStringLiteral("cpu-only")});
        REQUIRE(process.waitForStarted());
        REQUIRE(process.waitForFinished());
        CHECK(process.exitStatus() == QProcess::NormalExit);
        CHECK(process.exitCode() == 0);
    }

    settings.setCpuOnlyPreviewCapture(false);
    CHECK_FALSE(controller.cpuCaptureOnly());
    CHECK(modeChanged.count() == 2);

    settings.setCpuOnlyPreviewCapture(true);
    settings.save();
    qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "unrecognized");
    kdockw::PreviewController invalidOverride(nullptr, nullptr, &settings);
    CHECK_FALSE(invalidOverride.captureModeOverridden());
    CHECK(invalidOverride.cpuCaptureOnly());

    qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "auto");
    kdockw::PreviewController autoOverride(nullptr, nullptr, &settings);
    CHECK(autoOverride.captureModeOverridden());
    CHECK_FALSE(autoOverride.cpuCaptureOnly());
    CHECK(settings.cpuOnlyPreviewCapture());

    settings.setCpuOnlyPreviewCapture(false);
    qputenv("KDOCKW_PREVIEW_CAPTURE_MODE", "cpu-only");
    kdockw::PreviewController cpuOverride(nullptr, nullptr, &settings);
    CHECK(cpuOverride.captureModeOverridden());
    CHECK(cpuOverride.cpuCaptureOnly());
    CHECK_FALSE(settings.cpuOnlyPreviewCapture());
    KDockWSettings restartedAfterOverride;
    restartedAfterOverride.setConfig(std::make_unique<KConfig>(configHome.path() + QStringLiteral("/kdockwrc"), KConfig::SimpleConfig));
    restartedAfterOverride.load();
    CHECK_FALSE(restartedAfterOverride.cpuOnlyPreviewCapture());
}
