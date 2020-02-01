local lovetoys = require("lovetoys")
local path = require("path")
local json = require("lunajson")
local lume = require("lume")

lovetoys.initialize({
      debug = true,
      globals = true
})

local M = {}

M.DrawableSpriteComponent = Component.create("DrawableSprite", {"sprite", "texture", "z"})

M.RenderSystem = class("RenderSystem", System)

function M.RenderSystem:requires()
   return {"DrawableSprite"}
end

function M.RenderSystem:onAddEntity(entity)
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

function M.RenderSystem:draw()
   for _, entity in pairs(self.targets) do
      local drawable = entity:get("DrawableSprite")

      GLOBAL.drawing_target:draw(drawable.sprite)
   end
end

M.TransformableComponent = Component.create("Transformable", {"transformable"})

M.AnimationComponent = Component.create(
   "Animation",
   {"frames", "current_frame", "playable", "playing", "time_since_frame_change"},
   { time_since_frame_change = 0, playable = true, playing = false, current_frame = 1 }
)

M.AnimationSystem = class("AnimationSystem", System)

function M.AnimationSystem:requires()
   return {"DrawableSprite", "Animation"}
end

function M.AnimationSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local anim = entity:get("Animation")

      anim.time_since_frame_change = anim.time_since_frame_change + dt

      if anim.playable and anim.playing then
         if anim.time_since_frame_change > anim.frames[anim.current_frame].duration then
            anim.time_since_frame_change = 0

            if anim.current_frame + 1 <= #anim.frames then
               anim.current_frame = anim.current_frame + 1
            else
               anim.current_frame = 1
            end
         end
      elseif anim.playable and not anim.playing then
         anim.current_frame = 1
      end

      local drawable = entity:get("DrawableSprite")
      drawable.sprite.texture_rect = anim.frames[anim.current_frame].rect
   end
end

-- Loads the spritesheet frames from the spritesheet directory
function M.load_sheet_frames(dir_path)
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

return M
