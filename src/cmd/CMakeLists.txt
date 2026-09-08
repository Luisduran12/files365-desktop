# SPDX-FileCopyrightText: 2017 Nextcloud GmbH and Nextcloud contributors
# SPDX-FileCopyrightText: 2014 ownCloud GmbH
# SPDX-License-Identifier: GPL-2.0-or-later
project(cmd)
set(CMAKE_AUTOMOC TRUE)

add_library(cmdCore STATIC
    simplesslerrorhandler.h
    simplesslerrorhandler.cpp
    netrcparser.h
    netrcparser.cpp)

target_link_libraries(cmdCore
  PUBLIC
  Nextcloud::sync
  Qt::Core
  Qt::Network
  )

if(UNIX AND NOT APPLE)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIE")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIE")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pie")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -L/usr/local/lib")
endif()

if(NOT BUILD_LIBRARIES_ONLY)
  add_executable(nextcloudcmd
      cmd.h
      cmd.cpp)
  ecm_mark_nongui_executable(nextcloudcmd)
  set_target_properties(nextcloudcmd PROPERTIES RUNTIME_OUTPUT_NAME "${APPLICATION_EXECUTABLE}cmd")

  target_link_libraries(nextcloudcmd cmdCore nextcloudCore)

  if(BUILD_OWNCLOUD_OSX_BUNDLE)
    # This binary lands in Contents/MacOS and links the two private dylibs as
    # @rpath/lib${APPLICATION_EXECUTABLE}sync.0.dylib and
    # @rpath/lib${APPLICATION_EXECUTABLE}_csync.0.dylib, which src/gui's POST_BUILD
    # deploys into Contents/Frameworks -- so it needs that RPATH baked in.  Without
    # BUILD_WITH_INSTALL_RPATH the only RPATH it gets is CMake's automatic build-tree
    # one (an absolute path into this checkout's build/bin), which resolves on the
    # build machine and nowhere else, so the shipped binary aborts at launch.
    set_target_properties(nextcloudcmd PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY "${BIN_OUTPUT_DIRECTORY}/${OWNCLOUD_OSX_BUNDLE}/Contents/MacOS"
      BUILD_WITH_INSTALL_RPATH TRUE
      INSTALL_RPATH "@loader_path/../Frameworks")
  else()
    set_target_properties(nextcloudcmd PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${BIN_OUTPUT_DIRECTORY})

    install(TARGETS nextcloudcmd
	  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
	  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
	  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
    if (WIN32)
      install(FILES $<TARGET_PDB_FILE:nextcloudcmd> DESTINATION bin OPTIONAL)
    endif()
  endif()
endif()
