// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "previewcontroller.h"

#include "dockview.h"
#include "dockvisibilitycontroller.h"
#include "models/icondiag.h"
#include "kdockw.h"
#include "models/dockmodel.h"
#include "utils/inputregion.h"
#include "utils/layershellpolicy.h"

#include <LayerShellQt/Window>

#include <taskmanager/abstracttasksmodel.h>
#include <taskmanager/tasksmodel.h>

#include <wayland-client.h>

#include <cmath>
#include <algorithm>
#include <limits>

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QQmlEngine>
#include <QQuickView>
#include <QScreen>
#include <QPainterPath>
#include <qpa/qplatformnativeinterface.h>

Q_LOGGING_CATEGORY(lcPreview, "kdockw.shell.preview")

namespace kdockw
{

PreviewController::PreviewController(DockModel *model, DockView *dockView, KDockWSettings *settings, QObject *parent)
    : QObject(parent)
    , m_model(model)
    , m_dockView(dockView)
    , m_settings(settings)
{
    const QByteArray captureMode = qgetenv("KDOCKW_PREVIEW_CAPTURE_MODE").trimmed().toLower();
    if (captureMode == "cpu-only") {
        m_captureModeOverridden = true;
        m_overrideCpuCaptureOnly = true;
    } else if (captureMode == "auto") {
        m_captureModeOverridden = true;
    } else if (!captureMode.isEmpty()) {
        qCWarning(lcPreview) << "Unsupported KDOCKW_PREVIEW_CAPTURE_MODE; using the saved setting";
    }
    qCInfo(lcPreview) << "Capture mode:" << (cpuCaptureOnly() ? "cpu-only" : "auto")
                      << "source:" << (m_captureModeOverridden ? "environment" : "settings");

    if (m_settings) {
        connect(m_settings, &KDockWSettings::CpuOnlyPreviewCaptureChanged, this, [this]() {
            if (!m_captureModeOverridden) {
                qCInfo(lcPreview) << "Capture mode changed by settings:" << (cpuCaptureOnly() ? "cpu-only" : "auto");
                Q_EMIT captureModeChanged();
            }
        });
        connect(m_settings, &KDockWSettings::PreviewDockGapChanged, this, [this]() {
            applyEdgeLayout();
        });
        const auto updateBackground = [this]() { updateInputRegion(); };
        connect(m_settings, &KDockWSettings::BackgroundStyleChanged, this, updateBackground);
        connect(m_settings, &KDockWSettings::BackgroundOpacityChanged, this, updateBackground);
        connect(m_settings, &KDockWSettings::CornerRadiusChanged, this, updateBackground);
    }

    m_hideTimer.setSingleShot(true);
    m_hideTimer.setInterval(m_settings ? m_settings->previewHideDelay() : 400);
    connect(&m_hideTimer, &QTimer::timeout, this, [this]() {
        qCDebug(lcPreview) << "Hide timer fired, previewHovered:" << m_previewHovered;
        if (!m_previewHovered) {
            doHide();
        }
    });

}

PreviewController::~PreviewController() = default;

void PreviewController::initialize()
{
    // Share the dock's QQmlEngine so QML types (Kirigami, TaskManager, etc.)
    // are available. m_previewView is a std::unique_ptr so the preview
    // surface is destroyed with this controller (DockShell owns it) instead
    // of leaking on the old output across a topology change.
    m_previewView = std::make_unique<QQuickView>(m_dockView->engine(), nullptr);
    m_previewView->setColor(Qt::transparent);
    m_previewView->setResizeMode(QQuickView::SizeRootObjectToView);

    // Layer-shell configuration: overlay above the dock
    auto *layerWindow = LayerShellQt::Window::get(m_previewView.get());
    if (layerWindow) {
        // Pin the preview surface to the dock's output. QWindow::setScreen
        // alone does not pin a layer surface on QtWayland: the platform window
        // re-derives its screen from the window geometry at creation, so the
        // position must also land on the target output (layer-shell ignores
        // absolute position). The LayerShellQt-level screen is what
        // get_layer_surface() binds to.
        if (auto *screen = m_dockView->dockScreen()) {
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
            // LayerShellQt < 6.6: get_layer_surface() binds QWindow::screen()
            // (ScreenFromQWindow), so the Qt-side screen below is the pin.
            layerWindow->setScreenConfiguration(LayerShellQt::Window::ScreenFromQWindow);
#else
            layerWindow->setScreen(screen);
#endif
            m_previewView->setScreen(screen);
            // Only before the platform window exists: LayerShellQt < 6.6
            // already created it in Window::get(), and QtWayland then pins a
            // toplevel to its screen origin, so a setPosition() from the stale
            // origin would re-derive the old screen.
            if (!m_previewView->handle()) {
                m_previewView->setPosition(screen->geometry().topLeft());
            }
        } else {
            qCWarning(lcPreview) << "Dock view has no screen; preview surface not pinned";
        }
        layerWindow->setLayer(LayerShellQt::Window::LayerOverlay);
        // KWin types a layer surface only from its scope (layershellv1window.cpp
        // scopeToType); an unknown name such as "kdockw-preview" becomes a Normal
        // window. This surface stays mapped, so as a Normal window it would
        // permanently top Slide Back's usable-window list (normal || dialog) and
        // the effect would never fire. Plasma's own task-manager previews are
        // tooltips too.
        layerWindow->setScope(QStringLiteral("tooltip"));
        layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        // KWin lays zero-zone layer surfaces out in the remaining work area.
        // This overlay must stay edge-relative to the output, independently
        // of the dock's positive exclusive zone, so use the protocol's -1 mode.
        layerWindow->setExclusiveZone(previewLayerShellExclusiveZone);
        layerWindow->setCloseOnDismissed(false);
    }

    // Configure anchors/margins/size for the current edge
    applyEdgeLayout();

    // Load the preview QML
    m_previewView->setSource(QUrl(QStringLiteral("qrc:/qml/PreviewPopup.qml")));

    if (m_previewView->status() == QQuickView::Error) {
        const auto errs = m_previewView->errors();
        for (const auto &err : errs) {
            qCCritical(lcPreview) << "Preview QML error:" << err.toString();
        }
    }

    // Block all meaningful input with a 1x1 region in the top-left corner.
    // IMPORTANT: QRegion() / QRegion(0,0,0,0) is empty → clears mask → accepts ALL input!
    const QRegion hiddenInputRegion(0, 0, 1, 1);
    m_previewView->setMask(hiddenInputRegion);
    m_inputRegion = hiddenInputRegion;

    // Pre-show the surface so compositor has it mapped and ready for input routing.
    // The 1x1 mask above prevents it from intercepting any meaningful input.
    m_previewView->show();

    qCDebug(lcPreview) << "Preview controller initialized (surface pre-shown)";
}

bool PreviewController::isVisible() const
{
    return m_visible;
}

int PreviewController::parentIndex() const
{
    return m_parentIndex;
}

QModelIndex PreviewController::rootModelIndex() const
{
    if (m_parentIndex < 0) {
        return {};
    }
    return m_model->taskModelIndex(m_parentIndex);
}

bool PreviewController::isGrouped() const
{
    if (m_parentIndex < 0) {
        return false;
    }
    return m_model->childCount(m_parentIndex) > 1;
}

QVariantList PreviewController::windowIds() const
{
    if (m_parentIndex < 0) {
        return {};
    }
    return m_model->windowIds(m_parentIndex);
}

QString PreviewController::appName() const
{
    if (m_parentIndex < 0) {
        return {};
    }
    const QModelIndex idx = m_model->tasksModel()->index(m_parentIndex, 0);
    return idx.data(TaskManager::AbstractTasksModel::AppName).toString();
}

qreal PreviewController::contentX() const
{
    return m_contentX;
}

qreal PreviewController::contentY() const
{
    return m_contentY;
}

qreal PreviewController::contentWidth() const
{
    return m_contentWidth;
}

qreal PreviewController::contentHeight() const
{
    return m_contentHeight;
}

qreal PreviewController::previewAnchorOffset() const
{
    return m_previewAnchorOffset;
}

bool PreviewController::cpuCaptureOnly() const
{
    return m_captureModeOverridden ? m_overrideCpuCaptureOnly : (m_settings && m_settings->cpuOnlyPreviewCapture());
}

bool PreviewController::captureModeOverridden() const
{
    return m_captureModeOverridden;
}

void PreviewController::showPreview(int index, qreal itemGlobalPos, qreal itemExtent)
{
    const auto edge = m_dockView->platform()->edge();
    const bool vertical = edge == DockPlatform::Edge::Left || edge == DockPlatform::Edge::Right;
    const qreal surfacePos = itemGlobalPos - (vertical ? m_dockView->y() : m_dockView->x());
    showPreview(index, surfacePos, itemExtent,
                std::numeric_limits<qreal>::quiet_NaN(), 0.0, 0.0);
}

void PreviewController::showPreview(int index, qreal itemSurfacePos, qreal itemExtent,
                                    qreal iconRestEdgeInSurface, qreal maxZoomOverflow,
                                    qreal shadowMargin)
{
    if (m_held) {
        // The preview is an Overlay surface and would cover the context menu.
        qCDebug(lcPreview) << "showPreview ignored: held by context menu";
        return;
    }

    m_hideTimer.stop();

    const auto dockEdge = m_dockView->platform()->edge();
    const bool indexChanged = (m_parentIndex != index);
    m_parentIndex = index;
    m_itemPos = itemSurfacePos;
    m_itemExtent = itemExtent;
    updatePreviewAnchorGeometry(itemSurfacePos, itemExtent, iconRestEdgeInSurface,
                                maxZoomOverflow, shadowMargin);

    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCInfo(lcPreview).noquote()
            << "[kdockw.preview.position.cpp] stage=show coordinateSpace=dock-surface-logical"
            << "edge=" << static_cast<int>(dockEdge)
            << "dockAxisItemPos=" << m_itemPos << "itemExtent=" << m_itemExtent
            << "iconRestEdgeInSurface=" << m_iconRestEdgeInSurface
            << "fixedAnchorOffset=" << m_previewAnchorOffset
            << "maxZoomOverflow=" << m_maxPreviewZoomOverflow
            << "dockSurfaceSize=" << m_dockView->size()
            << "dockWindowPositionHint=" << m_dockView->position()
            << "screenGeometry=" << (m_dockView->dockScreen() ? m_dockView->dockScreen()->geometry() : QRect());
    }

    applyEdgeLayout();
    recalcContentPosition();

    if (indexChanged) {
        Q_EMIT parentIndexChanged();
    }
    Q_EMIT positionChanged();

    doShow();
}

void PreviewController::updatePreviewAnchorGeometry(qreal itemSurfacePos, qreal itemExtent,
                                                    qreal iconRestEdgeInSurface,
                                                    qreal maxZoomOverflow, qreal shadowMargin)
{
    const qreal safeItemPos = std::isfinite(itemSurfacePos) ? itemSurfacePos : 0.0;
    const qreal safeItemExtent = std::isfinite(itemExtent) ? std::max<qreal>(0.0, itemExtent) : 0.0;
    const qreal safeMaxOverflow = std::isfinite(maxZoomOverflow)
        ? std::max<qreal>(0.0, maxZoomOverflow) : 0.0;
    const qreal safeShadowMargin = std::isfinite(shadowMargin)
        ? std::max<qreal>(0.0, shadowMargin) : 0.0;
    const bool hasIconGeometry = std::isfinite(iconRestEdgeInSurface);
    const qreal safeRestEdge = hasIconGeometry ? iconRestEdgeInSurface : 0.0;
    const bool changed = !qFuzzyCompare(m_itemPos + 1.0, safeItemPos + 1.0)
        || !qFuzzyCompare(m_itemExtent + 1.0, safeItemExtent + 1.0)
        || !qFuzzyCompare(m_iconRestEdgeInSurface + 1.0, safeRestEdge + 1.0)
        || !qFuzzyCompare(m_maxPreviewZoomOverflow + 1.0, safeMaxOverflow + 1.0)
        || !qFuzzyCompare(m_shadowMargin + 1.0, safeShadowMargin + 1.0)
        || m_hasIconGeometry != hasIconGeometry;
    if (!changed) {
        return;
    }

    m_itemPos = safeItemPos;
    m_itemExtent = safeItemExtent;
    m_iconRestEdgeInSurface = safeRestEdge;
    m_maxPreviewZoomOverflow = safeMaxOverflow;
    m_shadowMargin = safeShadowMargin;
    m_hasIconGeometry = hasIconGeometry;
    if (!qFuzzyCompare(m_previewAnchorOffset + 1.0, safeMaxOverflow + 1.0)) {
        m_previewAnchorOffset = safeMaxOverflow;
        Q_EMIT previewAnchorOffsetChanged();
    }

    if (m_previewView) {
        applyEdgeLayout();
        if (m_visible) {
            recalcContentPosition();
            Q_EMIT positionChanged();
            updateInputRegion();
        }
    }
}

void PreviewController::hidePreview()
{
    m_hideTimer.stop();
    doHide();
}

void PreviewController::hidePreviewDelayed()
{
    if (!m_visible || m_held) {
        return;
    }
    qCDebug(lcPreview) << "hidePreviewDelayed: starting" << m_hideTimer.interval() << "ms timer";
    m_hideTimer.start();
}

void PreviewController::cancelHide()
{
    m_hideTimer.stop();
}

void PreviewController::setPreviewHovered(bool hovered)
{
    qCDebug(lcPreview) << "setPreviewHovered:" << hovered;
    m_previewHovered = hovered;
    if (hovered) {
        m_hideTimer.stop();
    } else {
        if (m_visible && !m_held) {
            m_hideTimer.start();
        }
    }
}

void PreviewController::setHeld(bool held)
{
    if (m_held == held) {
        return;
    }
    m_held = held;
    qCDebug(lcPreview) << "setHeld:" << held;
    if (held) {
        hidePreview();
    }
}

void PreviewController::setContentSize(qreal width, qreal height)
{
    bool changed = false;
    if (!qFuzzyCompare(m_contentWidth, width)) {
        m_contentWidth = width;
        changed = true;
    }
    if (!qFuzzyCompare(m_contentHeight, height)) {
        m_contentHeight = height;
        changed = true;
    }
    if (changed) {
        // The popup reports its laid-out extent after QML completes the
        // thumbnail row. Resize the native surface before recalculating the
        // popup position and publishing the corresponding input region.
        applyEdgeLayout();

        // Recalculate position to stay centered on the icon
        if (m_visible && m_parentIndex >= 0) {
            recalcContentPosition();
            Q_EMIT positionChanged();
        }
        Q_EMIT contentSizeChanged();

        // Update input region to match new content size
        if (m_visible) {
            updateInputRegion();
        }
    }
}

void PreviewController::doShow()
{
    if (!m_previewView) {
        return;
    }

    // Reapply edge layout (margins may change with icon size / zoom)
    applyEdgeLayout();

    const bool wasVisible = m_visible;
    if (!wasVisible) {
        m_visible = true;
        // Surface is always pre-shown — no need to call show().
        // Prepare its input region before notifying QML that the popup is
        // visible. Otherwise AT-SPI can expose the popup while the Wayland
        // surface still has its previous (hidden) input region.

        // Lock dock visibility while preview is open
        if (m_dockView->visibilityController()) {
            m_dockView->visibilityController()->setInteracting(true);
        }
    }

    updateInputRegion();
    if (!wasVisible) {
        Q_EMIT visibleChanged(true);
    }
}

void PreviewController::doHide()
{
    if (!m_visible) {
        return;
    }

    m_visible = false;
    m_previewHovered = false;
    m_parentIndex = -1;

    // End preview keyboard nav if active
    if (m_previewKeyboardActive) {
        m_previewKeyboardActive = false;
        m_focusedThumbnailIndex = -1;
        Q_EMIT previewKeyboardActiveChanged();
        Q_EMIT focusedThumbnailIndexChanged();
    }

    // Block input on the preview surface (keep it mapped for fast re-show)
    updateInputRegion();

    // Release dock visibility lock
    if (m_dockView->visibilityController()) {
        m_dockView->visibilityController()->setInteracting(false);
    }

    Q_EMIT visibleChanged(false);
    Q_EMIT parentIndexChanged();
}

// --- Preview keyboard navigation (driven from dock surface) ---

bool PreviewController::isPreviewKeyboardActive() const
{
    return m_previewKeyboardActive;
}

int PreviewController::focusedThumbnailIndex() const
{
    return m_focusedThumbnailIndex;
}

void PreviewController::startPreviewKeyboardNav()
{
    if (!m_visible || m_parentIndex < 0) {
        return;
    }
    m_previewKeyboardActive = true;
    m_focusedThumbnailIndex = 0;
    Q_EMIT previewKeyboardActiveChanged();
    Q_EMIT focusedThumbnailIndexChanged();
}

void PreviewController::endPreviewKeyboardNav()
{
    if (!m_previewKeyboardActive) {
        return;
    }
    m_previewKeyboardActive = false;
    m_focusedThumbnailIndex = -1;
    Q_EMIT previewKeyboardActiveChanged();
    Q_EMIT focusedThumbnailIndexChanged();
}

void PreviewController::navigatePreviewThumbnail(int delta)
{
    if (!m_previewKeyboardActive) {
        return;
    }
    const int count = previewThumbnailCount();
    if (count == 0) {
        return;
    }
    int newIndex = m_focusedThumbnailIndex + delta;
    newIndex = qBound(0, newIndex, count - 1);
    if (newIndex != m_focusedThumbnailIndex) {
        m_focusedThumbnailIndex = newIndex;
        Q_EMIT focusedThumbnailIndexChanged();
    }
}

void PreviewController::activatePreviewThumbnail()
{
    const QModelIndex idx = focusedThumbnailModelIndex();
    if (!idx.isValid()) {
        return;
    }
    m_model->tasksModel()->requestActivate(idx);
    hidePreview();
}

void PreviewController::closePreviewThumbnail()
{
    const QModelIndex idx = focusedThumbnailModelIndex();
    if (!idx.isValid()) {
        return;
    }
    m_model->tasksModel()->requestClose(idx);

    // Adjust focus index if needed
    const int count = previewThumbnailCount();
    if (m_focusedThumbnailIndex >= count - 1) {
        m_focusedThumbnailIndex = qMax(0, count - 2);
        Q_EMIT focusedThumbnailIndexChanged();
    }
}

int PreviewController::previewThumbnailCount() const
{
    if (m_parentIndex < 0) {
        return 0;
    }
    // Single window (no children) counts as 1 thumbnail
    int childCount = m_model->childCount(m_parentIndex);
    if (childCount == 0) {
        // Check if it's a window (not just a launcher)
        const QModelIndex parentIdx = m_model->tasksModel()->index(m_parentIndex, 0);
        bool isWindow = parentIdx.data(TaskManager::AbstractTasksModel::IsWindow).toBool();
        return isWindow ? 1 : 0;
    }
    return childCount;
}

QString PreviewController::focusedThumbnailTitle() const
{
    const QModelIndex idx = focusedThumbnailModelIndex();
    if (!idx.isValid()) {
        return {};
    }
    return idx.data(Qt::DisplayRole).toString();
}

bool PreviewController::focusedThumbnailIsActive() const
{
    const QModelIndex idx = focusedThumbnailModelIndex();
    if (!idx.isValid()) {
        return false;
    }
    return idx.data(TaskManager::AbstractTasksModel::IsActive).toBool();
}

bool PreviewController::focusedThumbnailIsMinimized() const
{
    const QModelIndex idx = focusedThumbnailModelIndex();
    if (!idx.isValid()) {
        return false;
    }
    return idx.data(TaskManager::AbstractTasksModel::IsMinimized).toBool();
}

QModelIndex PreviewController::focusedThumbnailModelIndex() const
{
    if (m_parentIndex < 0 || m_focusedThumbnailIndex < 0) {
        return {};
    }
    int childCount = m_model->childCount(m_parentIndex);
    if (childCount == 0) {
        // Single window: use parent row directly
        return m_model->tasksModel()->index(m_parentIndex, 0);
    }
    if (m_focusedThumbnailIndex >= childCount) {
        return {};
    }
    return m_model->tasksModel()->makeModelIndex(m_parentIndex, m_focusedThumbnailIndex);
}

void PreviewController::setHideDelay(int ms)
{
    m_hideTimer.setInterval(ms);
}

void PreviewController::updateEdge()
{
    if (!m_previewView) {
        return;
    }
    applyEdgeLayout();
    if (m_visible) {
        updateInputRegion();
    }
    if (m_previewView->isVisible())
        m_previewView->update();
}

void PreviewController::applyEdgeLayout()
{
    if (!m_previewView) {
        return;
    }

    auto *layerWindow = LayerShellQt::Window::get(m_previewView.get());
    if (!layerWindow) {
        return;
    }

    const auto edge = m_dockView->platform()->edge();
    const bool vertical = (edge == DockPlatform::Edge::Left || edge == DockPlatform::Edge::Right);
    // This preview is anchored against output geometry because its exclusive
    // zone is negative. Use the dock's actual layer-shell edge margin here;
    // floating padding is already inside the dock surface and must not be
    // counted a second time.
    const auto *visibility = m_dockView->visibilityController();
    const bool dockReservesPanelBar = visibility
        && visibility->mode() == static_cast<int>(DockPlatform::VisibilityMode::AlwaysVisible)
        && m_settings->reserveScreenSpace();
    const int zoomOverflow = static_cast<int>(std::ceil(m_settings->iconSize() * (m_settings->maxZoomFactor() - 1.0)));
    const int fallbackDockMargin = computePreviewSurfaceMargin(
        m_dockView->panelBarHeight(), zoomOverflow, m_settings->previewDockGap(), dockReservesPanelBar);

    const QRect screenGeo = m_dockView->dockScreen() ? m_dockView->dockScreen()->geometry() : QRect(0, 0, 1920, 1080);
    const qreal dockSurfaceExtent = vertical ? m_dockView->width() : m_dockView->height();
    const int dockSurfaceEdgeMargin = m_dockView->platform()->margin();
    const int dockMargin = m_hasIconGeometry
        ? computePreviewSurfaceMarginForIcon(static_cast<int>(edge), m_iconRestEdgeInSurface,
                                             dockSurfaceExtent, dockSurfaceEdgeMargin,
                                             m_settings->previewDockGap(), m_shadowMargin)
        : fallbackDockMargin;

    // Anchors: same edge as dock + stretch along that edge
    LayerShellQt::Window::Anchors anchors;
    QMargins margins;

    switch (edge) {
    case DockPlatform::Edge::Bottom:
        anchors.setFlag(LayerShellQt::Window::AnchorBottom);
        anchors.setFlag(LayerShellQt::Window::AnchorLeft);
        anchors.setFlag(LayerShellQt::Window::AnchorRight);
        margins.setBottom(dockMargin);
        break;
    case DockPlatform::Edge::Top:
        anchors.setFlag(LayerShellQt::Window::AnchorTop);
        anchors.setFlag(LayerShellQt::Window::AnchorLeft);
        anchors.setFlag(LayerShellQt::Window::AnchorRight);
        margins.setTop(dockMargin);
        break;
    case DockPlatform::Edge::Left:
        anchors.setFlag(LayerShellQt::Window::AnchorLeft);
        anchors.setFlag(LayerShellQt::Window::AnchorTop);
        anchors.setFlag(LayerShellQt::Window::AnchorBottom);
        margins.setLeft(dockMargin);
        break;
    case DockPlatform::Edge::Right:
        anchors.setFlag(LayerShellQt::Window::AnchorRight);
        anchors.setFlag(LayerShellQt::Window::AnchorTop);
        anchors.setFlag(LayerShellQt::Window::AnchorBottom);
        margins.setRight(dockMargin);
        break;
    }

    layerWindow->setAnchors(anchors);
    layerWindow->setMargins(margins);

    // Surface size: stretch along dock axis. Keep the historical 400px
    // minimum for the transition from hidden/default geometry, then grow the
    // perpendicular extent from the popup's actual laid-out size. The
    // available depth excludes only this overlay's anchor margin. A negative
    // exclusive zone pins it to output geometry, independently of the dock's
    // reserved work area.
    constexpr int previewDepth = 400;
    const int contentExtent = static_cast<int>(std::ceil(vertical ? m_contentWidth : m_contentHeight));
    const int availableExtent = (vertical ? screenGeo.width() : screenGeo.height()) - dockMargin;
    const int requiredDepth = contentExtent + static_cast<int>(std::ceil(m_maxPreviewZoomOverflow));
    const int depth = qBound(1, qMax(previewDepth, requiredDepth), qMax(1, availableExtent));
    QSize size;
    if (vertical) {
        size = QSize(depth, screenGeo.height());
    } else {
        size = QSize(screenGeo.width(), depth);
    }

    m_previewView->setWidth(size.width());
    m_previewView->setHeight(size.height());
#ifdef KDOCKW_COMPAT_NO_LAYERSHELL_DESIRED_SIZE
    m_previewView->resize(size);
#else
    layerWindow->setDesiredSize(size);
#endif

    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        const int surfaceDepth = vertical ? size.width() : size.height();
        const QRect predictedSurfaceRect = [&]() {
            switch (edge) {
            case DockPlatform::Edge::Top:
                return QRect(screenGeo.x(), screenGeo.y() + dockMargin, screenGeo.width(), surfaceDepth);
            case DockPlatform::Edge::Bottom:
                return QRect(screenGeo.x(), screenGeo.y() + screenGeo.height() - dockMargin - surfaceDepth,
                             screenGeo.width(), surfaceDepth);
            case DockPlatform::Edge::Left:
                return QRect(screenGeo.x() + dockMargin, screenGeo.y(), surfaceDepth, screenGeo.height());
            case DockPlatform::Edge::Right:
                return QRect(screenGeo.x() + screenGeo.width() - dockMargin - surfaceDepth,
                             screenGeo.y(), surfaceDepth, screenGeo.height());
            }
            return QRect();
        }();
        const QScreen *dockScreen = m_dockView->dockScreen();
        const QRect availableGeometry = dockScreen ? dockScreen->availableGeometry() : screenGeo;
        const int dockExclusiveZone = !visibility
                || visibility->mode() != static_cast<int>(DockPlatform::VisibilityMode::AlwaysVisible)
            ? -1
            : (m_settings->reserveScreenSpace() ? m_dockView->panelBarHeight() : 0);
        const int dockReservation = dockExclusiveZone > 0
            ? dockExclusiveZone + m_dockView->platform()->margin()
            : 0;
        const QRect zoneZeroSurfaceRectFromDockReservation = [&]() {
            const int boundsTop = screenGeo.top() + (edge == DockPlatform::Edge::Top ? dockReservation : 0);
            const int boundsLeft = screenGeo.left() + (edge == DockPlatform::Edge::Left ? dockReservation : 0);
            const int boundsBottom = screenGeo.y() + screenGeo.height()
                - (edge == DockPlatform::Edge::Bottom ? dockReservation : 0);
            const int boundsRight = screenGeo.x() + screenGeo.width()
                - (edge == DockPlatform::Edge::Right ? dockReservation : 0);
            switch (edge) {
            case DockPlatform::Edge::Top:
                return QRect(screenGeo.x(), boundsTop + dockMargin, screenGeo.width(), surfaceDepth);
            case DockPlatform::Edge::Bottom:
                return QRect(screenGeo.x(), boundsBottom - dockMargin - surfaceDepth, screenGeo.width(), surfaceDepth);
            case DockPlatform::Edge::Left:
                return QRect(boundsLeft + dockMargin, screenGeo.y(), surfaceDepth, screenGeo.height());
            case DockPlatform::Edge::Right:
                return QRect(boundsRight - dockMargin - surfaceDepth, screenGeo.y(), surfaceDepth, screenGeo.height());
            }
            return QRect();
        }();
        qCInfo(lcPreview).noquote()
            << "[kdockw.preview.position.cpp] stage=layout coordinateSpace=output-logical"
            << "edge=" << static_cast<int>(edge) << "screenGeometry=" << screenGeo
            << "qtAvailableGeometry=" << availableGeometry
            << "dockSurfaceSize=" << m_dockView->size()
            << "dockLayer=top dockScope=dock dockExclusiveZone=" << dockExclusiveZone
            << "dockLayerShellMargin=" << dockSurfaceEdgeMargin
            << "dockFloatingInsetInsideSurface=" << m_dockView->floatingPadding()
            << "previewLayer=overlay previewScope=tooltip previewExclusiveZone=" << previewLayerShellExclusiveZone
            << "iconRestEdgeInSurface=" << m_iconRestEdgeInSurface
            << "iconDistanceFromSurfaceEdge="
            << (edge == DockPlatform::Edge::Top || edge == DockPlatform::Edge::Left
                    ? m_iconRestEdgeInSurface : dockSurfaceExtent - m_iconRestEdgeInSurface)
            << "configuredGap=" << m_settings->previewDockGap() << "shadowInset=" << m_shadowMargin
            << "previewAnchorMargin=" << dockMargin << "availableExtent=" << availableExtent
            << "surfaceDepth=" << surfaceDepth << "requiredDepth=" << requiredDepth
            << "predictedOutputBoundPreviewRect=" << predictedSurfaceRect
            << "zoneZeroRectFromDockReservationOnly=" << zoneZeroSurfaceRectFromDockReservation
            << "previewWindowPositionHint=" << m_previewView->position()
            << "dockReservationExtent=" << dockReservation;
    }
}

void PreviewController::recalcContentPosition()
{
    if (!m_previewView) {
        return;
    }

    const auto edge = m_dockView->platform()->edge();
    const bool vertical = (edge == DockPlatform::Edge::Left || edge == DockPlatform::Edge::Right);

    constexpr qreal pad = 8;

    if (vertical) {
        // Vertical dock: center popup vertically on the icon
        const qreal popupCenter = m_itemPos + m_itemExtent / 2.0;
        m_contentY = popupCenter - m_contentHeight / 2.0;

        const int screenH = m_previewView->height();
        if (m_contentY < pad) {
            m_contentY = pad;
        }
        if (m_contentY + m_contentHeight > screenH - pad) {
            m_contentY = screenH - pad - m_contentHeight;
        }
        // contentX is determined by QML based on edge (left=0 or right=parent.width-width)
    } else {
        // Horizontal dock: center popup horizontally on the icon
        const qreal popupCenter = m_itemPos + m_itemExtent / 2.0;
        m_contentX = popupCenter - m_contentWidth / 2.0;

        const int screenW = m_previewView->width();
        if (m_contentX < pad) {
            m_contentX = pad;
        }
        if (m_contentX + m_contentWidth > screenW - pad) {
            m_contentX = screenW - pad - m_contentWidth;
        }
        // contentY is determined by QML based on edge (top=0 or bottom=parent.height-height)
    }
}

void PreviewController::commitInputRegion()
{
    if (!m_previewView) {
        return;
    }

    auto *nativeInterface = QGuiApplication::platformNativeInterface();
    if (!nativeInterface) {
        return;
    }

    auto *surface = static_cast<wl_surface *>(nativeInterface->nativeResourceForWindow(QByteArrayLiteral("surface"), m_previewView.get()));
    if (surface) {
        // setMask() leaves the Wayland input region pending. Publish it now,
        // rather than waiting for the next rendered frame.
        wl_surface_commit(surface);
    }
}

void PreviewController::updateInputRegion()
{
    if (!m_previewView) {
        return;
    }

    applyPreviewBackgroundEffect();

    QRegion inputRegion;
    if (!m_visible) {
        // Hidden: block all meaningful input with a 1x1 region in the corner.
        // IMPORTANT: empty QRegion (including QRegion(0,0,0,0)) clears the mask,
        // which makes the entire surface accept ALL input — the opposite of intended!
        inputRegion = QRegion(0, 0, 1, 1);
    } else {
        // Input region = the visible popup only. The surface depth is at
        // least 400 px and grows when the popup's layout needs more room;
        // it spans the whole dock axis. Any transparent part in the region
        // would take pointer focus (e.g. when KWin re-picks focus after a
        // window closes) and the surface HoverHandler would then end preview
        // keyboard navigation.
        PreviewInputRegionParams params{};
        params.surfaceWidth = m_previewView->width();
        params.surfaceHeight = m_previewView->height();
        params.contentX = m_contentX;
        params.contentY = m_contentY;
        params.contentWidth = m_contentWidth;
        params.contentHeight = m_contentHeight;
        params.edgeOffset = m_previewAnchorOffset;
        params.shadowMargin = m_shadowMargin;
        params.edge = static_cast<int>(m_dockView->platform()->edge());
        inputRegion = computePreviewInputRegion(params);
    }

    if (inputRegion == m_inputRegion) {
        return;
    }

    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCInfo(lcPreview).noquote()
            << "[kdockw.preview.position.cpp] stage=input-region coordinateSpace=preview-surface-logical"
            << "surfaceSize=" << m_previewView->size()
            << "contentAxisPos=" << (m_dockView->isVertical() ? m_contentY : m_contentX)
            << "popupSize=" << QSizeF(m_contentWidth, m_contentHeight)
            << "fixedAnchorOffset=" << m_previewAnchorOffset
            << "shadowInset=" << m_shadowMargin
            << "inputRegionBounds=" << inputRegion.boundingRect();
    }

    m_previewView->setMask(inputRegion);
    m_inputRegion = inputRegion;
    commitInputRegion();
}

void PreviewController::applyPreviewBackgroundEffect()
{
    if (!m_previewView || !m_settings) {
        return;
    }

    const auto type = static_cast<BackgroundStyleType>(m_settings->backgroundStyle());
    if (!m_visible || m_contentWidth <= 0 || m_contentHeight <= 0
        || (styleUsesBlur(type) && qFuzzyIsNull(m_settings->backgroundOpacity()))) {
        removeBackgroundFromWindow(m_previewView.get());
        m_backgroundEffectPlan = {};
        return;
    }

    // Match the visible rounded card, excluding the transparent shadow bounds.
    QRegion region;
    QRectF cardRect;
    const qreal inset = std::clamp(m_shadowMargin, 0.0,
                                   std::min(m_contentWidth, m_contentHeight) / 2.0);
    switch (m_dockView->platform()->edge()) {
    case DockPlatform::Edge::Top:
        cardRect = QRectF(m_contentX + inset, m_previewAnchorOffset + inset,
                          m_contentWidth - 2 * inset, m_contentHeight - 2 * inset);
        break;
    case DockPlatform::Edge::Bottom:
        cardRect = QRectF(m_contentX + inset,
                          m_previewView->height() - m_contentHeight
                              - m_previewAnchorOffset + inset,
                          m_contentWidth - 2 * inset, m_contentHeight - 2 * inset);
        break;
    case DockPlatform::Edge::Left:
        cardRect = QRectF(m_previewAnchorOffset + inset, m_contentY + inset,
                          m_contentWidth - 2 * inset, m_contentHeight - 2 * inset);
        break;
    case DockPlatform::Edge::Right:
        cardRect = QRectF(m_previewView->width() - m_contentWidth - m_previewAnchorOffset,
                          m_contentY + inset,
                          m_contentWidth - 2 * inset, m_contentHeight - 2 * inset);
        cardRect.translate(inset, 0);
        break;
    }
    const qreal radius = qMin<qreal>(m_settings->cornerRadius(), qMin(cardRect.width(), cardRect.height()) / 2.0);
    if (radius > 0) {
        QPainterPath path;
        path.addRoundedRect(cardRect, radius, radius);
        region = QRegion(path.toFillPolygon().toPolygon());
    } else {
        region = QRegion(cardRect.toAlignedRect());
    }

    if (region.isEmpty()) {
        removeBackgroundFromWindow(m_previewView.get());
        m_backgroundEffectPlan = {};
        return;
    }

    if (IconDiagnostics::previewCaptureMetricsEnabled()) {
        qCInfo(lcPreview).noquote()
            << "[kdockw.preview.position.cpp] stage=blur-region coordinateSpace=preview-surface-logical"
            << "surfaceSize=" << m_previewView->size()
            << "visibleCardRect=" << cardRect
            << "blurRegionBounds=" << region.boundingRect();
    }

    const BackgroundEffectPlan plan = backgroundEffectPlan(type, region);
    applyBackgroundToWindow(m_previewView.get(), plan, m_backgroundEffectPlan);
    m_backgroundEffectPlan = plan;
}

} // namespace kdockw
