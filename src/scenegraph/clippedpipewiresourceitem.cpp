// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "clippedpipewiresourceitem.h"

#include "models/icondiag.h"
#include "roundedclipgeometry.h"

#include <QSGClipNode>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGImageNode>
#include <QSGOpacityNode>
#include <QSGTransformNode>
#include <QSet>
#include <QDebug>

#include <algorithm>

namespace kdockw
{

namespace
{

QSGClipNode *createClipNode()
{
    auto *clip = new QSGClipNode;
    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    clip->setGeometry(geometry);
    clip->setFlag(QSGNode::OwnsGeometry, true);
    return clip;
}

void updateClip(QSGClipNode *clip, const QRectF &rect, qreal radius, bool rectangular)
{
    const QVector<QPointF> vertices = roundedClipTriangleVertices(rect, rectangular ? 0 : radius);
    const int vertexCount = static_cast<int>(vertices.size());
    QSGGeometry *geometry = clip->geometry();
    if (geometry->vertexCount() != vertexCount) {
        geometry->allocate(vertexCount);
    }

    auto *points = geometry->vertexDataAsPoint2D();
    for (int i = 0; i < vertexCount; ++i) {
        points[i].set(vertices[i].x(), vertices[i].y());
    }

    clip->setIsRectangular(rectangular);
    clip->setClipRect(rect);
    clip->markDirty(QSGNode::DirtyGeometry);
}

QString nodeTypeName(const QSGNode *node)
{
    if (!node) {
        return QStringLiteral("null");
    }
    if (dynamic_cast<const QSGClipNode *>(node)) {
        return QStringLiteral("QSGClipNode");
    }
    if (dynamic_cast<const QSGImageNode *>(node)) {
        return QStringLiteral("QSGImageNode");
    }
    if (dynamic_cast<const QSGTransformNode *>(node)) {
        return QStringLiteral("QSGTransformNode");
    }
    if (dynamic_cast<const QSGOpacityNode *>(node)) {
        return QStringLiteral("QSGOpacityNode");
    }
    if (dynamic_cast<const QSGGeometryNode *>(node)) {
        return QStringLiteral("QSGGeometryNode");
    }
    return QStringLiteral("QSGNode/container");
}

QString filterName(QSGTexture::Filtering filter)
{
    switch (filter) {
    case QSGTexture::None:
        return QStringLiteral("none");
    case QSGTexture::Nearest:
        return QStringLiteral("nearest");
    case QSGTexture::Linear:
        return QStringLiteral("linear");
    }
    return QStringLiteral("unknown");
}

void dumpNode(const QSGNode *node, const QString &path, QStringList &lines)
{
    if (!node) {
        return;
    }

    lines.append(QStringLiteral("%1%2 children=%3")
                     .arg(path, nodeTypeName(node))
                     .arg(node->childCount()));
    if (const auto *image = dynamic_cast<const QSGImageNode *>(node)) {
        const QSGTexture *texture = image->texture();
        const QRectF rect = image->rect();
        const QRectF sourceRect = image->sourceRect();
        const QSize textureSize = texture ? texture->textureSize() : QSize();
        lines.append(QStringLiteral("%1image rect=%2 sourceRect=%3 filtering=%4 mipmapFiltering=%5 textureSize=%6 hasMipmaps=%7")
                         .arg(path)
                         .arg(QStringLiteral("[%1,%2 %3x%4]").arg(rect.x()).arg(rect.y()).arg(rect.width()).arg(rect.height()))
                         .arg(QStringLiteral("[%1,%2 %3x%4]").arg(sourceRect.x()).arg(sourceRect.y()).arg(sourceRect.width()).arg(sourceRect.height()))
                         .arg(filterName(image->filtering()))
                         .arg(filterName(image->mipmapFiltering()))
                         .arg(texture ? QStringLiteral("%1x%2").arg(textureSize.width()).arg(textureSize.height()) : QStringLiteral("none"))
                         .arg(texture && texture->hasMipmaps()));
    }
    for (const QSGNode *child = node->firstChild(); child; child = child->nextSibling()) {
        dumpNode(child, path + QStringLiteral("  "), lines);
    }
}

} // namespace

QSGClipNode *wrapSourceNodeWithClip(QSGNode *sourceRoot)
{
    if (!sourceRoot) {
        return nullptr;
    }
    auto *clip = createClipNode();
    clip->appendChildNode(sourceRoot);
    return clip;
}

ClippedPipeWireSourceItem::ClippedPipeWireSourceItem(QQuickItem *parent)
    : PipeWireSourceItem(parent)
{
    connect(this, &QQuickItem::widthChanged, this, [this] { update(); });
    connect(this, &QQuickItem::heightChanged, this, [this] { update(); });
}

QString ClippedPipeWireSourceItem::clipMode() const
{
    return m_clipMode;
}

void ClippedPipeWireSourceItem::setClipMode(const QString &mode)
{
    if (m_clipMode == mode) {
        return;
    }
    m_clipMode = mode;
    Q_EMIT clipModeChanged();
    update();
}

QRectF ClippedPipeWireSourceItem::clipViewportRect() const
{
    return m_clipViewportRect;
}

void ClippedPipeWireSourceItem::setClipViewportRect(const QRectF &rect)
{
    if (m_clipViewportRect == rect) {
        return;
    }
    m_clipViewportRect = rect;
    Q_EMIT clipViewportRectChanged();
    update();
}

qreal ClippedPipeWireSourceItem::clipRadius() const
{
    return m_clipRadius;
}

void ClippedPipeWireSourceItem::setClipRadius(qreal radius)
{
    radius = std::max(qreal(0), radius);
    if (qFuzzyCompare(m_clipRadius + 1, radius + 1)) {
        return;
    }
    m_clipRadius = radius;
    Q_EMIT clipRadiusChanged();
    update();
}

QSGNode *ClippedPipeWireSourceItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data)
{
    auto *clip = static_cast<QSGClipNode *>(oldNode);
    QSGNode *oldSourceTree = clip ? clip->firstChild() : nullptr;

    // KPipeWire's implementation expects the exact node it returned last
    // frame. Keep that source node as a child of our outer clip wrapper.
    QSGNode *sourceTree = PipeWireSourceItem::updatePaintNode(oldSourceTree, data);
    if (!sourceTree) {
        delete clip;
        return nullptr;
    }

    if (!clip) {
        clip = wrapSourceNodeWithClip(sourceTree);
    } else if (sourceTree->parent() != clip) {
        if (sourceTree->parent()) {
            sourceTree->parent()->removeChildNode(sourceTree);
        }
        clip->appendChildNode(sourceTree);
    }

    const QString filterMode = IconDiagnostics::previewFilterTestMode();
    if (filterMode == QLatin1String("linear")) {
        // KPipeWire 6.6.4 does not set QSGImageNode filtering. Its Qt 6.10
        // default image material therefore stays Nearest. This opt-in
        // diagnostic override changes only the screen image node; it adds no
        // render target or image-processing pass.
        QSGNode *node = sourceTree->firstChild();
        while (node && !dynamic_cast<QSGImageNode *>(node)) {
            node = node->firstChild();
        }
        if (auto *image = dynamic_cast<QSGImageNode *>(node)) {
            image->setFiltering(QSGTexture::Linear);
        }
    }

    const bool center50 = m_clipMode == QLatin1String("center50");
    const QRectF rect = center50
        ? QRectF(width() / 4, height() / 4, width() / 2, height() / 2)
        : (m_clipViewportRect.isValid() && !m_clipViewportRect.isEmpty() ? m_clipViewportRect : boundingRect());
    updateClip(clip, rect, m_clipRadius, center50);

    if (IconDiagnostics::previewSceneGraphTraceEnabled()) {
        logNodeTree("wrapped", clip);
        qInfo().noquote() << "[kdockw.preview.sg] geometry"
                          << "mode=" << m_clipMode
                          << "sourceItem=" << size()
                          << "sourcePosition=" << QPointF(x(), y())
                          << "clipRect=" << rect
                          << "radius=" << m_clipRadius
                          << "filterTest=" << (filterMode.isEmpty() ? QStringLiteral("baseline") : filterMode)
                          << "clipParent=" << nodeTypeName(clip->parent())
                          << "sourceParent=" << nodeTypeName(sourceTree->parent())
                          << "transformNode=" << nodeTypeName(data ? data->transformNode : nullptr);
    }

    return clip;
}

void ClippedPipeWireSourceItem::logNodeTree(const char *stage, const QSGNode *node) const
{
    QStringList lines;
    dumpNode(node, QString(), lines);
    const QString description = QStringLiteral("%1 %2").arg(QLatin1String(stage), lines.join(QStringLiteral(" | ")));
    static QSet<QString> loggedStates;
    if (loggedStates.contains(description)) {
        return;
    }
    loggedStates.insert(description);
    qInfo().noquote() << "[kdockw.preview.sg]" << description;
}

} // namespace kdockw
