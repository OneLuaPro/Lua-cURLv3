if(ONELUAPRO)
# ==============================================================================
#
# MIT License
#
# Copyright (c) 2014-2021 Alexey Melnichuk
# Copyright (c) 2026      The OneLuaPro project authors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in 
# the Software without restriction, including without limitation the rights to 
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all 
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ------------------------------------------------------------------------------
# CMake for lcurl
# ------------------------------------------------------------------------------
# Setup with Visual Studio 17 2022 generator for x64
# ------------------------------------------------------------------------------
# Visual Studio is a mutlti-configuration generator
# https://stackoverflow.com/questions/24460486/
#
# Basic instructions for out-of-source build
# ------------------------------------------
# mkdir build && cd build
# cmake .. -G "Visual Studio 17 2022" -A x64
# cmake --build . --config Release
# cmake --install . --config Release
# 
# Available architectures (-A ...) are: Win32, x64, ARM, ARM64

# ------------------------------------------------------------------------------
# General definitions
cmake_minimum_required(VERSION 3.31 FATAL_ERROR)

# ------------------------------------------------------------------------------
# find liblua installation and version info
if(NOT LUA_HINTS)
  if(WIN32)
    set(LUA_HINTS "c:/Apps")
  endif()
endif()
find_package(liblua REQUIRED CONFIG HINTS ${LUA_HINTS})
if(liblua_FOUND)
  message(STATUS "liblua version        : ${liblua_VERSION}")
  message(STATUS "liblua install prefix : ${LIBLUA_INSTALLDIR}")
  message(STATUS "liblua include dir    : ${LIBLUA_INCLUDEDIR}")
  message(STATUS "liblua lib dir        : ${LIBLUA_LIBDIR}")
else()
  message(FATAL_ERROR "Unable to find liblua version ${liblua_VERSION}.")
endif()
# Note: liblua_VERSION is set by find_package() directly. LIBLUA_INSTALLDIR,
# LIBLUA_INCLUDEDIR and LIBLUA_LIBDIR are set by libluaConfigVersion.cmake in
# <prefix>/share/cmake/liblua.

# ------------------------------------------------------------------------------
# Installation prefix directory - automatically set from find_package()
# Needs to be defined before project definition statement - for whatever reason
if(NOT CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX ${LIBLUA_INSTALLDIR})
endif()

# ------------------------------------------------------------------------------
# Project defintion
project(lcurl C)

# ------------------------------------------------------------------------------
# Other settings
set(CMAKE_VERBOSE_MAKEFILE ON)

# ------------------------------------------------------------------------------
# Setup GNU-alike installatin directories
include (GNUInstallDirs)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/${CMAKE_INSTALL_LIBDIR})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/${CMAKE_INSTALL_LIBDIR})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/${CMAKE_INSTALL_BINDIR})
set(INSTALL_LIBDIR
  ${CMAKE_INSTALL_LIBDIR} CACHE PATH "Installation directory for libraries")
set(INSTALL_BINDIR
  ${CMAKE_INSTALL_BINDIR} CACHE PATH "Installation directory for executables")
set(INSTALL_INCLUDEDIR
  ${CMAKE_INSTALL_INCLUDEDIR} CACHE PATH "Installation directory for header files")
set(INSTALL_DOCDIR
  ${CMAKE_INSTALL_DOCDIR} CACHE PATH "Installation directory for documentation")
set(INSTALL_MANDIR
  ${CMAKE_INSTALL_MANDIR} CACHE PATH "Installation directory for manpages")
set(INSTALL_DATAROOTDIR
  ${CMAKE_INSTALL_DATAROOTDIR} CACHE PATH "Installation directory for data")
# Lua-specific installation dirs
set(INSTALL_TOP_CDIR
  ${INSTALL_LIBDIR}/lua/${liblua_VERSION_MAJOR}.${liblua_VERSION_MINOR})
set(INSTALL_TOP_LDIR
  ${INSTALL_DATAROOTDIR}/lua/${liblua_VERSION_MAJOR}.${liblua_VERSION_MINOR})

# ------------------------------------------------------------------------------
# lcurl DLL
add_library(lcurl SHARED)
# setup lua include directory
target_include_directories(lcurl PRIVATE
  ${LIBLUA_INCLUDEDIR}
  ${LIBLUA_INCLUDEDIR}/curl
)
# plattform-independend sources
file(GLOB lcurl_sources ./src/**.c)
target_sources(lcurl PRIVATE ${lcurl_sources})
# setup platform-specific sources, compile and linker options
if(WIN32 AND NOT MinGW)
  # Important definitions for DLL and symbol export
  target_compile_definitions(lcurl PRIVATE
    LUA_BUILD_AS_DLL LUA_LIB
    _WINDLL _WIN32 _CRT_SECURE_NO_WARNINGS
    CURL_STATICLIB
    NGHTTP2_STATICLIB
    NGHTTP3_STATICLIB
    NGTCP2_STATICLIB
  )
  if(CMAKE_C_COMPILER_ID MATCHES "Intel")
    target_compile_options(lcurl PRIVATE
      -Wno-deprecated-declarations
      -Wno-parentheses
      -Wno-constant-conversion
      -Wno-return-type
    )
  endif()
  # We silently assume all libs are available with headers and static lib
  target_link_directories(lcurl PRIVATE
    ${LIBLUA_LIBDIR}
  )
  target_link_libraries(lcurl PRIVATE liblua libcurl ssl crypto nghttp2
    ngtcp2 ngtcp2_crypto_libressl nghttp3 zlibstatic zstd brotlidec
    brotlicommon ws2_32 wldap32 crypt32 advapi32 bcrypt normaliz
    Secur32 IPHLPAPI
  )
else()
  message(FATAL_ERROR "Not yet fully implemented.")
endif()
# Install
install(TARGETS lcurl RUNTIME DESTINATION ${INSTALL_TOP_CDIR})
install(
  DIRECTORY src/lua/ DESTINATION ${INSTALL_TOP_LDIR}
)

# ------------------------------------------------------------------------------
# Create docs with ldoc from CMAKE_INSTALL_PREFIX
set(LDOC_EXE "${CMAKE_INSTALL_PREFIX}/bin/ldoc.exe")
set(DOC_INST_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen-docs")
add_custom_target(docs
  COMMENT "Generate documentation ..."
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMAND ${LDOC_EXE} -c "doc/config.ld" . -d "${DOC_INST_DIR}"
)
add_dependencies(lcurl docs)

# ------------------------------------------------------------------------------
# Install 
install(
  DIRECTORY ${DOC_INST_DIR}/
  DESTINATION ${INSTALL_DOCDIR}/doc
  PATTERN "*~" EXCLUDE
)
install(
  DIRECTORY examples
  DESTINATION ${INSTALL_DOCDIR}
  PATTERN "*~" EXCLUDE
)
install(
  DIRECTORY spec
  DESTINATION ${INSTALL_DOCDIR}/test
  PATTERN "*~" EXCLUDE
)
# ==============================================================================
else()
cmake_minimum_required (VERSION 2.6)
project (lcurl)

file(GLOB lcurl_sources ./src/**.c)
SET(lcurl ${lcurl_sources})

ADD_LIBRARY (lcurl  ${lcurl})
TARGET_LINK_LIBRARIES (lcurl)
endif()
