lovetoys = require("lovetoys")
path = require("path")
json = require("lunajson")
lume = require("lume")

lovetoys.initialize({
      debug: true,
      globals: true
})

DrawableSpriteComponent = Component.create("DrawableSprite", {"sprite", "z"})

RenderSystem = _G.class("RenderSystem", System)
RenderSystem.requires = () =>
   {"DrawableSprite"}
RenderSystem.onAddEntity = (entity) =>
  -- Sort targets according to the z level
  @targets = lume.sort(
      @targets,
      (a, b) ->
        drawable_a = a\get("DrawableSprite")
        drawable_b = b\get("DrawableSprite")

        drawable_a.z < drawable_b.z
    )
RenderSystem.draw = () =>
  for _, entity in pairs @targets
    drawable = entity\get("DrawableSprite")

    GLOBAL.drawing_target\draw(drawable.sprite)

TransformableComponent = Component.create("Transformable", {"transformable"})

AnimationComponent = Component.create(
   "Animation",
   {"frames", "current_frame", "playable", "playing", "time_since_frame_change"},
   { time_since_frame_change: 0, playable: true, playing: false, current_frame: 1 }
)

AnimationSystem = _G.class("AnimationSystem", System)
AnimationSystem.requires = () =>
  {"DrawableSprite", "Animation"}
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


      entity\get("DrawableSprite").sprite.texture_rect = .frames[.current_frame].rect

load_sheet_frames = (dir_path) ->
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
    frame_num = tonumber(fname)

    animation_frames[frame_num] = {
      -- Translate duration to seconds
      duration: frame["duration"] / 1000,
      rect: IntRect.new(
        frame_f["x"], frame_f["y"], frame_f["w"], frame_f["h"]
      )
    }

  animation_frames

{
  :DrawableSpriteComponent, :RenderSystem,
  :AnimationComponent, :AnimationSystem,
  :TransformableComponent,
  :load_sheet_frames
}
