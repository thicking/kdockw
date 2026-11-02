# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

file(REMOVE_RECURSE "${STAGE_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --prefix "${STAGE_DIR}"
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

file(READ "${STAGE_DIR}/share/applications/com.thicking.kdockw.desktop" desktop_file)
if(NOT desktop_file MATCHES "Icon=com[.]thicking[.]kdockw")
    message(FATAL_ERROR "The installed desktop file does not reference the KDockW icon name")
endif()
