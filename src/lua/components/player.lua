local lovetoys = require("lovetoys")

local shared = require("components.shared")
local path = require("path")

local M = {}

M.PlayerMovementComponent = Component.create(
   "PlayerMovement",
   {"step_sound_buffer", "step_sound", "walking", "look_direction", "active"},
   { walking = false, look_direction = 1, active = true}
)

M.PlayerMovementSystem = class("PlayerMovementSystem", System)

function M.PlayerMovementSystem:requires()
   return {"PlayerMovement", "Transformable", "DrawableSprite", "Animation"}
end

function M.PlayerMovementSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local player_movement = entity:get("PlayerMovement")

      if player_movement.active then
         local tf = entity:get("Transformable")

         local drawable = entity:get("DrawableSprite")
         local animation = entity:get("Animation")

         if Keyboard.is_key_pressed(KeyboardKey.D) then
            tf.transformable.position = tf.transformable.position + Vector2f.new(1.0, 0.0)
            player_movement.walking = true
            player_movement.look_direction = 1
         elseif Keyboard.is_key_pressed(KeyboardKey.A) then
            tf.transformable.position = tf.transformable.position + Vector2f.new(-1.0, 0.0)
            player_movement.walking = true
            player_movement.look_direction = -1
         else
            player_movement.walking = false
         end

         drawable.sprite.scale = Vector2f.new(player_movement.look_direction, 1.0)
         animation.playing = player_movement.walking

         -- Play the step sound every two steps of the animation, which are the moments
         -- when the feet hit the ground
         if player_movement.walking and animation.current_frame % 2 == 0 and player_movement.step_sound.status ~= SoundStatus.Playing then
            player_movement.step_sound:play()
         end
      end
   end
end

function M.create_player_entity()
   local dir_path = "resources/sprites/mainchar"
   local animation_frames = shared.load_sheet_frames(dir_path)

   local dir_basename = path.basename(path.remove_dir_end(dir_path))
   local sheet_path = path.join(dir_path, dir_basename) .. ".png"

   local first_frame = animation_frames[1]

   local player_texture = Texture.new()
   player_texture:load_from_file(sheet_path)

   local player_sprite = Sprite.new()
   player_sprite.texture = player_texture
   player_sprite.origin = Vector2f.new(first_frame.rect.width / 2, first_frame.rect.height)
   player_sprite.position = Vector2f.new(420, 820)

   local footstep_sound_path = "resources/sounds/footstep.ogg"
   local step_sound_buf = SoundBuffer.new()
   step_sound_buf:load_from_file(footstep_sound_path)

   local step_sound = Sound.new()
   step_sound.buffer = step_sound_buf

   local player = Entity()
   player:add(shared.DrawableSpriteComponent(player_sprite, player_texture, 2))
   player:add(shared.AnimationComponent(animation_frames))
   player:add(shared.TransformableComponent(player_sprite))
   player:add(M.PlayerMovementComponent(step_sound_buf, step_sound))

   return player
end

return M
