default:
    @just --list

configure:
    cmake --preset dev

build: configure
    cmake --build --preset dev

release:
    cmake --preset release
    cmake --build --preset release

test:
    ctest --preset dev

run: build
    ./build/dev/bin/kdockw

format:
    ninja -C build/dev clang-format

clean:
    rm -rf build/

# OBS 로컬 빌드 테스트
obs-build-rpm distro="openSUSE_Tumbleweed" arch="x86_64":
    osc build {{distro}} {{arch}} packaging/obs/kdockw.spec

obs-build-deb distro="Debian_13" arch="x86_64":
    osc build {{distro}} {{arch}} packaging/obs/debian.control

distro-update-digests target="all":
    tests/distro/update-digests.sh {{target}}

# Install .desktop file and app icons for development (KWin Wayland protocol access)
dev-desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.local/share/applications
    sed -e 's|@KDE_INSTALL_FULL_BINDIR@/kdockw|'"$PWD"'/build/dev/bin/kdockw|' \
        -e '/^NoDisplay=/d' \
        src/com.thicking.kdockw.desktop.in > ~/.local/share/applications/com.thicking.kdockw.desktop
    for png in branding/logo/kdockw-app-icons/*-apps-com.thicking.kdockw.png; do
        size=$(basename "$png" | cut -d- -f1)
        install -Dm644 "$png" ~/.local/share/icons/hicolor/${size}x${size}/apps/com.thicking.kdockw.png
    done
    kbuildsycoca6 --noincremental
    echo "Installed dev launcher and icons under ~/.local/share"

# Remove dev .desktop file and the icons dev-desktop installed
dev-desktop-clean:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -f ~/.local/share/applications/com.thicking.kdockw.desktop \
        ~/.local/share/icons/hicolor/scalable/apps/com.thicking.kdockw.svg
    for png in branding/logo/kdockw-app-icons/*-apps-com.thicking.kdockw.png; do
        size=$(basename "$png" | cut -d- -f1)
        rm -f ~/.local/share/icons/hicolor/${size}x${size}/apps/com.thicking.kdockw.png
    done
    echo "Removed dev .desktop file and icons"
