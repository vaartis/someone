local util = require("util")
local lume = require("lume")

local rooms = require("components.rooms")
local interaction_components = require("components.interaction")
local collider_components = require("components.collider")

local state_variables = {}

-- Load the room
--rooms.load_room("day3/first_puzzle_room")

local function update(dt)
   rooms.engine:update(dt)
end

local function draw()
   rooms.engine:draw()
end


local function draw_overlay()
   rooms.engine:draw("overlay")
end

local debug_menu_state = {
   selected_moving = { obj = nil, x_diff = nil, y_diff = nil }
}

local function debug_menu()
   util.debug_menu_process_state_variable_node("State variables", state_variables)

   if not ImGui.IsAnyWindowHovered() and not ImGui.IsAnyItemHovered() then
      -- Need to get the position from the window and not the drawing target,
      -- because the window scales the coordinates as needed, even when
      -- the actual size of the window is different
      local world_pos = GLOBAL.window:map_pixel_to_coords(ImGui.GetMousePos())

      local physics_world = collider_components.physics_world
      local ents_at_pos, ents_count = physics_world:queryPoint(world_pos.x, world_pos.y)
      local ent
      if ents_count > 0 then
         ent = ents_at_pos[1]

         ImGui.SetTooltip(ent:get("Name").name)
      end

      if ImGui.IsMouseDown(ImGuiMouseButton.Left) then
         if ImGui.IsKeyDown(KeyboardKey.LControl) and not debug_menu_state.selected_moving then
            local x, y, _, _ = physics_world:getRect(ent)

            -- Save the different betweent the mouse position and the actual entity position,
            -- this difference is used to set the position according to where the mouse is in relation to the object
            -- instead of just setting the object's top left corner to the mouse position. Basically,
            -- this means that when clicked in the center of the object, it will stay in the center wherever the object
            -- is moved.
            local x_diff, y_diff = world_pos.x - x, world_pos.y - y

            debug_menu_state.selected_moving = { obj = ent, x_diff = x_diff, y_diff = y_diff }
         end
      else
         debug_menu_state.selected_moving = nil
      end

      if debug_menu_state.selected_moving then
         ImGui.SetTooltip(debug_menu_state.selected_moving.obj:get("Name").name)

         local x, y, w, h = physics_world:getRect(debug_menu_state.selected_moving.obj)

         -- Get the previously acquired diff and subtract it from the mouse position
         local x_diff, y_diff = debug_menu_state.selected_moving.x_diff, debug_menu_state.selected_moving.y_diff
         physics_world:update(debug_menu_state.selected_moving.obj, world_pos.x - x_diff, world_pos.y - y_diff, w, h)
      end
   end
end

return {
   load_room = rooms.load_room,
   room_shaders = rooms.room_shaders,
   add_event = interaction_components.add_event,

   update = update, draw = draw, draw_overlay = draw_overlay,
   state_variables = state_variables,
   clear_event_store = interaction_components.clear_event_store,

   debug_menu = debug_menu
}
