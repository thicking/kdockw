if(NOT DEFINED SOURCE_DIR OR NOT DEFINED FIXTURE_DIR)
    message(FATAL_ERROR "SOURCE_DIR and FIXTURE_DIR are required")
endif()

set(files
    CMakeLists.txt
    src/main.cpp
    src/app/application.cpp
    src/com.thicking.kdockw.metainfo.xml
    src/po/ru/kdockw.po
    packaging/arch/PKGBUILD
    packaging/arch/.SRCINFO
    packaging/obs/kdockw.spec
    packaging/obs/kdockw.dsc
    packaging/obs/debian.changelog
)
file(REMOVE_RECURSE "${FIXTURE_DIR}")
foreach(file IN LISTS files)
    get_filename_component(directory "${file}" DIRECTORY)
    file(MAKE_DIRECTORY "${FIXTURE_DIR}/${directory}")
    configure_file("${SOURCE_DIR}/${file}" "${FIXTURE_DIR}/${file}" COPYONLY)
endforeach()

# The fixture models the stable 0.1.0 release metadata. The real checkout stays
# at its development version throughout this test.
set(stable_mappings
    "0.1.0-dev|0.1.0"
    "0.1.0_pre|0.1.0"
    "0.1.0~dev-1|0.1.0-1"
    "0.1.0~dev|0.1.0"
)
foreach(mapping IN LISTS stable_mappings)
    string(REPLACE "|" ";" pair "${mapping}")
    list(GET pair 0 development)
    list(GET pair 1 stable)
    foreach(file IN LISTS files)
        file(READ "${FIXTURE_DIR}/${file}" contents)
        string(REPLACE "${development}" "${stable}" contents "${contents}")
        if(file STREQUAL "src/com.thicking.kdockw.metainfo.xml" AND development STREQUAL "0.1.0-dev")
            string(REPLACE " type=\"development\"" "" contents "${contents}")
        endif()
        file(WRITE "${FIXTURE_DIR}/${file}" "${contents}")
    endforeach()
endforeach()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${FIXTURE_DIR}"
        "-DKDOCKW_VERSION=0.1.0"
        -P "${SOURCE_DIR}/tests/check_version_metadata.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Stable metadata fixture failed:\n${output}${error}")
endif()
