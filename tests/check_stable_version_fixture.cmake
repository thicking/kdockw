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
# package-format conversion rules in the opposite direction. The real tree
# remains at its release version during this fixture test.
file(READ "${FIXTURE_DIR}/CMakeLists.txt" contents)
string(REPLACE "KDOCKW_VERSION \"0.1.0\"" "KDOCKW_VERSION \"0.1.0-dev\"" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/CMakeLists.txt" "${contents}")
file(READ "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" contents)
string(REPLACE "version=\"0.1.0\"" "version=\"0.1.0-dev\"" contents "${contents}")
string(REPLACE "date=\"2026-11-03\">" "date=\"2026-11-03\" type=\"development\">" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/src/com.thicking.kdockw.metainfo.xml" "${contents}")
file(READ "${FIXTURE_DIR}/src/po/ru/kdockw.po" contents)
string(REPLACE "Project-Id-Version: KDockW 0.1.0\\n" "Project-Id-Version: KDockW 0.1.0-dev\\n" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/src/po/ru/kdockw.po" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/arch/PKGBUILD" contents)
string(REPLACE "pkgver=0.1.0" "pkgver=0.1.0_pre" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/arch/PKGBUILD" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/arch/.SRCINFO" contents)
string(REPLACE "pkgver = 0.1.0" "pkgver = 0.1.0_pre" contents "${contents}")
string(REPLACE "kdockw-0.1.0.tar.gz" "kdockw-0.1.0-dev.tar.gz" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/arch/.SRCINFO" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.spec" contents)
string(REPLACE "Version:        0.1.0" "Version:        0.1.0~dev" contents "${contents}")
string(REPLACE "upstream_version 0.1.0" "upstream_version 0.1.0-dev" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.spec" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" contents)
string(REPLACE "Version: 0.1.0-1" "Version: 0.1.0~dev-1" contents "${contents}")
string(REPLACE "kdockw-0.1.0.tar.gz" "kdockw-0.1.0-dev.tar.gz" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/kdockw.dsc" "${contents}")
file(READ "${FIXTURE_DIR}/packaging/obs/debian.changelog" contents)
string(REPLACE "kdockw (0.1.0-1)" "kdockw (0.1.0~dev-1)" contents "${contents}")
file(WRITE "${FIXTURE_DIR}/packaging/obs/debian.changelog" "${contents}")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${FIXTURE_DIR}"
        "-DKDOCKW_VERSION=0.1.0-dev"
        -P "${SOURCE_DIR}/tests/check_version_metadata.cmake"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Stable metadata fixture failed:\n${output}${error}")
endif()
