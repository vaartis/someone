lovetoys = require("lovetoys")
lume = require("lume")
path = require("path")
json = require("lunajson")
inspect = require("inspect")
toml = require("toml")
bump = require("bump")

assets = require("components.assets")
shared_components = require("components.shared")
player_components = require("components.player")
debug_components = require("components.debug")
coroutines = require("coroutines")
terminal = require("terminal")

first_puzzle = require("components.first_puzzle")
util = require("util")

state_variables = {}

native_event_manager = EventManager()

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

event_store = EventStore()

local engine

native_event_manager\addListener("NativeEvent", event_store, event_store.add_event)

physics_world = bump.newWorld()

seconds_since_last_interaction = 0 -- Time tracked by dt, since last interaction
seconds_before_next_interaction = 0.3 -- A constant that represents how long to wait between interactions

NoteComponent = Component.create("Note", {"text", "bottom_text", "text_object", "bottom_text_object"})

NoteSystem = _G.class("NoteSystem", System)
NoteSystem.requires = () => {"Slices", "Note", "Transformable"}
NoteSystem.draw = () =>
  for _, entity in pairs @targets
    drawable = entity\get("Drawable")

    if drawable.enabled
      tf = entity\get("Transformable")
      slice, bottom_slice = do
        slices = entity\get("Slices").slices
        slices.text, slices.bottom_text

      note = entity\get("Note")

      if not note._formatted
        note._formatted = true

        max_text_len = util.rect_max_text_width(slice.width)
        note.text_object.string = lume.wordwrap(note.text, max_text_len)
        note.text_object.position = tf.transformable.position + Vector2f.new(slice.left, slice.top)

        note.bottom_text_object.string = lume.wordwrap(note.bottom_text, max_text_len)
        bottom_text_width = note.bottom_text_object.global_bounds.width
        note.bottom_text_object.position = tf.transformable.position + Vector2f.new(
            bottom_slice.left + bottom_slice.width - bottom_text_width,
            bottom_slice.top
        )
      GLOBAL.drawing_target\draw(note.text_object)
      GLOBAL.drawing_target\draw(note.bottom_text_object)
NoteInteractionSystem = _G.class("NoteInteractionSystem", System)
NoteInteractionSystem.requires = () => {"Note", "Drawable"}
NoteInteractionSystem.update = (dt) =>
  for _, entity in pairs @targets
    drawable = entity\get("Drawable")

    if drawable.enabled
      -- Keep the interaction system disabled
      engine\stopSystem("InteractionSystem")

      seconds_since_last_interaction += dt

      for _, native_event in pairs event_store.events
        event = native_event.event
        if seconds_since_last_interaction > seconds_before_next_interaction and
           event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
            seconds_since_last_interaction = 0
            -- Delete the note entity and re-enable interactions
            engine\removeEntity(entity)
            engine\startSystem("InteractionSystem")


InteractionTextTag = Component.create("InteractionTextTag")

ColliderComponent = Component.create("Collider", {"physics_world", "mode", "trigger"}, {trigger: false})

ColliderUpdateSystem = _G.class("ColliderUpdateSystem", System)
ColliderUpdateSystem.requires = () => {"Collider"}
ColliderUpdateSystem.update = (dt) =>
  for _, entity in pairs @targets
    collider = entity\get("Collider")

    switch collider.mode
      when "sprite"
        self.update_from_sprite(entity)
ColliderUpdateSystem.update_from_sprite = (entity) ->
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

InteractionComponent = Component.create(
   "Interaction",
   {"on_interaction", "is_activatable" , "interaction_args", "current_state", "state_map", "interaction_sound", "action_text"}
)

InteractionSystem = _G.class("InteractionSystem", System)
InteractionSystem.requires = () => {
  objects: {"Interaction", "Collider"},
  interaction_text: {"InteractionTextTag"}
}
InteractionSystem.onStopSystem = () =>
  interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
  if not interaction_text_key then error("No interaction text entity found")
  interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")
  interaction_text_drawable.enabled = false

InteractionSystem.update = (dt) =>
  interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
  if not interaction_text_key then error("No interaction text entity found")
  interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")

  seconds_since_last_interaction += dt

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

      for _, native_event in pairs event_store.events
        event = native_event.event
        if seconds_since_last_interaction > seconds_before_next_interaction and
           event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
          seconds_since_last_interaction = 0
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

SoundPlayerComponent = Component.create("SoundPlayer", {"sound", "activate_callback", "played"}, { played: false })
SoundPlayerSystem = _G.class("SoundPlayerSystem", System)
SoundPlayerSystem.requires = () => {"SoundPlayer"}
SoundPlayerSystem.update = () =>
  for _, entity in pairs @targets
    sound_comp = entity\get("SoundPlayer")
    unless sound_comp.played
      if sound_comp.activate_callback()
        sound_comp.sound\play()
        sound_comp.played = true

find_player = () ->
  pents = engine\getEntitiesWithComponent("PlayerMovement")
  player_key = lume.first(lume.keys(pents))
  if not player_key then error("No player entity found")

  pents[player_key]

local load_room, load_prefab, instantiate_entity

activatable_callbacks = {
  first_button_pressed: () -> state_variables.first_button_pressed == true
  state_is_disabled: (curr_state) -> curr_state == "disabled",
  first_puzzle_solved: first_puzzle.first_puzzle_solved,
  first_puzzle_not_solved: first_puzzle.first_puzzle_not_solved
}

interaction_callbacks = {
   computer_switch_to_terminal: (curr_state) ->
    player = find_player!

    player\get("PlayerMovement").active = false

    coroutines.create_coroutine(
      coroutines.black_screen_out,
        () ->
          GLOBAL.set_current_state(CurrentState.Terminal)
          terminal.active = true
    )

    "enabled"

  activate_computer: (curr_state) ->
    state_variables.first_button_pressed = true

    "enabled",

  switch_room: (curr_state, args) ->
    { :room, :player_pos } = args

    load_room(room)

    if player_pos then
      player = find_player!

      physics_world = player\get("Collider").physics_world
      physics_world\update(player, player_pos[1], player_pos[2])

  first_puzzle_button: first_puzzle.button_callback
  read_note: (state, note_name) ->
    local notes
    with io.open("resources/rooms/notes.toml", "r")
      notes = toml.parse(\read("*all"))
      \close()

    note = notes[note_name]

    if not note
      error("Note #{note} not found")

    note_entity = instantiate_entity("note_paper", {
        prefab: "note",
        note: { text: note.text, bottom_text: note.bottom_text }
    })
    engine\addEntity(note_entity)
}

load_assets = () ->
  local l_assets
  with io.open("resources/rooms/assets.toml", "r")
    l_assets = toml.parse(\read("*all"))
    \close()

  if l_textures = l_assets.textures
    for name, path in pairs l_textures
      assets.add_to_known_assets("textures", name, path)

  if l_sounds = l_assets.sounds
    for name, path in pairs l_sounds
      assets.add_to_known_assets("sounds", name, path)


CustomEngine = _G.class("CustomEgine", Engine)
CustomEngine.draw = (layer) =>
  for _, system in ipairs(@systems["draw"]) do
    if system.active then
        system\draw(layer)
CustomEngine.stopSystem = (name) =>
  CustomEngine.super.stopSystem(self, name)
  system = @systemRegistry[name]
  if system and system.onStopSystem then system\onStopSystem!

reset_engine = () ->
  engine = CustomEngine()
  with engine
    shared_components.add_systems(engine)
    player_components.add_systems(engine)
    first_puzzle.add_systems(engine)

    \addSystem(InteractionSystem())
    \addSystem(ColliderUpdateSystem())
    \addSystem(SoundPlayerSystem())

    \addSystem(NoteSystem())
    \addSystem(NoteInteractionSystem())

    debug_components.add_systems(engine)

-- Loads the room's toml file, processing parent relationships
load_room_toml = (name) ->
  local room_toml
  with io.open("resources/rooms/#{name}.toml", "r")
    room_toml = toml.parse(\read("*all"))
    \close()

  -- If there's a prefab/base room, load it
  if room_toml.prefab
    with room_toml.prefab
        prefab_room = load_room_toml(.name)

        if .removed_entities
          for k, v in pairs(prefab_room.entities)
            if lume.find(.removed_entities, k)
              -- Remove the entity
              prefab_room.entities[k] = nil

        room_toml = util.deep_merge(prefab_room, room_toml)
    -- Remove the mention of the prefab
    room_toml.prefab = nil

  room_toml

_room_shaders = {}
room_shaders = () -> _room_shaders

load_prefab = (prefab_name_or_conf, base_data) ->
  local prefab_name, removed_components
  -- Allow prefab to either be just a name or a table with more info
  switch type(prefab_name_or_conf)
    when "table"
      prefab_name = prefab_name_or_conf.name
      removed_components = prefab_name_or_conf.removed_components
    when "string"
      prefab_name = prefab_name_or_conf

  prefab_data = do
    local data
    with io.open("resources/rooms/prefabs/#{prefab_name}.toml", "r")
      data = toml.parse(\read("*all"))
      \close()
    data

  base_data = util.deep_merge(prefab_data, base_data)

  -- Clear the components requested by removed_components
  if removed_components
    for _, name_to_remove in pairs removed_components
      base_data[name_to_remove] = nil

  -- Remove the mention of the prefab from the entity
  base_data.prefab = nil

  base_data


instantiate_entity = (entity_name, entity) ->
  new_ent = Entity()

  if entity.prefab
    entity = load_prefab(entity.prefab, entity)

  add_transformable_actions = {}
  add_collider_actions = {}

  for comp_name, comp in pairs entity
    switch comp_name
      when "transformable"
        table.insert(
          add_transformable_actions,
          ->
            unless new_ent\has("Transformable")
              -- If there's no transformable component, create and add it
              new_ent\add(shared_components.TransformableComponent(Transformable.new()))
            tf_component = new_ent\get("Transformable")

            with tf_component.transformable
              .position = Vector2f.new(comp.position[1], comp.position[2]) if comp.position
              .origin = Vector2f.new(comp.origin[1], comp.origin[2]) if comp.origin
              .scale = Vector2f.new(comp.scale[1], comp.scale[2]) if comp.scale
        )
      when "interaction"
        unless interaction_callbacks[comp.callback_name]
          error(lume.format("{1}.{2} requires a {3} interaction callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))
        if comp.activatable_callback_name
          unless activatable_callbacks[comp.activatable_callback_name]
            error(lume.format("{1}.{2} requires a {3} activatable callback that doesn't exist", {entity_name, comp_name, comp.activatable_callback_name}))

        local interaction_sound
        if comp.interaction_sound_asset
          interaction_sound = with Sound.new!
            .buffer = assets.assets.sounds[comp.interaction_sound_asset]

        new_ent\add(
          InteractionComponent(
            interaction_callbacks[comp.callback_name],
            if comp.activatable_callback_name then activatable_callbacks[comp.activatable_callback_name] else nil,
            comp.args,
            comp.initial_state,
            comp.state_map,
            interaction_sound,
            comp.action_text
          )
        )
      when "collider"
        table.insert(
          add_collider_actions,
          ->
            unless new_ent\has("Transformable")
              error("Transformable is required for a collider on #{entity_name}")

            pos = new_ent\get("Transformable").transformable.position

            switch comp.mode
              when "sprite"
                unless new_ent\has("Drawable") and new_ent\get("Drawable").kind == "sprite"
                  error("Drawable sprite is required for a collider with sprite mode on #{entity_name}")

                -- Add the collider component and update the collider from the sprite, also adding it to the physics world
                new_ent\add(ColliderComponent(physics_world, comp.mode, comp.trigger))
                ColliderUpdateSystem.update_from_sprite(new_ent)
              when "constant"
                unless comp.size
                  error("size is required for a collider with constant mode on #{entity_name}")
                ph_width, ph_height = comp.size[1], comp.size[2]

                physics_world\add(new_ent, pos.x, pos.y, ph_width, ph_height)
                new_ent\add(ColliderComponent(physics_world, comp.mode, comp.trigger))
              else
                error("Unknown collider mode #{comp.mode} for #{entity_name}")
        )
      when "sound_player"
        callback = activatable_callbacks[comp.activate_callback_name]
        unless callback
          error(lume.format("{1}.{2} requires a {3} interaction callback that doesn't exist", {entity_name, comp_name, comp.activate_callback_name}))

        sound = with Sound.new!
          .buffer = assets.assets.sounds[comp.sound_asset]

        new_ent\add(SoundPlayerComponent(sound, callback))
      when "tags"
        -- TODO: this tag system doesn't seem like a very good solution, maybe
        -- it should be changed somehow to allow selecting entities by tags directly,
        -- though it is likely that this change has to be done in the ECS itself
        for _, tag in pairs comp
          switch tag
            when "interaction_text"
              new_ent\add(InteractionTextTag())
            else
              error("Unknown tag in #{entity_name}.#{comp_name}: #{tag}")
      when "note"
        note_text = with Text.new("", StaticFonts.main_font, StaticFonts.font_size)
          .fill_color = Color.Black
        bottom_text = with Text.new("", StaticFonts.main_font, StaticFonts.font_size)
          .fill_color = Color.Black

        new_ent\add(NoteComponent(comp.text, comp.bottom_text, note_text, bottom_text))
      else
        component_processors = {
          shared_components.process_components,
          player_components.process_components,
          first_puzzle.process_components
        }

        processed = false
        for _, processor in pairs component_processors
          if processor(new_ent, comp_name, comp)
            processed = true
            break
        if not processed
          error("Unknown component: #{comp_name} on #{entity_name}")

  -- Call all the "after all inserted" actions
  for _, actions in pairs {add_transformable_actions, add_collider_actions}
      for _, action in pairs actions
        action!

  new_ent

load_room = (name) ->
  reset_engine!
  physics_world = bump.newWorld()

  room_toml = load_room_toml(name)

  if room_toml.shaders
      _room_shaders = room_toml.shaders
  else
    _room_shaders = {}

  for entity_name, entity in pairs room_toml.entities
    engine\addEntity(instantiate_entity(entity_name, entity))

-- Load the assets.toml file
load_assets!
-- Load the room
-- load_room "first_puzzle_room"

add_event = (event) ->
  native_event_manager\fireEvent(NativeEvent(event))

update = (dt) ->
  engine\update(dt)

  event_store\clear()

draw = () ->
  engine\draw()

draw_overlay = () ->
  engine\draw("overlay")

{
  :add_event, :update, :draw, :draw_overlay
  :state_variables, :load_room,
  :room_shaders
}
