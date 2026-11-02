# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

add_executable(kdockw_unit_tests
    main.cpp
    smoke_test.cpp
    test_zoom_calculator.cpp
    test_surface_geometry.cpp
    test_input_region.cpp
    test_output_order.cpp
    test_background_opacity.cpp
    test_background_effects.cpp
    test_settings_autosave.cpp
    test_settings_migration.cpp
    test_taskiconprovider.cpp
    test_desktop_actions.cpp
)

target_link_libraries(kdockw_unit_tests PRIVATE
    Catch2::Catch2
    Qt6::Widgets
    kdockw_lib
)

target_include_directories(kdockw_unit_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/tests
)

catch_discover_tests(kdockw_unit_tests
    PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
)
