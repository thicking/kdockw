// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "shell/previewcontroller.h"

#include <catch2/catch_test_macros.hpp>

#include <QByteArray>

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
