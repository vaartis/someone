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

-- A component holding button interaction logic.
-- state_map: a mapping from the state name to the animation frame
-- change_state: a function that is provided with the current state and needs to return the new state
ButtonComponent = Component.create(
   "Button",
   {"current_state", "change_state", "state_map"}
)

ButtonInteractionSystem = _G.class("ButtonInteractionSystem", System)
ButtonInteractionSystem.requires = () => {
  buttons: {"Button", "Transformable", "DrawableSprite", "Animation"},
  -- The PlayerMovement component only exists on the player
  player: {"PlayerMovement", "Transformable"}
}
ButtonInteractionSystem.update = (dt) =>
  player_key = lume.first(lume.keys(@targets.player))
  if not player_key then error("No player entity found")
  player = @targets.player[player_key]

  player_sprite = player\get("DrawableSprite").sprite

  for _, button in pairs @targets.buttons
    local button_pos, button_comp, button_sprite
    with button
      button_pos = \get("Transformable").position
      button_comp = \get("Button")
      button_sprite = \get("DrawableSprite").sprite

    if player_sprite.global_bounds\intersects(button_sprite.global_bounds) then
      for _, native_event in pairs event_store.events
        event = native_event.event
        if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
          old_state = button_comp.current_state
          -- Update the state using the function provided by the component
          button_comp.current_state = button_comp.change_state(button_comp.current_state)
          if button_comp.current_state ~= old_state
              -- If the state changed, play the button press sound

              button_press_soundbuf = SoundBuffer.new()
              button_press_soundbuf\load_from_file("resources/sounds/button_press.ogg")
              button_press_sound = Sound.new()
              button_press_sound.buffer = button_press_soundbuf

              button_press_sound\play()

    -- Update the current texture frame
    anim = button\get("Animation")
    anim.current_frame = button_comp.state_map[button_comp.current_state]

button_callbacks = {
   switch_to_terminal: (curr_state) ->
      state_variables["first_button_pressed"] = true

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
}

local room_toml
with io.open("resources/rooms/computer_room.toml", "r")
  room_toml = toml.parse(\read("*all"))
  \close()

-- Load assets
r_assets = room_toml.assets
if r_assets
  r_sprites = r_assets.sprites
  if r_sprites
    for name, path in pairs r_sprites
      assets.add_sprite(name, path)

  r_sounds = r_assets.sounds
  if r_sounds then
    for name, path in pairs r_sounds
      assets.add_sound(name, path)

for entity_name, entity in pairs room_toml.entities
  new_ent = Entity()

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
        unless button_callbacks[comp.callback_name]
          error(lume.format("{1}.{2} requires a {3} button callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))

        new_ent\add(
          ButtonComponent(
            comp.initial_state,
            button_callbacks[comp.callback_name],
            comp.state_map
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
