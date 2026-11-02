// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "dockwidget.h"

namespace kdockw
{

DockWidget::DockWidget(QObject *parent)
    : QObject(parent)
{
}

DockWidget::~DockWidget() = default;

} // namespace kdockw
