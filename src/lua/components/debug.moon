lovetoys = require("lovetoys")

DebugColliderDrawingSystem = _G.class("DebugColliderDrawingSystem", System)
DebugColliderDrawingSystem.requires = () => {"Collider"}
DebugColliderDrawingSystem.draw = () =>
  for _, entity in pairs @targets
    physics_world = entity\get("Collider").physics_world

    x, y, w, h = physics_world\getRect(entity)
    shape = RectangleShape.new(Vector2f.new(w, h))
    shape.outline_thickness = 1.0
    shape.outline_color = Color.Red
    shape.fill_color = Color.new(0, 0, 0, 0)
    shape.position = Vector2f.new(x, y)
    GLOBAL.drawing_target\draw(shape)

add_systems = (engine) ->
  with engine
    --\addSystem(DebugColliderDrawingSystem())
    -- To have something if other things are commented out
    nil

{
  :DebugColliderDrawingSystem,
  :add_systems
}
