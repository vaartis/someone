lume = require("lume")
path = require("path")

assets = require("components.assets")
shared = require("components.shared")

x_movement_speed = 1.0

PlayerMovementComponent = Component.create(
  "PlayerMovement",
  { "step_sound", "walking", "look_direction", "active" },
  { walking: false, look_direction: 1, active: true }
)

PlayerMovementSystem = _G.class("PlayerMovementSystem", System)
PlayerMovementSystem.requires = =>
  {"PlayerMovement", "Transformable", "DrawableSprite", "Animation", "Collider"}

PlayerMovementSystem.update = (dt) =>
  for _, entity in pairs @targets do
    player_movement = entity\get("PlayerMovement")

    if player_movement.active
      tf = entity\get("Transformable")
      drawable = entity\get("DrawableSprite")
      animation = entity\get("Animation")
      physics_world = entity\get("Collider").physics_world

      local pos_diff, look_direction
      if Keyboard.is_key_pressed KeyboardKey.D
        pos_diff = Vector2f.new(x_movement_speed, 0.0)
        look_direction = 1
      elseif Keyboard.is_key_pressed KeyboardKey.A
        pos_diff = Vector2f.new(-x_movement_speed, 0.0)
        look_direction = -1

      if pos_diff ~= nil
        expected_new_pos = do
          x, y = physics_world\getRect(entity)
          Vector2f.new(x, y) + pos_diff

        _, _, cols, col_count = physics_world\check(
          entity,
          expected_new_pos.x,
          expected_new_pos.y,
          (item, other) -> if other\get("Collider").trigger then "cross" else "slide"
        )
        if col_count == 0 or not lume.any(cols, (c) -> c.type == "slide")
          -- Don't check for collisions here, since the've already been checked,
          -- just update the position
          physics_world\update(entity, expected_new_pos.x, expected_new_pos.y)
          player_movement.walking = true

        player_movement.look_direction = look_direction
      else
        player_movement.walking = false

      drawable.sprite.scale = Vector2f.new(player_movement.look_direction, 1.0)
      animation.playing = player_movement.walking

      -- Play the step sound every two steps of the animation, which are the moments
      -- when the feet hit the ground
      if player_movement.walking and animation.current_frame % 2 == 0 and player_movement.step_sound.status ~= SoundStatus.Playing then
        player_movement.step_sound\play()

process_components = (new_ent, comp_name, comp) ->
  switch comp_name
    when "player_movement"
      sound_buf_asset = assets.assets.sounds[comp.footstep_sound_asset]
      if not sound_buf_asset then
        error(lume.format("{1}.{2} requires a sound named {3}", {entity_name, comp_name, comp.footstep_sound_asset}))

      sound = with Sound.new!
        .buffer = assets.assets.sounds[comp.footstep_sound_asset]

      new_ent\add(PlayerMovementComponent(sound))

      true

{
  :PlayerMovementComponent, :PlayerMovementSystem,
  :process_components
}
