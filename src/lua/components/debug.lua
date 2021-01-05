local util = require("util")
local collider_components = require("components.collider")

local DebugColliderDrawingSystem = class("DebugColliderDrawingSystem", System)
function DebugColliderDrawingSystem:requires() return { "Collider" } end
function DebugColliderDrawingSystem:draw()
   for _, entity in pairs(self.targets) do
      local physics_world = collider_components.physics_world

      local x, y, w, h = physics_world:getRect(entity)
      local shape = RectangleShape.new(Vector2f.new(w, h))
      shape.outline_thickness = 1.0
      shape.outline_color = Color.Red
      shape.fill_color = Color.new(0, 0, 0, 0)
      shape.position = Vector2f.new(x, y)
      GLOBAL.drawing_target:draw(shape)
   end
end

local M = {}

function M.add_systems(engine)
   -- engine:addSystem(DebugColliderDrawingSystem())
end

local debug_menu_state = {
   selected_moving = { obj = nil, x_diff = nil, y_diff = nil }
}

function M.debug_menu()
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
         if ImGui.IsKeyDown(KeyboardKey.LControl) and not debug_menu_state.selected_moving and ent then
            local x, y, _, _ = physics_world:getRect(ent)

            -- Save the different betweent the mouse position and the actual entity position,
            -- this difference is used to set the position according to where the mouse is in relation to the object
            -- instead of just setting the object's top left corner to the mouse position. Basically,
            -- this means that when clicked in the center of the object, it will stay in the center wherever the object
            -- is moved.
            local x_diff, y_diff = world_pos.x - x, world_pos.y - y

            debug_menu_state.selected_moving = { obj = ent, x_diff = x_diff, y_diff = y_diff }
         end

         if ent then
            debug_menu_state.selected = ent
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

         if not debug_menu_state.selected_moving.obj:get("Drawable") then
            -- Get the updated position
            local x, y, _, _ = physics_world:getRect(debug_menu_state.selected_moving.obj)

            debug_menu_state.selected_moving.obj:get("Transformable").transformable.position =
               Vector2f.new(x, y)
         end
      end
   end
   if ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) and not ent then
      debug_menu_state.selected = nil
   end

   if debug_menu_state.selected then
      ImGui.Separator()
      ImGui.Text("Selected: " .. debug_menu_state.selected:get("Name").name)

      local comps = debug_menu_state.selected:getComponents()
      local sorted_comps = {}
      for comp_name, comp in pairs(comps) do
         table.insert(sorted_comps, { name = comp_name, comp = comp })
      end
      table.sort(sorted_comps, function (a, b) return a.name < b.name end)

      for _, comp in ipairs(sorted_comps) do
         util.entities_mod().show_editor(comp.name, comp.comp, debug_menu_state.selected)
      end
   end
end

return M
