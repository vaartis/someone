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
coroutines = require("coroutines")
terminal = require("terminal")

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

ColliderComponent = Component.create("Collider", {"physics_world", "mode", "trigger"}, {trigger: false})

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

ColliderUpdateSystem = _G.class("ColliderUpdateSystem", System)
ColliderUpdateSystem.requires = () => {"Collider"}
ColliderUpdateSystem.update = (dt) =>
  for _, entity in pairs @targets
    collider = entity\get("Collider")

    switch collider.mode
      when "sprite"
        self.update_from_sprite(entity)
ColliderUpdateSystem.update_from_sprite = (entity) ->
  sprite_size = entity\get("DrawableSprite").sprite.global_bounds
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

      -- Return the data for the transforamble position
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
   {"on_interaction", "interaction_args", "current_state", "state_map", "interaction_sound"}
)

InteractionSystem = _G.class("InteractionSystem", System)
InteractionSystem.requires = () => {
  objects: {"Interaction", "Transformable", "DrawableSprite", "Collider"},
  -- The PlayerMovement component only exists on the player
  player: {"PlayerMovement", "Transformable"}
}
InteractionSystem.update = (dt) =>
  player_key = lume.first(lume.keys(@targets.player))
  if not player_key then error("No player entity found")
  player = @targets.player[player_key]

  player_sprite = player\get("DrawableSprite").sprite

  for _, obj in pairs @targets.objects
    local obj_pos, obj_sprite, interaction_comp, physics_world
    with obj
      obj_pos = \get("Transformable").position
      obj_sprite = \get("DrawableSprite").sprite
      interaction_comp = \get("Interaction")
      physics_world = \get("Collider").physics_world

    cols = do
      x, y, w, h = physics_world\getRect(obj)
      physics_world\queryRect(x, y, w, h)

    -- If the player is in the rectangle of the sprite, then check if the interaction button is pressed
    if lume.any(cols, (e) -> e\has("PlayerMovement")) then
      for _, native_event in pairs event_store.events
        event = native_event.event
        if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
          interaction_res = interaction_comp.on_interaction(
            interaction_comp.current_state,
            if interaction_comp.interaction_args then table.unpack(interaction_comp.interaction_args) else {}
          )

          -- If some kind of result was returned, use it as the new state
          if interaction_res ~= nil and interaction_res ~= interaction_comp.current_state
            interaction_comp.current_state = interaction_res

            -- Play the sound if there is one
            if interaction_comp.interaction_sound
              interaction_comp.interaction_sound\play()

    -- Update the current texture frame if there's a state map
    if interaction_comp.state_map
      anim = obj\get("Animation")
      anim.current_frame = interaction_comp.state_map[interaction_comp.current_state]

local load_room

interaction_callbacks = {
   computer_switch_to_terminal: (curr_state) ->
    unless state_variables.first_button_pressed
      return "disabled"

    pents = engine\getEntitiesWithComponent("PlayerMovement")
    player_key = lume.first(lume.keys(pents))
    if not player_key then error("No player entity found")
    player = pents[player_key]

    player\get("PlayerMovement").active = false

    coroutines.create_coroutine(
      coroutines.black_screen_out,
        () ->
          GLOBAL.set_current_state(CurrentState.Terminal)
          terminal.active = true
    )

    "enabled"

  activate_computer: (curr_state) ->
    if curr_state == "enabled"
      return curr_state

    state_variables.first_button_pressed = true

    "enabled",

  switch_room: (curr_state, room) ->
    load_room(room)
}

load_assets = (l_assets) ->
    l_sprites = l_assets.sprites
    if l_sprites
      for name, path in pairs l_sprites
        assets.add_sprite(name, path)

    l_sounds = l_assets.sounds
    if l_sounds then
      for name, path in pairs l_sounds
        assets.add_sound(name, path)

deep_merge = (t1, t2) ->
  result = {}
  for k, v in pairs t1
    result[k] = v

  for k, _ in pairs t2
    if type(t1[k]) == "table" and type(t2[k]) == "table"
      result[k] = deep_merge(t1[k], t2[k])
    else
      result[k] = t2[k] or t1[k]

  result

reset_engine = () ->
  engine = Engine()
  with engine
    \addSystem(shared_components.RenderSystem())
    \addSystem(shared_components.AnimationSystem())
    \addSystem(player_components.PlayerMovementSystem())
    \addSystem(InteractionSystem())
    \addSystem(ColliderUpdateSystem())

    \addSystem(DebugColliderDrawingSystem())

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
        if .removed_assets
          with .removed_assets
            if .sprites and prefab_room.assets.sprites
              for k, v in pairs(prefab_room.assets.sprites)
                if lume.find(.sprites, k)
                  prefab_room.assets.sprites[k] = nil
            if .sounds and prefab_room.assets.sounds
              for k, v in pairs(prefab_room.assets.sounds)
                if lume.find(.sounds, k)
                  prefab_room.assets.sounds[k] = nil

        room_toml = deep_merge(prefab_room, room_toml)
    -- Remove the mention of the prefab
    room_toml.prefab = nil

  room_toml

load_room = (name) ->
  reset_engine!

  room_toml = load_room_toml(name)

  -- Load assets
  load_assets(room_toml.assets) if room_toml.assets

  for entity_name, entity in pairs room_toml.entities
    new_ent = Entity()

    if entity.prefab then
      prefab_data = do
        local data
        with io.open("resources/rooms/prefabs/#{entity.prefab}.toml", "r")
          data = toml.parse(\read("*all"))
          \close()
        data

      -- Load the assets of the prefab and remove them from the data
      load_assets(prefab_data.assets)
      prefab_data.assets = nil
      entity = deep_merge(prefab_data, entity)

      -- Remove the mention of the prefab from the entity
      entity.prefab = nil

    add_transformable_actions = {}
    add_collider_actions = {}

    for comp_name, comp in pairs entity
      switch comp_name
        when "drawable_sprite"
          sprite_asset = assets.assets.sprites[comp.sprite_asset]
          unless sprite_asset
            error(lume.format("{1}.{2} requires a sprite named {3}", {entity_name, comp_name, comp.sprite_asset}))

          unless comp.z then
            error(lume.format("{1}.{2} requires a {3} value", {entity_name, comp_name, "z"}))

          sprite = sprite_asset.sprite
          new_ent\add(shared_components.DrawableSpriteComponent(sprite, comp.z))
          new_ent\add(shared_components.TransformableComponent(sprite))
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
        when "animation"
          sheet_frames = shared_components.load_sheet_frames(comp.sheet)

          anim = with shared_components.AnimationComponent(sheet_frames)
            .playable = comp.playable if type(comp.playable) == "boolean"
            .playing = comp.playing if type(comp.playing) == "boolean"

          new_ent\add(anim)
        when "interaction"
          unless interaction_callbacks[comp.callback_name]
            error(lume.format("{1}.{2} requires a {3} interaction callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))

          local interaction_sound
          if comp.interaction_sound_asset
            interaction_sound = assets.assets.sounds[comp.interaction_sound_asset].sound

          new_ent\add(
            InteractionComponent(
              interaction_callbacks[comp.callback_name],
              comp.args,
              comp.initial_state,
              comp.state_map,
              interaction_sound
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
                  unless new_ent\has("DrawableSprite")
                    error("DrawableSprite is required for a collider with sprite mode on #{entity_name}")

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
        else
          component_processors = {
            player_components.process_components
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

    engine\addEntity(new_ent)

load_room "computer_room"

add_event = (event) ->
  native_event_manager\fireEvent(NativeEvent(event))

update = (dt) ->
  engine\update(dt)

  event_store\clear()

draw = () ->
  engine\draw()

{
  :add_event, :update, :draw
  :state_variables
}
