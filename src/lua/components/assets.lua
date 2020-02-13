local M = {
   assets = {
      sprites = {},
      sounds = {}
   }
}

function M.add_sprite(name, path)
   local texture = Texture.new()
   texture:load_from_file(path)

   local sprite = Sprite.new()
   sprite.texture = texture

   M.assets.sprites[name] = {
      texture = texture,
      sprite = sprite
   }

   return sprite
end

function M.add_sound(name, path)
   local sound_buf = SoundBuffer.new()
   sound_buf:load_from_file(path)

   local sound = Sound.new()
   sound.buffer = sound_buf

   M.assets.sounds[name] = {
      buffer = sound_buf,
      sound = sound
   }

   return sound
end

return M
