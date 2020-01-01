cmake_minimum_required(VERSION 3.16)

set(CMAKE_CXX_COMPILER clang++)

project(vacances CXX)

set(CMAKE_CXX_STANDARD 17)

set(SFML_STATIC_LIBRARIES TRUE)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/sfml" "${PROJECT_BINARY_DIR}/sfml")
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/fmt" "${PROJECT_BINARY_DIR}/fmt")

set(YAML_CPP_BUILD_CONTRIB FALSE)
set(YAML_CPP_BUILD_TOOLS FALSE)
add_subdirectory("${PROJECT_SOURCE_DIR}/deps/yaml-cpp" "${PROJECT_BINARY_DIR}/yaml-cpp")

add_subdirectory("${PROJECT_SOURCE_DIR}/deps/spdlog")

set(vacances_src
  "src/fonts.cpp"
  "src/string_utils.cpp"
  "src/term.cpp"

  "src/main.cpp"
)

add_executable(vacances ${vacances_src})

target_link_libraries(vacances sfml-graphics fmt yaml-cpp spdlog)

# Copy all resources
add_custom_target(copy-resources ALL
  COMMAND ${CMAKE_COMMAND} -E copy_directory
  ${CMAKE_SOURCE_DIR}/resources/ ${CMAKE_CURRENT_BINARY_DIR}/resources
)
