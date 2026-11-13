# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

# GUI integration tests: real dock shells and settings QML on a private
# KWin virtual compositor (see tests/run-with-kwin.sh).
find_program(KWIN_WAYLAND_EXECUTABLE kwin_wayland)
find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(kdockw_integration_tests
    test_settings_lifecycle.cpp
)

target_link_libraries(kdockw_integration_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

add_executable(kdockw_launcher_entry_tests
    test_launcher_entry.cpp
)

target_link_libraries(kdockw_launcher_entry_tests PRIVATE
    Catch2::Catch2
    Qt6::Test
    kdockw_lib
)

if(KWIN_WAYLAND_EXECUTABLE AND DBUS_RUN_SESSION_EXECUTABLE)
    add_test(NAME kdockw_integration_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_integration_tests>
    )
    add_test(NAME kdockw_launcher_entry_tests
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- ${CMAKE_SOURCE_DIR}/tests/run-with-kwin.sh $<TARGET_FILE:kdockw_launcher_entry_tests>
    )
    set_tests_properties(kdockw_integration_tests kdockw_launcher_entry_tests PROPERTIES TIMEOUT 180)
    set_tests_properties(kdockw_integration_tests PROPERTIES RUN_SERIAL TRUE)
else()
    message(STATUS "kwin_wayland or dbus-run-session not found: kdockw_integration_tests is built but not registered with CTest")
endif()
