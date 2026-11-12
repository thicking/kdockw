if(NOT DEFINED SOURCE_DIR OR NOT DEFINED FIXTURE_DIR)
    message(FATAL_ERROR "SOURCE_DIR and FIXTURE_DIR are required")
endif()

set(files
    CMakeLists.txt
    src/main.cpp
    src/app/application.cpp
    src/com.thicking.kdockw.metainfo.xml
    src/po/ru/kdockw.po
    packaging/obs/kdockw.spec
    packaging/obs/kdockw.dsc
    packaging/obs/debian.changelog
    tests/distro/build-package.sh
    tests/distro/source-version.sh
    tests/distro/pkg/rpm-build.sh
)
file(REMOVE_RECURSE "${FIXTURE_DIR}")
foreach(file IN LISTS files)
    get_filename_component(directory "${file}" DIRECTORY)
    file(MAKE_DIRECTORY "${FIXTURE_DIR}/${directory}")
    configure_file("${SOURCE_DIR}/${file}" "${FIXTURE_DIR}/${file}" COPYONLY)
endforeach()

# Model a development checkout from the stable release source and verify the
# package-format conversion rules in the opposite direction. Derive the source
# version so this fixture continues to cover subsequent stable version bumps.
file(READ "${FIXTURE_DIR}/CMakeLists.txt" contents)
string(REGEX MATCH "set\\(KDOCKW_VERSION \"([^\"]+)\"\\)" _ "${contents}")
set(source_version "${CMAKE_MATCH_1}")
if(NOT source_version)
    message(FATAL_ERROR "Fixture source has no KDOCKW_VERSION")
endif()
string(REGEX REPLACE "-dev$" "" stable_version "${source_version}")
if(source_version MATCHES "-dev$")
    # Development candidates already carry development package metadata.
    # Normalize the copied tree back to a synthetic stable baseline so this
    # fixture continues to test stable-to-development conversion at every
    # point in the release cycle.
    string(REPLACE "KDOCKW_VERSION \"${source_version}\""
        "KDOCKW_VERSION \"${stable_version}\"" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/CMakeLists.txt" "${contents}")

    file(READ "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" contents)
    string(REGEX MATCH "<release version=\"${source_version}\" date=\"[0-9-]+\" type=\"development\">" release_header "${contents}")
    if(NOT release_header)
        message(FATAL_ERROR "AppStream development release header is missing for ${source_version}")
    endif()
    string(REPLACE "${release_header}" "<release version=\"${stable_version}\" date=\"2026-01-01\">" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" "${contents}")

    file(READ "${FIXTURE_DIR}/src/po/ru/kdockw.po" contents)
    string(REPLACE "Project-Id-Version: KDockW ${source_version}\\n"
        "Project-Id-Version: KDockW ${stable_version}\\n" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/src/po/ru/kdockw.po" "${contents}")

    file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.spec" contents)
    string(REPLACE "Version:        ${stable_version}~dev" "Version:        ${stable_version}" contents "${contents}")
    string(REPLACE "upstream_version ${source_version}" "upstream_version ${stable_version}" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.spec" "${contents}")

    file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" contents)
    string(REPLACE "Version: ${stable_version}~dev-1" "Version: ${stable_version}-1" contents "${contents}")
    string(REPLACE "kdockw-${source_version}.tar.gz" "kdockw-${stable_version}.tar.gz" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" "${contents}")

    file(READ "${FIXTURE_DIR}/packaging/obs/debian.changelog" contents)
    string(REPLACE "kdockw (${stable_version}~dev-1)" "kdockw (${stable_version}-1)" contents "${contents}")
    file(WRITE "${FIXTURE_DIR}/packaging/obs/debian.changelog" "${contents}")
endif()
if(NOT stable_version)
    message(FATAL_ERROR "Expected a stable SemVer core in fixture source")
endif()
set(development_version "${stable_version}-dev")
file(READ "${FIXTURE_DIR}/CMakeLists.txt" contents)
string(REPLACE "KDOCKW_VERSION \"${stable_version}\"" "KDOCKW_VERSION \"${development_version}\"" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/CMakeLists.txt" "${contents}")
file(READ "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" contents)
string(REGEX MATCH "<release version=\"${stable_version}\" date=\"([^\"]+)\">" _ "${contents}")
set(stable_release_date "${CMAKE_MATCH_1}")
if(NOT stable_release_date)
    message(FATAL_ERROR "AppStream has no release entry for ${stable_version}")
endif()
string(REPLACE "version=\"${stable_version}\"" "version=\"${development_version}\"" contents "${contents}")
string(REPLACE "date=\"${stable_release_date}\">" "date=\"${stable_release_date}\" type=\"development\">" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" "${contents}")
file(READ "${FIXTURE_DIR}/src/po/ru/kdockw.po" contents)
string(REPLACE "Project-Id-Version: KDockW ${stable_version}\\n" "Project-Id-Version: KDockW ${development_version}\\n" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/src/po/ru/kdockw.po" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.spec" contents)
string(REPLACE "Version:        ${stable_version}" "Version:        ${stable_version}~dev" contents "${contents}")
string(REPLACE "upstream_version ${stable_version}" "upstream_version ${development_version}" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.spec" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" contents)
string(REPLACE "Version: ${stable_version}-1" "Version: ${stable_version}~dev-1" contents "${contents}")
string(REPLACE "kdockw-${stable_version}.tar.gz" "kdockw-${development_version}.tar.gz" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/debian.changelog" contents)
string(REPLACE "kdockw (${stable_version}-1)" "kdockw (${stable_version}~dev-1)" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/debian.changelog" "${contents}")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${FIXTURE_DIR}"
        "-DKDOCKW_VERSION=${development_version}"
        -P "${SOURCE_DIR}/tests/check_version_metadata.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Stable metadata fixture failed:\n${output}${error}")
endif()
