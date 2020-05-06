cmake_minimum_required(VERSION 3.16)

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

if(NOT WIN32)
  set(CMAKE_C_COMPILER clang)
  set(CMAKE_CXX_COMPILER clang++)
endif()

project(someone CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS FALSE)

set(someone_src
  "src/fonts.cpp"
  "src/string_utils.cpp"
  "src/usertypes.cpp"
  "src/story_parser.cpp"
  "src/main.cpp"
)

if(WIN32)
  add_executable(someone WIN32 ${someone_src})

  target_compile_definitions(someone PRIVATE -DSOMEONE_LIB_EXT="dll")
  target_link_options(someone PRIVATE -Wl,--export-all-symbols)
else()
  if(APPLE)
    add_executable(someone MACOSX_BUNDLE ${someone_src})

    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}")

    install(CODE "
    include(BundleUtilities)
    fixup_bundle(\"${CMAKE_BINARY_DIR}/someone.app\" \"\" \"\")
    " COMPONENT Runtime)
    install(DIRECTORY "${CMAKE_BINARY_DIR}/resources" DESTINATION "${CMAKE_INSTALL_PREFIX}/someone.app/Contents/MacOS")
  else()
    add_executable(someone ${someone_src})
  endif()

  target_link_libraries(someone dl)
  target_compile_definitions(someone PRIVATE -DSOMEONE_LIB_EXT="so")

  if(APPLE)
    target_link_options(someone PRIVATE -Wl,-export_dynamic)
  else()
    target_link_options(someone PRIVATE -Wl,-E)
  endif()
endif()

target_include_directories(someone PRIVATE "src")

if (CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
  set(BUILD_SHARED_LIBS FALSE)
  set(YAML_BUILD_SHARED_LIBS FALSE)
endif()

# === SFML

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sfml" EXCLUDE_FROM_ALL)
target_link_libraries(someone sfml-graphics sfml-audio)
set_target_properties(sfml-graphics sfml-audio PROPERTIES CXX_STANDARD 14)

# ===

# === IMGUI SFML

set(IMGUI_SFML_FIND_SFML FALSE)
set(IMGUI_DIR "${PROJECT_SOURCE_DIR}/deps/imgui")
set(SFML_DIR "${PROJECT_SOURCE_DIR}/deps/sfml")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/imgui-sfml" EXCLUDE_FROM_ALL)
target_link_libraries(someone ImGui-SFML::ImGui-SFML)

# ===

# === fmt

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/fmt")
target_link_libraries(someone fmt)

# ===

# === yaml-cpp

set(YAML_CPP_BUILD_CONTRIB FALSE)
set(YAML_CPP_BUILD_TOOLS FALSE)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/yaml-cpp")
target_link_libraries(someone yaml-cpp)

# === yaml-cpp

# === spdlog

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/spdlog")
target_link_libraries(someone spdlog)

# ===

# === sol2

target_compile_definitions(someone PRIVATE SOL_ALL_SAFETIES_ON=1)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sol2" EXCLUDE_FROM_ALL)
target_link_libraries(someone sol2)

# ===

# === Building lua
# TODO: might need to be built as C++: https://sol2.readthedocs.io/en/latest/errors.html#destructors-and-safety
include(ExternalProject)

if(WIN32)
  set(LUA_PLATFORM mingw)
elseif(APPLE)
  set(LUA_PLATFORM macosx)
else()
  set(LUA_PLATFORM linux)
endif()

ExternalProject_Add(lua
   URL "https://www.lua.org/ftp/lua-5.3.5.tar.gz"
   CONFIGURE_COMMAND ""
   BUILD_COMMAND make ${LUA_PLATFORM}
   BUILD_ALWAYS true
   BUILD_IN_SOURCE true
   INSTALL_COMMAND ""
   PREFIX "${PROJECT_BINARY_DIR}/deps/lua/"
)
ExternalProject_Get_property(lua SOURCE_DIR)

set(LUA_SRC "${PROJECT_BINARY_DIR}/deps/lua/src/lua/src/")

if(WIN32)
  set(LUA_EXECUTABLE "${LUA_SRC}/lua.exe")
  set(LUA_LIBRARY "${LUA_SRC}/lua53.dll")
else()
  set(LUA_EXECUTABLE "${LUA_SRC}/lua")
  set(LUA_LIBRARY "${LUA_SRC}/liblua.a")
endif()

set(SOMEONE_LUA_VERSION "5.3")
target_compile_definitions(someone PRIVATE SOMEONE_LUA_VERSION="${SOMEONE_LUA_VERSION}")
target_link_libraries(someone ${LUA_LIBRARY})
target_include_directories(someone PRIVATE ${LUA_SRC})

# ===

# === Building luarocks

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/luarocks/"
  COMMAND cmake -E copy_directory "${PROJECT_SOURCE_DIR}/deps/luarocks/" "${PROJECT_BINARY_DIR}/deps/luarocks/"
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
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
  )
endif()
add_custom_target(luarocks DEPENDS ${LUAROCKS_BIN})

# ===

# === Copying lua sources

# Temporary (?) fix for lovetoys luarocks package being broken

set(LUAROCKS_COMMAND ${LUAROCKS_BIN} --tree=${PROJECT_BINARY_DIR}/resources/lua)

function(build_rockspec name rockspec output)
  set(full_output_path "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/${output}")
  add_custom_command(
    OUTPUT ${full_output_path}
    DEPENDS luarocks "${PROJECT_SOURCE_DIR}/src/lua/${rockspec}"
    COMMAND ${LUAROCKS_COMMAND} build ${rockspec}
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua"
  )
  add_custom_target(${name}-rockspec-build DEPENDS ${full_output_path})
endfunction()

build_rockspec(lovetoys lovetoys-0.4.0-2.rockspec lovetoys)
build_rockspec(toml lua-toml-2.1-0.rockspec toml.lua)

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/walking.moon"
  DEPENDS lovetoys-rockspec-build toml-rockspec-build "${PROJECT_SOURCE_DIR}/src/lua/**"
  COMMAND ${LUAROCKS_COMMAND} make someone-0.1-0.rockspec
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua"
)
add_custom_target(luarocks-build DEPENDS "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/walking.moon")

# ===

add_dependencies(someone luarocks-build)

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
