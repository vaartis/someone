local lume = require("lume")
local fs = require("path.fs")
local path = require("path")

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

local debug_menu_state
local DebugMenuResetSystem = class("DebugMenuResetSystem", System)
function DebugMenuResetSystem:onBeforeResetEngine()
   debug_menu_state.selected = nil
   debug_menu_state.selected_moving = nil
end

local M = {}

function M.add_systems(engine)
   engine:addSystem(DebugColliderDrawingSystem())
   -- This doesn't actually do anything except resetting the debug menu data on room unload
   engine:addSystem(DebugMenuResetSystem())
end

debug_menu_state = {
   selected = nil,
   selected_moving = { obj = nil, x_diff = nil, y_diff = nil },
   added_component = { index = 1, search = "" },
   selected_entity_search = { index = 1, search = "" }
}

function M.debug_menu()
   util.debug_menu_process_state_variable_node("State variables", WalkingModule.state_variables)

   ImGui.Separator()

   if ImGui.Button("Select entity") then
      ImGui.OpenPopup("Select entity")
   end
   if ImGui.BeginPopup("Select entity") then
      local entities = util.rooms_mod().engine:getRootEntity().children

      local changed
      debug_menu_state.selected_entity_search.search, changed =
         ImGui.InputText("Search", debug_menu_state.selected_entity_search.search, ImGuiInputTextFlags.None)
      if changed then
         -- Reset the list position on search change
         debug_menu_state.selected_entity_search.index = 1
      end

      local entity_tbl = {}
      for _, ent in pairs(entities) do
         local name = ent:get("Name").name
         if string.match(name:lower(), debug_menu_state.selected_entity_search.search:lower()) then
            table.insert(entity_tbl, { name = name, ent = ent })
         end
      end
      table.sort(entity_tbl, function (a, b) return a.name < b.name end)

      local entity_names = lume.map(entity_tbl, function (e) return e.name end)

      -- Translate the position in the array to plus or minus one

      local new_index, changed = ImGui.ListBox("Entities", debug_menu_state.selected_entity_search.index - 1, entity_names)
      debug_menu_state.selected_entity_search.index = new_index + 1

      if changed then
         debug_menu_state.selected = entity_tbl[debug_menu_state.selected_entity_search.index].ent

         ImGui.CloseCurrentPopup()
      end

      ImGui.EndPopup()
   end
   ImGui.SameLine()

   if ImGui.Button("Add entity") then
      debug_menu_state.creating_entity = { name = "", prefab = nil }

      ImGui.OpenPopup("Add entity")
   end
   if ImGui.BeginPopupModal("Add entity") then

      debug_menu_state.creating_entity.name = ImGui.InputText("Name", debug_menu_state.creating_entity.name)

      if ImGui.BeginCombo("Prefab", debug_menu_state.creating_entity.prefab or "(none)") then
         if ImGui.Selectable("(none)", not debug_menu_state.creating_entity.prefab) then
            debug_menu_state.creating_entity.prefab = nil
         end

         local prefab_path = "resources/rooms/prefabs/"

         local list_dir
         list_dir = function(dir_path)
            for file in fs.dir(dir_path) do
               if file == "." or file == ".." then
                  goto continue
               end

               local filename_without_ext = path.splitext(file)
               local fullpath = path.join(dir_path, file)

               if fs.isfile(fullpath) then
                  local without_prefab_path = path.splitext(fullpath):gsub(prefab_path, "")

                  if ImGui.Selectable(filename_without_ext, debug_menu_state.creating_entity.prefab == without_prefab_path) then
                     debug_menu_state.creating_entity.prefab = without_prefab_path
                  end
               elseif fs.isdir(fullpath) then
                  if ImGui.BeginMenu(file, true) then
                     list_dir(fullpath)

                     ImGui.EndMenu()
                  end

               end

               ::continue::
            end
         end

         list_dir(prefab_path)

         ImGui.EndCombo()
      end

      if ImGui.Button("Add") then
         local trimmed_name = lume.trim(debug_menu_state.creating_entity.name)
         if trimmed_name ~= "" then
            local any_same_named = false
            for _, ent in pairs(util.rooms_mod().engine:getRootEntity().children) do
               -- Ensure there are no same-named entities
               if ent:get("Name").name == trimmed_name then
                  any_same_named = true
                  break
               end
            end

            if not any_same_named then
               local entities_mod = util.entities_mod()

               debug_menu_state.selected = entities_mod.instantiate_entity(
                  trimmed_name,
                  { prefab = debug_menu_state.creating_entity.prefab }
               )

               ImGui.CloseCurrentPopup()
            end
         end
      end
      ImGui.SameLine()
      if ImGui.Button("Cancel") then ImGui.CloseCurrentPopup() end

      ImGui.EndPopup()
   end
   ImGui.SameLine()

   -- Onlhy show when an entity is selected
   if debug_menu_state.selected and ImGui.Button("Add component") then
      ImGui.OpenPopup("Add component")
   end
   if ImGui.BeginPopupModal("Add component") then
      local changed
      debug_menu_state.added_component.search, changed = ImGui.InputText("Search", debug_menu_state.added_component.search, ImGuiInputTextFlags.None)
      if changed then
         -- Reset the list position on search change
         debug_menu_state.added_component.index = 1
      end

      local selected_ent = debug_menu_state.selected

      local entities_mod = util.entities_mod()

      -- Collect all known components from known modules
      local all_components = {}
      for _, mod in ipairs(entities_mod.all_components) do
         if mod.components then
            for comp_name, comp_data in pairs(mod.components) do
               local class_name = comp_data.class.name
               -- Only collect components that:
               -- 1. don't already exist on the entity
               -- 2. have default data
               -- 3. match lower-cased search
               if not selected_ent:has(comp_data.class.name)
                  and comp_data.class.default_data
                  and string.match(class_name:lower(), debug_menu_state.added_component.search:lower())
               then
                  table.insert(all_components, { name = comp_name, comp = comp_data, class_name = class_name })
               end
            end
         end
      end
      local all_components_names = lume.map(
         all_components,
         function (c) return c.class_name end
      )

      -- Translate the position in the array to plus or minus one
      debug_menu_state.added_component.index = ImGui.ListBox(
         "Components",
         debug_menu_state.added_component.index - 1,
         all_components_names
      ) + 1

      local selected_component = all_components[debug_menu_state.added_component.index]
      if ImGui.Button("Add") then
         local selected_ent_name = selected_ent:get("Name").name

         local selected_class = selected_component.comp.class
         local default_data = selected_class:default_data(selected_ent)

         local processor_data = entities_mod.comp_processor_for_name(
            selected_component.name,
            default_data,
            selected_ent_name
         )
         local is_ok, err = pcall(
            entities_mod.run_comp_processor,

            selected_ent,
            processor_data,
            selected_ent_name
         )
         if not is_ok then
            debug_menu_state.added_component.last_error = err
         else
            ImGui.CloseCurrentPopup()
         end
      end
      ImGui.SameLine()
      if ImGui.Button("Cancel") then ImGui.CloseCurrentPopup() end

      if debug_menu_state.added_component.last_error then
         ImGui.Text(debug_menu_state.added_component.last_error)
      end

      ImGui.EndPopup()
   end

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
         ImGui.Separator()

         if comp.comp.show_editor then
            comp.comp:show_editor(debug_menu_state.selected)
         else
            ImGui.Text("No editor for component " .. comp.name)
         end
      end
   end
end

--- Loads all entities from the room but doesn't add them to the world.
--- Probably very expensive, but only used for the editor so should be fine.
function M.load_entities_from_room(name, with_components)
   local room_toml = util.rooms_mod().load_room_file(name)

   -- Save current physics world
   local curr_phys_world = collider_components.physics_world
   -- Reset world for the previewed entities to insert into.
   -- This world will then be thrown out, it's only need is to not pollute the
   -- main one.
   collider_components.reset_world()

   local ents = {}
   for entity_name, entity in pairs(room_toml.entities) do
      -- Don't add the entities to the world
      local instantiated = util.entities_mod().instantiate_entity(entity_name, entity, nil, false)
      if with_components then
         -- Ignore entities that don't have all specified components
         if lume.any(with_components, function(c_name) return not instantiated:has(c_name) end) then
            goto continue
         end
      end

      table.insert(ents, instantiated)

      ::continue::
   end

   -- Restore the real physics world
   collider_components.physics_world = curr_phys_world

   return ents
end

return M
