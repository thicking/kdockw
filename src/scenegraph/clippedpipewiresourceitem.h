// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <KPipeWire/PipeWireSourceItem>

#include <QRectF>
#include <QString>

class QSGClipNode;
class QSGNode;

namespace kdockw
{

/** Return a scene-graph clip node whose direct child is sourceRoot. */
[[nodiscard]] QSGClipNode *wrapSourceNodeWithClip(QSGNode *sourceRoot);

/**
 * Applies a rounded clip directly around KPipeWire's own scene-graph subtree.
 *
 * The clip wraps the node returned by PipeWireSourceItem::updatePaintNode().
 * It intentionally does not try to clip QML child items: Qt places those as
 * siblings of a custom paint node unless the built-in QQuickItem::clip path is
 * used.
 */
class ClippedPipeWireSourceItem : public PipeWireSourceItem
{
    Q_OBJECT
    Q_PROPERTY(QString clipMode READ clipMode WRITE setClipMode NOTIFY clipModeChanged)
    Q_PROPERTY(QRectF clipViewportRect READ clipViewportRect WRITE setClipViewportRect NOTIFY clipViewportRectChanged)
    Q_PROPERTY(qreal clipRadius READ clipRadius WRITE setClipRadius NOTIFY clipRadiusChanged)

public:
    explicit ClippedPipeWireSourceItem(QQuickItem *parent = nullptr);

    [[nodiscard]] QString clipMode() const;
    void setClipMode(const QString &mode);
    [[nodiscard]] QRectF clipViewportRect() const;
    void setClipViewportRect(const QRectF &rect);
    [[nodiscard]] qreal clipRadius() const;
    void setClipRadius(qreal radius);

Q_SIGNALS:
    void clipModeChanged();
    void clipViewportRectChanged();
    void clipRadiusChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;

private:
    void logNodeTree(const char *stage, const QSGNode *node) const;

    QString m_clipMode = QStringLiteral("rounded");
    QRectF m_clipViewportRect;
    qreal m_clipRadius = 0;
};

} // namespace kdockw
