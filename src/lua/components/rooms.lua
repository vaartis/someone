local lume = require("lume")
local util = require("util")

local interaction_components = require("components.interaction")
local collider_components = require("components.collider")
local assets = require("components.assets")
local entities = require("components.entities")

local M = {}

function M.to_full_room_file(name)
   local without_extension = "resources/rooms/" .. name

   local lua_path = without_extension .. ".lua"
   local file = io.open(lua_path, "r")
   if file then
      file:close()
      return lua_path, "lua"
   end

   local toml_path = without_extension .. ".toml"
   file = io.open(toml_path, "r")
   if file then
      file:close()
      return toml_path, "toml"
   end
end

-- Loads the room's toml file, processing parent relationships
local function load_room_file(name)
   local path, file_type = M.to_full_room_file(name)

   local room_table

   local file = io.open(path, "r")
   if file_type == "lua" then
      local contents = file:read("*all")

      local loaded, err = load(contents, path)
      if err then error(err) end
      room_table = loaded()
   else
      room_table = TOML.parse(path)
   end

   file:close()

   -- If there's a prefab/base room, load it
   if room_table.prefab then
      do
         local prefab = room_table.prefab
         local prefab_room = load_room_file(prefab.name)

         if prefab.removed_entities then
            for k, v in pairs(prefab_room.entities) do
               if lume.find(prefab.removed_entities, k) then
                  -- Remove the entity
                  prefab_room.entities[k] = nil
               end
            end
         end

         room_table = util.deep_merge(prefab_room, room_table)
      end
      -- Remove the mention of the prefab
      room_table.prefab = nil
   end

   return room_table
end

local CustomEngine = class("CustomEgine", Engine)
function CustomEngine:draw(layer)
   for _, system in ipairs(self.systems["draw"]) do
      if system.active then system:draw(layer) end
   end
end
function CustomEngine:stopSystem(name)
   CustomEngine.super.stopSystem(self, name)
   local system = self.systemRegistry[name]
   if system and system.onStopSystem then system:onStopSystem() end
end

function M.reset_engine()
   if M.engine then
      for _, system in pairs(M.engine.systemRegistry) do
         if system.onBeforeResetEngine then
            -- Give the systems a chance to clean up before the engine is reset
            system:onBeforeResetEngine()
         end
      end
   end

   M.engine = CustomEngine()

   for _, module in pairs(entities.all_components) do
      if module.add_systems then
         module.add_systems(M.engine)
      end
   end
end

local function load_assets()
   local l_assets = TOML.parse("resources/rooms/assets.toml")

   if l_assets.textures then
      for name, path in pairs(l_assets.textures) do
         assets.add_to_known_assets("textures", name, path)
      end
   end

   if l_assets.sounds then
      for name, path in pairs(l_assets.sounds) do
         assets.add_to_known_assets("sounds", name, path)
      end
   end
end

-- Load the assets.toml file
load_assets()

local _room_shaders = {}
function M.room_shaders() return _room_shaders end

function M.load_room(name, switch_namespace)
   M.reset_engine()
   collider_components.reset_world()

   if switch_namespace then
      -- If switch_namespace is passed, use the room's namespace as the "current" one

      -- Find the last /
      local last = name:find("/[^/]+$")
      -- Use everything that is before it
      M.current_namespace = name:sub(1, last - 1)
   end

   local room_toml = load_room_file(name)

   if room_toml.shaders then
      _room_shaders = room_toml.shaders
      for _, shader in pairs(_room_shaders) do
         shader.enabled = interaction_components.process_activatable(
            shader,
            "enabled",
            { entity_name = "rooms", comp_name = "load_room", needed_for = "shader enabled" }
         )
      end
   else
      _room_shaders = {}
   end

   for entity_name, entity in pairs(room_toml.entities) do
      local entity_location = getmetatable(room_toml)["toml_location"]["entities"][entity_name]

      setmetatable(entity, { toml_location = entity_location })

      entities.instantiate_entity(entity_name, entity)
   end
end

function M.find_player()
   local player = util.first(M.engine:getEntitiesWithComponent("PlayerMovement"))
   if not player then
      error("No player entity found")
   end

   return player
end

return M
