local lume = require("lume")

local collider_components = require("components.collider")
local util = require("util")
local coroutines = require("coroutines")
local terminal = require("terminal")

local M = {}

local x_movement_speed = 8

local ball_speed = 7
local direction = Vector2f.new(1, 1)

local ArkanoidPadSystem = class("ArkanoidPadSystem", System)
function ArkanoidPadSystem:requires() return { "ArkanoidPadTag" } end
function ArkanoidPadSystem:update()
   for _, entity in pairs(self.targets) do
      local tf = entity:get("Transformable")
      local physics_world = collider_components.physics_world

      local pos_diff
      if Keyboard.is_key_pressed(KeyboardKey.D) then
         pos_diff = Vector2f.new(x_movement_speed, 0.0)
      elseif Keyboard.is_key_pressed(KeyboardKey.A) then
         pos_diff = Vector2f.new(-x_movement_speed, 0.0)
      elseif Keyboard.is_key_pressed(KeyboardKey.Z) and Keyboard.is_key_pressed(KeyboardKey.LControl) then
         coroutines.create_coroutine(
            coroutines.black_screen_out,
            function()
               GLOBAL.set_current_state(CurrentState.Terminal)
            end,
            function()
               -- Reset ball movement direction
               direction = Vector2f.new(1, 1)

               terminal.active = true
            end
         )
      end

      if pos_diff then
         local x, y = physics_world:getRect(entity)
         local expected_new_pos = Vector2f.new(x, y) + pos_diff

         local _, _, cols, col_count = physics_world:check(
            entity, expected_new_pos.x, expected_new_pos.y,
            function(item, other) if other:get("Collider").trigger then return "cross" else return "slide" end end
         )
         if col_count == 0 or not lume.any(cols, function(c) return c.type == "slide" end) then
            physics_world:update(entity, expected_new_pos.x, expected_new_pos.y)
         end
      end
   end
end

local ArkanoidBallSystem = class("ArkanoidBallSystem", System)
function ArkanoidBallSystem:requires() return { ball = { "ArkanoidBallTag" }, score = { "ArkanoidScoreTag" } } end
function ArkanoidBallSystem:update()
   for _, entity in pairs(self.targets.ball) do
      local tf = entity:get("Transformable")
      local physics_world = collider_components.physics_world
      local arkanoid_data = entity:get("ArkanoidData")

      local x, y = physics_world:getRect(entity)
      local expected_new_pos = Vector2f.new(x, y) + (direction * ball_speed)

      local _, _, cols, len = physics_world:move(
         entity, expected_new_pos.x, expected_new_pos.y,
         function(item, other) return "bounce" end
      )
      if len > 0 then
         local touch = Vector2f.new(cols[1].touch.x, cols[1].touch.y)
         local bounce = Vector2f.new(cols[1].bounce.x, cols[1].bounce.y)
         direction = bounce - touch

         local magnitude = math.sqrt(math.pow(direction.x, 2) + math.pow(direction.y, 2))
         -- Normalize the direction vector
         direction = direction / magnitude

         if cols[1].other:get("ArkanoidBlockTag") then
            util.rooms_mod().engine:removeEntity(cols[1].other)
            arkanoid_data.score = arkanoid_data.score + 10

            for _, score in pairs(self.targets.score) do
               score:get("Drawable").drawable.string = "Score: " .. tostring(arkanoid_data.score)
            end
         end
      end

      local screen_size = GLOBAL.drawing_target.size
      if x > screen_size.x or y > screen_size.y then
         physics_world:update(entity, 640, 480)
         direction = Vector2f.new(1, 1)
      end


      if not arkanoid_data.started then
         arkanoid_data.started = true

         local template_x, template_y = 10, 50
         while template_y < 300 do
            local template = {
               tags = { "ArkanoidBlock" },
               drawable = { kind = "sprite", texture_asset = "mod.block", z = 1 },
               collider = { mode = "sprite" },
               transformable = { position = {template_x, template_y} }
            }

            local ent_drawable = util.entities_mod().instantiate_entity("block", template):get("Drawable").drawable
            ent_drawable.color = lume.randomchoice({Color.Red, Color.Yellow, Color.Green})

            template_x = template_x + 90
            if template_x > screen_size.x - 20 then
               template_x = 10
               template_y = template_y + 50
            end
         end
      end
   end
end

M.systems = {
   ArkanoidPadSystem,
   ArkanoidBallSystem
}

M.components = {
   arkanoid_data = {
      class = Component.create("ArkanoidData", {"started", "score"}, { started = false, score = 0 })
   }
}

function M.components.arkanoid_data.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.arkanoid_data.class(sound))
end

return M
