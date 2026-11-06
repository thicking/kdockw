// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

namespace kdockw
{

// KWin anchors negative-exclusive-zone surfaces to output geometry. A zero
// zone instead lets KWin position the surface within the current work area.
inline constexpr int previewLayerShellExclusiveZone = -1;

} // namespace kdockw
