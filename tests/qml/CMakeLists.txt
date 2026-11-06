# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Qt Quick Test component tests for src/qml. The real QML files are loaded
# from the source tree; C++ backends are replaced by mocks (see README.md).
# Run: ctest -R qml --output-on-failure

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS QuickTest)

add_executable(kdockw_qml_tests
    main.cpp
    qmltestmocks.cpp
    qmltestmocks.h
)

target_compile_definitions(kdockw_qml_tests PRIVATE
    KDOCKW_QML_MOCKS_DIR="${CMAKE_CURRENT_SOURCE_DIR}/mocks"
)

# utils/zoomcalculator.h (header-only) backs the DockView.zoomLayout() mock.
target_include_directories(kdockw_qml_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_link_libraries(kdockw_qml_tests PRIVATE
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickTest
    KF6::I18nQml
)

set(KDOCKW_QML_TEST_FILES
    tst_dockitem_zoom
    tst_dockitem_geometry
    tst_dockitem_indicators
    tst_icon_alpha
    tst_badge_color_settings
    tst_rounded_clip
    tst_dock_main
    tst_preview_popup
    tst_tooltip_bounds
)

foreach(test_name IN LISTS KDOCKW_QML_TEST_FILES)
    add_test(NAME qml_${test_name}
        COMMAND kdockw_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/${test_name}.qml
    )
    set_tests_properties(qml_${test_name} PROPERTIES
        LABELS "qml"
        TIMEOUT 120
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_QUICK_CONTROLS_STYLE=Basic;LANGUAGE=en_US;XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-config;XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-cache"
    )
endforeach()

# Tooltip placement is also checked with fractional/high-DPI surface scales.
foreach(tooltip_dpr IN ITEMS 1.25 1.5 2.0)
    string(REPLACE "." "_" tooltip_dpr_suffix "${tooltip_dpr}")
    add_test(NAME qml_tst_tooltip_bounds_dpr_${tooltip_dpr_suffix}
        COMMAND kdockw_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_tooltip_bounds.qml
    )
    set_tests_properties(qml_tst_tooltip_bounds_dpr_${tooltip_dpr_suffix} PROPERTIES
        LABELS "qml;tooltip;dpr"
        TIMEOUT 120
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_QUICK_CONTROLS_STYLE=Basic;LANGUAGE=en_US;QT_SCALE_FACTOR=${tooltip_dpr};XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-config;XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-cache"
    )
endforeach()

# Run the pixel-alpha scene-graph check at fractional and high-DPI window
# scales as well as the regular 1.0 scale covered by the ordinary QML test.
foreach(icon_dpr IN ITEMS 1.25 1.5 2.0)
    string(REPLACE "." "_" icon_dpr_suffix "${icon_dpr}")
    add_test(NAME qml_tst_icon_alpha_dpr_${icon_dpr_suffix}
        COMMAND kdockw_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_icon_alpha.qml
    )
    set_tests_properties(qml_tst_icon_alpha_dpr_${icon_dpr_suffix} PROPERTIES
        LABELS "qml"
        TIMEOUT 120
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_QUICK_CONTROLS_STYLE=Basic;LANGUAGE=en_US;QT_SCALE_FACTOR=${icon_dpr};XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-config;XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-cache"
    )
endforeach()

# The preview card is positioned inside a Wayland layer surface and its input
# region follows the same logical geometry. Exercise its edge placement and
# thumbnail settings under fractional and high-DPI scale factors as well.
foreach(preview_dpr IN ITEMS 1.0 1.25 1.5 2.0)
    string(REPLACE "." "_" preview_dpr_suffix "${preview_dpr}")
    add_test(NAME qml_tst_preview_popup_dpr_${preview_dpr_suffix}
        COMMAND kdockw_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_preview_popup.qml
    )
    set_tests_properties(qml_tst_preview_popup_dpr_${preview_dpr_suffix} PROPERTIES
        LABELS "qml;preview;dpr"
        TIMEOUT 120
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_QUICK_CONTROLS_STYLE=Basic;LANGUAGE=en_US;QT_SCALE_FACTOR=${preview_dpr};XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-config;XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/xdg-cache"
    )
endforeach()
