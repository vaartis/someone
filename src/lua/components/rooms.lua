local lume = require("lume")
local util = require("util")

local interaction_components = require("components.interaction")
local collider_components = require("components.collider")
local assets = require("components.assets")
local entities = require("components.entities")

local M = {}

-- Loads the room's toml file, processing parent relationships
function M.load_room_file(name)
   local path_root
   if _G.mod then
      path_root = lume.format("resources/mods/{1}/resources/rooms/", {getmetatable(_G.mod).name})
   else
      path_root = "resources/rooms/"
   end

   local path = path_root .. name .. ".toml"

   local room_table, err = TOML.parse(path)
   if not room_table then
      error(err)
   end

   -- If there's a prefab/base room, load it
   if room_table.prefab then
      do
         local prefab = room_table.prefab
         local prefab_room = M.load_room_file(prefab.name)

         if prefab.removed_entities then
            for k, v in pairs(prefab_room.entities) do
               if lume.find(prefab.removed_entities, k) then
                  -- Remove the entity
                  prefab_room.entities[k] = nil
               end
            end
         end

         local base_meta, prefab_meta = getmetatable(room_table), getmetatable(prefab_room)
         room_table = util.deep_merge(prefab_room, room_table)

         setmetatable(room_table, util.deep_merge(prefab_meta, base_meta))
      end
      -- Remove the mention of the prefab
      room_table.prefab = nil
   end

   return room_table, path
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
      if module.systems then
         for _, sys_class in ipairs(module.systems) do
            M.engine:addSystem(sys_class())
         end
      end
   end
end

-- Load the assets.toml file
assets.load_assets()

M._room_shaders = {}
function M.room_shaders() return M._room_shaders or {} end

function M.compile_room_shader_enabled()
   if M._room_shaders then
      for name, shader in pairs(M._room_shaders) do
         local meta = {}
         for name, value in pairs(shader) do
            -- This is a function description
            if type(value) == "table" and value["module"] and value["name"] then
               local processor
               if name == "enabled" then
                  processor = interaction_components.process_activatable
               else
                  processor = interaction_components.process_interaction
               end

               meta[name .. "_compiled"] = processor(
                  shader,
                  name,
                  { entity_name = "rooms", comp_name = "load_room", needed_for = "shader " .. name }
               )
            end
         end

         setmetatable(M._room_shaders[name], meta)
      end
   end
end

function M.load_room(name, switch_namespace)
   M.reset_engine()
   collider_components.reset_world()

   -- Find the last /
   local last = name:find("/[^/]+$") or 0
   if switch_namespace then
      -- If switch_namespace is passed, use the room's namespace as the "current" one
      -- Use everything that is before it
      M.current_namespace = name:sub(1, last - 1)
   end
   -- Save the name of the room without a namespace
   M.current_unqualified_room_name = name:sub(last + 1, #name)

   local room_toml, room_file_path = M.load_room_file(name)
   -- Save the current file path, when the editor wants to save a new entity
   M.current_room_file = room_file_path

   if room_toml.shaders then
      M._room_shaders = room_toml.shaders
      setmetatable(M._room_shaders, {toml_location = getmetatable(room_toml)["toml_location"]["shaders"] })

      M.compile_room_shader_enabled()
   else
      M._room_shaders = {}
   end

   if room_toml.entities then
      for entity_name, entity in pairs(room_toml.entities) do
         local entity_location = getmetatable(room_toml)["toml_location"]["entities"][entity_name]

         setmetatable(entity, { toml_location = entity_location })

         entities.instantiate_entity(entity_name, entity)
      end
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
