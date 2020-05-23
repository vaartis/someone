toml = require("toml")
lume = require("lume")
util = require("util")
  
shared_components = require("components.shared")
player_components = require("components.player")
interaction_components = require("components.interaction")
collider_components = require("components.collider")
debug_components = require("components.debug")
sound_components = require("components.sound")
note_components = require("components.note")
assets = require("components.assets")
entities = require("components.entities")  

first_puzzle = require("components.first_puzzle")
dial_puzzle = require("components.dial_puzzle")

M = {}

-- Loads the room's toml file, processing parent relationships
load_room_toml = (name) ->
  local room_toml
  with io.open("resources/rooms/#{name}.toml", "r")
    room_toml = toml.parse(\read("*all"))
    \close()

  -- If there's a prefab/base room, load it
  if room_toml.prefab
    with room_toml.prefab
        prefab_room = load_room_toml(.name)

        if .removed_entities
          for k, v in pairs(prefab_room.entities)
            if lume.find(.removed_entities, k)
              -- Remove the entity
              prefab_room.entities[k] = nil

        room_toml = util.deep_merge(prefab_room, room_toml)
    -- Remove the mention of the prefab
    room_toml.prefab = nil

  room_toml

load_prefab = (prefab_name_or_conf, base_data) ->
  local prefab_name, removed_components
  -- Allow prefab to either be just a name or a table with more info
  switch type(prefab_name_or_conf)
    when "table"
      prefab_name = prefab_name_or_conf.name
      removed_components = prefab_name_or_conf.removed_components
    when "string"
      prefab_name = prefab_name_or_conf

  prefab_data = do
    local data
    with io.open("resources/rooms/prefabs/#{prefab_name}.toml", "r")
      data = toml.parse(\read("*all"))
      \close()
    data

  base_data = util.deep_merge(prefab_data, base_data)

  -- Clear the components requested by removed_components
  if removed_components
    for _, name_to_remove in pairs removed_components
      base_data[name_to_remove] = nil

  -- Remove the mention of the prefab from the entity
  base_data.prefab = nil

  base_data

CustomEngine = _G.class("CustomEgine", Engine)
CustomEngine.draw = (layer) =>
  for _, system in ipairs(@systems["draw"]) do
    if system.active then
        system\draw(layer)
CustomEngine.stopSystem = (name) =>
  CustomEngine.super.stopSystem(self, name)
  system = @systemRegistry[name]
  if system and system.onStopSystem then system\onStopSystem!
    
reset_engine = () ->
  M.engine = CustomEngine()

  modules = {
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
  for _, module in pairs modules do
    module.add_systems(M.engine)

load_assets = () ->
  local l_assets
  with io.open("resources/rooms/assets.toml", "r")
    l_assets = toml.parse(\read("*all"))
    \close()

  if l_textures = l_assets.textures
    for name, path in pairs l_textures
      assets.add_to_known_assets("textures", name, path)

  if l_sounds = l_assets.sounds
    for name, path in pairs l_sounds
      assets.add_to_known_assets("sounds", name, path)

-- Load the assets.toml file
load_assets!

_room_shaders = {}
M.room_shaders = () -> _room_shaders

M.load_room = (name) ->
  reset_engine!
  collider_components.reset_world!

  room_toml = load_room_toml(name)

  if room_toml.shaders
      _room_shaders = room_toml.shaders
  else
    _room_shaders = {}

  for entity_name, entity in pairs room_toml.entities
    entities.instantiate_entity(entity_name, entity)

M.find_player = () ->
  pents = M.engine\getEntitiesWithComponent("PlayerMovement")
  player_key = lume.first(lume.keys(pents))
  if not player_key then error("No player entity found")

  pents[player_key]
      
return M
