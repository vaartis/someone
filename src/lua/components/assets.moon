lume = require("lume")

known_assets =
  textures: {}
  sounds: {}
assets =
  textures: {}
  sounds: {}

load_from_known_assets = (asset_type, key) ->
  maybe_known_asset_path = known_assets[asset_type][key]
  if not maybe_known_asset_path
    error("Trying to load an unknown asset: #{key}")

  switch asset_type
    when "textures"
      texture = with Texture.new!
        \load_from_file(maybe_known_asset_path)

      assets.textures[key] = texture

      texture
    when "sounds"
      buffer = with SoundBuffer.new!
        \load_from_file(maybe_known_asset_path)

      assets.sounds[key] = buffer

      buffer
    else
      error("Unknown asset type: #{asset_type}")

add_to_known_assets = (asset_type, key, path) ->
  known_assets[asset_type][key] = path

setmetatable(
  assets.textures,
  { __index: (_, key) -> load_from_known_assets("textures", key) }
)
setmetatable(
  assets.sounds,
  { __index: (_, key) -> load_from_known_assets("sounds", key) }
)

{ :assets, :add_to_known_assets }
