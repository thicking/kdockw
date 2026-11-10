# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

cmake_minimum_required(VERSION 3.22)

# This is the canonical product version. CMake's project VERSION only accepts
# numeric components, so derive its compatibility value from this string.
set(KDOCKW_VERSION "0.4.1")
string(REGEX MATCH "^[0-9]+\\.[0-9]+\\.[0-9]+" KDOCKW_CMAKE_VERSION "${KDOCKW_VERSION}")
if(NOT KDOCKW_CMAKE_VERSION)
    message(FATAL_ERROR "KDOCKW_VERSION must start with a SemVer core (x.y.z)")
endif()
project(kdockw VERSION "${KDOCKW_CMAKE_VERSION}" LANGUAGES C CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.0.0")
set(LAYER_SHELL_QT_MIN_VERSION "6.0.0")

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(KDEClangFormat)
include(KDEGitCommitHooks)
include(ECMDeprecationSettings)
include(FeatureSummary)

# XDG Autostart's system-wide directory is in XDG_CONFIG_DIRS (normally
# /etc/xdg), not below CMAKE_INSTALL_PREFIX. Keep this absolute by default so
# both /usr and /usr/local installs are discoverable by Plasma. Packaging
# formats such as Flatpak can still pass their own explicit directory.
get_property(_kdockw_autostart_override CACHE KDE_INSTALL_AUTOSTARTDIR PROPERTY VALUE)
if(NOT _kdockw_autostart_override)
    set(KDE_INSTALL_AUTOSTARTDIR "/etc/xdg/autostart")
endif()
unset(_kdockw_autostart_override)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    DBus
    Network
    Quick
    QuickControls2
    ShaderTools
    WaylandClient
)
# Qt 6.9 moved private targets into separate CMake packages.
if(Qt6Gui_VERSION VERSION_GREATER_EQUAL "6.9.0")
    find_package(Qt6GuiPrivate ${Qt6Gui_VERSION} EXACT REQUIRED)
endif()
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    WindowSystem
    Config
    CoreAddons
    DBusAddons
    I18n
    GlobalAccel
    ColorScheme
    IconThemes
    Crash
    XmlGui
    Service
    KIO
    JobWidgets
    Notifications
)
find_package(KF6Kirigami ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6KirigamiAddons REQUIRED)
find_package(LayerShellQt ${LAYER_SHELL_QT_MIN_VERSION} REQUIRED)
find_package(LibTaskManager REQUIRED)
find_package(LibNotificationManager REQUIRED)
find_package(KPipeWire REQUIRED)
find_package(Wayland 1.22 REQUIRED COMPONENTS Client)
find_package(WaylandScanner REQUIRED)

ecm_set_disabled_deprecation_versions(
    QT ${QT_MIN_VERSION}
    KF ${KF6_MIN_VERSION}
)

# LayerShellQt < 6.4 lacks Window::setDesiredSize — detect and flag for fallback
include(CheckCXXSourceCompiles)
set(CMAKE_REQUIRED_INCLUDES ${LayerShellQt_INCLUDE_DIRS})
set(CMAKE_REQUIRED_LIBRARIES LayerShellQt::Interface)
check_cxx_source_compiles("
#include <LayerShellQt/Window>
#include <QSize>
int main() { static_cast<LayerShellQt::Window*>(nullptr)->setDesiredSize(QSize{}); }
" _HAVE_LAYERSHELLQT_DESIRED_SIZE)

# LayerShellQt < 6.6 lacks Window::setScreen — detect and flag for fallback
check_cxx_source_compiles("
#include <LayerShellQt/Window>
#include <QScreen>
int main() { static_cast<LayerShellQt::Window*>(nullptr)->setScreen(static_cast<QScreen*>(nullptr)); }
" _HAVE_LAYERSHELLQT_SET_SCREEN)

add_compile_definitions(KDOCKW_VERSION_STRING="${KDOCKW_VERSION}")
option(KDOCKW_DIAGNOSTIC_BUILD "Enable opt-in diagnostic-only configuration routing" OFF)
if(KDOCKW_DIAGNOSTIC_BUILD)
    add_compile_definitions(KDOCKW_DIAGNOSTIC_BUILD)
endif()
if(NOT _HAVE_LAYERSHELLQT_DESIRED_SIZE)
    add_compile_definitions(KDOCKW_COMPAT_NO_LAYERSHELL_DESIRED_SIZE)
endif()
if(NOT _HAVE_LAYERSHELLQT_SET_SCREEN)
    add_compile_definitions(KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN)
endif()

add_subdirectory(src)

if(KDOCKW_DIAGNOSTIC_BUILD)
    # Keep candidate-local translations available without changing the
    # Plasma session's global locale or data paths. The diagnostic binary
    # adds this locale directory only to its own KI18n domain lookup.
    find_program(KDOCKW_MSGFMT_EXECUTABLE msgfmt REQUIRED)
    set(KDOCKW_DIAGNOSTIC_RU_CATALOG
        "${CMAKE_BINARY_DIR}/src/locale/ru/LC_MESSAGES/kdockw.mo")
    add_custom_command(
        OUTPUT "${KDOCKW_DIAGNOSTIC_RU_CATALOG}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${CMAKE_BINARY_DIR}/src/locale/ru/LC_MESSAGES"
        COMMAND "${KDOCKW_MSGFMT_EXECUTABLE}" --check
            -o "${KDOCKW_DIAGNOSTIC_RU_CATALOG}"
            "${CMAKE_SOURCE_DIR}/src/po/ru/kdockw.po"
        DEPENDS "${CMAKE_SOURCE_DIR}/src/po/ru/kdockw.po"
        VERBATIM)
    add_custom_target(kdockw_diagnostic_ru_catalog
        DEPENDS "${KDOCKW_DIAGNOSTIC_RU_CATALOG}")
    add_executable(kdockw_diagnostic_metadata_check tools/verify-kdockw-wayland-metadata.cpp)
    target_link_libraries(kdockw_diagnostic_metadata_check PRIVATE Qt6::Core KF6::Service)
    # A diagnostic candidate is not usable without the KService/KWin preflight
    # checker. Building the documented `kdockw` target must produce both.
    add_dependencies(kdockw kdockw_diagnostic_metadata_check)
    add_dependencies(kdockw kdockw_diagnostic_ru_catalog)
endif()

option(KDOCKW_E2E_TESTS "Register the Docker-based AT-SPI E2E suite (tests/appium/run-e2e.sh) with CTest" OFF)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

file(GLOB_RECURSE ALL_CLANG_FORMAT_SOURCE_FILES src/*.cpp src/*.h)
kde_clang_format(${ALL_CLANG_FORMAT_SOURCE_FILES})
kde_configure_git_pre_commit_hook(CHECKS CLANG_FORMAT)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
