cmake_minimum_required(VERSION 3.16)

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

if(NOT WIN32 AND NOT CMAKE_TOOLCHAIN_FILE MATCHES "Emscripten")
  # To allow overriding to clang of different name
  if(NOT CMAKE_C_COMPILER)
    set(CMAKE_C_COMPILER clang)
  endif()
  if(NOT CMAKE_CXX_COMPILER)
    set(CMAKE_CXX_COMPILER clang++)
  endif()
endif()

if(SOMEONE_TESTING)
  add_compile_options(-O0 -g -fprofile-instr-generate -fcoverage-mapping)
  add_link_options(-O0 -g -fprofile-instr-generate -fcoverage-mapping)
endif()

project(someone CXX C)

if(EMSCRIPTEN)
  add_link_options("-sLLD_REPORT_UNDEFINED" "-sFULL_ES3"
    "-sFORCE_FILESYSTEM" "-sINCLUDE_FULL_LIBRARY"
    "-sALLOW_MEMORY_GROWTH" "-lidbfs.js")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS FALSE)

set(someone_src
  "src/fonts.cpp"
  "src/string_utils.cpp"

  "src/usertypes/imgui.cpp"
  "src/usertypes/sfml.cpp"
  "src/usertypes.cpp"

  "src/story_parser.cpp"
  "src/toml.cpp"

  "src/sound.cpp")

set(someone_main
  "src/main.cpp")

add_library(someone_lib STATIC ${someone_src})
set_target_properties(someone_lib PROPERTIES OUTPUT_NAME "someone")

if(WIN32)
  add_executable(someone WIN32 ${someone_main})

  target_compile_definitions(someone_lib PUBLIC SOMEONE_LIB_EXT="dll")
  target_link_options(someone_lib PUBLIC -Wl,--export-all-symbols)
else()
  if(APPLE)
    add_executable(someone MACOSX_BUNDLE ${someone_main})

    # Silence OpenGL deprecation warnings on MacOS
    target_compile_definitions(someone PUBLIC GL_SILENCE_DEPRECATION)

    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}")

    install(CODE "
    include(BundleUtilities)
    fixup_bundle(\"${CMAKE_BINARY_DIR}/someone.app\" \"\" \"\")
    " COMPONENT Runtime)
    install(DIRECTORY "${CMAKE_BINARY_DIR}/resources" DESTINATION "${CMAKE_INSTALL_PREFIX}/someone.app/Contents/MacOS")
  else()
    add_executable(someone ${someone_main})
  endif()

  target_link_libraries(someone_lib dl)
  target_compile_definitions(someone_lib PUBLIC SOMEONE_LIB_EXT="so")

  if(APPLE)
    target_link_options(someone_lib PUBLIC -Wl,-export_dynamic)
    target_compile_definitions(someone_lib PUBLIC SOMEONE_APPLE)
  else()
    target_link_options(someone_lib PUBLIC -Wl,-E)
  endif()
  if (EMSCRIPTEN)
    target_compile_definitions(someone_lib PUBLIC SOMEONE_EMSCRIPTEN)
  endif()
endif()
target_include_directories(someone_lib PUBLIC "${CMAKE_SOURCE_DIR}/src/web_stubs/")

target_link_libraries(someone someone_lib)

target_include_directories(someone_lib PUBLIC "src")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Disabled shared libraries everywhere" FORCE)
set(YAML_BUILD_SHARED_LIBS OFF CACHE BOOL "Disable shared libraries")

if(NOT SOMEONE_TESTING)
  file(RELATIVE_PATH SOMEONE_EDITOR_BASE_PATH "${CMAKE_BINARY_DIR}" "${CMAKE_SOURCE_DIR}")
  target_compile_definitions(someone_lib PUBLIC SOMEONE_EDITOR_BASE_PATH="${SOMEONE_EDITOR_BASE_PATH}")
endif()

# SDL / SDL_mixer

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(SDL)

target_link_libraries(someone_lib SDL2-static)
target_link_libraries(someone_lib SDL2::mixer)
target_link_libraries(someone_lib SDL2_ttf)
target_link_libraries(someone_lib SDL_gpu)

if(EMSCRIPTEN)
  target_compile_options(someone_lib PUBLIC "-sUSE_ZLIB=1")
  target_link_options(someone_lib PUBLIC "-sUSE_ZLIB=1")
else()
  find_package(ZLIB REQUIRED)
  target_link_libraries(someone_lib ZLIB::ZLIB)
endif()

if(WIN32 OR APPLE)
  target_link_libraries(someone_lib SDL2main)
endif()

target_include_directories(someone_lib PUBLIC "${PROJECT_SOURCE_DIR}/deps/SDL_gpu/include/")

add_library(imgui_lib STATIC
  "${PROJECT_SOURCE_DIR}/deps/imgui/imgui.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/imgui.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/imgui_draw.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/imgui_tables.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/imgui_widgets.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/misc/cpp/imgui_stdlib.cpp"

  "${PROJECT_SOURCE_DIR}/deps/imgui/backends/imgui_impl_sdl.cpp"
  "${PROJECT_SOURCE_DIR}/deps/imgui/backends/imgui_impl_opengl3.cpp")
target_include_directories(imgui_lib PUBLIC "${PROJECT_SOURCE_DIR}/deps/imgui")
target_link_libraries(imgui_lib SDL2-static)
if(EMSCRIPTEN)
  target_compile_definitions(imgui_lib PUBLIC IMGUI_IMPL_OPENGL_ES3)
endif()

target_link_libraries(someone_lib imgui_lib)

if(NOT EMSCRIPTEN)
  if(APPLE OR WIN32)
    find_package(OpenGL REQUIRED OpenGL)
  else()
    find_package(OpenGL REQUIRED OpenGL GLX)

    target_link_libraries(someone_lib OpenGL::GLX)
  endif()
  target_link_libraries(someone_lib OpenGL::GL)
endif()

# === fmt

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/fmt")
target_link_libraries(someone_lib fmt)

# ===

# === yaml-cpp

set(YAML_CPP_BUILD_CONTRIB FALSE CACHE BOOL "")
set(YAML_CPP_BUILD_TOOLS FALSE CACHE BOOL "")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/yaml-cpp")
target_link_libraries(someone_lib yaml-cpp)

# === yaml-cpp

# === tomlplusplus

target_include_directories(someone_lib PUBLIC "${PROJECT_SOURCE_DIR}/deps/tomlplusplus/include/")

# ===

# === spdlog

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/spdlog")
target_link_libraries(someone_lib spdlog)

# ===

# === args

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/args" EXCLUDE_FROM_ALL)
target_link_libraries(someone_lib args)

# ===

# === sol2

target_compile_definitions(someone_lib PUBLIC SOL_ALL_SAFETIES_ON=1)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sol2" EXCLUDE_FROM_ALL)
target_link_libraries(someone_lib sol2)

# ===

# === Building lua
# TODO: might need to be built as C++: https://sol2.readthedocs.io/en/latest/errors.html#destructors-and-safety

include(ExternalProject)

set(LUA_SRC "${PROJECT_BINARY_DIR}/deps/lua/src/lua/src/")
if(WIN32)
  set(LUA_PLATFORM mingw)
elseif(APPLE)
  set(LUA_PLATFORM macosx)
elseif(EMSCRIPTEN)
  set(LUA_PLATFORM linux CC=clang)
  set(LUA_PLATFORM_ADDITIONAL
    COMMAND ${CMAKE_COMMAND} -E copy ${LUA_SRC}/lua ${LUA_SRC}/_lua
    COMMAND make clean
    COMMAND make generic CC=${CMAKE_C_COMPILER} CFLAGS=-DLUA_USE_POSIX
    COMMAND ${CMAKE_COMMAND} -E copy ${LUA_SRC}/_lua ${LUA_SRC}/lua)
else()
  set(LUA_PLATFORM linux)
endif()

ExternalProject_Add(lua
  URL "https://www.lua.org/ftp/lua-5.3.5.tar.gz"
   CONFIGURE_COMMAND ""
   BUILD_COMMAND
   make ${LUA_PLATFORM}
   ${LUA_PLATFORM_ADDITIONAL}
   BUILD_IN_SOURCE true
   INSTALL_COMMAND ""
   PREFIX "${PROJECT_BINARY_DIR}/deps/lua/"
)

if(WIN32)
  set(LUA_EXECUTABLE "${LUA_SRC}/lua.exe")
  set(LUA_LIBRARY "${LUA_SRC}/lua53.dll")
else()
  set(LUA_EXECUTABLE "${LUA_SRC}/lua")
  set(LUA_LIBRARY "${LUA_SRC}/liblua.a")
endif()

set(SOMEONE_LUA_VERSION "5.3")
target_compile_definitions(someone_lib PUBLIC SOMEONE_LUA_VERSION="${SOMEONE_LUA_VERSION}")
target_link_libraries(someone_lib ${LUA_LIBRARY})
target_include_directories(someone_lib PUBLIC ${LUA_SRC})

# ===

# === Building luarocks

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/luarocks/"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${PROJECT_SOURCE_DIR}/deps/luarocks/" "${PROJECT_BINARY_DIR}/deps/luarocks/"
)
add_custom_target(copy-luarocks-before-build DEPENDS "${PROJECT_BINARY_DIR}/deps/luarocks/")

if(WIN32)
  set(LUAROCKS_BIN "${PROJECT_BINARY_DIR}/deps/luarocks/install/luarocks.bat")
  add_custom_command(
    OUTPUT ${LUAROCKS_BIN}
    DEPENDS lua copy-luarocks-before-build
    COMMAND cmd //c "install.bat /lua ${LUA_SRC} /inc ${LUA_SRC} /lib ${LUA_SRC} /mw /selfcontained /p ${PROJECT_BINARY_DIR}/deps/luarocks/install /q /f /noadmin"
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
  )
else()
  set(LUAROCKS_BIN "${PROJECT_BINARY_DIR}/deps/luarocks/luarocks")
  add_custom_command(
    OUTPUT ${LUAROCKS_BIN}
    DEPENDS lua copy-luarocks-before-build
    COMMAND ./configure --with-lua-bin=${LUA_SRC} --with-lua-include=${LUA_SRC} --with-lua-lib=${LUA_SRC} && PATH=${LUA_SRC}:$ENV{PATH} make
    COMMAND ${LUAROCKS_BIN} config variables.CC ${CMAKE_C_COMPILER}
    COMMAND ${LUAROCKS_BIN} config variables.LD ${CMAKE_C_COMPILER}
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
  )
endif()
add_custom_target(luarocks DEPENDS ${LUAROCKS_BIN})

# ===

# === Copying lua sources

# Temporary (?) fix for lovetoys luarocks package being broken

set(LUAROCKS_COMMAND ${LUAROCKS_BIN} --tree=${PROJECT_BINARY_DIR}/resources/lua)


# A function with a variable amount of arguments to sequentially bulild rocks from rockspecs
# (as luarocks doesn't seem to work when trying to build multiple rocks in parallel), it
# makes each subsequent rock depend on the previous one and exposes the last one as LAST_ROCK_TARGET
# so that the next target could depend on it and build them all at once
# Each argument is a list of either "name;rockspec;output" to build a rockspec, or "name;output" to
# install a package
function(install_rocks)
  set(current_arg_n 0)
  # Loop through the arguments
  while(${current_arg_n} LESS ${ARGC})

    list(LENGTH ARGV${current_arg_n} arg_length)
    # 2 args = install package, 3 args = build rockspec
    if(${arg_length} EQUAL 3)
      # Get the values from the lists into variables
      list(GET ARGV${current_arg_n} 0 name)
      list(GET ARGV${current_arg_n} 1 rockspec)
      list(GET ARGV${current_arg_n} 2 output)
    elseif(${ARGC} EQUAL 2)
      list(GET ARGV${current_arg_n} 0 name)
      unset(rockspec)
      list(GET ARGV${current_arg_n} 1 output)
    endif()

    set(full_output_path "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/${output}")

    # If rockspec is defined, build it, otherwise install the package by name
    if (rockspec)
      add_custom_command(
        OUTPUT ${full_output_path}
        DEPENDS luarocks "${PROJECT_SOURCE_DIR}/src/lua/${rockspec}"
        COMMAND CC=${CMAKE_C_COMPILER} ${LUAROCKS_COMMAND} build ${rockspec}
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua")
    else()
      add_custom_command(
        OUTPUT ${full_output_path}
        DEPENDS luarocks
        COMMAND CC=${CMAKE_C_COMPILER} ${LUAROCKS_COMMAND} install ${name})
    endif()

    add_custom_target(${name}-rockspec-build DEPENDS ${full_output_path})

    # If there was a target before, add a dependency on that target
    if(DEFINED last_target)
      add_dependencies(${name}-rockspec-build ${last_target})
    endif()
    set(last_target ${name}-rockspec-build)

    math(EXPR current_arg_n "${current_arg_n} + 1")
  endwhile()

  set(LAST_ROCK_TARGET ${last_target} PARENT_SCOPE)
endfunction()

install_rocks(
  "lume;lume-2.3.0-0.rockspec;lume.lua"
  "bump;bump-3.1.7-1.rockspec;bump.lua"
  "lovetoys;lovetoys-0.4.0-2.rockspec;lovetoys"
  "middleclass;middleclass-4.1.2-0.rockspec;middleclass.lua"
)

file(GLOB_RECURSE LUA_SRC_FILES
  LIST_DIRECTORIES FALSE
  RELATIVE "${PROJECT_SOURCE_DIR}"
  CONFIGURE_DEPENDS
  "${PROJECT_SOURCE_DIR}/src/lua/*")
add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/walking.lua"
  DEPENDS ${LAST_ROCK_TARGET} ${LUA_SRC_FILES}
  COMMAND ${LUAROCKS_COMMAND} make someone-0.1-0.rockspec
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua"
)
add_custom_target(luarocks-build DEPENDS "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/walking.lua")

# ===

add_dependencies(someone_lib luarocks-build)

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
add_dependencies(someone copy-resources)

if(EMSCRIPTEN)
  set(EMSCRIPTEN_OUTPUTS
    "${PROJECT_BINARY_DIR}/html5/index.html"
    "${PROJECT_BINARY_DIR}/someone.js" "${PROJECT_BINARY_DIR}/someone.wasm"
    "${PROJECT_BINARY_DIR}/resources.data" "${PROJECT_BINARY_DIR}/resources.js")
  add_custom_target(copy-emscripten-resources ALL
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_SOURCE_DIR}/src/web_stubs/emscripten_template.html" "${PROJECT_BINARY_DIR}/html5/index.html"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_BINARY_DIR}/someone.js" "${PROJECT_BINARY_DIR}/someone.wasm" "${PROJECT_BINARY_DIR}/html5/"
    COMMAND "${EMSCRIPTEN_ROOT_PATH}/tools/file_packager" html5/resources.data --preload resources --js-output=html5/resources.js &> /dev/null)

  add_dependencies(copy-emscripten-resources someone)
endif()

# Testing

if (SOMEONE_TESTING)
  target_compile_definitions(someone PUBLIC SOMEONE_TESTING)

  # Lua tests

  file(GLOB_RECURSE LUA_TEST_FILES
    LIST_DIRECTORIES FALSE
    RELATIVE "${PROJECT_SOURCE_DIR}/test/lua/"
    CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/test/lua/*.moon")
  # Add the output test dir to the paths
  list(TRANSFORM LUA_TEST_FILES
    PREPEND "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/test/"
    OUTPUT_VARIABLE OUTPUT_LUA_TEST_FILES)
  # Add the input test dir to the paths again
  list(TRANSFORM LUA_TEST_FILES
    PREPEND "${PROJECT_SOURCE_DIR}/test/lua/"
    OUTPUT_VARIABLE INPUT_LUA_TEST_FILES)

  set(LUA_TEST_ROCKSPEC "someone-test-0.1-0.rockspec")

  add_custom_command(
    OUTPUT ${OUTPUT_LUA_TEST_FILES}
    DEPENDS ${LAST_ROCK_TARGET} ${INPUT_LUA_TEST_FILES} "${PROJECT_SOURCE_DIR}/test/lua/${LUA_TEST_ROCKSPEC}"
    COMMAND ${LUAROCKS_COMMAND} make ${LUA_TEST_ROCKSPEC}
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/test/lua")
  add_custom_target(lua-test-build DEPENDS ${OUTPUT_LUA_TEST_FILES})

  add_custom_command(
    OUTPUT "${PROJECT_BINARY_DIR}/.luacov"
    DEPENDS "${PROJECT_SOURCE_DIR}/test/lua/.luacov"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_SOURCE_DIR}/test/lua/.luacov" "${PROJECT_BINARY_DIR}/.luacov")
  add_custom_target(lua-test-copy-luacov DEPENDS "${PROJECT_BINARY_DIR}/.luacov")

  add_custom_target(lua-test
    DEPENDS someone lua-test-build lua-test-copy-luacov
    COMMAND ./someone)

  # C++ tests

  add_subdirectory("${PROJECT_SOURCE_DIR}/deps/catch2" EXCLUDE_FROM_ALL)
  add_executable(someone_tests
    test/cpp/main.cpp
    test/cpp/story_parser_test.cpp
    test/cpp/toml_test.cpp)

  target_link_libraries(someone_tests Catch2::Catch2 someone_lib)


  # Copy test resources
  add_custom_target(copy-test-resources ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/test/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources/
    )
  add_dependencies(someone_tests copy-test-resources)

  add_custom_target(cpp-test
    DEPENDS someone_tests
    COMMAND ./someone_tests)
endif()
