# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

qt_add_resources(QML_RESOURCES qml/qml.qrc)
if(KDOCKW_DIAGNOSTIC_BUILD)
    qt6_add_resources(KDOCKW_DIAGNOSTIC_QML_RESOURCES qml/diagnostic.qrc)
endif()

kconfig_add_kcfg_files(KDOCKW_KCFG_SRCS GENERATE_MOC config/kdockw.kcfgc)

add_library(kdockw_lib STATIC
    app/application.cpp
    app/application.h

    platform/dockplatform.h
    platform/dockplatformfactory.h
    platform/dockplatformfactory.cpp
    platform/kwinpointermotionwatcher.h
    platform/kwinpointermotionwatcher.cpp
    platform/pointerfocustracker.h
    platform/pointerfocustracker.cpp
    platform/waylanddockplatform.h
    platform/waylanddockplatform.cpp

    shell/dockshell.h
    shell/dockshell.cpp
    shell/multidockmanager.h
    shell/multidockmanager.cpp
    shell/dockview.h
    shell/dockview.cpp
    shell/dockvisibilitycontroller.h
    shell/dockvisibilitycontroller.cpp
    shell/edgetrigger.h
    shell/edgetrigger.cpp
    shell/previewcontroller.h
    shell/previewcontroller.cpp
    shell/previewframecache.h
    shell/previewframecache.cpp
    shell/dockwidget.h
    shell/dockwidget.cpp
    shell/settingswindow.h
    shell/settingswindow.cpp
    shell/outputordermonitor.h
    shell/outputordermonitor.cpp

    update/releaseupdatechecker.h
    update/releaseupdatechecker.cpp

    config/screensettings.h
    config/screensettings.cpp

    style/backgroundstyle.h
    style/backgroundstyle.cpp

    scenegraph/clippedpipewiresourceitem.h
    scenegraph/clippedpipewiresourceitem.cpp

    models/dockmodel.h
    models/dockmodel.cpp
    models/dockentry.h
    models/dockentry.cpp
    models/dockactions.h
    models/dockactions.cpp
    models/dockcontextmenu.h
    models/dockcontextmenu.cpp
    models/desktopactions.h
    models/desktopactions.cpp
    models/taskiconprovider.h
    models/taskiconprovider.cpp
    models/icondiag.h
    models/icondiag.cpp
    models/notificationtracker.h
    models/notificationtracker.cpp
    models/launcherentrytracker.h
    models/launcherentrytracker.cpp

    utils/zoomcalculator.h
    utils/zoomlayoutvariant.h
    utils/springzoomcontroller.h
    utils/springzoomcontroller.cpp
    utils/surfacegeometry.h
    utils/inputregion.h
    utils/inputregion.cpp

    ${KDOCKW_KCFG_SRCS}
    ${QML_RESOURCES}
    ${KDOCKW_DIAGNOSTIC_QML_RESOURCES}
)

# kde_output_order_v1: KWin's published primary-output order. The XML is
# vendored because upstream treats the protocol as a DE implementation
# detail and does not install it. qt6_generate_* emits both the C
# marshalling layer (wayland-*-protocol.c) and the C++ wrapper.
qt6_generate_wayland_protocol_client_sources(kdockw_lib
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/protocols/kde-output-order-v1.xml
)

qt6_add_shaders(kdockw_lib "acrylic_shaders"
    BATCHABLE PRECOMPILE OPTIMIZED
    PREFIX "/"
    FILES qml/shaders/acrylic_overlay.frag
          qml/shaders/outer_shadow.frag
)

target_link_libraries(kdockw_lib PUBLIC
    K::KPipeWire
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::DBus
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WaylandClient
    KF6::WindowSystem
    KF6::ConfigCore
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::I18n
    KF6::I18nQml
    KF6::GlobalAccel
    KF6::ColorScheme
    KF6::IconThemes
    KF6::Crash
    KF6::XmlGui
    KF6::Service
    KF6::KIOGui
    KF6::JobWidgets
    KF6::Notifications
    LayerShellQt::Interface
    PW::LibTaskManager
    PW::LibNotificationManager
    Wayland::Client
)
target_link_libraries(kdockw_lib PRIVATE Qt6::GuiPrivate)

target_include_directories(kdockw_lib PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)

add_executable(kdockw main.cpp)
target_link_libraries(kdockw PRIVATE kdockw_lib)
target_compile_definitions(kdockw PRIVATE
    KDOCKW_INSTALL_LOCALE_RELATIVE_PATH="${KDOCKW_INSTALL_LOCALE_RELATIVE_PATH}"
)

ki18n_install(po)

install(TARGETS kdockw ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})

# Generate .desktop file with resolved install paths for KWin Wayland protocol access
configure_file(
    com.thicking.kdockw.desktop.in
    ${CMAKE_CURRENT_BINARY_DIR}/com.thicking.kdockw.desktop
    @ONLY
)
install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/com.thicking.kdockw.desktop
    DESTINATION ${KDE_INSTALL_APPDIR}
)

configure_file(
    com.thicking.kdockw.autostart.desktop.in
    ${CMAKE_CURRENT_BINARY_DIR}/com.thicking.kdockw.autostart.desktop
    @ONLY
)
install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/com.thicking.kdockw.autostart.desktop
    DESTINATION ${KDE_INSTALL_AUTOSTARTDIR}
)

install(
    FILES com.thicking.kdockw.metainfo.xml
    DESTINATION ${KDE_INSTALL_METAINFODIR}
)

install(FILES kdockw.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})

include(ECMInstallIcons)
ecm_install_icons(
    ICONS
        ../branding/logo/kdockw-app-icons/16-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/22-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/24-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/32-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/48-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/64-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/128-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/256-apps-com.thicking.kdockw.png
        ../branding/logo/kdockw-app-icons/512-apps-com.thicking.kdockw.png
    DESTINATION ${KDE_INSTALL_ICONDIR}
    THEME hicolor
)
