local lume = require("lume")
local fs = require("path.fs")
local path = require("path")

local util = require("util")
local collider_components = require("components.collider")
local assets = require("components.assets")

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
   selected_entity_search = { index = 1, search = "" },
   adding_shader = { name = nil }
}

function M.show_table_typed(name, parent, table_name, size, declared_types)
   if not parent[table_name] then
      parent[table_name] = {}
   end

   local the_table = parent[table_name]

   if ImGui.BeginChild(name, size) then
      for i, arg_type in pairs(declared_types) do
         local arg = the_table[i]

         if arg_type == "string" then
            the_table[i] = ImGui.InputText(tostring(i), arg or "")
         elseif arg_type == "float" then
            the_table[i] =
               ImGui.InputFloat(tostring(i), arg or 0.0)
         elseif arg_type == "integer" then
            the_table[i] =
               ImGui.InputInt(tostring(i), arg or 0)
         elseif arg_type == "boolean" then
            the_table[i] =
               ImGui.Checkbox(tostring(i), arg or false)
         elseif arg_type == "vec2i" then
            the_table[i] =
               ImGui.InputInt2(tostring(i), arg or {0, 0})
         elseif arg_type == "table" then
            -- If type == table, the table can be anything

            ImGui.Text(tostring(i))
            ImGui.SameLine()
            M.show_table(name .. i, the_table, i, Vector2f.new(size.x, size.y / 2))
         elseif type(arg_type) == "table" then
            -- If arg_type itself is a table then it declares types for underlying levels of arguments
            M.show_table_typed(name .. i, the_table, i, Vector2f.new(size.x, size.y / 2), arg_type)
         else
            ImGui.InputText(tostring(i), "Unsupported type: " .. tostring(arg), ImGuiInputTextFlags.ReadOnly)
         end
      end

   end
   ImGui.EndChild()
end

function M.show_table(name, parent, table_name, size)
   local the_table = parent[table_name]

   if ImGui.BeginChild(name, size) then
      if the_table then
         for i, arg in pairs(the_table) do
            local minus_button = function()
               -- Add ID at the end of the button name (invisible in UI)
               if ImGui.Button("-##" .. i) then
                  -- For arrays, use table.remove, for tables set to nil
                  if #the_table > 0 then
                     table.remove(the_table, i)
                  else
                     the_table[i] = nil
                  end
                  if lume.count(the_table) == 0 then
                     parent[table_name] = nil
                  end

                  return true
               end
            end

            if type(arg) == "string" then
               the_table[i] = ImGui.InputText(tostring(i), tostring(arg))
            elseif type(arg) == "number" then
               if math.type(arg) == "float" then
                  the_table[i] =
                     ImGui.InputFloat(tostring(i), arg)
               else
                  the_table[i] =
                     ImGui.InputInt(tostring(i), arg)
               end
            elseif type(arg) == "table" then
               ImGui.Text(tostring(i))
               ImGui.SameLine()
               -- For tables, show the minus button before the actual content
               if minus_button() then break end

               M.show_table(name .. i, the_table, i, Vector2f.new(size.x, size.y / 2))
            elseif type(arg) == "boolean" then
               the_table[i] =
                  ImGui.Checkbox(tostring(i), arg)
            else
               ImGui.InputText(tostring(i), "Unsupported type: " .. tostring(arg), ImGuiInputTextFlags.ReadOnly)
            end

            if type(arg) ~= "table" then
               -- For non-tables, show the button on the right
               ImGui.SameLine()
               if minus_button() then break end
            end
         end
      end

      if ImGui.Button("+") then
         ImGui.OpenPopup("Select type##" .. name)

         debug_menu_state.new_argument = { }
         -- If the argument is nil, has no values or is an array, mark it as such
         if not the_table or lume.count(the_table) == 0 or #the_table > 0 then
            debug_menu_state.new_argument.selected_type = "array"
         else
            debug_menu_state.new_argument.selected_type = "table"
            debug_menu_state.new_argument.table_key = ""
         end
      end
      if ImGui.BeginPopup("Select type##" .. name) then
         local inserted_value_type = type(debug_menu_state.new_argument.inserted_value)
         if ImGui.RadioButton("String", inserted_value_type == "string") then
            debug_menu_state.new_argument.inserted_value = ""
         end
         ImGui.SameLine()
         if ImGui.RadioButton("Bool", inserted_value_type == "boolean") then
            debug_menu_state.new_argument.inserted_value = true
         end

         if ImGui.RadioButton(
            "Integer",
            inserted_value_type == "number" and math.type(debug_menu_state.new_argument.inserted_value) == "integer"
         ) then
            debug_menu_state.new_argument.inserted_value = 0
         end
         ImGui.SameLine()
         if ImGui.RadioButton(
            "Float",
            inserted_value_type == "number" and math.type(debug_menu_state.new_argument.inserted_value) == "float"
         ) then
            debug_menu_state.new_argument.inserted_value = 0.0
         end

         if ImGui.RadioButton("Table", inserted_value_type == "table") then
            debug_menu_state.new_argument.inserted_value = {}
         end

         if debug_menu_state.new_argument.inserted_value then
            -- In case the argument table had nothing previosly, allow selecting if it's a table or an array
            if not the_table or lume.count(the_table) == 0  then
               ImGui.Text("Argument container type")
               if ImGui.RadioButton("Array##container_type", debug_menu_state.new_argument.selected_type == "array") then
                  debug_menu_state.new_argument.selected_type = "array"
               end
               ImGui.SameLine()
               if ImGui.RadioButton("Table##container_type", debug_menu_state.new_argument.selected_type == "table") then
                  debug_menu_state.new_argument.selected_type = "table"
                  debug_menu_state.new_argument.table_key = ""
               end
            end
            -- For table key, show the field to input the key
            if debug_menu_state.new_argument.selected_type == "table" then
               debug_menu_state.new_argument.table_key = ImGui.InputText(
                  "Table key",
                  debug_menu_state.new_argument.table_key
               )
            end

            if ImGui.Button("Add") then
               -- In case there were no arguments previosly, create the table
               if not the_table then
                  parent[table_name] = {}
                  the_table = parent[table_name]
               end

               if debug_menu_state.new_argument.selected_type == "array" then
                  table.insert(the_table, debug_menu_state.new_argument.inserted_value)

                  ImGui.CloseCurrentPopup()
               elseif lume.trim(debug_menu_state.new_argument.table_key) ~= "" then
                  the_table[debug_menu_state.new_argument.table_key] =
                     debug_menu_state.new_argument.inserted_value

                  ImGui.CloseCurrentPopup()
               end
            end
         end

         ImGui.EndPopup()
      end
   end
   ImGui.EndChild()
end

local function shader_debug_menu()
   local available_shaders = GLOBAL.available_shaders

   if ImGui.BeginCombo("##add_shader_combo", debug_menu_state.adding_shader.name or "(none)") then
      for name, shader in pairs(available_shaders) do
         if not lume.find(lume.keys(util.rooms_mod()._room_shaders), name)
            and ImGui.Selectable(name, debug_menu_state.adding_shader.name == name)
         then
            debug_menu_state.adding_shader.name = name
         end
      end

      ImGui.EndCombo()
   end

   if ImGui.Button("Add##add_shader") and debug_menu_state.adding_shader.name then
      local name = debug_menu_state.adding_shader.name
      util.rooms_mod()._room_shaders[name] = {}

      -- Run this once to fill in the default values
      M.show_table_typed(name, util.rooms_mod()._room_shaders, name, Vector2f.new(0, 0), available_shaders[name].declared_args)
      -- Set "enabled" to default value
      util.rooms_mod().compile_room_shader_enabled()

      -- Reset the selection
      debug_menu_state.adding_shader.name = nil
   end

   for name, value in pairs(util.rooms_mod()._room_shaders) do
      local height = 0
      for _, val in pairs(available_shaders[name].declared_args) do
         if type(val) == "table" or val == "table" then
            -- Set height to at least 200 when there's a table
            height = 200
         else
            height = height + 50
         end
      end
      height = lume.clamp(height, 0, 500)

      ImGui.Text(name)
      ImGui.SameLine()
      if ImGui.Button("-") then
         util.rooms_mod()._room_shaders[name] = nil

         break
      end

      M.show_table_typed(
         name,
         util.rooms_mod()._room_shaders,
         name,
         Vector2f.new(500, height),
         available_shaders[name].declared_args
      )
   end

   if ImGui.Button("Save##shaders") then
      TOML.save_shaders(util.rooms_mod()._room_shaders)

      util.rooms_mod().compile_room_shader_enabled()
   end
end

local function room_debug_menu()
   local rooms_path = "resources/rooms/"
   local current_room_file = util.rooms_mod().current_room_file
   local current_room_without_room_path = path.splitext(current_room_file):gsub(rooms_path, "")

   local open_new_room_popup
   if ImGui.BeginCombo("Current room", current_room_without_room_path) then
      local exclude_paths = { "assets.toml", "notes.toml", "prefabs" }

      local list_dir
      list_dir = function(dir_path)
         local sorted_dir = lume.array(fs.dir(dir_path))
         table.sort(sorted_dir)

         for _, file in ipairs(sorted_dir) do
            if file == "." or file == ".." or lume.find(exclude_paths, file) then
               goto continue
            end

            local filename_without_ext = path.splitext(file)
            local fullpath = path.join(dir_path, file)

            if fs.isfile(fullpath) then
               local without_room_path = path.splitext(fullpath):gsub(rooms_path, "")

               if ImGui.Selectable(filename_without_ext, current_room_file == fullpath) then
                  -- Switch the room
                  util.rooms_mod().load_room(without_room_path, true)

                  return
               end
            elseif fs.isdir(fullpath) then
               if ImGui.BeginMenu(file, true) then
                  list_dir(fullpath)

                  ImGui.EndMenu()
               end
            end

            ::continue::
         end

         if ImGui.Selectable("New room...", false) then
            debug_menu_state.creating_room = { name = "", dir_path = path.ensure_dir_end(dir_path) }

            -- Workaround for popups not opening from a menu item
            open_new_room_popup = true
         end
      end

      list_dir(rooms_path)

      ImGui.EndCombo()
   end
   if open_new_room_popup then
      ImGui.OpenPopup("Create new room")
   end

   if ImGui.BeginPopupModal("Create new room") then
      ImGui.Text(debug_menu_state.creating_room.dir_path)

      ImGui.SameLine()
      debug_menu_state.creating_room.name =
         ImGui.InputText(".toml", debug_menu_state.creating_room.name)

      local full_path = debug_menu_state.creating_room.dir_path .. debug_menu_state.creating_room.name .. ".toml"
      if ImGui.Button("Create")
         and lume.trim(debug_menu_state.creating_room.name) ~= ""
         and not path.exists(full_path)
      then
         local without_room_path = path.splitext(full_path):gsub(rooms_path, "")
         TOML.create_new_room(full_path)
         util.rooms_mod().load_room(without_room_path, true)

         ImGui.CloseCurrentPopup()
      end
      ImGui.SameLine()
      if ImGui.Button("Cancel") then
         ImGui.CloseCurrentPopup()
      end

      ImGui.EndPopup()
   end

   if ImGui.TreeNode("Shaders") then
      shader_debug_menu()

      ImGui.TreePop()
   end
end

function rooms_debug_menu()
   util.debug_menu_process_state_variable_node("State variables", WalkingModule.state_variables)

   ImGui.Separator()

   room_debug_menu()

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

function M.debug_menu()
   if ImGui.BeginTabBar("Tab bar", ImGuiTabBarFlags.None) then

      if ImGui.BeginTabItem("Rooms") then
         rooms_debug_menu()

         ImGui.EndTabItem()
      end
      if ImGui.BeginTabItem("Assets") then
         assets.debug_menu()

         ImGui.EndTabItem()
      end

      ImGui.EndTabBar()
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

M.declared_callback_arguments = {}
setmetatable(M.declared_callback_arguments, {__mode = "k"})

function M.declare_callback_args(fnc, arg_types, params)
   M.declared_callback_arguments[fnc] = { args = arg_types, params = params }
end

return M
