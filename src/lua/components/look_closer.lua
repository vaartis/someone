local util = require("util")

local interaction_components
local debug_components = require("components.debug")

local M = {}

M.components = {
   look_closer_image = {
      class = Component.create("LookCloserImage", {"on_close_callback"})
   }
}

function M.components.look_closer_image.process_component(new_ent, comp, entity_name)
   local maybe_callback
   if comp.on_close_callback then
      -- Lazy-load interaction_components
      if not interaction_components then
         interaction_components = require("components.interaction")
      end

      maybe_callback = interaction_components.process_interaction(
         comp,
         "on_close_callback",
         { entity_name = entity_name, comp_name = "look_closer_image", needed_for = "on_close_callback", entity = new_ent }
      )
   end

   new_ent:add(M.components.look_closer_image.class(maybe_callback))
end

local LookCloserSystem = class("LookCloserSystem", System)
function LookCloserSystem:requires()
   return { "LookCloserImage" }
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
               local look_closer_comp = entity:get("LookCloserImage")
               if look_closer_comp.on_close_callback then
                  look_closer_comp.on_close_callback()
               end

               -- Delete the entity and re-enable interactions and movement
               engine:removeEntity(entity, true)
               interaction_components.enable_player(engine)
            end
      })
   end
end

M.systems = {
   LookCloserSystem
}

M.interaction_callbacks = {}
function M.interaction_callbacks.look(_current_state, args)
   local entities = util.entities_mod()

   entities.instantiate_entity(
      "look_closer",
      {
         prefab = args.prefab
      }
   )
end
debug_components.declare_callback_args(
   M.interaction_callbacks.look,
   {prefab = "string"}
)


return M
