// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QByteArray>

namespace kdockw::previewcapturepolicy
{

/** Return true for renderer identifiers that indicate software rasterization. */
inline bool isSoftwareRenderer(const QByteArray &rendererName)
{
    const QByteArray normalized = rendererName.toLower();
    return normalized.contains("llvmpipe") || normalized.contains("softpipe") || normalized.contains("swrast")
        || normalized.contains("software rasterizer") || normalized.contains("lavapipe")
        || normalized.contains("swiftshader");
}

/** Software-renderer safety takes precedence without changing user settings. */
inline bool cpuCaptureOnly(bool rendererPending, bool softwareRenderer,
                           bool environmentOverride, bool overrideCpuOnly, bool savedCpuOnly)
{
    return rendererPending || softwareRenderer || (environmentOverride ? overrideCpuOnly : savedCpuOnly);
}

} // namespace kdockw::previewcapturepolicy
