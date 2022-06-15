# SDL
add_subdirectory(deps/SDL EXCLUDE_FROM_ALL)

# Specifically override this for packages that want to link with the dynamic
# system library instead of our static one
set(SDL2_INCLUDE_DIR "${PROJECT_SOURCE_DIR}/deps/SDL/include" CACHE STRING "" FORCE)
set(SDL2_LIBRARY SDL2-static CACHE STRING "" FORCE)

# SDL_mixer

set(BUILD_TESTING FALSE CACHE BOOL "Disble OGG tests" FORCE)
set(SUPPORT_OGG TRUE CACHE BOOL "Disable FLAC" FORCE)
set(SUPPORT_FLAC FALSE CACHE BOOL "Disable FLAC" FORCE)
set(SUPPORT_OPUS FALSE CACHE BOOL "Disable opus" FORCE)
set(SUPPORT_MP3_MPG123 FALSE CACHE BOOL "Disable MPG123" FORCE)
set(SUPPORT_MOD_MODPLUG FALSE CACHE BOOL "Disable modplug" FORCE)
set(SUPPORT_MID_TIMIDITY FALSE CACHE BOOL "Disble timidity" FORCE)
add_subdirectory(deps/SDL_mixer EXCLUDE_FROM_ALL)

# SDL_ttf

set(FT_DISABLE_ZLIB FALSE CACHE BOOL "Use system zlib" FORCE)
set(FT_REQUIRE_ZLIB TRUE CACHE BOOL "Use system zlib" FORCE)

set(BUILD_SAMPLES FALSE CACHE BOOL "Don't build samples" FORCE)
set(TTF_DISABLE_INSTALL TRUE CACHE BOOL "Disable install" FORCE)
add_subdirectory(deps/SDL_ttf EXCLUDE_FROM_ALL)

# SDL_gpu

set(DISABLE_GLES_1 TRUE CACHE BOOL "Disable GLES1" FORCE)
set(INSTALL_LIBRARY FALSE CACHE BOOL "Disable installing" FORCE)
set(BUILD_STATIC TRUE CACHE BOOL "Enable static" FORCE)
set(BUILD_SHARED FALSE CACHE BOOL "Disable shared" FORCE)
set(BUILD_DEMOS FALSE CACHE BOOL "Disable demos" FORCE)
add_subdirectory(deps/SDL_gpu EXCLUDE_FROM_ALL)
