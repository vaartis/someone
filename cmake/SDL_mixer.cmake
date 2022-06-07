include(ExternalProject)

# Create the directories for imported targets, or cmake will complain that they don't exist
set(SDL_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL/install")
file(MAKE_DIRECTORY
  "${SDL_INSTALL}/include/SDL2"
  "${SDL_INSTALL}/lib")

if (NOT WIN32)
   set(SDL2_DISABLED
   --disable-joystick --disable-haptic --disable-sensor
   --disable-power)
endif()

ExternalProject_Add(SDL
  #URL "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.14.zip"
  GIT_REPOSITORY "https://github.com/libsdl-org/SDL"
  GIT_TAG 61115ae
  # Keeps the project from rebuilding every time
  UPDATE_COMMAND ""

  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${SDL_INSTALL}
  ${SDL2_DISABLED} --disable-shared

  BUILD_COMMAND make
  INSTALL_COMMAND make install
  PREFIX "${PROJECT_BINARY_DIR}/deps/SDL")
add_library(SDL2::SDL2 STATIC IMPORTED)
set_target_properties(SDL2::SDL2
  PROPERTIES IMPORTED_LOCATION "${SDL_INSTALL}/lib/libSDL2.a")
target_include_directories(SDL2::SDL2 INTERFACE "${SDL_INSTALL}/include/SDL2")

add_library(SDL2::SDL2_main STATIC IMPORTED)
set_target_properties(SDL2::SDL2_main
  PROPERTIES IMPORTED_LOCATION "${SDL_INSTALL}/lib/libSDL2main.a")

if(WIN32)
  target_link_libraries(SDL2::SDL2 INTERFACE dinput8 dxguid dxerr8 user32 gdi32 winmm imm32 ole32 oleaut32 shell32 setupapi version uuid)
elseif(APPLE)
  target_link_libraries(SDL2::SDL2 INTERFACE "-framework CoreAudio" "-framework AudioToolbox" "-weak_framework CoreHaptics"
    "-weak_framework GameController" "-framework ForceFeedback" "-framework CoreVideo" "-framework Cocoa" "-framework Carbon"
    "-framework IOKit" "-weak_framework QuartzCore" "-weak_framework Metal"
    iconv)
endif()

add_dependencies(SDL2::SDL2 SDL)
add_dependencies(SDL2::SDL2_main SDL2::SDL2)

# SDL_mixer

set(SDL_MIXER_SRC "${PROJECT_BINARY_DIR}/deps/SDL_mixer/src/SDL_mixer")
set(SDL_MIXER_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL_mixer/install")

ExternalProject_Add(SDL_mixer
   URL "https://github.com/libsdl-org/SDL_mixer/archive/refs/tags/release-2.0.4.zip"
   BUILD_IN_SOURCE true

   CONFIGURE_COMMAND
   cmake -E env
   PKG_CONFIG_PATH=${SDL_INSTALL}/lib/pkgconfig

   sh -c "./configure \
   CC=${CMAKE_C_COMPILER} \
   CFLAGS=-I${SDL_MIXER_INSTALL}/include \
   LDFLAGS=-L${SDL_MIXER_INSTALL}/lib \
   --prefix=${SDL_MIXER_INSTALL} \
   --disable-music-cmd --disable-music-mod \
   --disable-music-midi --disable-music-flac --disable-music-mp3-mpg123 --disable-music-opus --disable-music-ogg-shared --disable-shared"

   BUILD_COMMAND make
   INSTALL_COMMAND make install
   PREFIX "${PROJECT_BINARY_DIR}/deps/SDL_mixer/")
ExternalProject_Add_Step(SDL_mixer build-ogg
  DEPENDEES patch
  WORKING_DIRECTORY <SOURCE_DIR>/external/libogg-1.3.2/
  COMMAND ./configure CC=${CMAKE_C_COMPILER} --disable-shared --enable-static --prefix=${SDL_MIXER_INSTALL}
  COMMAND make install)
ExternalProject_Add_Step(SDL_mixer build-vorbis
  WORKING_DIRECTORY <SOURCE_DIR>/external/libvorbis-1.3.5/
  COMMAND cmake -E env
  PKG_CONFIG_PATH=${SDL_MIXER_INSTALL}/lib/pkgconfig/

  sh -c "./configure \
  CC=${CMAKE_C_COMPILER} \
  --disable-shared --enable-static \
  --prefix=${SDL_MIXER_INSTALL}"
  COMMAND make install

  DEPENDEES build-ogg
  DEPENDERS configure)
add_dependencies(SDL_mixer SDL)

add_library(SDL2::SDL2_mixer STATIC IMPORTED)
set_target_properties(SDL2::SDL2_mixer
  PROPERTIES IMPORTED_LOCATION "${SDL_MIXER_INSTALL}/lib/libSDL2_mixer.a")
target_link_directories(SDL2::SDL2_mixer INTERFACE "${SDL_MIXER_INSTALL}/lib")
target_link_libraries(SDL2::SDL2_mixer INTERFACE
  "libvorbisfile.a" "libvorbisenc.a" "libvorbis.a" "libogg.a"
  SDL2::SDL2)
target_include_directories(SDL2::SDL2_mixer INTERFACE "${SDL_MIXER_SRC}")
add_dependencies(SDL2::SDL2_mixer SDL_mixer)

set(SDL_GFX_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL_gfx/install")
ExternalProject_Add(SDL_gfx
  URL "http://www.ferzkopp.net/Software/SDL2_gfx/SDL2_gfx-1.0.4.zip"

  CONFIGURE_COMMAND
  chmod +x <SOURCE_DIR>/configure
  COMMAND
  <SOURCE_DIR>/configure --prefix=${SDL_GFX_INSTALL} --disable-shared

  BUILD_COMMAND make
  INSTALL_COMMAND make install
  PREFIX "${PROJECT_BINARY_DIR}/deps/SDL_gfx")
add_library(SDL2::SDL2_gfx STATIC IMPORTED)
set_target_properties(SDL2::SDL2_gfx
  PROPERTIES IMPORTED_LOCATION "${SDL_GFX_INSTALL}/lib/libSDL2_gfx.a")
add_dependencies(SDL2::SDL2_gfx SDL_gfx)
target_include_directories(SDL2::SDL2_gfx INTERFACE "${PROJECT_BINARY_DIR}/deps/SDL_gfx/src/SDL_gfx")

set(SDL_IMAGE_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL_image/install")
ExternalProject_Add(SDL_image
  URL "https://github.com/libsdl-org/SDL_image/archive/refs/tags/release-2.0.5.zip"

  CONFIGURE_COMMAND
  chmod +x <SOURCE_DIR>/configure
  COMMAND
  <SOURCE_DIR>/configure --prefix=${SDL_IMAGE_INSTALL} --disable-shared

  BUILD_COMMAND make
  INSTALL_COMMAND make install
  PREFIX "${PROJECT_BINARY_DIR}/deps/SDL_image")
add_library(SDL2::SDL2_image STATIC IMPORTED)
set_target_properties(SDL2::SDL2_image
  PROPERTIES IMPORTED_LOCATION "${SDL_IMAGE_INSTALL}/lib/libSDL2_image.a")
add_dependencies(SDL2::SDL2_image SDL_image)
target_include_directories(SDL2::SDL2_image INTERFACE "${PROJECT_BINARY_DIR}/deps/SDL_image/src/SDL_image")

set(SDL_TTF_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL_ttf/install")
ExternalProject_Add(SDL_ttf
  URL "https://github.com/libsdl-org/SDL_ttf/archive/refs/tags/release-2.0.18.zip"

  CONFIGURE_COMMAND
  chmod +x <SOURCE_DIR>/configure
  COMMAND
  <SOURCE_DIR>/configure --prefix=${SDL_TTF_INSTALL} --disable-shared

  BUILD_COMMAND make
  INSTALL_COMMAND make install
  PREFIX "${PROJECT_BINARY_DIR}/deps/SDL_ttf")
add_library(SDL2::SDL2_ttf STATIC IMPORTED)
set_target_properties(SDL2::SDL2_ttf
  PROPERTIES IMPORTED_LOCATION "${SDL_TTF_INSTALL}/lib/libSDL2_ttf.a")
add_dependencies(SDL2::SDL2_ttf SDL_ttf)
target_include_directories(SDL2::SDL2_ttf INTERFACE "${PROJECT_BINARY_DIR}/deps/SDL_ttf/src/SDL_ttf")
