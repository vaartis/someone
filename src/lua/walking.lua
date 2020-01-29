local lovetoys = require("lovetoys")
local lume = require("lume")
local path = require("path")
local json = require("lunajson")
local inspect = require("inspect")

lovetoys.initialize({
      debug = true,
      globals = true
})

local DrawableSpriteComponent = Component.create("DrawableSprite", {"sprite", "texture", "z"})

local RenderSystem = class("RenderSystem", System)

function RenderSystem:requires()
   return {"DrawableSprite"}
end

function RenderSystem:onAddEntity(entity)
   -- Sort targets according to the z level
   self.targets =
      lume.sort(
         self.targets,
         function(a, b)
            local drawable_a = a:get("DrawableSprite")
            local drawable_b = b:get("DrawableSprite")

            return drawable_a.z < drawable_b.z
         end
      )
end

function RenderSystem:draw()
   for _, entity in pairs(self.targets) do
      local drawable = entity:get("DrawableSprite")

      DRAWING_TARGET:draw(drawable.sprite)
   end
end

local TransformableComponent = Component.create("Transformable", {"transformable"})

local AnimationComponent = Component.create(
   "Animation",
   {"frames", "current_frame", "playing", "time_since_frame_change"},
   { time_since_frame_change = 0, playing = false, current_frame = 1 }
)

local AnimationSystem = class("AnimationSystem", System)

function AnimationSystem:requires()
   return {"DrawableSprite", "Animation"}
end

function AnimationSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local anim = entity:get("Animation")

      anim.time_since_frame_change = anim.time_since_frame_change + dt

      if anim.playing then
         if anim.time_since_frame_change > anim.frames[anim.current_frame].duration then
            anim.time_since_frame_change = 0

            if anim.current_frame + 1 <= #anim.frames then
               anim.current_frame = anim.current_frame + 1
            else
               anim.current_frame = 1
            end
         end
      else
         anim.current_frame = 1
      end

      local drawable = entity:get("DrawableSprite")
      drawable.sprite.texture_rect = anim.frames[anim.current_frame].rect
   end
end

local PlayerMovementComponent = Component.create(
   "PlayerMovement",
   {"step_sound_buffer", "step_sound", "walking", "look_direction"},
   { walking = false, look_direction = 1}
)

local PlayerMovementSystem = class("PlayerMovementSystem", System)

function PlayerMovementSystem:requires()
   return {"PlayerMovement", "Transformable", "DrawableSprite", "Animation"}
end

function PlayerMovementSystem:update(dt)
   for _, entity in pairs(self.targets) do

      local tf = entity:get("Transformable")
      local player_movement = entity:get("PlayerMovement")
      local drawable = entity:get("DrawableSprite")
      local animation = entity:get("Animation")

      if Keyboard.is_key_pressed(KeyboardKey.D) then
         tf.transformable.position = tf.transformable.position + Vector2f.new(1.0, 0.0)
         player_movement.walking = true
         player_movement.look_direction = 1
      elseif Keyboard.is_key_pressed(KeyboardKey.A) then
         tf.transformable.position = tf.transformable.position + Vector2f.new(-1.0, 0.0)
         player_movement.walking = true
         player_movement.look_direction = -1
      else
         player_movement.walking = false
      end

      drawable.sprite.scale = Vector2f.new(player_movement.look_direction, 1.0)
      animation.playing = player_movement.walking

      -- Play the step sound every two steps of the animation, which are the moments
      -- when the feet hit the ground
      if player_movement.walking and animation.current_frame % 2 == 0 and player_movement.step_sound.status ~= SoundStatus.Playing then
         player_movement.step_sound:play()
      end
   end
end

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

-- Player sprite loading

local dir_path = "resources/sprites/mainchar"
local dir_basename = path.basename(path.remove_dir_end(dir_path))
local sheet_path = path.join(dir_path, dir_basename) .. ".png"
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

local first_frame = animation_frames[1]

local player_texture = Texture.new()
player_texture:load_from_file(sheet_path)

local player_sprite = Sprite.new()
player_sprite.texture = player_texture
player_sprite.origin = Vector2f.new(first_frame.rect.width / 2, first_frame.rect.height)
player_sprite.position = Vector2f.new(180, 880)

local footstep_sound_path = "resources/sounds/footstep.ogg"
local step_sound_buf = SoundBuffer.new()
step_sound_buf:load_from_file(footstep_sound_path)

local step_sound = Sound.new()
step_sound.buffer = step_sound_buf

player:add(DrawableSpriteComponent(player_sprite, player_texture, 1))
player:add(AnimationComponent(animation_frames))
player:add(TransformableComponent(player_sprite))
player:add(PlayerMovementComponent(step_sound_buf, step_sound))

engine:addEntity(player)

local room_texture = Texture.new()
room_texture:load_from_file("resources/sprites/room/room.png")

local room_sprite = Sprite.new()
room_sprite.texture = room_texture

local room = Entity()
room:add(DrawableSpriteComponent(room_sprite, room_texture, 0))

engine:addEntity(room)

engine:addSystem(RenderSystem())
engine:addSystem(AnimationSystem())
engine:addSystem(PlayerMovementSystem())

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
