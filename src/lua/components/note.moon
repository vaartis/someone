toml = require("toml")
util = require("util")
lume = require("lume")

local interaction_components

NoteComponent = Component.create("Note", {"text", "bottom_text", "text_object", "bottom_text_object"})

NoteSystem = _G.class("NoteSystem", System)
NoteSystem.requires = () => {"Slices", "Note", "Transformable"}
NoteSystem.draw = () =>
  for _, entity in pairs @targets
    drawable = entity\get("Drawable")

    if drawable.enabled
      tf = entity\get("Transformable")
      slice, bottom_slice = do
        slices = entity\get("Slices").slices
        slices.text, slices.bottom_text

      note = entity\get("Note")

      if not note._formatted
        note._formatted = true

        max_text_len = util.rect_max_text_width(slice.width)
        note.text_object.string = lume.wordwrap(note.text, max_text_len)
        note.text_object.position = tf.transformable.position + Vector2f.new(slice.left, slice.top)

        note.bottom_text_object.string = lume.wordwrap(note.bottom_text, max_text_len)
        bottom_text_width = note.bottom_text_object.global_bounds.width
        note.bottom_text_object.position = tf.transformable.position + Vector2f.new(
            bottom_slice.left + bottom_slice.width - bottom_text_width,
            bottom_slice.top
        )
      GLOBAL.drawing_target\draw(note.text_object)
      GLOBAL.drawing_target\draw(note.bottom_text_object)
NoteInteractionSystem = _G.class("NoteInteractionSystem", System)
NoteInteractionSystem.requires = () => {
  objects: {"Note", "Drawable"},
  interaction_text: {"InteractionTextTag"}
}

NoteInteractionSystem.update = (dt) =>
  for _, entity in pairs @targets.objects
    drawable = entity\get("Drawable")

    if drawable.enabled
      engine = util.rooms_mod!.engine

      -- Keep the interaction and movement system disabled
      engine\stopSystem("InteractionSystem")
      engine\stopSystem("PlayerMovementSystem")

      interaction_text_key = lume.first(lume.keys(@targets.interaction_text))
      if not interaction_text_key then error("No interaction text entity found")
      interaction_text_drawable = @targets.interaction_text[interaction_text_key]\get("Drawable")
      if not interaction_text_drawable.enabled
        interaction_text_drawable.enabled = true
        interaction_text_drawable.drawable.string = "[E] to close the note"

      -- Lazy-load interaction_components
      if not interaction_components
        interaction_components = require("components.interaction")

      interaction_components.seconds_since_last_interaction += dt

      for _, native_event in pairs interaction_components.event_store.events
        event = native_event.event
        if interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction and
           event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
            interaction_components.seconds_since_last_interaction = 0
            -- Delete the note entity and re-enable interactions and movement
            engine\removeEntity(entity)
            engine\startSystem("InteractionSystem")
            engine\startSystem("PlayerMovementSystem")

process_components = (new_ent, comp_name, comp, entity_name) ->
  switch comp_name
    when "note"
      note_text = with Text.new("", StaticFonts.main_font, StaticFonts.font_size)
        .fill_color = Color.Black
      bottom_text = with Text.new("", StaticFonts.main_font, StaticFonts.font_size)
        .fill_color = Color.Black

      new_ent\add(NoteComponent(comp.text, comp.bottom_text, note_text, bottom_text))

      true

add_systems = (engine) ->
  with engine
    \addSystem(NoteSystem())
    \addSystem(NoteInteractionSystem())

read_note = (state, note_name) ->
    local notes
    with io.open("resources/rooms/notes.toml", "r")
      notes = toml.parse(\read("*all"))
      \close()

    note = notes[note_name]

    if not note
      error("Note #{note} not found")

    note_entity = util.entities_mod!.instantiate_entity("note_paper", {
        prefab: "note",
        note: { text: note.text, bottom_text: note.bottom_text }
    })
    util.rooms_mod!.engine\addEntity(note_entity)

{
  NoteComponent, NoteSystem, NoteInteractionSystem,
  :add_systems, :process_components,
  :read_note
}
