include(FetchContent)

if (SOMEONE_NETWORKING_STEAM)
  set(steamworkssdk_SOURCE_DIR "${PROJECT_SOURCE_DIR}/deps/steamworks")

  target_include_directories(someone_lib PUBLIC "${steamworkssdk_SOURCE_DIR}/public/")
  add_compile_definitions(someone_lib PUBLIC SOMEONE_NETWORKING_STEAM)

  # TODO: non-linux
  if(WIN32)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
      set(steam_lib "${steamworkssdk_SOURCE_DIR}/redistributable_bin/win64/steam_api64.lib")
      set(steam_dynamic "${steamworkssdk_SOURCE_DIR}/redistributable_bin/win64/steam_api64.dll")
      # 64 bits
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
      set(steam_lib "${steamworkssdk_SOURCE_DIR}/redistributable_bin/steam_api.lib")
      set(steam_dynamic "${steamworkssdk_SOURCE_DIR}/redistributable_bin/steam_api.dll")
      # 32 bits
    endif()
  elseif(APPLE)
    # TODO
    message(FATAL_ERROR "No MacOS support yet")
  else()
    set(steam_lib "${steamworkssdk_SOURCE_DIR}/redistributable_bin/linux64/libsteam_api.so")
    set(steam_dynamic "${steamworkssdk_SOURCE_DIR}/redistributable_bin/linux64/libsteam_api.so")

    target_link_options(someone_lib PUBLIC "-Wl,-rpath,.")
  endif()
  configure_file("${steam_dynamic}" "${CMAKE_BINARY_DIR}" COPYONLY)
  target_link_libraries(someone_lib "${steam_lib}")

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
