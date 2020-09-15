local toml = require("toml")
local util = require("util")
local lume = require("lume")

local interaction_components

local NoteComponent = Component.create("Note", {"text", "bottom_text", "text_object", "bottom_text_object"})

local NoteSystem = class("NoteSystem", System)
function NoteSystem:requires() return { "Slices", "Note", "Transformable" } end
function NoteSystem:draw()
   for _, entity in pairs(self.targets) do
      local drawable = entity:get("Drawable")

      if drawable.enabled then
         local tf = entity:get("Transformable")
         local slices = entity:get("Slices").slices
         local slice, bottom_slice = slices.text, slices.bottom_text

         local note = entity:get("Note")

         if not note._formatted then
            note._formatted = true

            local max_text_len = util.rect_max_text_width(slice.width)
            note.text_object.string = lume.wordwrap(note.text, max_text_len)
            note.text_object.position = tf:world_position(entity) + Vector2f.new(slice.left, slice.top)

            note.bottom_text_object.string = lume.wordwrap(note.bottom_text, max_text_len)
            local bottom_text_width = note.bottom_text_object.global_bounds.width
            note.bottom_text_object.position =
               tf:world_position(entity) + Vector2f.new(bottom_slice.left + bottom_slice.width - bottom_text_width, bottom_slice.top)
         end

         GLOBAL.drawing_target:draw(note.text_object)
         GLOBAL.drawing_target:draw(note.bottom_text_object)
      end
   end
end

local NoteInteractionSystem = class("NoteInteractionSystem", System)
function NoteInteractionSystem:requires()
   return {
      objects = { "Note", "Drawable" },
      interaction_text = { "InteractionTextTag" }
   }
end
function NoteInteractionSystem:update(dt)
   for _, entity in pairs(self.targets.objects) do
      local drawable = entity:get("Drawable")

      if drawable.enabled then
         local engine = util.rooms_mod().engine

         -- Keep the interaction and movement system disabled
         engine:stopSystem("InteractionSystem")
         engine:stopSystem("PlayerMovementSystem")

         local interaction_text_drawable = util.first(self.targets.interaction_text):get("Drawable")
         if not interaction_text_drawable.enabled then
            interaction_text_drawable.enabled = true
            interaction_text_drawable.drawable.string = "[E] to close the note"
         end

         -- Lazy-load interaction_components
         if not interaction_components then
            interaction_components = require("components.interaction")
         end

         interaction_components.seconds_since_last_interaction = interaction_components.seconds_since_last_interaction + dt

         for _, native_event in pairs(interaction_components.event_store.events) do
            local event = native_event.event
            if interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction and
            event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
               interaction_components.seconds_since_last_interaction = 0
               -- Delete the note entity and re-enable interactions and movement
               engine:removeEntity(entity)
               engine:startSystem("InteractionSystem")
               engine:startSystem("PlayerMovementSystem")
            end
         end
      end
   end
end

local M = {}

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "note" then
      local note_text = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
      note_text.fill_color = Color.Black
      local bottom_text = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
      bottom_text.fill_color = Color.Black

      new_ent:add(NoteComponent(comp.text, comp.bottom_text, note_text, bottom_text))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(NoteSystem())
   engine:addSystem(NoteInteractionSystem())
end

M.interaction_callbacks = {}

function M.interaction_callbacks.read_note(state, note_name)
   local file = io.open("resources/rooms/notes.toml", "r")
   local notes = toml.parse(file:read("*all"))
   file:close()

   local note = notes[note_name]

   if not note then
      error("Note " .. tostring(note) .. " not found")
   end

   local mod = util.entities_mod()
   mod.instantiate_entity(
      "note_paper",
      {
         prefab = "note",
         note = {
            text = note.text,
            bottom_text = note.bottom_text
         }
      }
   )
end

return M
