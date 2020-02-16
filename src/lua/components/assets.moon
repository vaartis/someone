assets =
  sprites: {}
  sounds: {}

add_sprite = (name, path) ->
  texture = with Texture.new!
    \load_from_file(path)

  sprite = with Sprite.new!
    .texture = texture

  if assets.sprites[name]
    print("Overriding sprite asset #{name}")
  assets.sprites[name] = { :texture, :sprite }

  sprite

add_sound = (name, path) ->
  buffer = with SoundBuffer.new!
    \load_from_file(path)

  sound = with Sound.new!
    .buffer = buffer

  if assets.sprites[name]
    print("Overriding audio asset #{name}")
  assets.sounds[name] = { :buffer, :sound }

  sound

{ :assets, :add_sprite, :add_sound }
