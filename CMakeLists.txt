cmake_minimum_required(VERSION 3.16)

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

set(vacances_src
  "src/fonts.cpp"
  "src/string_utils.cpp"
  "src/term.cpp"

  "src/main.cpp"
)

add_executable(vacances ${vacances_src})

target_link_libraries(vacances sfml-graphics sfml-audio fmt yaml-cpp spdlog nlohmann_json::nlohmann_json)
target_include_directories(vacances PRIVATE "src")

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
