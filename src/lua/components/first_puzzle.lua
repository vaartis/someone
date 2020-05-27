local lume = require("lume")

local FirstPuzzleButtonComponent = Component.create("FirstPuzzleButton", {"n"})

local FirstPuzzleButtonSystem = class("FirstPuzzleButtonSystem", System)
function FirstPuzzleButtonSystem:requires() return {"FirstPuzzleButton", "Interaction"} end
function FirstPuzzleButtonSystem:update()
   for _, entity in pairs(self.targets) do
      if WalkingModule.state_variables.first_puzzle then
         entity:get("Interaction").current_state = WalkingModule.state_variables.first_puzzle[entity:get("FirstPuzzleButton").n]
      end
   end
end

local M = {}

function M.process_components(new_ent, comp_name, comp)
   if comp_name == "first_puzzle_button" then
      new_ent:add(FirstPuzzleButtonComponent(comp.n))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(FirstPuzzleButtonSystem())
end

M.interaction_callbacks = {}

function M.interaction_callbacks.button_callback(curr_state, n)
   local puzzle_state = WalkingModule.state_variables.first_puzzle

   if n == "first" then
      if puzzle_state.first == "right" then puzzle_state.first = "wrong" else puzzle_state.first = "right" end
      if puzzle_state.third == "right" then puzzle_state.third = "wrong" else puzzle_state.third = "right" end
   elseif n == "second" then
      if puzzle_state.second == "right" then puzzle_state.second = "wrong" else puzzle_state.second = "right" end
      if puzzle_state.first == "right" then puzzle_state.first = "wrong" else puzzle_state.first = "right" end
   elseif n == "third" then
      if puzzle_state.third == "right" then puzzle_state.third = "wrong" else puzzle_state.third = "right" end
   end

   if lume.all({puzzle_state.first, puzzle_state.second, puzzle_state.third}, function(x) return x == "right" end) then
      WalkingModule.state_variables.first_puzzle.solved = true
   end

   return WalkingModule.state_variables.first_puzzle[n]
end

M.activatable_callbacks = {}

local played_music
function M.activatable_callbacks.first_puzzle_solved()
   if not WalkingModule.state_variables.first_puzzle then
      WalkingModule.state_variables.first_puzzle = {
         first = "wrong",
         second = "wrong",
         third = "wrong",
         solved = false
      }
   end

   return WalkingModule.state_variables.first_puzzle.solved
end

function M.activatable_callbacks.first_puzzle_not_solved()
   return not M.activatable_callbacks.first_puzzle_solved()
end

function M.activatable_callbacks.first_puzzle_solved_music()
   -- Return true only if music has not already played
   local result = M.activatable_callbacks.first_puzzle_solved() and not played_music

   if result and not played_music then
      -- Mark that music has played
      played_music = true
   end

   return result
end

return M
