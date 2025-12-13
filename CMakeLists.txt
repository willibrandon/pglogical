cmake_minimum_required(VERSION 3.14)
project(pglogical C)

# Extract version from pglogical.h
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/pglogical.h" PGLOGICAL_H_CONTENT)
string(REGEX MATCH "#define PGLOGICAL_VERSION \"([0-9]+\\.[0-9]+\\.[0-9]+)\"" _ ${PGLOGICAL_H_CONTENT})
set(PGLOGICAL_VERSION ${CMAKE_MATCH_1})
message(STATUS "pglogical version: ${PGLOGICAL_VERSION}")

# Find pg_config
find_program(PG_CONFIG pg_config
    HINTS
        $ENV{PGROOT}/bin
        $ENV{PG_CONFIG}
    DOC "Path to pg_config executable"
)

if(NOT PG_CONFIG)
    message(FATAL_ERROR "pg_config not found. Set PG_CONFIG or add PostgreSQL bin directory to PATH.")
endif()

message(STATUS "Using pg_config: ${PG_CONFIG}")

# Helper macro to get pg_config values
macro(pg_config_get VAR FLAG)
    execute_process(
        COMMAND ${PG_CONFIG} ${FLAG}
        OUTPUT_VARIABLE ${VAR}
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _pg_config_result
    )
    if(NOT _pg_config_result EQUAL 0)
        message(FATAL_ERROR "pg_config ${FLAG} failed")
    endif()
endmacro()

# Get PostgreSQL paths
pg_config_get(PG_INCLUDEDIR --includedir)
pg_config_get(PG_INCLUDEDIR_SERVER --includedir-server)
pg_config_get(PG_PKGINCLUDEDIR --pkgincludedir)
pg_config_get(PG_LIBDIR --libdir)
pg_config_get(PG_PKGLIBDIR --pkglibdir)
pg_config_get(PG_SHAREDIR --sharedir)
pg_config_get(PG_BINDIR --bindir)
pg_config_get(PG_VERSION --version)

message(STATUS "PostgreSQL include dir: ${PG_INCLUDEDIR}")
message(STATUS "PostgreSQL server include dir: ${PG_INCLUDEDIR_SERVER}")
message(STATUS "PostgreSQL lib dir: ${PG_LIBDIR}")
message(STATUS "PostgreSQL version: ${PG_VERSION}")

# Extract major version number for compat directory selection
# PostgreSQL version string looks like "PostgreSQL 16.2" or "PostgreSQL 9.6.24"
string(REGEX MATCH "([0-9]+)\\.([0-9]+)" _ ${PG_VERSION})
set(PG_MAJOR ${CMAKE_MATCH_1})
set(PG_MINOR ${CMAKE_MATCH_2})

# For PostgreSQL 9.x, we use "9X" format, otherwise just major version
if(PG_MAJOR EQUAL 9)
    set(PGVER "${PG_MAJOR}${PG_MINOR}")
else()
    set(PGVER "${PG_MAJOR}")
endif()

message(STATUS "PostgreSQL major version: ${PG_MAJOR}")
message(STATUS "Using compat directory: compat${PGVER}")

# Verify compat directory exists
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/compat${PGVER}")
    message(FATAL_ERROR "Compatibility directory compat${PGVER} not found. PostgreSQL ${PG_MAJOR}.${PG_MINOR} may not be supported.")
endif()

# Platform-specific settings
if(WIN32)
    # Windows/MSVC specific settings (from pg_config --cppflags)
    add_definitions(
        -DWIN32
        -DWINDOWS
        -D__WINDOWS__
        -D__WIN32__
        -D_CRT_SECURE_NO_DEPRECATE
        -D_CRT_NONSTDC_NO_DEPRECATE
        -D_CRT_SECURE_NO_WARNINGS
    )

    # Windows needs to link against postgres.lib
    find_library(POSTGRES_LIB postgres HINTS ${PG_LIBDIR})
    if(NOT POSTGRES_LIB)
        message(FATAL_ERROR "postgres.lib not found in ${PG_LIBDIR}")
    endif()
    message(STATUS "Found postgres library: ${POSTGRES_LIB}")

    # Windows-specific include paths for MSVC builds
    set(PG_PORT_INCLUDES
        "${PG_INCLUDEDIR_SERVER}/port/win32"
        "${PG_INCLUDEDIR_SERVER}/port/win32_msvc"
    )
endif()

# Find libpq
find_library(LIBPQ_LIBRARY
    NAMES pq libpq
    HINTS ${PG_LIBDIR}
)
if(NOT LIBPQ_LIBRARY)
    message(FATAL_ERROR "libpq not found in ${PG_LIBDIR}")
endif()
message(STATUS "Found libpq: ${LIBPQ_LIBRARY}")

# Common include directories
set(PGLOGICAL_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/compat${PGVER}
    ${PG_INCLUDEDIR}
    ${PG_INCLUDEDIR_SERVER}
    "${PG_INCLUDEDIR}/internal"  # For pqexpbuffer.h and other internal headers
)

if(WIN32)
    list(APPEND PGLOGICAL_INCLUDES ${PG_PORT_INCLUDES})
endif()

# Main pglogical extension sources
set(PGLOGICAL_SOURCES
    pglogical.c
    pglogical_apply.c
    pglogical_apply_heap.c
    pglogical_apply_spi.c
    pglogical_conflict.c
    pglogical_dependency.c
    pglogical_executor.c
    pglogical_fe.c
    pglogical_functions.c
    pglogical_manager.c
    pglogical_monitoring.c
    pglogical_node.c
    pglogical_output_config.c
    pglogical_output_plugin.c
    pglogical_output_proto.c
    pglogical_proto_json.c
    pglogical_proto_native.c
    pglogical_queue.c
    pglogical_relcache.c
    pglogical_repset.c
    pglogical_rpc.c
    pglogical_sequences.c
    pglogical_sync.c
    pglogical_worker.c
    compat${PGVER}/pglogical_compat.c
)

# Build pglogical shared library
add_library(pglogical SHARED ${PGLOGICAL_SOURCES})
target_include_directories(pglogical PRIVATE ${PGLOGICAL_INCLUDES})

if(WIN32)
    # On Windows, extensions link against postgres.lib (import library)
    # which provides stubs for symbols exported by postgres.exe.
    # Do NOT define BUILDING_DLL - that's for building PostgreSQL itself.
    # Also need libintl for gettext i18n functions.
    find_library(LIBINTL_LIBRARY NAMES intl libintl HINTS ${PG_LIBDIR})
    target_link_libraries(pglogical PRIVATE ${POSTGRES_LIB} ${LIBPQ_LIBRARY})
    if(LIBINTL_LIBRARY)
        target_link_libraries(pglogical PRIVATE ${LIBINTL_LIBRARY})
    endif()
    set_target_properties(pglogical PROPERTIES PREFIX "")
else()
    target_link_libraries(pglogical PRIVATE ${LIBPQ_LIBRARY})
    set_target_properties(pglogical PROPERTIES PREFIX "")
endif()

# Compiler options
if(MSVC)
    # /Zc:preprocessor - Use conformant preprocessor (handles #if in macro args like GCC/Clang)
    # /W3 - Warning level 3
    # /wd4267 /wd4244 - Disable size_t conversion warnings (common in PG headers)
    target_compile_options(pglogical PRIVATE /W3 /Zc:preprocessor /wd4267 /wd4244)
else()
    target_compile_options(pglogical PRIVATE -Wall -Werror=implicit-function-declaration)
endif()

# Build pglogical_output shared library (backwards compatibility shim)
add_library(pglogical_output SHARED pglogical_output.c)
target_include_directories(pglogical_output PRIVATE ${PGLOGICAL_INCLUDES})

if(WIN32)
    target_link_libraries(pglogical_output PRIVATE ${POSTGRES_LIB})
    set_target_properties(pglogical_output PROPERTIES PREFIX "")
    target_compile_options(pglogical_output PRIVATE /W3 /Zc:preprocessor /wd4267 /wd4244)
else()
    set_target_properties(pglogical_output PROPERTIES PREFIX "")
endif()

# Build pglogical_create_subscriber executable
# Note: On Windows, this requires pgport and pgcommon static libraries
# which may not be available in all PostgreSQL distributions.
add_executable(pglogical_create_subscriber
    pglogical_create_subscriber.c
    pglogical_fe.c
)
target_include_directories(pglogical_create_subscriber PRIVATE ${PGLOGICAL_INCLUDES})
target_link_libraries(pglogical_create_subscriber PRIVATE ${LIBPQ_LIBRARY})

if(WIN32)
    # Windows needs pgport and pgcommon for frontend utility functions
    find_library(PGPORT_LIBRARY NAMES pgport libpgport HINTS ${PG_LIBDIR} PATH_SUFFIXES lib)
    find_library(PGCOMMON_LIBRARY NAMES pgcommon libpgcommon HINTS ${PG_LIBDIR} PATH_SUFFIXES lib)

    if(PGPORT_LIBRARY AND PGCOMMON_LIBRARY)
        target_link_libraries(pglogical_create_subscriber PRIVATE ${PGCOMMON_LIBRARY} ${PGPORT_LIBRARY})
        message(STATUS "Found pgport: ${PGPORT_LIBRARY}")
        message(STATUS "Found pgcommon: ${PGCOMMON_LIBRARY}")
    else()
        message(WARNING "pgport/pgcommon libraries not found - pglogical_create_subscriber may not link")
    endif()

    if(LIBINTL_LIBRARY)
        target_link_libraries(pglogical_create_subscriber PRIVATE ${LIBINTL_LIBRARY})
    endif()
    target_link_libraries(pglogical_create_subscriber PRIVATE ws2_32)
    target_compile_options(pglogical_create_subscriber PRIVATE /W3 /Zc:preprocessor /wd4267 /wd4244)
endif()

# Generate pglogical.control from template
set(REQUIRES_LINE "")
if(PGVER STREQUAL "94")
    set(REQUIRES_LINE "requires = pglogical_origin")
endif()

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/pglogical.control.in
    ${CMAKE_CURRENT_BINARY_DIR}/pglogical.control
    @ONLY
)

# Custom target to generate control file with proper substitutions
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/pglogical.control
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pglogical.control.in ${CMAKE_CURRENT_BINARY_DIR}/pglogical.control.tmp
    COMMAND ${CMAKE_COMMAND} -DINPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/pglogical.control.tmp
                             -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/pglogical.control
                             -DPGLOGICAL_VERSION=${PGLOGICAL_VERSION}
                             -DREQUIRES=${REQUIRES_LINE}
                             -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/configure_control.cmake
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/pglogical.control.in
    COMMENT "Generating pglogical.control"
)

# For now, do a simple file replacement
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/pglogical.control.in CONTROL_CONTENT)
string(REPLACE "__PGLOGICAL_VERSION__" "${PGLOGICAL_VERSION}" CONTROL_CONTENT "${CONTROL_CONTENT}")
string(REPLACE "__REQUIRES__" "${REQUIRES_LINE}" CONTROL_CONTENT "${CONTROL_CONTENT}")
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/pglogical.control "${CONTROL_CONTENT}")

# Collect SQL files for installation
file(GLOB SQL_FILES "${CMAKE_CURRENT_SOURCE_DIR}/pglogical--*.sql")
list(APPEND SQL_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/pglogical_origin.control"
    "${CMAKE_CURRENT_SOURCE_DIR}/pglogical_origin--1.0.0.sql"
)

# Installation rules
install(TARGETS pglogical pglogical_output
    LIBRARY DESTINATION "${PG_PKGLIBDIR}"
    RUNTIME DESTINATION "${PG_PKGLIBDIR}"  # For Windows DLLs
)

install(TARGETS pglogical_create_subscriber
    RUNTIME DESTINATION "${PG_BINDIR}"
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/pglogical.control
    DESTINATION "${PG_SHAREDIR}/extension"
)

install(FILES ${SQL_FILES}
    DESTINATION "${PG_SHAREDIR}/extension"
)

# Summary
message(STATUS "")
message(STATUS "=== pglogical ${PGLOGICAL_VERSION} build configuration ===")
message(STATUS "PostgreSQL version: ${PG_VERSION}")
message(STATUS "Compatibility layer: compat${PGVER}")
message(STATUS "Install pkglibdir: ${PG_PKGLIBDIR}")
message(STATUS "Install sharedir: ${PG_SHAREDIR}")
message(STATUS "")
