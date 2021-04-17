local lume = require("lume")
local path = require("path")
local fs = require("path.fs")

local util = require("util")

local M = {}

local toml_data = nil

local known_assets = {
  textures = {},
  sounds = {}
}

M.assets = {
  textures = {},
  sounds = {}
}

M.placeholder_texture = Texture.new()
M.placeholder_texture:load_from_file("resources/sprites/room/placeholder.png")

local function add_to_known_assets(asset_type, key, path)
   known_assets[asset_type][key] = path
end

local function load_from_known_assets(asset_type, key)
   local maybe_known_asset_path = known_assets[asset_type][key]
   if not maybe_known_asset_path then
      return nil
   end

   local asset
   if asset_type == "textures" then
      asset = Texture.new()
   elseif asset_type == "sounds" then
      asset = SoundBuffer.new()
   else
      error("Unknown asset type: " .. tostring(asset_type))
   end

   asset:load_from_file(maybe_known_asset_path)
   M.assets[asset_type][key] = asset

   return asset
end

function M.list_known_assets(asset_type)
   return lume.keys(known_assets[asset_type])
end


setmetatable(M.assets.textures, {
  __index = function(_, key)
    return load_from_known_assets("textures", key)
  end
})
setmetatable(M.assets.sounds, {
  __index = function(_, key)
    return load_from_known_assets("sounds", key)
  end
})

M.used_assets = {}
-- Mark table keys as weak, so they don't prevent GC
setmetatable(M.used_assets, {__mode = "k"})

function M.create_sound_from_asset(asset_name)
   local sound = Sound.new()
   sound.buffer = M.assets.sounds[asset_name]

   M.used_assets[sound] = asset_name

   return sound
end

function M.create_sprite_from_asset(asset_name)
   local drawable = Sprite.new()
   if asset_name ~= "placeholder" then
      drawable.texture = M.assets.textures[asset_name]
   else
      drawable.texture = M.placeholder_texture
   end

   M.used_assets[drawable] = asset_name

   return drawable
end

local debug_menu_state = {
   textures = { selected = 1, search = "",
                select_path_search = "", selected_dir = nil, selected_path = nil },
   sounds = { selected = 1, search = "",
              select_path_search = "" }
}

function M.debug_menu()
   local function list_toml_assets(key)
      local key_debug_menu = debug_menu_state[key]

      local function select_asset_file_popup()
         if ImGui.BeginPopupModal("Select asset file##" .. key) then
            ImGui.Text(key_debug_menu.selected_dir)

            local sorted_dir = lume.array(fs.dir(key_debug_menu.selected_dir))
            if key_debug_menu.selected_dir == "resources" then
               lume.remove(sorted_dir, "..")
            end
            lume.remove(sorted_dir, ".")

            table.sort(sorted_dir)
            for k, v in ipairs(sorted_dir) do
               local fullpath = path.join(key_debug_menu.selected_dir, v)

               if fs.isdir(fullpath) then
                  sorted_dir[k] = path.ensure_dir_end(v)
               end
            end

            key_debug_menu.select_path_search = ImGui.InputText("Search##path_" .. key, key_debug_menu.select_path_search)

            sorted_dir = lume.filter(sorted_dir, function (k) return k:match(key_debug_menu.select_path_search) end)

            ImGui.SetNextItemWidth(300)
            local new_selected, changed = ImGui.ListBox("", -1, sorted_dir)
            if changed then
               -- Normalize in case the path includes ..
               local fullpath = path.normalize(
                  path.join(
                     key_debug_menu.selected_dir, sorted_dir[new_selected + 1]
                  )
               )

               if fs.isdir(fullpath) then
                  key_debug_menu.selected_dir = fullpath
               else
                  -- Clear the search string
                  key_debug_menu.select_path_search = ""

                  key_debug_menu.selected_path = fullpath

                  ImGui.CloseCurrentPopup()
               end
            end

            ImGui.EndPopup()
         end
      end

      local key_assets = toml_data[key]

      key_debug_menu.search = ImGui.InputText("Search##" .. key, key_debug_menu.search)

      local keys = lume.keys(key_assets)
      table.sort(keys)
      keys = lume.filter(keys, function (k) return k:match(key_debug_menu.search) end)

      ImGui.SetNextItemWidth(250)
      local new_selected, changed = ImGui.ListBox(key, key_debug_menu.selected - 1, keys)
      if changed then
         key_debug_menu.selected = new_selected + 1
      end
      if ImGui.Button("Edit##" .. key) then
         local k = keys[key_debug_menu.selected]
         key_debug_menu.editing_asset = {
            name = k,
            new_name = k,
            path = key_assets[k]
         }

         ImGui.OpenPopup("Edit " .. key)
      end
      ImGui.SameLine()
      if ImGui.Button("New##" .. key) then
         key_debug_menu.editing_asset = {
            new_name = ""
         }

         ImGui.OpenPopup("Edit " .. key)
      end

      if ImGui.BeginPopupModal("Edit " .. key) then
         local key_debug_menu = key_debug_menu
         local editing_asset = key_debug_menu.editing_asset

         editing_asset.new_name = ImGui.InputText("Name", editing_asset.new_name)
         if ImGui.Button(editing_asset.path or "None") then
            key_debug_menu.selected_dir = path.dirname(
               path.join(M.resources_root(), toml_data.config[key].root, editing_asset.path)
            )

            ImGui.OpenPopup("Select asset file##" .. key)
         end
         select_asset_file_popup()
         if key_debug_menu.selected_path then
            local new_path = key_debug_menu.selected_path
            key_debug_menu.selected_path = nil

            new_path = new_path:gsub(path.join(M.resources_root(), toml_data.config[key].root), "")
            editing_asset.path = new_path
         end

         ImGui.Separator()

         local function save_and_update_used_asset()
            TOML.save_asset(
               toml_data, key,
               editing_asset.name, editing_asset.new_name, editing_asset.path
            )

            -- Delete the old asset, if there was one
            if editing_asset.name then
               M.assets[key][editing_asset.name] = nil
            end
            if editing_asset.new_name then
               -- Put the new asset in its place, if there is one
               add_to_known_assets(
                  key,
                  editing_asset.new_name,
                  path.join(M.resources_root(), toml_data.config[key].root, editing_asset.path)
               )
            end
            -- Go through all the used assets and replace the old ones with the new ones
            for obj, asset_name in pairs(M.used_assets) do
               if asset_name == editing_asset.name then
                  local updated_field
                  local updated_value = M.assets[key][editing_asset.new_name]
                  if key == "textures" and obj.__type.name == "sf::Sprite" then
                     updated_field = "texture"

                     if not editing_asset.new_name then
                        updated_value = M.placeholder_texture
                     end
                  elseif key == "sounds" and obj.__type.name == "sf::Sound" then
                     updated_field = "buffer"
                  end

                  -- Put the new asset into the object
                  obj[updated_field] = updated_value
                  -- Update the used assets entry
                  M.used_assets[obj] = editing_asset.new_name
               end
            end

            toml_data = TOML.parse("resources/rooms/assets.toml")
         end

         if ImGui.Button("Save") then
            if lume.trim(editing_asset.new_name) ~= "" and editing_asset.path then
               save_and_update_used_asset()

               ImGui.CloseCurrentPopup()
            end
         end
         ImGui.SameLine()
         if ImGui.Button("Cancel") then ImGui.CloseCurrentPopup() end

         if editing_asset.name then
            ImGui.SameLine(0, 100)
            if ImGui.Button("Delete") then
               editing_asset.new_name = nil
               -- Mark new_name as nil to delete the asset
               editing_asset.new_name = nil
               save_and_update_used_asset()

               ImGui.CloseCurrentPopup()
            end
         end

         ImGui.EndPopup()
      end
   end


   list_toml_assets("textures")
   ImGui.Separator()
   list_toml_assets("sounds")
end

function M.resources_root()
   if not _G.mod then
      return "resources"
   else
      return "resources/mods/" .. getmetatable(_G.mod).name .. "/resources"
   end
end

function M.load_assets()
   local resources_root = M.resources_root()

   local l_assets, err = TOML.parse(path.join(resources_root, "rooms/assets.toml"))
   if err then
      error(err)
   end

   toml_data = l_assets

   local asset_types = {
      { name = "textures", default_root = "sprites/"},
      { name = "sounds", default_root = "sounds/"}
   }

   for _, asset_type in ipairs(asset_types) do
      if l_assets[asset_type.name] then
         -- Actual root is determined by the value of resources_root,
         -- under which all resources reside, plus the value of per-resource
         -- root
         local root = path.join(
            resources_root,
            util.get_or_default(
               l_assets,
               {"config", asset_type.name, "root"},
               asset_type.default_root
            )
         )

         for name, asset_path in pairs(l_assets[asset_type.name]) do
            -- Prefix asset name with "mod." for mods
            if _G.mod then
               name = "mod." .. name
            end

            add_to_known_assets(asset_type.name, name, path.join(root, asset_path))
         end
      end
   end
end

function M.unload_known_mod_assets()
   for cat_name, category in pairs(known_assets) do
      for asset_name, _ in pairs(category) do
         -- Clear references to mod assets
         if asset_name:match("^mod%.(.*)") then
            category[asset_name] = nil
            rawset(M.assets[cat_name], asset_name, nil)
         end
      end
   end
end

return M
