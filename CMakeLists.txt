cmake_minimum_required(VERSION 3.16)

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

set(CMAKE_CXX_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)

project(vacances CXX)

set(CMAKE_CXX_STANDARD 17)

set(SFML_STATIC_LIBRARIES TRUE)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sfml")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/fmt")

set(YAML_CPP_BUILD_CONTRIB FALSE)
set(YAML_CPP_BUILD_TOOLS FALSE)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/yaml-cpp")

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/spdlog")

set(JSON_BuildTests OFF CACHE INTERNAL "")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/nlohmann-json")

# === Building lua ===
# TODO: might need to be built as C++: https://sol2.readthedocs.io/en/latest/errors.html#destructors-and-safety
add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/lua/"
  COMMAND cmake -E copy_directory "${PROJECT_SOURCE_DIR}/deps/lua/" "${PROJECT_BINARY_DIR}/deps/lua/"
)
add_custom_target(copy-lua-before-build DEPENDS "${PROJECT_BINARY_DIR}/deps/lua/")

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/lua/liblua.a" "${PROJECT_BINARY_DIR}/deps/lua/lua"
  DEPENDS copy-lua-before-build
  COMMAND make CC=${CMAKE_C_COMPILER} lua liblua.a
  WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/lua/"
)
add_custom_target(lua DEPENDS "${PROJECT_BINARY_DIR}/deps/lua/liblua.a" "${PROJECT_BINARY_DIR}/deps/lua/lua")
set(LUA_LIBRARIES "${PROJECT_BINARY_DIR}/deps/lua/liblua.a" dl)
set(LUA_INCLUDE_DIR "${PROJECT_BINARY_DIR}/deps/lua")
add_definitions(-DVACANCES_LUA_VERSION="5.3")

# ===

# === Building luarocks

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/luarocks/"
  COMMAND cmake -E copy_directory "${PROJECT_SOURCE_DIR}/deps/luarocks/" "${PROJECT_BINARY_DIR}/deps/luarocks/"
)
add_custom_target(copy-luarocks-before-build DEPENDS "${PROJECT_BINARY_DIR}/deps/luarocks/")

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/deps/luarocks/luarocks"
  DEPENDS lua copy-luarocks-before-build
  COMMAND ./configure --with-lua-bin=${PROJECT_BINARY_DIR}/deps/lua --with-lua-include=${PROJECT_BINARY_DIR}/deps/lua && make
  WORKING_DIRECTORY "${PROJECT_BINARY_DIR}/deps/luarocks/"
)
add_custom_target(luarocks DEPENDS "${PROJECT_BINARY_DIR}/deps/luarocks/luarocks")

# ===

# === Copying lua sources

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/resources/lua/"
  DEPENDS luarocks lua "${PROJECT_SOURCE_DIR}/src/lua"
  COMMAND ${PROJECT_BINARY_DIR}/deps/luarocks/luarocks --tree=${PROJECT_BINARY_DIR}/resources/lua build
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/src/lua"
)
add_custom_target(luarocks-build DEPENDS "${PROJECT_BINARY_DIR}/resources/lua/")

# ===

add_definitions("-DSOL_ALL_SAFETIES_ON=1")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sol2")

set(vacances_src
  "src/fonts.cpp"
  "src/string_utils.cpp"
  "src/main.cpp"
)

add_executable(vacances ${vacances_src})

add_dependencies(vacances luarocks-build)
target_link_libraries(vacances sfml-graphics sfml-audio fmt yaml-cpp spdlog nlohmann_json::nlohmann_json sol2 ${LUA_LIBRARIES})
target_include_directories(vacances PRIVATE "src" ${LUA_INCLUDE_DIR})

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
