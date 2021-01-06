local lovetoys = require("lovetoys")
local path = require("path")
local json = require("lunajson")
local lume = require("lume")

local assets = require("components.assets")
local interaction_components = require("components.interaction")
local collider_components = require("components.collider")

local M = {}

M.components = {
   drawable = {
      class = Component.create("Drawable", {"drawable", "z", "kind", "enabled", "layer"})
   },
   animation = {
      class = Component.create(
         "Animation",
         {"frames", "current_frame", "playable", "playing", "time_since_frame_change"},
         { time_since_frame_change = 0, playable = true, playing = false, current_frame = 1 }
      )
   },
   slices = {
      class = Component.create("Slices", {"slices"})
   },
   transformable = {
      class = Component.create("Transformable", {"transformable", "local_position"}),
      -- Put the priority high so it's last (but before collider)
      processing_priority = 1000
   },
   name = {
      class = Component.create("Name", {"name"})
   }
}

local RenderSystem = class("RenderSystem", System)
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

      local enabled = drawable.enabled
      if type(enabled) == "function" then
         enabled = enabled()
      end

      if enabled then
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

function M.components.transformable.class:world_position(ent)
   if not ent.parent or not ent.parent.id then
      return self.transformable.position
   else
      local parent_tf = ent.parent:get("Transformable")

      return self.local_position + parent_tf:world_position(ent.parent)
   end
end
function M.components.transformable.class:set_world_position(ent, pos)
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
function M.components.transformable.class:set_local_position(ent, pos)
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
function M.components.transformable.class:update_position(ent)
   local parent_tf = ent.parent:get("Transformable")

   self.transformable.position = self.local_position + parent_tf:world_position(ent.parent)

   for _, child in pairs(ent.children) do
      local child_tf = child:get("Transformable")
      child_tf:update_position(child)
   end
end

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

      local next_frame = anim_comp.frames[anim_comp.current_frame]
      if not next_frame then
         local name = entity:get("Name").name
         error(lume.format("Can't find animation frame {1} for entity {2}", {anim_comp.current_frame, name}))
      end

      entity:get("Drawable").drawable.texture_rect = next_frame.rect
   end
end

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

function M.components.transformable.process_component(new_ent, comp, entity_name, parent)
   if not (new_ent:has("Transformable")) then
      -- If there's no transformable component, create and add it
      new_ent:add(M.components.transformable.class(Transformable.new()))
   end
   local tf_component = new_ent:get("Transformable")

   local transformable = tf_component.transformable
   if parent then
      local parent_tf = parent:get("Transformable").transformable
      local relative_position = Vector2f.new(comp.position[1], comp.position[2])
      -- Apply the position in relation to the parent position
      transformable.position = parent_tf.position + relative_position

      tf_component.local_position = relative_position
   else
      transformable.position = Vector2f.new(comp.position[1], comp.position[2])

      tf_component.local_position = Vector2f.new(0, 0)
   end

   if comp.origin then transformable.origin = Vector2f.new(comp.origin[1], comp.origin[2]) end
   if comp.scale then transformable.scale = Vector2f.new(comp.scale[1], comp.scale[2]) end
end

function M.components.drawable.process_component(new_ent, comp, entity_name)
   local comp_name = "drawable"

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

   local enabled = interaction_components.process_activatable(
      comp,
      "enabled",
      { entity_name = entity_name, comp_name = comp_name, needed_for = "enabled" }
   )

   new_ent:add(
      M.components.drawable.class(drawable, comp.z, comp.kind, enabled, comp.layer)
   )
   new_ent:add(M.components.transformable.class(drawable))
end

function M.components.animation.process_component(new_ent, comp, entity_name)
   local sheet_frames = M.load_sheet_data(comp.sheet)

   local anim = M.components.animation.class(sheet_frames)
   if type(comp.playable) == "boolean" then anim.playable = comp.playable end
   if type(comp.playing) == "boolean" then anim.playing = comp.playing end
   anim.current_frame = comp.starting_frame or 1

   new_ent:add(anim)
end

function M.components.slices.process_component(new_ent, comp, entity_name)
   local _, slices = M.load_sheet_data(comp.sheet)
   new_ent:add(M.components.slices.class(slices))
end

function M.add_systems(engine)
   engine:addSystem(RenderSystem())
   engine:addSystem(AnimationSystem())
end

function M.components.transformable.class:default_data(ent)
   return { position = { 0, 0 } }
end

function M.components.transformable.class:show_editor(ent)
   ImGui.Text("Transformable")

   local tf = self.transformable
   if ent:get("Collider") then
      ImGui.Text(lume.format("X = {1}, Y = {2}", {tf.position.x, tf.position.y}))
   else
      local x, y = table.unpack(ImGui.InputInt2("XY", {tf.position.x, tf.position.y}))
      tf.position = Vector2f.new(x, y)

      if ImGui.Button("Save") then
         TOML.save_entity_component(ent, "transformable", self, { position = { x, y } })
      end
   end
end

function M.components.name.class:show_editor(ent)
   ImGui.Text("Name" .. " =")
   ImGui.SameLine()
   ImGui.Text(self.name)
end

M.system_run_priority = 0

return M
