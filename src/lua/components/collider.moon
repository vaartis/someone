bump = require("bump")

M = {}

M.reset_world = () ->
  M.physics_world = bump.newWorld!

M.ColliderComponent = Component.create("Collider", {"physics_world", "mode", "trigger"}, {trigger: false})

M.ColliderUpdateSystem = _G.class("ColliderUpdateSystem", System)
M.ColliderUpdateSystem.requires = () => {"Collider"}
M.ColliderUpdateSystem.update = (dt) =>
  for _, entity in pairs @targets
    collider = entity\get("Collider")

    switch collider.mode
      when "sprite"
        self.update_from_sprite(entity)
M.ColliderUpdateSystem.update_from_sprite = (entity) ->
  sprite_size = entity\get("Drawable").drawable.global_bounds
  tf = entity\get("Transformable").transformable
  physics_world = entity\get("Collider").physics_world

  if physics_world\hasItem(entity)
    -- If the item is already in the world, sychronize the position from the
    -- physics world, by getting the position from there and adding the origin change,
    -- plus putting the current width and height in the world from the sprite
    tf.position = do
      x, y = physics_world\getRect(entity)

      -- Update the physics world with the new size
      physics_world\update(entity, x, y, sprite_size.width, sprite_size.height)

      x, y = x + (tf.origin.x * tf.scale.x), y + (tf.origin.y * tf.scale.y)
      -- Adjust the position for scale (doing the opposite of the thing done when
      -- first putting the entity into the world)
      scale_modifier = if tf.scale.x > 0 then 1 - tf.scale.x else tf.scale.x * -1
      x += sprite_size.width * scale_modifier

      -- Return the data for the transformable position
      Vector2f.new(x, y)
  else
    -- If the item isn't in the world yet, add it there, but putting it at the
    -- transformable position minus the origin change

    x, y = tf.position.x - (tf.origin.x * tf.scale.x), tf.position.y - (tf.origin.y * tf.scale.y)

    -- Adjust the position for scale
    scale_modifier = if tf.scale.x > 0 then 1 - tf.scale.x else tf.scale.x * -1
    x -= sprite_size.width * scale_modifier

    physics_world\add(entity, x, y, sprite_size.width, sprite_size.height)

M.process_collider_component = (new_ent, comp, entity_name) ->
  unless new_ent\has("Transformable")
    error("Transformable is required for a collider on #{entity_name}")

  pos = new_ent\get("Transformable").transformable.position

  switch comp.mode
    when "sprite"
      unless new_ent\has("Drawable") and new_ent\get("Drawable").kind == "sprite"
        error("Drawable sprite is required for a collider with sprite mode on #{entity_name}")

      -- Add the collider component and update the collider from the sprite, also adding it to the physics world
      new_ent\add(M.ColliderComponent(M.physics_world, comp.mode, comp.trigger))
      M.ColliderUpdateSystem.update_from_sprite(new_ent)
    when "constant"
      unless comp.size
        error("size is required for a collider with constant mode on #{entity_name}")
      ph_width, ph_height = comp.size[1], comp.size[2]

      M.physics_world\add(new_ent, pos.x, pos.y, ph_width, ph_height)
      new_ent\add(M.ColliderComponent(M.physics_world, comp.mode, comp.trigger))
    else
      error("Unknown collider mode #{comp.mode} for #{entity_name}")

M.add_systems = (engine) ->
  with engine
    \addSystem(M.ColliderUpdateSystem())

return M
