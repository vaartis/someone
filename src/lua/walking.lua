local lovetoys = require("lovetoys")
local lume = require("lume")
local path = require("path")
local json = require("lunajson")
local inspect = require("inspect")
local toml = require("toml")

local assets = require("components.assets")
local shared_components = require("components.shared")
local player_components = require("components.player")
local coroutines = require("coroutines")
local terminal = require("terminal")

local M = {}

M.state_variables = {}

-- An event manager that stores native events
local native_event_manager = EventManager()

local NativeEvent = class("NativeEvent")
function NativeEvent:initialize(event)
   self.event = event
end

local EventStore = class('EventStore')
function EventStore:initialize()
   self.events = {}
end

function EventStore:add_event(event)
   if not self.events then
      self.events = {}
   end

   table.insert(self.events, event)
end

function EventStore:clear()
   self.events = {}
end

local event_store = EventStore()

local engine = Engine()

native_event_manager:addListener("NativeEvent", event_store, event_store.add_event)


-- Loads the spritesheet frames from the spritesheet directory
function load_sheet_frames(dir_path)
   local dir_basename = path.basename(path.remove_dir_end(dir_path))
   local json_path = path.join(dir_path, dir_basename) .. ".json"

   local sprite_json_file = io.open(json_path, "r")
   local sprite_json = json.decode(sprite_json_file:read("*all"))
   sprite_json_file:close()

   local animation_frames = {}
   for fname, frame in pairs(sprite_json["frames"]) do
      local frame_f = frame["frame"]

      -- Extract the frame number from the name
      frame_num = tonumber(fname)

      animation_frames[frame_num] = {
         -- Translate duration to seconds
         duration = frame["duration"] / 1000,
         rect = IntRect.new(
            frame_f["x"], frame_f["y"], frame_f["w"], frame_f["h"]
         )
      }
   end

   return animation_frames
end

--[[
   A component holding button interaction logic.
   state_map: a mapping from the state name to the animation frame
   change_state: a function that is provided with the current state and needs to return the new state
]]
local ButtonComponent = Component.create(
   "Button",
   {"current_state", "change_state", "state_map"}
)

local ButtonInteractionSystem = class("ButtonInteractionSystem", System)
function ButtonInteractionSystem:requires()
   return {
      buttons = {"Button", "Transformable", "DrawableSprite", "Animation"},
      -- The PlayerMovement component only exists on the player
      player = {"PlayerMovement", "Transformable"}
   }
end

function ButtonInteractionSystem:update(dt)
   local player_key = lume.first(lume.keys(self.targets.player))
   if not player_key then error("No player entity found") end
   local player = self.targets.player[player_key]

   local player_sprite = player:get("DrawableSprite").sprite

   for _, button in pairs(self.targets.buttons) do
      local button_pos = button:get("Transformable").position
      local button_comp = button:get("Button")

      local button_sprite = button:get("DrawableSprite").sprite

      if (player_sprite.global_bounds:intersects(button_sprite.global_bounds)) then
         for _, native_event in pairs(event_store.events) do
            local event = native_event.event
            if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
               local old_state = button_comp.current_state
               -- Update the state using the function provided by the component
               button_comp.current_state = button_comp.change_state(button_comp.current_state)
               if button_comp.current_state ~= old_state then
                  -- If the state changed, play the button press sound

                  local button_press_soundbuf = SoundBuffer.new()
                  button_press_soundbuf:load_from_file("resources/sounds/button_press.ogg")
                  local button_press_sound = Sound.new()
                  button_press_sound.buffer = button_press_soundbuf

                  button_press_sound:play()
               end
            end
         end
      end

      -- Update the current texture frame
      local anim = button:get("Animation")
      anim.current_frame = button_comp.state_map[button_comp.current_state]
   end
end

local button_callbacks = {
   switch_to_terminal = function(curr_state)
      M.state_variables["first_button_pressed"] = true

      local player = lume.first(engine:getEntitiesWithComponent("PlayerMovement"))
      player:get("PlayerMovement").active = false

      coroutines.create_coroutine(
         coroutines.black_screen_out,
         function()
            GLOBAL.set_current_state(CurrentState.Terminal)
            terminal.active = true
         end
      )

      return "enabled"
   end
}

local room_toml_file = io.open("resources/rooms/computer_room.toml", "r")
local room_toml = toml.parse(room_toml_file:read("*all"))
room_toml_file:close()

local r_assets = room_toml.assets
if r_assets then
   local r_sprites = r_assets.sprites
   if r_sprites then
      for name, path in pairs(r_sprites) do
         assets.add_sprite(name, path)
      end
   end

   local r_sounds = r_assets.sounds
   if r_sounds then
      for name, path in pairs(r_sounds) do
         assets.add_sound(name, path)
      end
   end
end

for entity_name, entity in pairs(room_toml.entities) do
   local new_ent = Entity()

   for comp_name, comp in pairs(entity) do
      if comp_name == "drawable_sprite" then
         local sprite_asset = assets.assets.sprites[comp.sprite_asset]
         if not sprite_asset then
            error(lume.format("{1}.{2} requires a sprite named {3}", {entity_name, comp_name, comp.sprite_asset}))
         end

         if not comp.z then
            error(lume.format("{1}.{2} requires a {3} value", {entity_name, comp_name, "z"}))
         end

         local sprite = sprite_asset.sprite
         if comp.position then
            sprite.position = Vector2f.new(comp.position[1], comp.position[2])
         end
         if comp.origin then
            sprite.origin = Vector2f.new(comp.origin[1], comp.origin[2])
         end

         new_ent:add(shared_components.DrawableSpriteComponent(sprite, comp.z))
         new_ent:add(shared_components.TransformableComponent(sprite))
      elseif comp_name == "animation" then
         local sheet_frames = shared_components.load_sheet_frames(comp.sheet)

         local anim = shared_components.AnimationComponent(sheet_frames)
         if type(comp.playable) == "boolean" then
            anim.playable = comp.playable
         end
         if type(comp.playing) == "boolean" then
            anim.playing = comp.playing
         end

         new_ent:add(anim)
      elseif comp_name == "button" then
         if not button_callbacks[comp.callback_name] then
            error(lume.format("{1}.{2} requires a {3} button callback that doesn't exist", {entity_name, comp_name, comp.callback_name}))
         end

         new_ent:add(
            ButtonComponent(
               comp.initial_state,
               button_callbacks[comp.callback_name],
               comp.state_map
            )
         )
      else
         local component_processors = {
            player_components.process_components
         }

         for _, processor in pairs(component_processors) do
            if processor(new_ent, comp_name, comp) then
               break
            end
         end
      end
   end

   engine:addEntity(new_ent)
end

engine:addSystem(shared_components.RenderSystem())
engine:addSystem(shared_components.AnimationSystem())
engine:addSystem(player_components.PlayerMovementSystem())
engine:addSystem(ButtonInteractionSystem())


function M.add_event(event)
   native_event_manager:fireEvent(NativeEvent(event))
end

function M.update(dt)
   engine:update(dt)

   event_store:clear()
end

function M.draw()
   engine:draw()
end

return M
