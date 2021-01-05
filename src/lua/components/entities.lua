local util = require("util")
local lume = require("lume")

local shared_components = require("components.shared")
local collider_components = require("components.collider")

local M = {}

-- Load all components modules and save them
M.all_components = {}
do
   local loaded_rockspec = {}
   local chunk, err = loadfile(
      "resources/lua/lib/luarocks/rocks-5.3/someone/0.1-0/someone-0.1-0.rockspec",
      "t",
      loaded_rockspec
   )
   if err then error(err) end
   chunk()

   local excluded_components = {"assets", "entities", "rooms"}
   for name, _ in pairs(loaded_rockspec.build.install.lua) do
      local maybe_matched = name:match("^components%.(.*)")
      if maybe_matched and not lume.find(excluded_components, maybe_matched) then
         local required = require(name)
         setmetatable(required, {__module_name = name})
         table.insert(M.all_components, required)
      end
   end

   table.sort(
      M.all_components,
      function(a, b)
         return (a.system_run_priority or math.huge) < (b.system_run_priority or math.huge)
      end
   )
end


local function load_prefab(prefab_name_or_conf, base_data)
   local prefab_name, removed_components
   -- Allow prefab to either be just a name or a table with more info
   local typ = type(prefab_name_or_conf)
   if typ == "table" then
      prefab_name = prefab_name_or_conf.name
      removed_components = prefab_name_or_conf.removed_components
   elseif typ == "string" then
      prefab_name = prefab_name_or_conf
   end

   local prefab_data, prefab_err = TOML.parse("resources/rooms/prefabs/" .. tostring(prefab_name) .. ".toml")
   if not prefab_data then
      error("Error loading prefab:\n" .. prefab_err)
   end

   -- Load prefabs recursively if needed
   if prefab_data.prefab then
      prefab_data = load_prefab(prefab_data.prefab, prefab_data)
   end

   local new_metatable
   if getmetatable(base_data) then
      new_metatable = util.deep_merge(getmetatable(prefab_data), getmetatable(base_data))
   else
      new_metatable = getmetatable(prefab_data)
   end

   base_data = util.deep_merge(prefab_data, base_data)
   setmetatable(base_data, new_metatable)

   -- Clear the components requested by removed_components
   if removed_components then
      for _, name_to_remove in pairs(removed_components) do
         base_data[name_to_remove] = nil
      end
   end

   -- Remove the mention of the prefab from the entity
   base_data.prefab = nil

   return base_data
end

-- This is used to create components for tags. When a tag is encountered for the first time,
-- a component class is created for it. It is reused when the same tag name is used again.
local tag_classes = {}
local function make_tag(name)
   if not tag_classes[name] then
      local class_name = tostring(name) .. "Tag"
      tag_classes[name] = Component.create(class_name)
   end

   return tag_classes[name]
end

function M.instantiate_entity(entity_name, entity, parent)
   local new_ent = Entity(parent)

   if entity.prefab then entity = load_prefab(entity.prefab, entity) end

   local entity_components = {}
   for comp_name, comp in pairs(entity) do
      -- Find a processor in the modules
      local comp_processor
      for _, processor in pairs(M.all_components) do
         if processor.components then
            if processor.components[comp_name] then
               comp_processor = processor.components[comp_name]
               break
            end
         end
      end
      if not comp_processor then
         if comp_name == "tags" then
            comp_processor = {
               process_component = function(new_ent, comp, entity_name)
                  for _, tag in pairs(comp) do
                     -- Add a tag component for each tag
                     new_ent:add(make_tag(tag)())
                  end
               end
            }
         elseif comp_name == "children" then
            comp_processor = {
               -- Do nothing
               process_component = function() end
            }
         else
            error("Unknown component: " .. tostring(comp_name) .. " on " .. tostring(entity_name))
         end
      end

      table.insert(entity_components, { name = comp_name, comp = comp, processor = comp_processor })
   end
   -- Sort components by processing priority
   table.sort(
      entity_components,
      function(a, b)
         return (a.processor.processing_priority or 0) < (b.processor.processing_priority or 0)
      end
   )

   for _, comp_data in ipairs(entity_components) do
      local comp_name, comp, processor = comp_data.name, comp_data.comp, comp_data.processor

      if comp_name == "transformable" then
         -- Pass parent to transformable processing
         processor.process_component(new_ent, comp, entity_name, parent)
      else
         processor.process_component(new_ent, comp, entity_name)
      end
   end

   util.rooms_mod().engine:addEntity(new_ent)
   if entity.children then
      for name, data in pairs(entity.children) do
         M.instantiate_entity(name, data, new_ent)
      end
   end

   new_ent:add(shared_components.components.name.class(entity_name))

   if getmetatable(entity) then
      new_ent.__toml_location = getmetatable(entity)["toml_location"]
   end

   return new_ent
end

return M
