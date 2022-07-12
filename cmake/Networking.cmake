include(FetchContent)

set(BUILD_SHARED_LIB FALSE CACHE BOOL "" FORCE)
set(Protobuf_USE_STATIC_LIBS TRUE CACHE BOOL "Link with protobuf statically" FORCE)

FetchContent_Declare(
  GameNetworkingSocketsLib
  URL "https://github.com/ValveSoftware/GameNetworkingSockets/archive/refs/tags/v1.4.1.zip"
)
FetchContent_MakeAvailable(GameNetworkingSocketsLib)
target_link_libraries(someone_lib GameNetworkingSockets::static)

install_rocks(
  "lua-protobuf;protoc.lua"
)
add_dependencies(luarocks-build ${LAST_ROCK_TARGET})

add_compile_definitions(someone_lib PUBLIC SOMEONE_NETWORKING)
target_sources(someone_lib PRIVATE "src/usertypes/networking.cpp")
