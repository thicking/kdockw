# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
#
# Opt-in (-DKDOCKW_E2E_TESTS=ON): runs the Docker-based AT-SPI E2E suite from
# CTest. The suite builds its own kdockw inside the container, so this target
# does not depend on the host build. Requires a working `docker` CLI.

find_program(KDOCKW_E2E_DOCKER docker REQUIRED)

add_test(NAME kdockw_e2e
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/run-e2e.sh
)
set_tests_properties(kdockw_e2e PROPERTIES
    LABELS "e2e"
    TIMEOUT 3600
    RUN_SERIAL TRUE
)
