# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

# GUI integration tests: real dock shells on a private KWin virtual compositor.
# Tests use two outputs by default; selected-monitor coverage uses three.
find_program(KWIN_WAYLAND_EXECUTABLE kwin_wayland)
find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(kdockw_kwin_tests
    test_primary_output.cpp
)

add_executable(kdockw_selected_output_tests
    test_selected_outputs.cpp
)

target_link_libraries(kdockw_selected_output_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

target_link_libraries(kdockw_kwin_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

target_include_directories(kdockw_kwin_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/tests
)

target_include_directories(kdockw_selected_output_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/tests
)

# Grouped-task click/wheel actions. A separate binary because
# kdockw_kwin_tests forces the layer-shell integration process-wide, while this
# test spawns itself as an ordinary two-window app.
add_executable(kdockw_grouped_activation_tests
    test_grouped_activation.cpp
)

target_link_libraries(kdockw_grouped_activation_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)
add_executable(kdockw_task_icons_tests
    test_task_icons.cpp
)

target_link_libraries(kdockw_task_icons_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_launch_in_place_tests
    test_launch_in_place.cpp
)

target_link_libraries(kdockw_launch_in_place_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)


add_executable(kdockw_showdesktop_tests
    test_show_desktop.cpp
)

target_link_libraries(kdockw_showdesktop_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_tooltip_tests
    test_tooltip_geometry.cpp
)

target_link_libraries(kdockw_tooltip_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_hittest_tests
    test_dock_hit_test.cpp
)

target_link_libraries(kdockw_hittest_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_preview_tests
    test_preview_setting.cpp
)

target_link_libraries(kdockw_preview_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_delegate_geometry_tests
    test_delegate_geometry.cpp
)

target_link_libraries(kdockw_delegate_geometry_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

if(KWIN_WAYLAND_EXECUTABLE AND DBUS_RUN_SESSION_EXECUTABLE)
    add_test(NAME kdockw_kwin_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_kwin_tests>
    )
    add_test(NAME kdockw_selected_output_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_selected_output_tests>
    )
    set_tests_properties(kdockw_selected_output_tests PROPERTIES
        TIMEOUT 300
        ENVIRONMENT "KDOCKW_TEST_OUTPUT_COUNT=3"
    )

    set_tests_properties(kdockw_kwin_tests PROPERTIES TIMEOUT 300)

    add_test(NAME kdockw_grouped_activation_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_grouped_activation_tests>
    )
    set_tests_properties(kdockw_grouped_activation_tests PROPERTIES TIMEOUT 300)
    add_test(NAME kdockw_task_icons_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_task_icons_tests>
    )
    set_tests_properties(kdockw_task_icons_tests PROPERTIES TIMEOUT 300)
    add_test(NAME kdockw_launch_in_place_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_launch_in_place_tests>
    )
    set_tests_properties(kdockw_launch_in_place_tests PROPERTIES TIMEOUT 300)


    add_test(NAME kdockw_showdesktop_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_showdesktop_tests>
    )
    set_tests_properties(kdockw_showdesktop_tests PROPERTIES
        TIMEOUT 120
        ENVIRONMENT "KDOCKW_TEST_KWIN_EFFECTS=${CMAKE_CURRENT_SOURCE_DIR}/effects"
    )

    add_test(NAME kdockw_tooltip_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_tooltip_tests>
    )
    set_tests_properties(kdockw_tooltip_tests PROPERTIES TIMEOUT 120)

    add_test(NAME kdockw_hittest_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_hittest_tests>
    )
    set_tests_properties(kdockw_hittest_tests PROPERTIES TIMEOUT 300)

    add_test(NAME kdockw_preview_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_preview_tests>
    )
    set_tests_properties(kdockw_preview_tests PROPERTIES TIMEOUT 120)

    add_test(NAME kdockw_delegate_geometry_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_delegate_geometry_tests>
    )
    set_tests_properties(kdockw_delegate_geometry_tests PROPERTIES
        TIMEOUT 120
        ENVIRONMENT "KDOCKW_TEST_KWIN_EFFECTS=${CMAKE_CURRENT_SOURCE_DIR}/effects"
    )
else()
    message(STATUS "kwin_wayland or dbus-run-session not found: kdockw_kwin_tests, kdockw_selected_output_tests, kdockw_grouped_activation_tests, kdockw_task_icons_tests, kdockw_launch_in_place_tests, kdockw_showdesktop_tests, kdockw_tooltip_tests, kdockw_hittest_tests, kdockw_preview_tests and kdockw_delegate_geometry_tests are built but not registered with CTest")
endif()
