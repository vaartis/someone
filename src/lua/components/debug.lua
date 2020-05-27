local DebugColliderDrawingSystem = class("DebugColliderDrawingSystem", System)
function DebugColliderDrawingSystem:requires() return { "Collider" } end
function DebugColliderDrawingSystem:draw()
   for _, entity in pairs(self.targets) do
      local physics_world = entity:get("Collider").physics_world

      local x, y, w, h = physics_world:getRect(entity)
      local shape = RectangleShape.new(Vector2f.new(w, h))
      shape.outline_thickness = 1.0
      shape.outline_color = Color.Red
      shape.fill_color = Color.new(0, 0, 0, 0)
      shape.position = Vector2f.new(x, y)
      GLOBAL.drawing_target:draw(shape)
   end
end

local M = {}

function M.add_systems(engine)
   -- engine:addSystem(DebugColliderDrawingSystem())
end

return M
