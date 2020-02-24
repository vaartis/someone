assets = require("components.assets")
shared = require("components.shared")
path = require("path")

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

      if Keyboard.is_key_pressed KeyboardKey.D
        expected_new_pos = tf.transformable.position + Vector2f.new(1.0, 0.0)
        actual_new_x, actual_new_y = physics_world\move(entity, expected_new_pos.x, expected_new_pos.y)
        tf.transformable.position = Vector2f.new(actual_new_x, actual_new_y)

        player_movement.walking = true
        player_movement.look_direction = 1
      elseif Keyboard.is_key_pressed KeyboardKey.A
        expected_new_pos = tf.transformable.position + Vector2f.new(-1.0, 0.0)
        actual_new_x, actual_new_y = physics_world\move(entity, expected_new_pos.x, expected_new_pos.y)
        tf.transformable.position = Vector2f.new(actual_new_x, actual_new_y)

        player_movement.walking = true
        player_movement.look_direction = -1
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
      sound_asset = assets.assets.sounds[comp.footstep_sound_asset]
      if not sound_asset then
        error(lume.format("{1}.{2} requires a sound named {3}", {entity_name, comp_name, comp.footstep_sound_asset}))

      new_ent\add(PlayerMovementComponent(sound_asset.sound))

      true

{
  :PlayerMovementComponent, :PlayerMovementSystem,
  :process_components
}
