local lume = require("lume")
local path = require("path")

local assets = require("components.assets")
local shared = require("components.shared")

local x_movement_speed = 4.0

local PlayerMovementComponent = Component.create(
   "PlayerMovement", {"step_sound", "walking", "look_direction", "active"}, { walking = false, look_direction = 1, active = true })

local PlayerMovementSystem = class("PlayerMovementSystem", System)
PlayerMovementSystem.requires = function(self)
   return { "PlayerMovement", "Transformable", "Drawable", "Animation", "Collider" }
end
PlayerMovementSystem.update = function(self, dt)
   for _, entity in pairs(self.targets) do
      local player_movement = entity:get("PlayerMovement")

      if player_movement.active then
         local tf = entity:get("Transformable")
         local drawable = entity:get("Drawable")
         local animation = entity:get("Animation")
         local physics_world = entity:get("Collider").physics_world

         local pos_diff, look_direction
         if Keyboard.is_key_pressed(KeyboardKey.D) then
            pos_diff = Vector2f.new(x_movement_speed, 0.0)
            look_direction = 1
         elseif Keyboard.is_key_pressed(KeyboardKey.A) then
            pos_diff = Vector2f.new(-x_movement_speed, 0.0)
            look_direction = -1
         end

         if pos_diff ~= nil then
            local x, y = physics_world:getRect(entity)
            local expected_new_pos = Vector2f.new(x, y) + pos_diff


            local _, _, cols, col_count = physics_world:check(
               entity, expected_new_pos.x, expected_new_pos.y,
               function(item, other) if other:get("Collider").trigger then return "cross" else return "slide" end end
            )
            if col_count == 0 or not lume.any(cols, function(c) return c.type == "slide" end) then
               -- Don't check for collisions here, since the've already been checked,
               -- just update the position
               physics_world:update(entity, expected_new_pos.x, expected_new_pos.y)
               player_movement.walking = true
            end

            player_movement.look_direction = look_direction
         else
            player_movement.walking = false
         end

         drawable.drawable.scale = Vector2f.new(player_movement.look_direction, 1.0)
         animation.playing = player_movement.walking

         -- Play the step sound every two steps of the animation, which are the moments
         -- when the feet hit the ground
         if player_movement.walking and animation.current_frame % 2 == 0 and player_movement.step_sound.status ~= SoundStatus.Playing then
            player_movement.step_sound:play()
         end
      end
   end
end

local M = {}

function M.process_components(new_ent, comp_name, comp)
   if comp_name == "player_movement" then
      local sound_buf_asset = assets.assets.sounds[comp.footstep_sound_asset]
      if not sound_buf_asset then
         error(lume.format("{1}.{2} requires a sound named {3}", {entity_name, comp_name, comp.footstep_sound_asset}))
      end

      local sound = Sound.new()
      sound.buffer = assets.assets.sounds[comp.footstep_sound_asset]

      new_ent:add(PlayerMovementComponent(sound))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(PlayerMovementSystem())
end

return M
