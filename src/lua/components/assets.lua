local lume = require("lume")

local M = {}

local known_assets = {
  textures = {},
  sounds = {}
}

M.assets = {
  textures = {},
  sounds = {}
}

function load_from_known_assets(asset_type, key)
   local maybe_known_asset_path = known_assets[asset_type][key]
   if not maybe_known_asset_path then
      error("Trying to load an unknown asset: " .. tostring(key))
   end

   local asset
   if asset_type == "textures" then
      asset = Texture.new()
   elseif asset_type == "sounds" then
      asset = SoundBuffer.new()
   else
      error("Unknown asset type: " .. tostring(asset_type))
   end

   asset:load_from_file(maybe_known_asset_path)
   M.assets[asset_type][key] = asset

   return asset
end

function M.list_known_assets(asset_type)
   return lume.keys(known_assets[asset_type])
end


function M.add_to_known_assets(asset_type, key, path)
   known_assets[asset_type][key] = path
end

setmetatable(M.assets.textures, {
  __index = function(_, key)
    return load_from_known_assets("textures", key)
  end
})
setmetatable(M.assets.sounds, {
  __index = function(_, key)
    return load_from_known_assets("sounds", key)
  end
})

function M.create_sound_from_asset(asset_name)
   local result = { sound = Sound.new(), asset_name = asset_name }

   result.sound.buffer = M.assets.sounds[asset_name]

   return result
end

return M
