util = require("util")
lume = require("lume")
assets = require("components.assets")

interaction_components = require("components.interaction")

interaction_callbacks =
  open_dial: () ->
    if not WalkingModule.state_variables.dial_puzzle
      WalkingModule.state_variables.dial_puzzle = { solved: false }

    util.entities_mod!.instantiate_entity("dial_closeup", { prefab: "dial" })

DialHandleComponent = Component.create("DialHandleComponent", {"position"}, {position: 1})

position = 1
position_rotations = {
  0, 36, 58, 88, 126, 148, 180,
  216, 236, 270, 302, 322
}

combination = { 4, 1, 10 }

combination_n = 1

local rotation_click_sound
local last_passed_position, last_side
local last_rotation

DialHandleSystem = _G.class("DialHandleSystem", System)
DialHandleSystem.requires = () => {
  objects: {"DialHandleTag", "Transformable"},
  interaction_text: {"InteractionTextTag"}
}
DialHandleSystem.update = (dt) =>
  for _, entity in pairs @targets.objects
    tf = entity\get("Transformable").transformable

    -- Restore rotation from previous opening
    if last_rotation
      tf.rotation = last_rotation
      last_rotation = nil

    engine = util.rooms_mod!.engine

    -- Keep these off
    engine\stopSystem("InteractionSystem")
    engine\stopSystem("PlayerMovementSystem")

    interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
    if not interaction_text_key then error("No interaction text entity found")
    interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")
    if not interaction_text_drawable.enabled
      interaction_text_drawable.enabled = true
      interaction_text_drawable.drawable.string = "[A/D] to rotate, [E] to close"

    interaction_components.seconds_since_last_interaction += dt

    rotation_change = 0
    unless WalkingModule.state_variables.dial_puzzle.solved
      if Keyboard.is_key_pressed(KeyboardKey.D)
        rotation_change = 1
      elseif Keyboard.is_key_pressed(KeyboardKey.A)
        rotation_change = -1

    tf\rotate(rotation_change)

    -- If the dial goes past 10 degrees from the last position,
    -- reset the last_passed_position, so the sound could can again
    if last_passed_position
      last_pos_value = position_rotations[last_passed_position]
      if math.abs(last_pos_value - tf.rotation) > 10
        last_passed_position = nil

    position_num = lume.find(position_rotations, tf.rotation)
    if rotation_change ~= 0 and position_num and position_num ~= last_passed_position
      last_passed_position = position_num

      if not rotation_click_sound
        rotation_click_sound = with Sound.new!
          .buffer = assets.assets.sounds["rotation_click"]

      if position_num == combination[combination_n]
        -- When approached from a different side, count as the correct value
        if rotation_change ~= last_side
          rotation_click_sound.volume = 100

          last_side = rotation_change

          if combination_n < #combination
            -- If there are more numbers in the combination, increase the counter
            combination_n += 1
          else
            -- Otherwise, the puzzle is solved
            WalkingModule.state_variables.dial_puzzle.solved = true
        else
          -- If approached from the same side, reset
          combination_n = 1
          last_side = nil
      else
        rotation_click_sound.volume = 30

      rotation_click_sound\play()

    for _, native_event in pairs interaction_components.event_store.events
      event = native_event.event
      if interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction and
         event.type == EventType.KeyReleased
          local interacted
          switch event.key.code
            when KeyboardKey.E
              interacted = true

              -- Save the last rotation value to restore on reopen
              last_rotation = tf.rotation

              -- Delete the whole dial
              engine\removeEntity(entity.parent, true)
              engine\startSystem("InteractionSystem")
              engine\startSystem("PlayerMovementSystem")
          if interacted
            interaction_components.seconds_since_last_interaction = 0

process_components = (new_ent, comp_name, comp) ->
  switch comp_name
    when "dial_handle"
      new_ent\add(DialHandleComponent())

      true

add_systems = (engine) ->
  with engine
    \addSystem(DialHandleSystem())

{
  :interaction_callbacks, :activatable_callbacks,
  :process_components, :add_systems
}
