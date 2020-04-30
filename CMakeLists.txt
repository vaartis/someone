cmake_minimum_required(VERSION 3.16)

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

if(NOT WIN32)
  set(CMAKE_C_COMPILER clang)
  set(CMAKE_CXX_COMPILER clang++)
endif()

project(someone CXX)

set(CMAKE_CXX_STANDARD 17)

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
  add_executable(someone ${someone_src})
  target_link_options(someone PRIVATE -Wl,--export-dynamic)
  target_link_libraries(someone dl)
endif()

if(UNIX AND NOT APPLE)
  target_compile_definitions(someone PRIVATE -DSOMEONE_LIB_EXT="so")
endif()

target_include_directories(someone PRIVATE "src")

if (CMAKE_BUILD_TYPE STREQUAL "Release")
  set(BUILD_SHARED_LIBS FALSE)
  set(YAML_BUILD_SHARED_LIBS FALSE)
endif()

# === SFML

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sfml")
target_link_libraries(someone sfml-graphics sfml-audio)

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
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sol2")
target_link_libraries(someone sol2)

# ===

# === Building lua
# TODO: might need to be built as C++: https://sol2.readthedocs.io/en/latest/errors.html#destructors-and-safety
add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/lua/"
  COMMAND cmake -E copy_directory "${PROJECT_SOURCE_DIR}/deps/lua/" "${PROJECT_BINARY_DIR}/deps/lua/"
)
add_custom_target(copy-lua-before-build DEPENDS "${PROJECT_BINARY_DIR}/deps/lua/")

if(WIN32)
  set(LUA_EXECUTABLE "${PROJECT_BINARY_DIR}/deps/lua/lua.exe")
  set(LUA_LIBRARY "${PROJECT_BINARY_DIR}/deps/lua/lua53.dll")
else()
  set(LUA_EXECUTABLE "${PROJECT_BINARY_DIR}/deps/lua/lua")
  set(LUA_LIBRARY "${PROJECT_BINARY_DIR}/deps/lua/liblua.a")
endif()

if(WIN32)
  add_custom_command(
    OUTPUT ${LUA_LIBRARY} ${LUA_EXECUTABLE}
    DEPENDS copy-lua-before-build
    COMMAND gcc -O2 -DLUA_BUILD_AS_DLL=1 *.c -c && mv lua.o lua.e && gcc -shared -o lua53.dll *.o
    COMMAND gcc -L. -llua53 lua.e -o lua.exe
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/lua/"
  )
else()
  add_custom_command(
    OUTPUT ${LUA_LIBRARY} ${LUA_EXECUTABLE}
    DEPENDS copy-lua-before-build
    COMMAND make CC=${CMAKE_C_COMPILER} lua liblua.a
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/lua/"
  )
endif()

add_custom_target(lua DEPENDS "${LUA_LIBRARY}" "${LUA_EXECUTABLE}")

set(LUA_INCLUDE_DIR "${PROJECT_BINARY_DIR}/deps/lua")
set(SOMEONE_LUA_VERSION "5.3")

target_compile_definitions(someone PRIVATE SOMEONE_LUA_VERSION="${SOMEONE_LUA_VERSION}")
target_link_libraries(someone ${LUA_LIBRARY})
target_include_directories(someone PRIVATE ${LUA_INCLUDE_DIR})

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
    COMMAND cmd //c "install.bat /lua ${PROJECT_BINARY_DIR}/deps/lua/ /inc ${PROJECT_BINARY_DIR}/deps/lua/ /lib ${PROJECT_BINARY_DIR}/deps/lua/ /mw /selfcontained /p ${PROJECT_BINARY_DIR}/deps/luarocks/install /q /f /noadmin"
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
  )
else()
  set(LUAROCKS_BIN "${PROJECT_BINARY_DIR}/deps/luarocks/luarocks")
  add_custom_command(
    OUTPUT ${LUAROCKS_BIN}
    DEPENDS lua copy-luarocks-before-build
    COMMAND ./configure --with-lua-bin=${PROJECT_BINARY_DIR}/deps/lua/ --with-lua-include=${PROJECT_BINARY_DIR}/deps/lua/ --with-lua-lib=${PROJECT_BINARY_DIR}/deps/lua/ && PATH=${PROJECT_BINARY_DIR}/deps/lua:$ENV{PATH} make
    WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
  )
endif()
add_custom_target(luarocks DEPENDS ${LUAROCKS_BIN})

# ===

# === Copying lua sources

# Temporary (?) fix for lovetoys luarocks package being broken

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/lovetoys"
  DEPENDS luarocks lua
  COMMAND ${LUAROCKS_BIN} --tree=${PROJECT_BINARY_DIR}/resources/lua build
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/deps/lovetoys"
)
add_custom_target(lovetoys-build DEPENDS "${PROJECT_BINARY_DIR}/resources/lua/share/lua/${SOMEONE_LUA_VERSION}/lovetoys")

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/resources/lua/share/lua/walking.moon"
  DEPENDS lovetoys-build "${PROJECT_SOURCE_DIR}/src/lua/"
  COMMAND ${LUAROCKS_BIN} --tree=${PROJECT_BINARY_DIR}/resources/lua build
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua"
)
add_custom_target(luarocks-build DEPENDS "${PROJECT_BINARY_DIR}/resources/lua/share/lua/walking.moon")

# ===

add_dependencies(someone luarocks-build lovetoys-build)

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
