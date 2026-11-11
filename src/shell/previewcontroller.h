// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <memory>

#include <QModelIndex>
#include <QObject>
#include <QRegion>
#include <QHash>
#include <QStringList>
#include <QSharedPointer>
#include <QWeakPointer>
#include <QTimer>
#include <QImage>
#include <QQuickItemGrabResult>

#include "style/backgroundstyle.h"

class KDockWSettings;
class QQuickView;
class QQuickItem;

namespace kdockw
{

class DockModel;
class DockView;
class PreviewFrameCache;

/**
 * Manages the preview popup window lifecycle.
 *
 * Creates a separate layer-shell overlay surface (full-width, transparent)
 * for showing PipeWire window thumbnails when hovering dock items.
 * Handles position calculation, hover transition logic, and input region.
 *
 * Preview keyboard navigation is driven from the dock surface — the dock
 * holds keyboard interactivity and forwards key events via Q_INVOKABLE methods.
 * This avoids unreliable focus transfer between layer-shell surfaces.
 */
class PreviewController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool visible READ isVisible NOTIFY visibleChanged)
    Q_PROPERTY(int parentIndex READ parentIndex NOTIFY parentIndexChanged)
    Q_PROPERTY(QModelIndex rootModelIndex READ rootModelIndex NOTIFY parentIndexChanged)
    Q_PROPERTY(bool isGrouped READ isGrouped NOTIFY parentIndexChanged)
    Q_PROPERTY(QVariantList windowIds READ windowIds NOTIFY parentIndexChanged)
    Q_PROPERTY(QString appName READ appName NOTIFY parentIndexChanged)
    Q_PROPERTY(qreal contentX READ contentX NOTIFY positionChanged)
    Q_PROPERTY(qreal contentY READ contentY NOTIFY positionChanged)
    Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentSizeChanged)
    Q_PROPERTY(qreal contentHeight READ contentHeight NOTIFY contentSizeChanged)
    Q_PROPERTY(qreal maxPopupWidth READ maxPopupWidth NOTIFY maxPopupWidthChanged)
    Q_PROPERTY(qreal previewAnchorOffset READ previewAnchorOffset NOTIFY previewAnchorOffsetChanged)
    Q_PROPERTY(bool cpuCaptureOnly READ cpuCaptureOnly NOTIFY captureModeChanged)
    Q_PROPERTY(quint64 previewFrameRevision READ previewFrameRevision NOTIFY previewFramesChanged)
    Q_PROPERTY(int dismissedTaskIndex READ dismissedTaskIndex NOTIFY dismissedTaskIndexChanged)

    // Preview keyboard navigation state (driven from dock)
    Q_PROPERTY(bool previewKeyboardActive READ isPreviewKeyboardActive NOTIFY previewKeyboardActiveChanged)
    Q_PROPERTY(int focusedThumbnailIndex READ focusedThumbnailIndex NOTIFY focusedThumbnailIndexChanged)

public:
    explicit PreviewController(DockModel *model, DockView *dockView, KDockWSettings *settings, QObject *parent = nullptr);
    ~PreviewController() override;

    /// Create the preview QQuickView and configure layer-shell.
    void initialize();

    [[nodiscard]] bool isVisible() const;
    [[nodiscard]] int parentIndex() const;
    [[nodiscard]] QModelIndex rootModelIndex() const;
    [[nodiscard]] bool isGrouped() const;
    [[nodiscard]] QVariantList windowIds() const;
    [[nodiscard]] QString appName() const;
    [[nodiscard]] qreal contentX() const;
    [[nodiscard]] qreal contentY() const;
    [[nodiscard]] qreal contentWidth() const;
    [[nodiscard]] qreal contentHeight() const;
    [[nodiscard]] qreal maxPopupWidth() const;
    [[nodiscard]] qreal previewAnchorOffset() const;
    [[nodiscard]] bool cpuCaptureOnly() const;
    [[nodiscard]] bool captureModeOverridden() const;
    [[nodiscard]] quint64 previewFrameRevision() const;
    [[nodiscard]] int dismissedTaskIndex() const;

    [[nodiscard]] bool isPreviewKeyboardActive() const;
    [[nodiscard]] int focusedThumbnailIndex() const;

    /// Show preview for the task at @p index, positioned near the icon.
    /// @p itemSurfacePos is the icon's X (horizontal) or Y (vertical) in the
    /// dock QML scene, already local to the dock layer-shell surface.
    /// @p itemExtent is the icon's width (horizontal) or height (vertical).
    /// @p iconRestEdgeInSurface is the resting icon edge along the cross axis.
    Q_INVOKABLE void showPreview(int index, qreal itemSurfacePos, qreal itemExtent,
                                 qreal iconRestEdgeInSurface, qreal maxZoomOverflow,
                                 qreal shadowMargin);
    /// Compatibility entry point for C++ geometry tests that pass window/global coordinates.
    void showPreview(int index, qreal itemGlobalPos, qreal itemExtent);
    /// Refresh the fixed anchor after icon size, zoom settings, or dock geometry changes.
    Q_INVOKABLE void updatePreviewAnchorGeometry(qreal itemSurfacePos, qreal itemExtent,
                                                 qreal iconRestEdgeInSurface,
                                                 qreal maxZoomOverflow, qreal shadowMargin);

    /// Reconfigure preview surface anchors/margins after edge change.
    void updateEdge();

    /// Hide the preview immediately.
    Q_INVOKABLE void hidePreview();

    /// Hide the preview after a delay (for dock→preview mouse transition).
    Q_INVOKABLE void hidePreviewDelayed();

    /// Cancel a pending delayed hide (mouse entered preview).
    Q_INVOKABLE void cancelHide();

    /// Update whether the mouse is hovering the preview surface.
    Q_INVOKABLE void setPreviewHovered(bool hovered);

    /// Hold the preview hidden while the dock context menu is open: hides it
    /// now and ignores showPreview() until released. Releasing only clears
    /// the hold; QML re-shows the preview through its normal hover pipeline.
    void setHeld(bool held);

    /// Update the content size from QML (after layout).
    Q_INVOKABLE void setContentSize(qreal width, qreal height);
    Q_INVOKABLE QString previewFrameUrl(const QString &windowUuid) const;
    Q_INVOKABLE QStringList cachedPreviewFrameUuids() const;
    Q_INVOKABLE bool storeMinimizedPreviewFrame(const QString &windowUuid, const QImage &image,
                                                bool minimized = true);
    Q_INVOKABLE bool setPreviewFrameMinimized(const QString &windowUuid, bool minimized);
    /// Capture a rendered preview item asynchronously into the bounded in-memory cache.
    /// The controller owns pending grab results so QML delegate destruction cannot
    /// leave callbacks referring to a dead QML object.
    Q_INVOKABLE bool capturePreviewFrame(QQuickItem *item, const QString &windowUuid, const QSize &targetSize);
    Q_INVOKABLE bool removePreviewFrame(const QString &windowUuid);
    /// Keep hover-triggered previews closed for a task after an explicit activation click.
    Q_INVOKABLE void suppressPreviewUntilPointerLeavesTask(int index);
    Q_INVOKABLE void clearDismissedTask();
    [[nodiscard]] QImage previewFrameByKey(const QString &key) const;

    // --- Preview keyboard navigation (called from dock key handler) ---

    /// Start keyboard navigation in the preview (focus first thumbnail).
    Q_INVOKABLE void startPreviewKeyboardNav();

    /// End keyboard navigation in the preview.
    Q_INVOKABLE void endPreviewKeyboardNav();

    /// Navigate preview thumbnails by delta (-1 = left, +1 = right).
    Q_INVOKABLE void navigatePreviewThumbnail(int delta);

    /// Activate the currently focused preview thumbnail window.
    Q_INVOKABLE void activatePreviewThumbnail(bool suppressHoverReopen = false);

    /// Close the currently focused preview thumbnail window.
    Q_INVOKABLE void closePreviewThumbnail();

    /// Get the number of preview thumbnails.
    Q_INVOKABLE int previewThumbnailCount() const;

    /// Get the title of the currently focused thumbnail (for screen reader).
    Q_INVOKABLE QString focusedThumbnailTitle() const;

    /// Get whether the focused thumbnail is active/minimized (for screen reader).
    Q_INVOKABLE bool focusedThumbnailIsActive() const;
    Q_INVOKABLE bool focusedThumbnailIsMinimized() const;

    /// Set the hide delay timer interval (from settings).
    void setHideDelay(int ms);

Q_SIGNALS:
    void visibleChanged(bool visible);
    void parentIndexChanged();
    void positionChanged();
    void contentSizeChanged();
    void maxPopupWidthChanged();
    void previewAnchorOffsetChanged();
    void captureModeChanged();
    void previewFramesChanged();
    void dismissedTaskIndexChanged();
    void previewKeyboardActiveChanged();
    void focusedThumbnailIndexChanged();

private:
    [[nodiscard]] int taskIndexForParent() const;
    void reconcileParentIndex();
    void updateInputRegion();
    void applyPreviewBackgroundEffect();
    void commitInputRegion();
    void applyEdgeLayout();

    void recalcContentPosition();
    void doShow();
    void doHide();

    /// Get the model index for the currently focused thumbnail.
    [[nodiscard]] QModelIndex focusedThumbnailModelIndex() const;

    DockModel *m_model;
    DockView *m_dockView;
    KDockWSettings *m_settings;
    bool m_captureModeOverridden = false;
    bool m_overrideCpuCaptureOnly = false;
    bool m_rendererDetectionPending = false;
    bool m_softwareRenderer = false;
    std::unique_ptr<QQuickView> m_previewView;
    std::unique_ptr<PreviewFrameCache> m_previewFrameCache;
    QHash<QString, QSharedPointer<QQuickItemGrabResult>> m_pendingPreviewFrames;
    QRegion m_inputRegion;
    BackgroundEffectPlan m_backgroundEffectPlan;

    bool m_visible = false;
    int m_dismissedTaskIndex = -1;
    bool m_previewHovered = false;
    bool m_held = false;
    int m_parentIndex = -1;
    QString m_parentEntryId;

    qreal m_contentX = 0;
    qreal m_contentY = 0;
    qreal m_contentWidth = 280;
    qreal m_contentHeight = 200;
    qreal m_maxPopupWidth = 0;
    qreal m_itemPos = 0; // icon position in dock-surface-local coordinates
    qreal m_itemExtent = 0;
    qreal m_iconRestEdgeInSurface = 0;
    qreal m_shadowMargin = 0;
    qreal m_previewAnchorOffset = 0;
    qreal m_maxPreviewZoomOverflow = 0;
    bool m_hasIconGeometry = false;

    // Preview keyboard navigation state
    bool m_previewKeyboardActive = false;
    int m_focusedThumbnailIndex = -1;

    QTimer m_hideTimer;
};

} // namespace kdockw
