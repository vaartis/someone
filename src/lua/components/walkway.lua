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
end

return M
