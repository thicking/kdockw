// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "scenegraph/clippedpipewiresourceitem.h"

#include <catch2/catch_test_macros.hpp>

#include <QSGClipNode>
#include <QSGNode>

TEST_CASE("PipeWire frame scene-graph tree is a child of its clip")
{
    auto *pipeWireRenderRoot = new QSGNode;
    auto *screenImage = new QSGNode;
    auto *cursorImage = new QSGNode;
    pipeWireRenderRoot->appendChildNode(screenImage);
    pipeWireRenderRoot->appendChildNode(cursorImage);

    QSGClipNode *clip = kdockw::wrapSourceNodeWithClip(pipeWireRenderRoot);
    REQUIRE(clip);
    REQUIRE(clip->firstChild() == pipeWireRenderRoot);
    REQUIRE(pipeWireRenderRoot->parent() == clip);
    REQUIRE(pipeWireRenderRoot->firstChild() == screenImage);
    REQUIRE(screenImage->parent() == pipeWireRenderRoot);
    REQUIRE(cursorImage->parent() == pipeWireRenderRoot);

    delete clip;
}
