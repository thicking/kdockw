// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include "scenegraph/clippedpipewiresourceitem.h"
#include "utils/springzoomcontroller.h"

#include <QtQml>

// Keep standalone QML harnesses aligned with the types registered by
// Application::run(). Each harness invokes this once before creating a QML
// engine that loads the production dock or preview components.
inline void registerDockQmlTypes()
{
    qmlRegisterType<kdockw::ClippedPipeWireSourceItem>("com.thicking.kdockw", 1, 0, "ClippedPipeWireSourceItem");
    qmlRegisterType<kdockw::SpringZoomController>("com.thicking.kdockw", 1, 0, "SpringZoomController");
}
