# KDockW brand assets

The current application icon is based on the supplied raster master
`logo/kdockw-icon-source.png`. Its hicolor exports (16, 22, 24, 32, 48, 64,
128, 256, and 512 px) live in `logo/kdockw-app-icons/` and are installed by
CMake under the existing `com.thicking.kdockw` icon name. Regenerate them with
`branding/logo/export-app-icons.sh` (ImageMagick's `magick` command is needed).
The original master is kept byte-for-byte; the README lockup is
`logo/kdockw-logo.png`.

The existing `logo/kdockw-icon.svg` and `logo/kdockw-icon-small.svg` are genuine
vector assets from the earlier KDockW identity. They remain unchanged and are
not raster images renamed with an `.svg` extension. The new app icon has a
different visual design, so the old scalable SVG is retained as historical
branding and is not installed as the current application icon. Existing PNG
icons under `src/icons/` are also retained unchanged.

The repository also retains inherited assets named `krema-*` and upstream
screenshots/social cards. They document the project's origin; they are not the
current KDockW app icon. Do not alter source-file copyright notices, the GPL
license, or original Git authorship as part of branding work.
