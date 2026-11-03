# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

file(REMOVE_RECURSE "${STAGE_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "DESTDIR=${STAGE_DIR}" "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "/"
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
)
if(NOT install_result EQUAL 0)
    message(FATAL_ERROR "Staged install failed (${install_result}): ${install_output}\n${install_error}")
endif()

foreach(size IN ITEMS 16 22 24 32 48 64 128 256 512)
    set(icon "${STAGE_DIR}/share/icons/hicolor/${size}x${size}/apps/com.thicking.kdockw.png")
    if(NOT EXISTS "${icon}")
        message(FATAL_ERROR "Installed KDockW icon missing at ${icon}")
    endif()
endforeach()

foreach(path IN ITEMS
        "${STAGE_DIR}/share/metainfo/com.thicking.kdockw.metainfo.xml"
        "${STAGE_DIR}/share/applications/com.thicking.kdockw.desktop")
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Expected KDockW identity resource missing at ${path}")
    endif()
endforeach()

set(autostart_entry "${STAGE_DIR}/etc/xdg/autostart/com.thicking.kdockw.autostart.desktop")
if(NOT EXISTS "${autostart_entry}")
    message(FATAL_ERROR "Installed XDG autostart entry missing at ${autostart_entry}")
endif()
file(GLOB_RECURSE installed_autostart_entries "${STAGE_DIR}/*com.thicking.kdockw.autostart.desktop")
list(LENGTH installed_autostart_entries autostart_count)
if(NOT autostart_count EQUAL 1)
    message(FATAL_ERROR "Expected exactly one KDockW XDG autostart entry, found ${autostart_count}")
endif()
file(READ "${autostart_entry}" autostart_content)
if(NOT autostart_content MATCHES "(^|\n)Exec=[^\n]*/kdockw\n")
    message(FATAL_ERROR "XDG autostart must launch the KDockW binary directly")
endif()

file(READ "${STAGE_DIR}/share/applications/com.thicking.kdockw.desktop" desktop_file)
if(NOT desktop_file MATCHES "(^|\n)X-KDE-Wayland-Interfaces=org_kde_plasma_window_management,org_kde_plasma_activation_feedback,zkde_screencast_unstable_v1(\n|$)")
    message(FATAL_ERROR "The application desktop ID or KWin Wayland interfaces changed unexpectedly")
endif()

file(GLOB_RECURSE installed_kdockw_units "${STAGE_DIR}/*kdockw.service")
if(installed_kdockw_units)
    message(FATAL_ERROR "The install tree must not contain a KDockW systemd user unit: ${installed_kdockw_units}")
endif()
if(EXISTS "${SOURCE_DIR}/packaging/systemd/kdockw.service")
    message(FATAL_ERROR "The project still ships packaging/systemd/kdockw.service")
endif()

if(NOT desktop_file MATCHES "Icon=com[.]thicking[.]kdockw")
    message(FATAL_ERROR "The installed desktop file does not reference the KDockW icon name")
endif()
