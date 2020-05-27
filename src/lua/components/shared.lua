local lovetoys = require("lovetoys")
local path = require("path")
local json = require("lunajson")
local lume = require("lume")

local assets = require("components.assets")

lovetoys.initialize({
      debug = true,
      globals = true
})

local DrawableComponent = Component.create("Drawable", {"drawable", "z", "kind", "enabled", "layer"})

local RenderSystem = _G.class("RenderSystem", System)
function RenderSystem:requires() return { "Drawable" } end
function RenderSystem:_sort_targets()
   -- Sorts targets according to the Z level.
   -- This has to be done in a roundabout way because sorting DOESN'T WORK
   -- on sequences with gaps, and pairs ignores sorting, so a separate,
   -- sorted array of targets needs to be stored for drawing

   local entities = {}
   for _, v in pairs(self.targets) do table.insert(entities, v) end

   table.sort(
      entities,
      function(a, b)
         local drawable_a = a:get("Drawable")
         local drawable_b = b:get("Drawable")
         return drawable_a.z < drawable_b.z
      end
   )
   self._sorted_targets = entities
end

function RenderSystem:onAddEntity() self:_sort_targets() end
function RenderSystem:onRemoveEntity() self:_sort_targets() end
function RenderSystem:draw(layer)
   for _, entity in ipairs(self._sorted_targets) do
      local drawable = entity:get("Drawable")

      if drawable.enabled then
         if layer then
            -- If the layer is specified, only draw entities on the layer
            if drawable.layer == layer then GLOBAL.drawing_target:draw(drawable.drawable) end
         else
            -- Otherwise draw those that don't have a layer
            if not drawable.layer then GLOBAL.drawing_target:draw(drawable.drawable) end
         end
      end
   end
end

local M = {}

M.TransformableComponent = Component.create("Transformable", {"transformable", "local_position"})
function M.TransformableComponent:world_position(ent)
   if not ent.parent or not ent.parent.id then
      return self.transformable.position
   else
      local parent_tf = ent.parent:get("Transformable")

      return self.local_position + parent_tf:world_position(ent.parent)
   end
end
function M.TransformableComponent:set_world_position(ent, pos)
   if not ent.parent or not ent.parent.id then
      self.transformable.position = pos
   else
      local parent_tf = ent.parent:get("Transformable")

      self.transformable.position = pos
      self.local_position = self.transformable.position - parent_tf:world_position(ent.parent)
   end

   for _, child in pairs(ent.children) do
      local child_tf = child:get("Transformable")
      child_tf:update_position(child)
   end
end
function M.TransformableComponent:set_local_position(ent, pos)
   if not ent.parent or not ent.parent.id then
      self.transformable.position = pos
   else
      local parent_tf = ent.parent:get("Transformable")

      self.local_position = pos
      self:update_position(ent)
   end

   for _, child in pairs(ent.children) do
      local child_tf = child:get("Transformable")
      child_tf:update_position(child)
   end
end
function M.TransformableComponent:update_position(ent)
   local parent_tf = ent.parent:get("Transformable")

   self.transformable.position = self.local_position + parent_tf:world_position(ent.parent)

   for _, child in pairs(ent.children) do
      local child_tf = child:get("Transformable")
      child_tf:update_position(child)
   end
end

local AnimationComponent = Component.create(
   "Animation",
   {"frames", "current_frame", "playable", "playing", "time_since_frame_change"},
   { time_since_frame_change = 0, playable = true, playing = false, current_frame = 1 }
)

local AnimationSystem = class("AnimationSystem", System)
function AnimationSystem:requires() return { "Drawable", "Animation" } end
function AnimationSystem:update(dt)
   for _, entity in pairs(self.targets) do
      local anim_comp = entity:get("Animation")

      anim_comp.time_since_frame_change = anim_comp.time_since_frame_change + dt

      if anim_comp.playable and anim_comp.playing then
         if anim_comp.time_since_frame_change > anim_comp.frames[anim_comp.current_frame].duration then
            anim_comp.time_since_frame_change = 0

            if anim_comp.current_frame + 1 <= #anim_comp.frames then
               anim_comp.current_frame = anim_comp.current_frame + 1
            else
               anim_comp.current_frame = 1
            end
         end
      elseif anim_comp.playable and not anim_comp.playing then
         anim_comp.current_frame = 1
      end

      entity:get("Drawable").drawable.texture_rect = anim_comp.frames[anim_comp.current_frame].rect
   end
end

local SlicesComponent = Component.create("Slices", {"slices"})

function M.load_sheet_data(dir_path)
   local dir_basename = path.basename(path.remove_dir_end(dir_path))
   local json_path = tostring(path.join(dir_path, dir_basename)) .. ".json"

   local file = io.open(json_path, "r")
   local sprite_json = json.decode(file:read("*all"))
   file:close()

   local animation_frames = {}
   for fname, frame in pairs(sprite_json["frames"]) do
      local frame_f = frame["frame"]

      -- Extract the frame number from the name
      -- For this to work, the format in sprite export has to be set to {frame1}
      local frame_num = tonumber(fname)

      animation_frames[frame_num] = {
         -- Translate duration to seconds
         duration = frame["duration"] / 1000,
         rect = IntRect.new(
            frame_f["x"], frame_f["y"], frame_f["w"], frame_f["h"]
         )
      }
   end

   local slices
   if sprite_json.meta.slices then
      slices = {}
      for _, slice in pairs(sprite_json.meta.slices) do
         -- For now, just get the first one
         local bounds = slice.keys[1].bounds
         slices[slice.name] = IntRect.new(bounds.x, bounds.y, bounds.w, bounds.h)
      end
   end

   return animation_frames, slices
end

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "drawable" then
      if not (comp.z) then
         error(lume.format("{1}.{2} requires a {3} value", {entity_name, comp_name, "z"}))
      end

      local drawable
      if comp.kind == "sprite" then
         local texture_asset = assets.assets.textures[comp.texture_asset]
         if not texture_asset then
            error(lume.format("{1}.{2} requires a texture named {3}", {entity_name, comp_name, comp.texture_asset}))
         end

         drawable = Sprite.new()
         drawable.texture = texture_asset
      elseif comp.kind == "text" then
         drawable = Text.new(comp.text.text, StaticFonts.main_font, comp.text.font_size or StaticFonts.font_size)
      else
         error("Unknown kind of drawable in " .. tostring(entity_name) .. "." .. tostring(comp_name))
      end

      local enabled
      if comp.enabled ~= nil then
         enabled = comp.enabled
      else
         enabled = true
      end

      new_ent:add(
         DrawableComponent(drawable, comp.z, comp.kind, enabled, comp.layer)
      )
      new_ent:add(M.TransformableComponent(drawable))

      return true
   elseif comp_name == "animation" then
      local sheet_frames = M.load_sheet_data(comp.sheet)

      local anim = AnimationComponent(sheet_frames)
      if type(comp.playable) == "boolean" then anim.playable = comp.playable end
      if type(comp.playing) == "boolean" then anim.playing = comp.playing end
      anim.current_frame = comp.starting_frame or 1

      new_ent:add(anim)

      return true
   elseif comp_name == "slices" then
      local _, slices = M.load_sheet_data(comp.sheet)
      new_ent:add(SlicesComponent(slices))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(RenderSystem())
   engine:addSystem(AnimationSystem())
end

return M
