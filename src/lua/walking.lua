local lovetoys = require("lovetoys")
local lume = require("lume")
local path = require("path")
local json = require("lunajson")
local inspect = require("inspect")

local shared_components = require("components.shared")
local player_components = require("components.player")

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

local button_texture = Texture.new();
button_texture:load_from_file("resources/sprites/room/button/button.png")
local button_sprite = Sprite.new()
button_sprite.texture = button_texture

local button_entity = Entity()
button_entity:add(shared_components.DrawableSpriteComponent(button_sprite, button_texture, 1))
engine:addEntity(button_entity)

engine:addSystem(shared_components.RenderSystem())
engine:addSystem(shared_components.AnimationSystem())
engine:addSystem(player_components.PlayerMovementSystem())

local M = {}

function M.add_event(event)
   native_event_manager:fireEvent(NativeEvent(event))
end

function M.update(dt)
   engine:update(dt)
end

function M.draw()
   engine:draw()
end

return M
