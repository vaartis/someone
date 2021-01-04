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

M.components = { rotation = {} }

function M.components.rotation.process_component(new_ent, comp, entity_name)
   new_ent:add(RotationComponent(comp.rotation_speed))
end

function M.add_systems(engine)
   engine:addSystem(RotationSystem())
end

return M
