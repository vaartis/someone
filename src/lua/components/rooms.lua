local toml = require("toml")
local lume = require("lume")
local util = require("util")

local shared_components = require("components.shared")
local player_components = require("components.player")
local interaction_components = require("components.interaction")
local collider_components = require("components.collider")
local debug_components = require("components.debug")
local sound_components = require("components.sound")
local note_components = require("components.note")
local assets = require("components.assets")
local entities = require("components.entities")

local first_puzzle = require("components.first_puzzle")
local dial_puzzle = require("components.dial_puzzle")

local M = {}

-- Loads the room's toml file, processing parent relationships
local function load_room_toml(name)
   local file = io.open("resources/rooms/" .. tostring(name) .. ".toml", "r")
   local room_toml = toml.parse(file:read("*all"))
   file:close()

   -- If there's a prefab/base room, load it
   if room_toml.prefab then
      do
         local prefab = room_toml.prefab
         local prefab_room = load_room_toml(prefab.name)

         if prefab.removed_entities then
            for k, v in pairs(prefab_room.entities) do
               if lume.find(prefab.removed_entities, k) then
                  -- Remove the entity
                  prefab_room.entities[k] = nil
               end
            end
         end

         room_toml = util.deep_merge(prefab_room, room_toml)
      end
      -- Remove the mention of the prefab
      room_toml.prefab = nil
   end

   return room_toml
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
   M.engine = CustomEngine()

   local modules = {
      shared_components,
      player_components,
      interaction_components,
      collider_components,
      sound_components,
      note_components,
      first_puzzle,
      dial_puzzle,
      debug_components
   }

   for _, module in pairs(modules) do module.add_systems(M.engine) end
end

local function load_assets()
   local file = io.open("resources/rooms/assets.toml", "r")
   local l_assets = toml.parse(file:read("*all"))
   file:close()

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

function M.load_room(name)
   M.reset_engine()
   collider_components.reset_world()

   local room_toml = load_room_toml(name)

   if room_toml.shaders then
      _room_shaders = room_toml.shaders
   else
      _room_shaders = {}
   end

   for entity_name, entity in pairs(room_toml.entities) do
      entities.instantiate_entity(entity_name, entity)
   end
end

function M.find_player()
   local pents = M.engine:getEntitiesWithComponent("PlayerMovement")
   local player_key = lume.first(lume.keys(pents))
   if not player_key then
      error("No player entity found")
   end

   return pents[player_key]
end

return M
