local util = require("util")
local lume = require("lume")
local assets = require("components.assets")

local interaction_components = require("components.interaction")

local position_rotations = {
   0, 36, 58, 88, 126, 148, 180,
   216, 236, 270, 302, 322
}

local M = {}

local function ensure_state_init()
   if not WalkingModule.state_variables.dial_puzzle then
      local puzzle_state = { solved = false, music_played = false, combination = {} }

      -- Update the random seed so that the numbers are actually random
      math.randomseed(os.time())

      for i = 1, 3 do
         local should_regenerate
         repeat
            random_num = math.random(1, #position_rotations)

            -- Combination digits must be unique.
            -- Also, the first number can't be on the first position.
            -- If these aren't true, a new number needs to be generated for this position.
            if (i ~= 1 and lume.find(puzzle_state.combination, random_num)) or (i == 1 and random_num == 1) then
               should_regenerate = true
            else
               should_regenerate = false

               puzzle_state.combination[i] = random_num
            end
         until not should_regenerate
      end

      WalkingModule.state_variables.dial_puzzle = puzzle_state
   end
end

M.interaction_callbacks = {}
function M.interaction_callbacks.open_dial()
   ensure_state_init()

   util.entities_mod().instantiate_entity("dial_closeup", { prefab = "dial" })
end


M.activatable_callbacks = {}

function M.activatable_callbacks.puzzle_solved()
   ensure_state_init()

   return WalkingModule.state_variables.dial_puzzle.solved
end

function M.activatable_callbacks.solved_music()
   ensure_state_init()

   if WalkingModule.state_variables.dial_puzzle then
      local state = WalkingModule.state_variables.dial_puzzle
      if M.activatable_callbacks.puzzle_solved() and not state.music_played then
         state.music_played = true

         return true
      end
   end
end

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

      -- Keep the player off
      interaction_components.disable_player(engine)

      local interaction_text_drawable = util.first(self.targets.interaction_text):get("Drawable")
      if not interaction_text_drawable.enabled then
         interaction_text_drawable.enabled = true
         interaction_text_drawable.drawable.string = "[A/D] to rotate, [E] to close"
      end

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
            rotation_click_sound = assets.create_sound_from_asset("rotation_click")
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

      interaction_components.update_seconds_since_last_interaction(dt)

      interaction_components.if_key_pressed({
            [KeyboardKey.E] = function()
               -- Save the last rotation value to restore on reopen
               last_rotation = tf.rotation

               -- Delete the whole dial
               engine:removeEntity(entity.parent, true)
               interaction_components.enable_player(engine)
            end
      })
   end
end

M.systems = {
   DialHandleSystem
}

return M
