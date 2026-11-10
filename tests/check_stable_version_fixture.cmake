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
set(stable_version "${CMAKE_MATCH_1}")
if(NOT stable_version OR stable_version MATCHES "-dev$")
    message(FATAL_ERROR "Expected a stable KDOCKW_VERSION in fixture source")
endif()
set(development_version "${stable_version}-dev")
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
# Arch is a manual-only compatibility recipe. During release preparation its
# source and checksum remain pinned to the latest published stable version.
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
