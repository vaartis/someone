local lume = require("lume")

local util = require("util")
local coroutines = require("coroutines")
local rooms

local M = {}

M.components = {
   passage = {
      class = Component.create("Passage", {"to", "from", "player_y"})
   }
}

function M.components.passage.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.passage.class(comp.to, comp.from, comp.player_y))
end

M.interaction_callbacks = {}

function M.interaction_callbacks.switch_room(_current_state, ent)
   local passage_comp = ent:get("Passage")

   if not rooms then
      rooms = util.rooms_mod()
   end

   local final_room_name
   if passage_comp.to:match("/") then
      -- If the name is qualified, just use it
      final_room_name = passage_comp.to
   else
      local in_current_namespace = lume.format(
         "{1}/{2}", { rooms.current_namespace, passage_comp.to }
      )

      local exists = "resources/rooms/" .. in_current_namespace .. ".toml"
      if exists then
         -- A version of the room in the current namespace exists, load that version
         final_room_name = in_current_namespace
      else
         local number_pos = rooms.current_namespace:find("%d+$")
         local number = tonumber(rooms.current_namespace:sub(number_pos))
         local without_number = rooms.current_namespace:sub(1, number_pos - 1)

         if number == nil then
            error(
               lume.format(
                  "There is no number at the end of the namespace {1}, that is the current namespace. To switch rooms without qualification, the namespace must be numbered, so a previous one could be found",
                  { rooms.current_namespace }
               )
            )
         end

         local function try_finding_in_previous(without_number, number)
            local name_to_use = lume.format(
               "{1}{2}/{3}",
               { without_number, number, passage_comp.to }
            )

            local exists = "resources/rooms/" .. name_to_use .. ".toml"
            if exists then
               return name_to_use
            elseif number == 0 then
               error(
                  lume.format(
                     "Tried finding {1} by going down the {2} namespaces but reached zero without result",
                     passage_comp.to, without_number
                  )
               )
            else
               return try_finding_in_previous(without_number, number - 1)
            end
         end
         final_room_name = try_finding_in_previous(without_number, number)
      end
   end

   local player_movement = util.rooms_mod().find_player():get("PlayerMovement")
   player_movement.active = false

   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         -- When the screen in blacked out, change the room and put the player
         -- where needed

         rooms.load_room(final_room_name)

         local passages_in_room = rooms.engine:getEntitiesWithComponent("Passage")

         local found_passage
         for _, ent in pairs(passages_in_room) do
            local searched_passage_comp = ent:get("Passage")

            -- If not player_y is specified, this passage shouldn't be used
            -- to spawn the player
            if searched_passage_comp.player_y and searched_passage_comp.to == passage_comp.from then
               found_passage = ent
               break
            end
         end
         if not found_passage then
            error(
               lume.format(
                  "Couldn't find a passage from {1} to {2} for passage {3}",
                  { passage_comp.from, passage_comp.to, ent:get("Name").name }
               )
            )
         end

         local player = rooms.find_player()
         local physics_world = player:get("Collider").physics_world

         local _, _, player_w, player_h = physics_world:getRect(player)
         local x, y = physics_world:getRect(found_passage)

         local found_passage_comp = found_passage:get("Passage")

         physics_world:update(player, x, found_passage_comp.player_y)
      end,
      function()
         -- Enable the player back when the room has changed
         player_movement.active = true
      end
   )
end

return M
