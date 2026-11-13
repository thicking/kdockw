# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(kdockw_unit_tests
    main.cpp
    smoke_test.cpp
    test_zoom_calculator.cpp
    test_spring_zoom_controller.cpp
    test_surface_geometry.cpp
    test_unlock_recovery_policy.cpp
    test_input_region.cpp
    test_output_order.cpp
    test_background_opacity.cpp
    test_background_effects.cpp
    test_settings_autosave.cpp
    test_application_config.cpp
    test_dock_visibility_geometry.cpp
    test_settings_migration.cpp
    test_dock_entries.cpp
    test_dock_entries_model.cpp
    test_dock_presentation_model.cpp
    test_folder_stack_model.cpp
    test_language_setting.cpp
    test_taskiconprovider.cpp
    test_icondiag.cpp
    test_desktop_actions.cpp
    test_about_data.cpp
    test_preview_capture_mode.cpp
    test_release_update_checker.cpp
    test_rounded_clip_geometry.cpp
    test_pipewire_clip_tree.cpp
    test_preview_frame_cache.cpp
)

target_compile_definitions(kdockw_unit_tests PRIVATE
    KDOCKW_TEST_LOCALE_DIR="${CMAKE_BINARY_DIR}/src/locale"
    KDOCKW_TEST_INSTALL_LOCALE_DIR="${KDE_INSTALL_FULL_LOCALEDIR}"
)

target_link_libraries(kdockw_unit_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
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
