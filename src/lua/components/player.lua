local lovetoys = require("lovetoys")

local assets = require("components.assets")
local shared = require("components.shared")
local path = require("path")

local M = {}

M.PlayerMovementComponent = Component.create(
   "PlayerMovement",
   {"step_sound", "walking", "look_direction", "active"},
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

function M.process_components(new_ent, comp_name, comp)
   if comp_name == "player_movement" then
      local sound_asset = assets.assets.sounds[comp.footstep_sound_asset]
      if not sound_asset then
         error(lume.format("{1}.{2} requires a sound named {3}", {entity_name, comp_name, comp.footstep_sound_asset}))
      end

      new_ent:add(M.PlayerMovementComponent(sound_asset.sound))

      return true
   end
end

return M
