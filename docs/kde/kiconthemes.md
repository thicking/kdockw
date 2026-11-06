# KIconThemes (KIconLoader / KIconTheme / KIconColors)

> Source: `/usr/include/KF6/KIconThemes/` headers

## KIconLoader

Global icon loading and management.

### Enums

#### Group (determines default icon size)

```cpp
enum Group {
    NoGroup     = -1,
    Desktop     = 0,
    FirstGroup  = 0,
    Toolbar,
    MainToolbar,
    Small,
    Panel,
    Dialog,
    LastGroup,
    User,
};
```

#### StdSizes

```cpp
enum StdSizes {
    SizeSmall       = 16,
    SizeSmallMedium = 22,
    SizeMedium      = 32,
    SizeLarge       = 48,
    SizeHuge        = 64,
    SizeEnormous    = 128,
};
```

#### Context (icon purpose)

```cpp
enum Context {
    Any, Action, Application, Device, MimeType,
    Animation, Category, Emblem, Emote,
    International, Place, StatusIcon,
};
```

#### States (visual state)

```cpp
enum States {
    DefaultState,
    ActiveState,
    DisabledState,
    SelectedState,
    LastState,
};
```

#### MatchType

```cpp
enum MatchType {
    MatchExact,
    MatchBest,
    MatchBestOrGreaterSize,
};
```

### Key Methods

```cpp
static KIconLoader *global();  // Global singleton

// Load icon as pixmap
QPixmap loadIcon(const QString &name, Group group, int size = 0,
                 int state = DefaultState, const QStringList &overlays = {},
                 QString *path_store = nullptr, bool canReturnNull = false);

// Load with DPI scaling
QPixmap loadScaledIcon(const QString &name, Group group, qreal scale,
                       const QSize &size = {}, int state = DefaultState,
                       const QStringList &overlays = {}, QString *path_store = nullptr,
                       bool canReturnNull = false,
                       std::optional<KIconColors> colors = std::nullopt);

// Load MIME type icon
QPixmap loadMimeTypeIcon(const QString &name, Group group, int size = 0,
                         int state = DefaultState, const QStringList &overlays = {},
                         QString *path_store = nullptr);

// Get icon file path
QString iconPath(const QString &name, int group_or_size, bool canReturnNull = false);

// Query available icons
QStringList queryIcons(int size, Context context = Any);
QStringList queryIconsByContext(int size, Context context = Any);

// Current size for icon group
int currentSize(Group group);

// Custom palette for SVG coloring
void setCustomPalette(const QPalette &palette);
void resetPalette();
bool hasCustomPalette() const;

// Get current theme
KIconTheme *theme() const;

// Notify icon changes
static void emitChange(Group group);

// Unknown icon fallback
static QPixmap unknown();
```

### Convenience Functions (KDE namespace)

```cpp
namespace KDE {
    QIcon icon(const QString &iconName, KIconLoader *iconLoader = nullptr);
    QIcon icon(const QString &iconName, const KIconColors &colors, KIconLoader * = nullptr);
    QIcon icon(const QString &iconName, const QStringList &overlays, KIconLoader * = nullptr);
}
```

---

## KIconTheme

Represents an installed icon theme.

### Key Methods

```cpp
KIconTheme(const QString &name, const QString &appName = {},
           const QString &basePathHint = {});

QString name() const;           // Display name
QString internalName() const;   // Internal ID
QString description() const;
QString dir() const;            // Theme directory
QStringList inherits() const;   // Fallback themes
bool isValid() const;
bool isHidden() const;
int depth() const;              // Min color depth (8 or 32)

// Sizes
int defaultSize(KIconLoader::Group group) const;
QList<int> querySizes(KIconLoader::Group group) const;

// Icon lookup
QString iconPath(const QString &name, int size,
                 KIconLoader::MatchType match, qreal scale = 1) const;
QString iconPathByName(const QString &name, int size,
                       KIconLoader::MatchType match, qreal scale = 1) const;

bool hasContext(KIconLoader::Context context) const;
bool followsColorScheme() const;  // SVG icons get colorized (monochrome themes)

// Static
static QStringList list();               // All installed themes
static QString current();                // Current theme name
static QString defaultThemeName();       // Default theme
static void reconfigure();               // Reload
static void forceThemeForTests(const QString &name);
static void initTheme();                 // Initialize Breeze with color scheme (KF6.3+)
```

---

## KIconColors

Controls SVG icon recoloring via CSS class injection.

### CSS Classes

SVG icons with these CSS classes will be recolored:
- `.ColorScheme-Text`
- `.ColorScheme-Background`
- `.ColorScheme-Highlight`
- `.ColorScheme-HighlightedText`
- `.ColorScheme-PositiveText`
- `.ColorScheme-NeutralText`
- `.ColorScheme-NegativeText`
- `.ColorScheme-Accent`

### Constructors

```cpp
KIconColors();                        // Default (from app palette)
KIconColors(const QColor &colors);    // All roles set to one color
KIconColors(const QPalette &palette); // From palette
```

### Properties

| Getter | Setter | CSS Class |
|--------|--------|-----------|
| `text()` | `setText()` | `.ColorScheme-Text` |
| `background()` | `setBackground()` | `.ColorScheme-Background` |
| `highlight()` | `setHighlight()` | `.ColorScheme-Highlight` |
| `highlightedText()` | `setHighlightedText()` | `.ColorScheme-HighlightedText` |
| `accent()` | `setAccent()` | `.ColorScheme-Accent` |
| `positiveText()` | `setPositiveText()` | `.ColorScheme-PositiveText` |
| `neutralText()` | `setNeutralText()` | `.ColorScheme-NeutralText` |
| `negativeText()` | `setNegativeText()` | `.ColorScheme-NegativeText` |

### Usage

```cpp
// Custom-colored icon
KIconColors colors;
colors.setText(Qt::white);
colors.setBackground(Qt::transparent);

QIcon icon = KDE::icon("document-open", colors);
```

---

## Dock-Relevant Patterns

### QML themed glyphs

The installed `org.kde.kirigami.primitives/Icon` type is exported to QML as
`Kirigami.Icon`. Its installed type metadata exposes `source`, `fallback`,
`isMask`, `color`, `status`, and `valid`. Use a symbolic theme asset with
`isMask: true` when the glyph must follow a contrast-selected theme color; test
that `valid` becomes true so a missing icon cannot silently pass as a rendered
control.

Icon names can resolve to different artwork within the same theme. For example,
the current MacTahoe theme's `window-close.svg` is a filled circle with the
cross cut out, while `window-close-symbolic.svg` is a monochrome cross. Use the
symbolic variant for a standalone close glyph rather than placing a second
button background behind the filled control.

### Plasma style controls versus KWin decoration buttons

When the in-app control must follow the active Plasma Style, use the public
`PlasmaComponents3.ToolButton` from `org.kde.plasma.components 3.0`. Its
installed QML source describes its visual style as determined by the active
Plasma theme. The public component creates a `Private.ButtonBackground` and
uses `KSvg.FrameSvgItem` with the standard `widgets/button` artwork prefixes:
`toolbutton-hover`/`normal` for hover and `toolbutton-pressed`/`pressed` for
pressed. Those states are driven by the control's `hovered` and `down` values.
Its content item uses `Kirigami.Icon`, so `icon.name` still resolves artwork
from the active icon theme. This is separate from `QQC2.ToolButton` using the
`org.kde.desktop` Controls style.

KWin window decorations are a third, separate system. KDE's Plasma developer
documentation describes them as Aurorae SVG themes or C++ KDecoration plugins.
The public KDecoration button API is implemented by decoration plugins and
requires a `Decoration` context; it does not expose a stable app-facing API for
rendering an arbitrary titlebar button inside another application's QML scene.
Therefore a button inside KDockW should use PlasmaComponents when the desired
source is the active Plasma Style; it should not load KWin decoration artwork
or claim to reproduce that decoration. The ordinary Qt Quick Controls style
may remain `org.kde.desktop` for other controls in KDockW.

Local API verification (2026-11-06): installed PlasmaComponents3
`ToolButton.qml`, `ButtonBackground.qml`, `FlatButtonBackground.qml`, and
`ButtonContent.qml` confirm that the component consumes active Plasma `widgets/button`
artwork, maps `hovered`/`down` to themed hover/pressed assets, and resolves the
icon name through Kirigami. The runtime QML module is supplied by the installed
`plasma-desktoptheme`, which is a dependency of the supported Plasma workspace
session in the inspected system. In that session, the icon theme was `MacTahoe`,
color scheme `KlassyLight`, Plasma style `WhiteSur-alt`, and KWin decoration
plugin `org.kde.klassy` (decoration theme `Klassy`). These settings identify
distinct theme systems and are host observations, not portable defaults.

References:

- [Qt Quick Controls styles](https://doc.qt.io/qt-6/qtquickcontrols-styles.html)
- [QQuickStyle](https://doc.qt.io/qt-6/qquickstyle.html)
- [KDE Plasma themes and plugins: window decorations](https://develop.kde.org/docs/plasma/)
- [Plasma QML API: PlasmaComponents controls](https://develop.kde.org/docs/plasma/widget/plasma-qml-api/)
- [KDecoration3::DecorationButton](https://api.kde.org/legacy/plasma/kdecoration/html/classKDecoration3_1_1DecorationButton.html)

### Loading Task Icons

```cpp
// Use KIconLoader for consistent theme integration
QPixmap icon = KIconLoader::global()->loadIcon(
    iconName, KIconLoader::Panel, 48, KIconLoader::DefaultState);
```

### Theme Color Scheme Awareness

```cpp
// Check if theme recolors icons (important for dock icon style)
if (KIconTheme(KIconTheme::current()).followsColorScheme()) {
    // Icons will be recolored via CSS classes — no manual coloring needed
}
```

### Icon Size for Dock Panel

```cpp
int panelIconSize = KIconLoader::global()->currentSize(KIconLoader::Panel);
```
