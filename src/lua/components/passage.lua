local lume = require("lume")

local util = require("util")
local coroutines = require("coroutines")
local rooms

local collider_components = require("components.collider")
local debug_components = require("components.debug")

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

local function get_final_room_name(passage_comp)
   if not rooms then
      rooms = util.rooms_mod()
   end

   local final_room_name
   if passage_comp.to:match("/") then
      -- If the name is qualified, just use it
      final_room_name = passage_comp.to
   else
      if rooms.current_namespace == nil then
         error("rooms.current_namespace is not set! This probably means that rooms.load_room was not asked to set a namespace.")
      end

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

   return final_room_name
end

local function find_passage(ent, passage_comp, passages_in_room)
   local found_passage
   for _, ent in pairs(passages_in_room) do
      local searched_passage_comp = ent:get("Passage")

      -- If no player_y is specified, this passage shouldn't be used
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

   return found_passage
end

function M.interaction_callbacks.switch_room(_current_state, ent)
   local passage_comp = ent:get("Passage")

   local final_room_name = get_final_room_name(passage_comp)

   local player_movement = util.rooms_mod().find_player():get("PlayerMovement")
   player_movement.active = false

   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         -- When the screen in blacked out, change the room and put the player
         -- where needed

         rooms.load_room(final_room_name)

         local passages_in_room = rooms.engine:getEntitiesWithComponent("Passage")
         local found_passage = find_passage(ent, passage_comp, passages_in_room)

         local player = rooms.find_player()
         local physics_world = collider_components.physics_world

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

function M.components.passage.class:default_data(ent)
   local physics_world = collider_components.physics_world
   local _, _, _, player_h = physics_world:getRect(util.rooms_mod().find_player())

   local _, y, _, _ = physics_world:getRect(ent)

   return { from = util.rooms_mod().current_unqualified_room_name, to = "", player_y = math.floor(y + (player_h / 2)) }
end

function M.components.passage.class:show_editor(ent)
   ImGui.Text("Passage")

   if not self.__editor_state then
      self.__editor_state = { is_player_dest = self.player_y ~= nil, can_go_from = self.from ~= nil }
   end

   self.__editor_state.can_go_from, changed = ImGui.Checkbox("Can go from", self.__editor_state.can_go_from)
   if changed then
      if self.__editor_state.can_go_from then
         self.from = util.rooms_mod().current_unqualified_room_name
      else
         self.from = nil
      end
   end

   if self.__editor_state.can_go_from then
      self.from = ImGui.InputText("From", self.from)
   end

   self.to = ImGui.InputText("To", self.to)

   local physics_world = collider_components.physics_world
   local _, _, _, player_h = physics_world:getRect(util.rooms_mod().find_player())

   local x, y, w, h = physics_world:getRect(ent)

   self.__editor_state.is_player_dest, changed = ImGui.Checkbox("Sets player Y", self.__editor_state.is_player_dest)
   if changed then
      if self.__editor_state.is_player_dest then
         self.player_y = math.floor(y + (player_h / 2))
      else
         self.player_y = nil
      end
   end

   if self.__editor_state.is_player_dest then
      self.player_y = ImGui.InputInt("Player Y", self.player_y)
      ImGui.Text("Set to")
      ImGui.SameLine()
      if ImGui.Button("Bottom + 1/2 player height") then
         -- Set the default position to be roughly at half player height
         self.player_y = math.floor(y + (player_h / 2))
      end
      ImGui.SameLine()
      if ImGui.Button("Bottom") then
         self.player_y = math.floor(y + h - player_h)
      end

      -- Map coordinates to pixel-coordinates for ImGui
      local pixel_x = GLOBAL.window:map_coords_to_pixel(Vector2f.new(x, 0)).x
      local pixel_w = GLOBAL.window:map_coords_to_pixel(Vector2f.new(w, h)).x

      local pixel_player_h = GLOBAL.window:map_coords_to_pixel(Vector2f.new(0, player_h)).y
      local pixel_player_y = GLOBAL.window:map_coords_to_pixel(Vector2f.new(0, self.player_y)).y + pixel_player_h

      ImGui.AddLine(Vector2f.new(pixel_x, pixel_player_y), Vector2f.new(pixel_x + pixel_w, pixel_player_y), Color.Green, 1)
   end

   if ImGui.Button("Save##passage") then
      -- Do additional checks if this is a passage that the player can go through
      if self.__editor_state.can_go_from then
         local was_ok, final_name = pcall(get_final_room_name, ent:get("Passage"))
         if not was_ok then
            self.__editor_state.last_error = final_name

            goto nosave
         end
         -- THIS CAUSES WEIRD THINGS
         was_ok, to_room_passages = pcall(
            debug_components.load_entities_from_room,
            final_name,
            {"Passage"}
         )

         if not was_ok then
            self.__editor_state.last_error = to_room_passages

            goto nosave
         end
         was_ok, err = pcall(
            find_passage,
            ent, self, to_room_passages
         )
         if not was_ok then
            self.__editor_state.last_error = err

            goto nosave
         end
      end

      self.__editor_state.last_error = nil

      TOML.save_entity_component(ent, "passage", self, { "from", "to", "player_y" }, { from = self.from, to = self.to, player_y = self.player_y })

      ::nosave::
   end

   if self.__editor_state.last_error then
      ImGui.Text(self.__editor_state.last_error)
   end
end

return M
