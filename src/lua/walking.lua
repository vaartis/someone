local lovetoys = require("lovetoys")
local lume = require("lume")
local path = require("path")
local json = require("lunajson")
local inspect = require("inspect")

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


local player = Entity()


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


local player = player_components.create_player_entity()
engine:addEntity(player)

local room_texture = Texture.new()
room_texture:load_from_file("resources/sprites/room/room.png")

local room_sprite = Sprite.new()
room_sprite.texture = room_texture

local room = Entity()
room:add(shared_components.DrawableSpriteComponent(room_sprite, room_texture, 0))

engine:addEntity(room)

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
   local player = lume.first(self.targets.player)
   if not player then error("No player entity found") end

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

--function

local button_texture = Texture.new();
button_texture:load_from_file("resources/sprites/room/button/button.png")
local button_sprite = Sprite.new()
button_sprite.texture = button_texture
button_sprite.position = Vector2f.new(1020, 672)
local button_frames = shared_components.load_sheet_frames("resources/sprites/room/button/")

local button_entity = Entity()
button_entity:add(
   ButtonComponent(
      "disabled",
      function (curr_state)
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
      end,
      { disabled = 1, enabled = 2 }
   )
)
button_entity:add(shared_components.TransformableComponent(button_sprite))
button_entity:add(shared_components.DrawableSpriteComponent(button_sprite, button_texture, 1))

local button_anim_comp = shared_components.AnimationComponent(button_frames)
button_anim_comp.playable = false
button_entity:add(button_anim_comp)
engine:addEntity(button_entity)

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
