local util = require("util")
local lume = require("lume")
local interaction_components

local M = {}

local RotationComponent = Component.create("Rotation", { "rotation_speed" })
local RotationSystem = class("RotationSystem", System)
function RotationSystem:requires()
   return { "Transformable", "Drawable", "Rotation" }
end
function RotationSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local tf = entity:get("Transformable").transformable
      local enabled = entity:get("Drawable").enabled
      local rotation = entity:get("Rotation")

      tf.rotation = tf.rotation + rotation.rotation_speed
   end
end

local LookCloserSystem = class("LookCloserSystem", System)
function LookCloserSystem:requires()
   return { "LookCloserImageTag" }
end

function LookCloserSystem:update(dt)
   -- There can only be one on the screen at a time
   for _, entity in pairs(self.targets) do
      local engine = util.rooms_mod().engine

      -- Lazy-load interaction_components
      if not interaction_components then
         interaction_components = require("components.interaction")
      end

      -- Keep the interaction and movement system disabled
      interaction_components.disable_player(engine)
      interaction_components.update_seconds_since_last_interaction(dt)

      local interaction_text_drawable = util.first(engine:getEntitiesWithComponent("InteractionTextTag")):get("Drawable")
      if not interaction_text_drawable.enabled then
         interaction_text_drawable.enabled = true
         interaction_text_drawable.drawable.string = "[E] to close"
      end

      interaction_components.if_key_pressed({
            [KeyboardKey.E] = function()
               -- Delete the entity and re-enable interactions and movement
               engine:removeEntity(entity, true)
               interaction_components.enable_player(engine)
            end
      })
   end
end

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "rotation" then
      new_ent:add(
         RotationComponent(comp.rotation_speed)
      )

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(RotationSystem())
   engine:addSystem(LookCloserSystem())
end

M.interaction_callbacks = {}
function M.interaction_callbacks.look(_current_state, direction)
   local entities = util.entities_mod()

   entities.instantiate_entity(
      "look_" .. direction,
      {
         prefab = "walkway/look_" .. direction
      }
   )
end

return M
