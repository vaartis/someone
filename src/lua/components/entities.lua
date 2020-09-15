local toml = require("toml")
local util = require("util")

local shared_components = require("components.shared")
local player_components = require("components.player")
local collider_components = require("components.collider")
local note_components = require("components.note")
local interaction_components
local sound_components = require("components.sound")

local first_puzzle = require("components.first_puzzle")
local dial_puzzle = require("components.dial_puzzle")
local passage = require("components.passage")

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

   local file = io.open("resources/rooms/prefabs/" .. tostring(prefab_name) .. ".toml", "r")
   local prefab_data = toml.parse(file:read("*all"))
   file:close()

   base_data = util.deep_merge(prefab_data, base_data)

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

local M = {}

local NameComponent = Component.create("Name", {"name"})

function M.instantiate_entity(entity_name, entity, parent)
   -- Has to be required from here to avoid recursive dependency
   if not interaction_components then
      interaction_components = require("components.interaction")
   end

   local new_ent = Entity(parent)

   if entity.prefab then entity = load_prefab(entity.prefab, entity) end

   local add_transformable_actions = {}
   local add_collider_actions = {}

   for comp_name, comp in pairs(entity) do
      if comp_name == "transformable"  then
         table.insert(
            add_transformable_actions,
            function()
               if not (new_ent:has("Transformable")) then
                  -- If there's no transformable component, create and add it
                  new_ent:add(shared_components.TransformableComponent(Transformable.new()))
               end
               local tf_component = new_ent:get("Transformable")

               local transformable = tf_component.transformable
               if parent then
                  local parent_tf = parent:get("Transformable").transformable
                  local relative_position = Vector2f.new(comp.position[1], comp.position[2])
                  -- Apply the position in relation to the parent position
                  transformable.position = parent_tf.position + relative_position

                  tf_component.local_position = relative_position
               else
                  transformable.position = Vector2f.new(comp.position[1], comp.position[2])

                  tf_component.local_position = Vector2f.new(0, 0)
               end

               if comp.origin then transformable.origin = Vector2f.new(comp.origin[1], comp.origin[2]) end
               if comp.scale then transformable.scale = Vector2f.new(comp.scale[1], comp.scale[2]) end
            end
         )
      elseif comp_name == "collider" then
         table.insert(
            add_collider_actions,
            function() collider_components.process_collider_component(new_ent, comp, entity_name) end
         )
      elseif comp_name == "tags" then
         for _, tag in pairs(comp) do
            -- Add a tag component for each tag
            new_ent:add(make_tag(tag)())
         end
      elseif comp_name == "children" then
         goto continue
      else
         local component_processors = {
            shared_components,
            player_components,
            interaction_components,
            sound_components,
            passage,
            note_components,
            first_puzzle,
            dial_puzzle
         }
         local processed = false
         for _, processor in pairs(component_processors) do
            if processor.process_components(new_ent, comp_name, comp, entity_name) then
               processed = true
               break
            end
         end
         if not processed then
            error("Unknown component: " .. tostring(comp_name) .. " on " .. tostring(entity_name))
         end
      end

      ::continue::
   end

   -- Call all the "after all inserted" actions
   for _, actions in ipairs({add_transformable_actions,add_collider_actions}) do
      for _, action in pairs(actions) do action() end
   end

   util.rooms_mod().engine:addEntity(new_ent)
   if entity.children then
      for name, data in pairs(entity.children) do
         M.instantiate_entity(name, data, new_ent)
      end
   end

   new_ent:add(NameComponent(entity_name))

   return new_ent
end

return M
