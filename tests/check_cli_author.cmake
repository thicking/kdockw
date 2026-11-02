# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

execute_process(
    COMMAND "${EXECUTABLE}" --author
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "kdockw --author failed (${result}): ${error}")
endif()
if(NOT output MATCHES "thicking" OR NOT output MATCHES "Byeonghoon Yoo")
    message(FATAL_ERROR "kdockw --author did not list both KDockW and original Krema attribution: ${output}")
endif()
