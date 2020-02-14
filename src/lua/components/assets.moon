assets =
  sprites: {}
  sounds: {}

add_sprite = (name, path) ->
  texture = with Texture.new!
    \load_from_file(path)

  sprite = with Sprite.new!
    .texture = texture

  assets.sprites[name] = { :texture, :sprite }

  sprite

add_sound = (name, path) ->
  buffer = with SoundBuffer.new!
    \load_from_file(path)

  sound = with Sound.new!
    .buffer = buffer

  assets.sounds[name] = { :buffer, :sound }

  sound

{ :assets, :add_sprite, :add_sound }
