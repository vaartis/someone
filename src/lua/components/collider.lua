local bump = require("bump")

local M = {}

function M.reset_world()
  M.physics_world = bump.newWorld()
end

local ColliderComponent = Component.create("Collider", { "physics_world", "mode", "trigger"}, { trigger = false })

local ColliderUpdateSystem = class("ColliderUpdateSystem", System)
function ColliderUpdateSystem:requires() return { "Collider" } end
function ColliderUpdateSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local collider = entity:get("Collider")

      if collider.mode == "sprite" then
         self.update_from_sprite(entity)
      end
   end
end
function ColliderUpdateSystem.update_from_sprite(entity)
   local sprite_size = entity:get("Drawable").drawable.global_bounds

  local tfc = entity:get("Transformable")
  local tf = tfc.transformable

  local physics_world = entity:get("Collider").physics_world

  if physics_world:hasItem(entity) then
     -- If the item is already in the world, sychronize the position from the
     -- physics world, by getting the position from there and adding the origin change,
     -- plus putting the current width and height in the world from the sprite

     local x, y = physics_world:getRect(entity)

     -- Update the physics world with the new size
     physics_world:update(entity, x, y, sprite_size.width, sprite_size.height)

     x, y = x + (tf.origin.x * tf.scale.x), y + (tf.origin.y * tf.scale.y)

     -- Adjust the position for scale (doing the opposite of the thing done when
     -- first putting the entity into the world)
     local scale_modifier
     if tf.scale.x > 0 then
        scale_modifier = 1 - tf.scale.x
     else
        scale_modifier = tf.scale.x * -1
     end
     x = x + (sprite_size.width * scale_modifier)

     tfc:set_world_position(entity, Vector2f.new(x, y))
  else
     -- If the item isn't in the world yet, add it there, but putting it at the
     -- transformable position minus the origin change

     local pos = tfc:world_position(entity)
     local x, y = pos.x - (tf.origin.x * tf.scale.x), pos.y - (tf.origin.y * tf.scale.y)

     -- Adjust the position for scale
     local scale_modifier
     if tf.scale.x > 0 then
        scale_modifier = 1 - tf.scale.x
     else
        scale_modifier = tf.scale.x * -1
     end
     x = x - (sprite_size.width * scale_modifier)

     physics_world:add(entity, x, y, sprite_size.width, sprite_size.height)
  end
end

function M.process_collider_component(new_ent, comp, entity_name)
   if not (new_ent:has("Transformable")) then
      error("Transformable is required for a collider on " .. tostring(entity_name))
   end

   local pos = new_ent:get("Transformable"):world_position(new_ent)

   if comp.mode == "sprite" then
      if not (new_ent:has("Drawable") and new_ent:get("Drawable").kind == "sprite") then
         error("Drawable sprite is required for a collider with sprite mode on " .. tostring(entity_name))
      end

      -- Add the collider component and update the collider from the sprite, also adding it to the physics world
      new_ent:add(ColliderComponent(M.physics_world, comp.mode, comp.trigger))
      ColliderUpdateSystem.update_from_sprite(new_ent)
   elseif comp.mode == "constant" then
      if not (comp.size) then
         error("size is required for a collider with constant mode on " .. tostring(entity_name))
      end
      local ph_width, ph_height = comp.size[1], comp.size[2]

      M.physics_world:add(new_ent, pos.x, pos.y, ph_width, ph_height)
      new_ent:add(ColliderComponent(M.physics_world, comp.mode, comp.trigger))
   else
      error("Unknown collider mode " .. tostring(comp.mode) .. " for " .. tostring(entity_name))
   end
end

function M.add_systems(engine)
   engine:addSystem(ColliderUpdateSystem())
end

return M