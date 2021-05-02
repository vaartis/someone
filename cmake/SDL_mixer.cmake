include(ExternalProject)

# Create the directories for imported targets, or cmake will complain that they don't exist
set(SDL_INSTALL "${PROJECT_BINARY_DIR}/deps/SDL/install")
file(MAKE_DIRECTORY
  "${SDL_INSTALL}/include/SDL2"
  "${SDL_INSTALL}/lib")

ExternalProject_Add(SDL
  #URL "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.14.zip"
  GIT_REPOSITORY "https://github.com/libsdl-org/SDL"
  GIT_TAG de6d290
  # Keeps the project from rebuilding every time
  UPDATE_COMMAND ""

  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${SDL_INSTALL}
  --disable-video --disable-video-vulkan --disable-video-dummy
  --disable-render --disable-events
  --disable-joystick --disable-haptic --disable-sensor
  --disable-power
  --disable-shared

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
   ./configure
   PKG_CONFIG_PATH=${SDL_MIXER_INSTALL}/lib/pkgconfig:${SDL_INSTALL}/lib/pkgconfig
   CC=${CMAKE_C_COMPILER}
   --prefix=${SDL_MIXER_INSTALL}
   --disable-music-cmd --disable-music-mod
   --disable-music-midi --disable-music-flac --disable-music-mp3-mpg123 --disable-music-opus --disable-music-ogg-shared --disable-shared

   BUILD_COMMAND make
   INSTALL_COMMAND make install
   PREFIX "${PROJECT_BINARY_DIR}/deps/SDL_mixer/")
ExternalProject_Add_Step(SDL_mixer build-ogg
  WORKING_DIRECTORY "<SOURCE_DIR>"
  DEPENDEES patch
  COMMAND cd external/libogg-1.3.2/
  && ./configure CC=${CMAKE_C_COMPILER} --disable-shared --enable-static --prefix=${SDL_MIXER_INSTALL}
  && make install)
ExternalProject_Add_Step(SDL_mixer build-vorbis
  WORKING_DIRECTORY "<SOURCE_DIR>"
  COMMAND cd external/libvorbis-1.3.5/ &&
  cmake -E env
  PKG_CONFIG_PATH=${SDL_MIXER_INSTALL}/lib/pkgconfig/

  ./configure
  CC=${CMAKE_C_COMPILER}
  --disable-shared --enable-static
  --prefix=${SDL_MIXER_INSTALL}
  && make install

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
