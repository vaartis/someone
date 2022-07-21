include(FetchContent)

if (SOMEONE_NETWORKING_STEAM)
  FetchContent_Declare(
    SteamworksSDK
    URL "https://partner.steamgames.com/downloads/steamworks_sdk.zip"
  )
  FetchContent_MakeAvailable(SteamworksSDK)

  target_include_directories(someone_lib PUBLIC "${steamworkssdk_SOURCE_DIR}/public/")
  add_compile_definitions(someone_lib PUBLIC SOMEONE_NETWORKING_STEAM)

  # TODO: non-linux
  configure_file("${steamworkssdk_SOURCE_DIR}/redistributable_bin/linux64/libsteam_api.so" "${CMAKE_BINARY_DIR}" COPYONLY)
  target_link_libraries(someone_lib "${CMAKE_BINARY_DIR}/libsteam_api.so")
  target_link_options(someone_lib PUBLIC "-Wl,-rpath,.")
  file(WRITE "${CMAKE_BINARY_DIR}/steam_appid.txt" "480")
else()
  set(BUILD_SHARED_LIB FALSE CACHE BOOL "" FORCE)
  set(Protobuf_USE_STATIC_LIBS TRUE CACHE BOOL "Link with protobuf statically" FORCE)

  FetchContent_Declare(
    GameNetworkingSocketsLib
    URL "https://github.com/ValveSoftware/GameNetworkingSockets/archive/refs/tags/v1.4.1.zip"
  )
  FetchContent_MakeAvailable(GameNetworkingSocketsLib)
  target_link_libraries(someone_lib GameNetworkingSockets::static)
endif()

install_rocks(
  "lua-protobuf;protoc.lua"
)
add_dependencies(luarocks-build ${LAST_ROCK_TARGET})

add_compile_definitions(someone_lib PUBLIC SOMEONE_NETWORKING)
target_sources(someone_lib PRIVATE "src/usertypes/networking.cpp")
