# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Built into the E2E image (tests/appium/Dockerfile), not part of the kdockw build.

cmake_minimum_required(VERSION 3.22)
project(kdockw-test-window LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets DBus)

add_executable(kdockw-test-window main.cpp)
target_link_libraries(kdockw-test-window Qt6::Widgets Qt6::DBus)

install(TARGETS kdockw-test-window DESTINATION bin)
install(FILES org.kde.kdockw.testwindow.desktop org.kde.kdockw.testwindow2.desktop DESTINATION share/applications)
install(FILES org.kdockw.icon008.desktop org.kdockw.icon009.drag-raw.desktop DESTINATION share/applications)
install(FILES raw-icon-quadrants.svg DESTINATION share/kdockw-test-window RENAME icon-raw-quadrants.svg)
