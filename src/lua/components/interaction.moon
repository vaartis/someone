lovetoys = require("lovetoys")
lume = require("lume")

terminal = require("terminal")
coroutines = require("coroutines")
util = require("util")

note_components = require("components.note")
entities = require("components.entities")
first_puzzle = require("components.first_puzzle")
assets = require("components.assets")

M = {}

M.seconds_since_last_interaction = 0 -- Time tracked by dt, since last interaction
M.seconds_before_next_interaction = 0.3 -- A constant that represents how long to wait between interactions

M.InteractionTextTag = Component.create("InteractionTextTag")

M.InteractionComponent = Component.create(
   "Interaction",
   {"on_interaction", "is_activatable" , "interaction_args", "current_state", "state_map", "interaction_sound", "action_text"}
)

M.InteractionSystem = _G.class("InteractionSystem", System)
M.InteractionSystem.requires = () => {
  objects: {"Interaction", "Collider"},
  interaction_text: {"InteractionTextTag"}
}
M.InteractionSystem.onStopSystem = () =>
  interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
  if not interaction_text_key then error("No interaction text entity found")
  interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")
  interaction_text_drawable.enabled = false

M.InteractionSystem.update = (dt) =>
  interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
  if not interaction_text_key then error("No interaction text entity found")
  interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")

  M.seconds_since_last_interaction += dt

  any_interactables_touched = false
  for _, obj in pairs @targets.objects
    local interaction_comp, physics_world
    with obj
      interaction_comp = \get("Interaction")
      physics_world = \get("Collider").physics_world

    cols = do
      x, y, w, h = physics_world\getRect(obj)
      physics_world\queryRect(x, y, w, h)

    -- If the player is in the rectangle of the sprite, then check if the interaction button is pressed
    if lume.any(cols, (e) -> e\has("PlayerMovement")) then
      if interaction_comp.is_activatable
        unless interaction_comp.is_activatable(interaction_comp.current_state)
          continue
      any_interactables_touched = true

      with interaction_comp
        interaction_text_drawable.drawable.string =  "[E] to " .. (if .action_text then .action_text else "interact")

      for _, native_event in pairs M.event_store.events
        event = native_event.event
        if M.seconds_since_last_interaction > M.seconds_before_next_interaction and
           event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
          M.seconds_since_last_interaction = 0
          args = if interaction_comp.interaction_args
            if lume.isarray(interaction_comp.interaction_args)
                table.unpack(interaction_comp.interaction_args)
            else
                interaction_comp.interaction_args
          else
            {}

          interaction_res = interaction_comp.on_interaction(interaction_comp.current_state, args)

          -- If some kind of result was returned, use it as the new state
          if interaction_res ~= nil and interaction_res ~= interaction_comp.current_state
            interaction_comp.current_state = interaction_res

            -- Play the sound if there is one
            if interaction_comp.interaction_sound
              interaction_comp.interaction_sound\play()

    interaction_text_drawable.enabled = any_interactables_touched

    -- Update the current texture frame if there's a state map
    if interaction_comp.state_map
      anim = obj\get("Animation")
      anim.current_frame = interaction_comp.state_map[interaction_comp.current_state]

M.activatable_callbacks = {
  first_button_pressed: () -> WalkingModule.state_variables.first_button_pressed == true
  state_is_disabled: (curr_state) -> curr_state == "disabled",
  first_puzzle_solved: first_puzzle.first_puzzle_solved,
  first_puzzle_solved_music: first_puzzle.first_puzzle_solved_music,
  first_puzzle_not_solved: first_puzzle.first_puzzle_not_solved
}

M.interaction_callbacks = {
   computer_switch_to_terminal: (curr_state) ->
    player = util.rooms_mod!.find_player!

    player\get("PlayerMovement").active = false

    coroutines.create_coroutine(
      -- TODO: make this work with an overlay entity or something
      coroutines.black_screen_out,
        () ->
          GLOBAL.set_current_state(CurrentState.Terminal)
          terminal.active = true
    )

    "enabled"

  activate_computer: (curr_state) ->
    WalkingModule.state_variables.first_button_pressed = true

    "enabled",

  switch_room: (curr_state, args) ->
    { :room, :player_pos } = args

    util.rooms_mod!.load_room(room)

    if player_pos then
      player = util.rooms_mod!.find_player!

      physics_world = player\get("Collider").physics_world
      physics_world\update(player, player_pos[1], player_pos[2])

  first_puzzle_button: first_puzzle.button_callback,
  read_note: note_components.read_note
}

M.process_components = (new_ent, comp_name, comp, entity_name) ->
  switch comp_name
    when "interaction"
      unless M.interaction_callbacks[comp.callback_name]
        error(lume.format("{1}.{2} requires a {3} interaction callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))
      if comp.activatable_callback_name
        unless M.activatable_callbacks[comp.activatable_callback_name]
          error(lume.format("{1}.{2} requires a {3} activatable callback that doesn't exist", {entity_name, comp_name, comp.activatable_callback_name}))

      local interaction_sound
      if comp.interaction_sound_asset
        interaction_sound = with Sound.new!
          .buffer = assets.assets.sounds[comp.interaction_sound_asset]

      new_ent\add(
        M.InteractionComponent(
          M.interaction_callbacks[comp.callback_name],
          if comp.activatable_callback_name then M.activatable_callbacks[comp.activatable_callback_name] else nil,
          comp.args,
          comp.initial_state,
          comp.state_map,
          interaction_sound,
          comp.action_text
        )
      )

      true

M.add_systems = (engine) ->
  with engine
    \addSystem(M.InteractionSystem())

NativeEvent = _G.class("NativeEvent")
NativeEvent.initialize = (event) =>
  @event = event

EventStore = _G.class("EventStore")
EventStore.initialize = () =>
   @events = {}
EventStore.add_event = (event) =>
  if not @events then
      @events = {}

  table.insert(@events, event)
EventStore.clear = () =>
  @events = {}

M.native_event_manager = EventManager()
M.event_store = EventStore()

M.native_event_manager\addListener("NativeEvent", M.event_store, M.event_store.add_event)

M.add_event = (event) ->
  M.native_event_manager\fireEvent(NativeEvent(event))

M.update = (dt) ->
  M.event_store\clear()

return M
