local util = require("util")
local lume = require("lume")
local assets = require("components.assets")

local interaction_components = require("components.interaction")

local position_rotations = {
   0, 36, 58, 88, 126, 148, 180,
   216, 236, 270, 302, 322
}

local M = {}

M.interaction_callbacks = {}
function M.interaction_callbacks.open_dial()
   if not WalkingModule.state_variables.dial_puzzle then
      local puzzle_state = { solved = false, music_played = false, combination = {} }
      for i = 1, 3 do
         puzzle_state.combination[i] = math.random(1, #position_rotations)
      end

      WalkingModule.state_variables.dial_puzzle = puzzle_state
   end

   util.entities_mod().instantiate_entity("dial_closeup", { prefab = "dial" })
end


M.activatable_callbacks = {}
function M.activatable_callbacks.solved_music()
   if WalkingModule.state_variables.dial_puzzle then
      local state = WalkingModule.state_variables.dial_puzzle
      if state.solved and not state.music_played then
         state.music_played = true

         return true
      end
   end
end

local DialHandleComponent = Component.create("DialHandleComponent")

local combination_n = 1

local rotation_click_sound
local last_passed_position, last_side
local last_rotation

local DialHandleSystem = class("DialHandleSystem", System)
function DialHandleSystem:requires()
   return {
      objects = { "DialHandleTag", "Transformable" },
      interaction_text = { "InteractionTextTag" }
   }
end
function DialHandleSystem:update(dt)
   for _, entity in pairs(self.targets.objects) do
      local tf = entity:get("Transformable").transformable

      -- Restore rotation from previous opening
      if last_rotation then
         tf.rotation = last_rotation
         last_rotation = nil
      end

      local engine = util.rooms_mod().engine

      -- Keep these off
      engine:stopSystem("InteractionSystem")
      engine:stopSystem("PlayerMovementSystem")

      local interaction_text_key = lume.first(lume.keys(self.targets.interaction_text))
      if not interaction_text_key then error("No interaction text entity found") end
      local interaction_text_drawable = self.targets.interaction_text[interaction_text_key]:get("Drawable")
      if not interaction_text_drawable.enabled then
         interaction_text_drawable.enabled = true
         interaction_text_drawable.drawable.string = "[A/D] to rotate, [E] to close"
      end

      interaction_components.seconds_since_last_interaction =
         interaction_components.seconds_since_last_interaction + dt

      local rotation_change = 0
      if not (WalkingModule.state_variables.dial_puzzle.solved) then
         if Keyboard.is_key_pressed(KeyboardKey.D) then
            rotation_change = 1
         elseif Keyboard.is_key_pressed(KeyboardKey.A) then
            rotation_change = -1
         end
      end
      tf:rotate(rotation_change)

      -- If the dial goes past 10 degrees from the last position,
      -- reset the last_passed_position, so the sound could can again
      if last_passed_position then
         local last_pos_value = position_rotations[last_passed_position]
         if math.abs(last_pos_value - tf.rotation) > 10 then
            last_passed_position = nil
         end
      end

      local position_num = lume.find(position_rotations, tf.rotation)
      if rotation_change ~= 0 and position_num and position_num ~= last_passed_position then
         last_passed_position = position_num

         if not rotation_click_sound then
            rotation_click_sound = Sound.new()
            rotation_click_sound.buffer = assets.assets.sounds["rotation_click"]
         end

         local combination = WalkingModule.state_variables.dial_puzzle.combination
         if position_num == combination[combination_n] then
            -- When approached from a different side, count as the correct value
            if rotation_change ~= last_side then
               rotation_click_sound.volume = 100

               last_side = rotation_change

               if combination_n < #combination then
                  -- If there are more numbers in the combination, increase the counter
                  combination_n = combination_n + 1
               else
                  -- Otherwise, the puzzle is solved
                  WalkingModule.state_variables.dial_puzzle.solved = true
               end
            else
               -- If approached from the same side, reset
               combination_n = 1
               last_side = nil
            end
         else
            rotation_click_sound.volume = 30
         end

         rotation_click_sound:play()
      end

      for _, native_event in pairs(interaction_components.event_store.events) do
         local event = native_event.event
         if interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction and
         event.type == EventType.KeyReleased then
            local interacted

            if event.key.code == KeyboardKey.E then
               interacted = true

               -- Save the last rotation value to restore on reopen
               last_rotation = tf.rotation

               -- Delete the whole dial
               engine:removeEntity(entity.parent, true)
               engine:startSystem("InteractionSystem")
               engine:startSystem("PlayerMovementSystem")
            end

            if interacted then
               interaction_components.seconds_since_last_interaction = 0
            end
         end
      end
   end
end


function M.process_components(new_ent, comp_name, comp)
   if comp_name == "dial_handle" then
      new_ent:add(DialHandleComponent())

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(DialHandleSystem())
end

return M
