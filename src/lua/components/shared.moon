lovetoys = require("lovetoys")
path = require("path")
json = require("lunajson")
lume = require("lume")

assets = require("components.assets")

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

TransformableComponent = Component.create("Transformable", {"transformable", "local_position"})
TransformableComponent.world_position = (ent) =>
  if not ent.parent or not ent.parent.id
    @transformable.position
  else
    parent_tf = ent.parent\get("Transformable")

    @local_position + parent_tf\world_position(ent.parent)
TransformableComponent.set_world_position = (ent, pos) =>
  if not ent.parent or not ent.parent.id
    @transformable.position = pos
  else
    parent_tf = ent.parent\get("Transformable")

    @transformable.position = pos
    @local_position = @transformable.position - parent_tf\world_position(ent.parent)

  for _, child in pairs(ent.children)
    child_tf = child\get("Transformable")
    child_tf\update_local_position(child)
TransformableComponent.set_local_position = (ent, pos) =>
  if not ent.parent or not ent.parent.id
    @transformable.position = pos
  else
    parent_tf = ent.parent\get("Transformable")

    @local_position = pos
    @update_local_position(ent)

  for _, child in pairs(ent.children)
    child_tf = child\get("Transformable")
    child_tf\update_local_position(child)
TransformableComponent.update_local_position = (ent) =>
    parent_tf = ent.parent\get("Transformable")

    @transformable.position = @local_position + parent_tf\world_position(ent.parent)
    for _, child in pairs(ent.children)
      child_tf = child\get("Transformable")
      child_tf\update_local_position(child)

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

process_components = (new_ent, comp_name, comp, entity_name) ->
  switch comp_name
    when "drawable"
      unless comp.z then
        error(lume.format("{1}.{2} requires a {3} value", {entity_name, comp_name, "z"}))

      local drawable
      switch comp.kind
        when "sprite"
          texture_asset = assets.assets.textures[comp.texture_asset]
          unless texture_asset
            error(lume.format("{1}.{2} requires a texture named {3}", {entity_name, comp_name, comp.texture_asset}))

          drawable = with Sprite.new!
            .texture = texture_asset
        when "text"
          drawable = Text.new(comp.text.text, StaticFonts.main_font, comp.text.font_size or StaticFonts.font_size)
        else
          error("Unknown kind of drawable kind in #{entity_name}.#{comp_name}")

      new_ent\add(
        DrawableComponent(
          drawable, comp.z, comp.kind, (if comp.enabled ~= nil then comp.enabled else true), comp.layer
        )
      )

      new_ent\add(TransformableComponent(drawable))

      true
    when "animation"
      sheet_frames = load_sheet_data(comp.sheet)

      anim = with AnimationComponent(sheet_frames)
        .playable = comp.playable if type(comp.playable) == "boolean"
        .playing = comp.playing if type(comp.playing) == "boolean"
        .current_frame = comp.starting_frame or 1

      new_ent\add(anim)

      true
    when "slices"
      _, slices = load_sheet_data(comp.sheet)
      new_ent\add(SlicesComponent(slices))

      true

add_systems = (engine) ->
  with engine
    \addSystem(RenderSystem())
    \addSystem(AnimationSystem())

{
  :process_components, :add_systems,
  :DrawableComponent, :RenderSystem,
  :AnimationComponent, :AnimationSystem,
  :TransformableComponent,
  :SlicesComponent,
  :load_sheet_data
}
