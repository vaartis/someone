lovetoys = require("lovetoys")
lume = require("lume")
path = require("path")
json = require("lunajson")
inspect = require("inspect")
toml = require("toml")

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

engine = Engine()

native_event_manager\addListener("NativeEvent", event_store, event_store.add_event)

InteractionComponent = Component.create(
   "Interaction",
   {"on_interaction", "current_state", "state_map", "interaction_sound"}
)

InteractionSystem = _G.class("InteractionSystem", System)
InteractionSystem.requires = () => {
  objects: {"Interaction", "Transformable", "DrawableSprite"},
  -- The PlayerMovement component only exists on the player
  player: {"PlayerMovement", "Transformable"}
}
InteractionSystem.update = (dt) =>
  player_key = lume.first(lume.keys(@targets.player))
  if not player_key then error("No player entity found")
  player = @targets.player[player_key]

  player_sprite = player\get("DrawableSprite").sprite

  for _, obj in pairs @targets.objects
    local obj_pos, obj_sprite, interaction_comp
    with obj
      obj_pos = \get("Transformable").position
      obj_sprite = \get("DrawableSprite").sprite
      interaction_comp = \get("Interaction")

    if player_sprite.global_bounds\intersects(obj_sprite.global_bounds) then
      for _, native_event in pairs event_store.events
        event = native_event.event
        if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
          interaction_res = interaction_comp.on_interaction(interaction_comp.current_state)

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

    "enabled"
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

local room_toml
with io.open("resources/rooms/computer_room.toml", "r")
  room_toml = toml.parse(\read("*all"))
  \close()

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

-- Load assets
r_assets = room_toml.assets
if r_assets
  load_assets(r_assets)

for entity_name, entity in pairs room_toml.entities
  new_ent = Entity()

  if entity.prefab then
    local prefab_data
    with io.open("resources/rooms/prefabs/#{entity.prefab}.toml", "r")
      prefab_data = toml.parse(\read("*all"))
      \close()
    -- Load the assets of the prefab and remove them from the data
    load_assets(prefab_data.assets)
    prefab_data.assets = nil
    entity = deep_merge(prefab_data, entity)

  for comp_name, comp in pairs entity
    switch comp_name
      when "drawable_sprite"
        sprite_asset = assets.assets.sprites[comp.sprite_asset]
        unless sprite_asset
          error(lume.format("{1}.{2} requires a sprite named {3}", {entity_name, comp_name, comp.sprite_asset}))

        unless comp.z then
          error(lume.format("{1}.{2} requires a {3} value", {entity_name, comp_name, "z"}))

        sprite = with sprite_asset.sprite
          .position = Vector2f.new(comp.position[1], comp.position[2]) if comp.position
          .origin = Vector2f.new(comp.origin[1], comp.origin[2]) if comp.origin

        new_ent\add(shared_components.DrawableSpriteComponent(sprite, comp.z))
        new_ent\add(shared_components.TransformableComponent(sprite))
      when "animation"
        sheet_frames = shared_components.load_sheet_frames(comp.sheet)

        anim = with shared_components.AnimationComponent(sheet_frames)
          .playable = comp.playable if type(comp.playable) == "boolean"
          .playing = comp.playing if type(comp.playing) == "boolean"

        new_ent\add(anim)
      when "button"
        unless interaction_callbacks[comp.callback_name]
          error(lume.format("{1}.{2} requires a {3} interaction callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))

        local interaction_sound
        if comp.interaction_sound_asset
          interaction_sound = assets.assets.sounds[comp.interaction_sound_asset].sound

        new_ent\add(
          InteractionComponent(
            interaction_callbacks[comp.callback_name],
            comp.initial_state,
            comp.state_map,
            interaction_sound
          )
        )
      else
        component_processors = {
          player_components.process_components
        }

        for _, processor in pairs component_processors
          break if processor(new_ent, comp_name, comp)

  engine\addEntity(new_ent)

with engine
  \addSystem(shared_components.RenderSystem())
  \addSystem(shared_components.AnimationSystem())
  \addSystem(player_components.PlayerMovementSystem())
  \addSystem(ButtonInteractionSystem())

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
