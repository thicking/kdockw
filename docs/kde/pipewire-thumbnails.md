# PipeWire Thumbnails (KPipeWire)

> Source: `/usr/include/KPipeWire/` headers

## Overview

KPipeWire provides Qt Quick integration for PipeWire streams. For a dock, the primary use case is rendering live window thumbnails via `PipeWireSourceItem`.

---

## PipeWireSourceItem

QML-ready item that renders a PipeWire stream.

**QML Element:** Yes (available directly in QML)
**Base:** `QQuickItem`

### Properties

| Property | Type | R/W | Description |
|----------|------|-----|-------------|
| `nodeId` | uint | RW | PipeWire node ID to render |
| `fd` | uint | RW | File descriptor for PipeWire connection |
| `state` | StreamState | R | Current stream state |
| `streamSize` | QSize | R | Source dimensions (updated after first frame) |
| `ready` | bool | R | True after first frame received |
| `allowDmaBuf` | bool | RW | Enable DMA-buffer GPU transfers |
| `usingDmaBuf` | bool | R | Whether currently using DMA-buf |

### StreamState Enum

```cpp
enum StreamState {
    Error,
    Unconnected,
    Connecting,
    Paused,
    Streaming,
};
```

### Methods

```cpp
void setNodeId(uint nodeId);
uint nodeId() const;

void setFd(uint fd);    // Ownership transferred
void resetFd();
uint fd() const;

QSize streamSize() const;
bool isReady() const;
bool usingDmaBuf() const;
bool allowDmaBuf() const;
void setAllowDmaBuf(bool allowed);

QString error() const;
StreamState state() const;
```

### Signals

```cpp
void nodeIdChanged(uint);
void fdChanged(uint);
void streamSizeChanged();
void stateChanged();
void usingDmaBufChanged();
void readyChanged();
```

---

## PipeWireSourceStream (Low-Level)

Manages the raw PipeWire stream and frame reception.

### UsageHint Enum

```cpp
enum class UsageHint {
    Render,           // Default: screen rendering
    EncodeSoftware,   // Software encoding
    EncodeHardware,   // Hardware encoding
};
```

### Key Methods

```cpp
bool createStream(uint nodeid, int fd);
void setActive(bool active);
void setMaxFramerate(const Fraction &framerate);
void setDamageEnabled(bool enabled);   // Track dirty regions
void setUsageHint(UsageHint hint);
QSize size() const;
Fraction framerate() const;
```

### Frame Data Structures

```cpp
struct PipeWireFrame {
    spa_video_format format;
    std::optional<quint64> sequential;            // Frame number
    std::optional<nanoseconds> presentationTimestamp;
    std::optional<DmaBufAttributes> dmabuf;       // GPU buffer
    std::optional<QRegion> damage;                 // Dirty regions
    std::optional<PipeWireCursor> cursor;          // Cursor info
    std::shared_ptr<PipeWireFrameData> dataFrame;  // CPU data
};

struct DmaBufAttributes {
    int width, height;
    uint32_t format;       // DRM pixel format
    uint64_t modifier;     // Layout modifier
    QList<DmaBufPlane> planes;
};

struct PipeWireFrameData {
    QImage toImage() const;                   // Convert to QImage
    std::shared_ptr<PipeWireFrameData> copy(); // Deep copy
};

struct PipeWireCursor {
    QPoint position;
    QPoint hotspot;
    QImage texture;
};
```

---

## Recording (PipeWireRecord)

For screen/window recording (not directly needed for dock thumbnails).

### Encoder Enum

```cpp
enum Encoder {
    NoEncoder, VP8, VP9, H264Main, H264Baseline, WebP, Gif
};
```

### State Enum

```cpp
enum State { Idle, Recording, Rendering };
```

### EncodingPreference

```cpp
enum EncodingPreference { NoPreference, Quality, Speed, Size };
```

---

## Usage Flow for Window Thumbnails

### Step 1: Get Window's PipeWire Stream

To get a PipeWire stream for a window, you need to use KWin's Screencast D-Bus interface:

```
org.kde.KWin → /Screencasting
Interface: org.kde.KWin.ScreencastV1

Method: StreamWindow(QString uuid, CursorMode cursorMode) → QDBusUnixFileDescriptor, uint nodeId
```

The `uuid` comes from the window's internal ID (available through KWin D-Bus or TaskManager).

### Step 2: Render in QML

```qml
import org.kde.pipewire as PipeWire

PipeWire.PipeWireSourceItem {
    id: thumbnailItem
    nodeId: windowNodeId   // From screencast request
    visible: ready

    width: parent.width
    height: width * (streamSize.height / Math.max(streamSize.width, 1))
}
```

### Step 3: Manage Lifecycle

```qml
// Start stream when tooltip/preview is shown
onVisibleChanged: {
    if (visible) {
        // Request screencast via D-Bus
        // Set nodeId on PipeWireSourceItem
    } else {
        thumbnailItem.nodeId = 0;  // Stop stream
    }
}
```

---

## Design Notes

1. **DMA-Buffer**: Hardware-accelerated GPU-to-GPU transfer; falls back to CPU if unavailable
2. **Async**: Frame reception is asynchronous; use `ready` property to show content
3. **Damage tracking**: Only dirty regions updated — efficient for live previews
4. **Resource management**: Set `nodeId = 0` or `resetFd()` to stop the stream and free resources
5. **Screencast permission**: KWin's screencast may require portal permission on Flatpak
6. **Frame timing**: `presentationTimestamp` allows frame-accurate presentation

## Scene-graph clipping

The installed `/usr/include/KPipeWire/pipewiresourceitem.h` declares
`PipeWireSourceItem::updatePaintNode(QSGNode *, UpdatePaintNodeData *)` as a
public virtual override. A subclass may call that override and wrap the exact
node it returns in a public `QSGClipNode`, provided it preserves KPipeWire's
returned node as the wrapper's child on subsequent updates. The base override
expects to receive its own previous returned node, not the outer clip wrapper.

Do not assume that a `QSGClipNode` returned from a different QQuickItem's
`updatePaintNode()` will contain that item's QML children. Qt 6 stores custom
paint nodes separately from the child-item scene-graph container; use the
built-in `QQuickItem::clip` for its supported rectangular clip, or wrap the
PipeWire item's own returned node when a custom rounded clip is required.
Avoid Qt private QQuickItem internals. The live QSG tree still needs inspection
on the target renderer because headless mocks cannot establish KPipeWire's
runtime frame-node topology.

## Software-renderer DMA-BUF fallback

The E2E core from Debian 13 confirmed a SIGSEGV in Mesa llvmpipe's JIT shader
while it sampled a PipeWire DMA-BUF-backed texture. The same PREV-012 scenario
passed with `PipeWireSourceItem.allowDmaBuf = false`; this isolates the failure
to the DMA-BUF import/render path in the llvmpipe software renderer. The core
does not establish whether the unmapped DMA-BUF address originates in Mesa,
KPipeWire buffer ownership, or their interaction, so do not label the upstream
component without further evidence.

Qt exposes the supported renderer inspection path through public APIs:
`QQuickWindow::afterSynchronizing` runs on the scene-graph rendering thread,
and for OpenGL the context used by Qt Quick is current at that point. A direct
connection can query `QOpenGLContext::currentContext()` and
`QOpenGLFunctions::glGetString(GL_RENDERER)` there. `QSGRendererInterface::graphicsApi()`
identifies Qt Quick's software backend directly. Do not query GL state from the
GUI thread or use Qt private scene-graph internals.

When the renderer is a software rasterizer (for example llvmpipe or softpipe),
KDockW detects it through Qt's public renderer APIs and disables DMA-BUF import,
keeping KPipeWire's CPU-readable buffer path. DMA-BUF remains enabled according
to the existing setting or environment override on hardware renderers. The
capture source starts in CPU mode until the preview surface's renderer has been
identified, so an early prefetch cannot enter the failing path. This is a
renderer-specific fallback, not a user setting or a change to frame caching.
Recheck it against the Debian PREV-012 pixel test and a hardware-rendered
Wayland session.

## Window stream resolution negotiation (Plasma 6.6.6)

The resolution option in `PipeWireSourceStream` is consumer-side format
acceptance, not a capture-size request. The public API has no target-size setter;
its format builder advertises supported video dimensions and `streamSize()`
reports the received frame size.

KWin 6.6.6 initializes `ScreenCastStream::m_resolution` from
`source->textureSize()`. Its SPA format builder publishes
`SPA_FORMAT_VIDEO_size` as one fixed `SPA_POD_Rectangle(resolution)`, not as a
range containing smaller dimensions. When the source size changes, KWin rebuilds
that format from `m_source->textureSize()`. Consequently a client cannot make a
window stream emit 790×452, 640×360, or 480×270 by changing its own SPA format
preferences. The producer's window capture/render path would have to be changed
to downsample before publishing the PipeWire buffers.

Sources: [KWin 6.6.6 `ScreenCastStream`](https://github.com/KDE/kwin/blob/v6.6.6/src/plugins/screencast/screencaststream.cpp)
and [KPipeWire 6.6.4 `PipeWireSourceStream`](https://github.com/KDE/kpipewire/blob/v6.6.4/src/pipewiresourcestream.cpp).

KDockW's diagnostic `pipeWireFramePixels` metric reads `PipeWireSourceItem.streamSize`
after frames arrive, so it records the actual received dimensions. Baseline and
Linear sampling experiments remain available. No resized-source variants were
added because KWin does not expose them through this window-stream negotiation.
If source-side scaling is needed later, evaluate KWin changes separately; the
application-side alternative is a quality-filtered downsample in the existing
render path, measured against the direct Baseline and Linear paths before
adoption. No performance or visual-quality improvement is claimed here.
