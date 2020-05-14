lovetoys = require("lovetoys")
path = require("path")
json = require("lunajson")
lume = require("lume")

lovetoys.initialize({
      debug: true,
      globals: true
})

DrawableComponent = Component.create("Drawable", {"drawable", "z", "kind", "enabled", "layer"})

RenderSystem = _G.class("RenderSystem", System)
RenderSystem.requires = () =>
   {"Drawable"}
RenderSystem._sort_targets = () =>
  -- Sorts targets according to the Z level.
  -- This has to be done in a roundabout way because sorting DOESN'T WORK
  -- on sequences with gaps, and pairs ignores sorting, so a separate,
  -- sorted array of targets needs to be stored for drawing

  entities = {}
  for _, v in pairs @targets do table.insert(entities, v)

  table.sort(
    entities,
    (a, b) ->
      drawable_a = a\get("Drawable")
      drawable_b = b\get("Drawable")

      drawable_a.z < drawable_b.z
  )
  @_sorted_targets = entities
RenderSystem.onAddEntity = () => @_sort_targets!
RenderSystem.onRemoveEntity = () => @_sort_targets!

RenderSystem.draw = (layer) =>
  for _, entity in ipairs @_sorted_targets
    drawable = entity\get("Drawable")

    if drawable.enabled
      if layer
        -- If the layer is specified, only draw entities on the layer
        if drawable.layer == layer
          GLOBAL.drawing_target\draw(drawable.drawable)
      else
        -- Otherwise draw those that don't have a layer
        if not drawable.layer
          GLOBAL.drawing_target\draw(drawable.drawable)

TransformableComponent = Component.create("Transformable", {"transformable"})

AnimationComponent = Component.create(
   "Animation",
   {"frames", "current_frame", "playable", "playing", "time_since_frame_change"},
   { time_since_frame_change: 0, playable: true, playing: false, current_frame: 1 }
)

AnimationSystem = _G.class("AnimationSystem", System)
AnimationSystem.requires = () =>
  {"Drawable", "Animation"}
AnimationSystem.update = (dt) =>
  for _, entity in pairs @targets
    with entity\get("Animation")
      .time_since_frame_change += dt

      if .playable and .playing then
        if .time_since_frame_change > .frames[.current_frame].duration then
          .time_since_frame_change = 0

          if .current_frame + 1 <= #.frames
            .current_frame = .current_frame + 1
          else
            .current_frame = 1
      elseif .playable and not .playing then
        .current_frame = 1


      entity\get("Drawable").drawable.texture_rect = .frames[.current_frame].rect

SlicesComponent = Component.create("Slices", {"slices"})

load_sheet_data = (dir_path) ->
  dir_basename = path.basename(path.remove_dir_end(dir_path))
  json_path = "#{path.join(dir_path, dir_basename)}.json"

  local sprite_json
  with io.open(json_path, "r")
    sprite_json = json.decode(\read("*all"))
    \close()

  animation_frames = {}
  for fname, frame in pairs(sprite_json["frames"])
    frame_f = frame["frame"]

    -- Extract the frame number from the name
    -- For this to work, the format in sprite export has to be set to {frame1}
    frame_num = tonumber(fname)

    animation_frames[frame_num] = {
      -- Translate duration to seconds
      duration: frame["duration"] / 1000,
      rect: IntRect.new(
        frame_f["x"], frame_f["y"], frame_f["w"], frame_f["h"]
      )
    }

  local slices
  if sprite_json.meta.slices
    slices = {}
    for _, slice in pairs(sprite_json.meta.slices)
      -- For now, just get the first one
      with slice.keys[1].bounds
        slices[slice.name] = IntRect.new(.x, .y, .w, .h)

  animation_frames, slices

{
  :DrawableComponent, :RenderSystem,
  :AnimationComponent, :AnimationSystem,
  :TransformableComponent,
  :SlicesComponent
  :load_sheet_data
}
