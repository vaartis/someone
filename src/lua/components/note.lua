local util = require("util")
local lume = require("lume")
local debug_components = require("components.debug")

local interaction_components

local M = {}

M.components = {
   note = {
      class = Component.create(
         "Note",
         {"pages", "text_object", "bottom_text_object", "page_number_text_object", "current_page"},
         { current_page = 1, displayed_page = -1 }
      )
   }
}

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

         if note.displayed_page ~= note.current_page then
            -- Make the current page the displayed one
            note.displayed_page = note.current_page

            local page = note.pages[note.displayed_page]

            local max_text_len = util.rect_max_text_width(slice.width)
            note.text_object.string = lume.wordwrap(page.text, max_text_len)
            note.text_object.position = tf:world_position(entity) + Vector2f.new(slice.left, slice.top)

            if page.bottom_text then
               note.bottom_text_object.string = lume.wordwrap(page.bottom_text, max_text_len)
               local bottom_text_width = note.bottom_text_object.global_bounds.width
               note.bottom_text_object.position =
                  tf:world_position(entity) + Vector2f.new(bottom_slice.left + bottom_slice.width - bottom_text_width, bottom_slice.top)
            end

            if #note.pages > 1 then
               note.page_number_text_object.position =
                  tf:world_position(entity) + Vector2f.new(bottom_slice.left + bottom_slice.width, bottom_slice.top)
               note.page_number_text_object.string = lume.format("{1}/{2}", {note.displayed_page, #note.pages})
            end
         end

         GLOBAL.drawing_target:draw(note.text_object)
         GLOBAL.drawing_target:draw(note.bottom_text_object)
         if #note.pages > 1 then
            GLOBAL.drawing_target:draw(note.page_number_text_object)
         end
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
      local note = entity:get("Note")

      local rooms = util.rooms_mod()

      local engine = rooms.engine

      -- Lazy-load interaction_components
      if not interaction_components then
         interaction_components = require("components.interaction")
      end

      -- Keep the player disabled
      interaction_components.disable_player(engine)
      local disabled_tile = false
      if lume.count(engine:getEntitiesWithComponent("TilePlayer")) > 0 then
         -- Keep the tile player disabled
         engine:stopSystem("TilePlayerSystem")
         disabled_tile = true
      end

      local interaction_text_drawable = util.first(self.targets.interaction_text):get("Drawable")
      if not interaction_text_drawable.enabled then
         interaction_text_drawable.enabled = true
         interaction_text_drawable.drawable.string = "[E] to close the note"
         if #note.pages > 1 then
            interaction_text_drawable.drawable.string = interaction_text_drawable.drawable.string ..
               ", [A/D] to turn pages"
         end
      end

      interaction_components.update_seconds_since_last_interaction(dt)
      interaction_components.if_key_pressed({
            [KeyboardKey.E] = function()
               -- Delete the note entity and re-enable the player
               engine:removeEntity(entity, true)
               -- Re-enabled player
               interaction_components.enable_player(engine)
               if disabled_tile then
                  -- Re-enable tile player
                  engine:startSystem("TilePlayerSystem")
                  interaction_text_drawable.enabled = false
               end
            end,
            [KeyboardKey.D] = function()
               if note.current_page + 1 <= #note.pages then
                  note.current_page = note.current_page + 1
               end
            end,
            [KeyboardKey.A] = function()
               if note.current_page - 1 <= 1 then
                  note.current_page = note.current_page - 1
               end
            end
      })
   end
end

function M.components.note.process_component(new_ent, comp, entity_name)
   local note_text = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
   note_text.fill_color = Color.Black
   local bottom_text = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
   bottom_text.fill_color = Color.Black
   local page_number_text = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
   page_number_text.fill_color = Color.Black

   new_ent:add(M.components.note.class(comp.pages, note_text, bottom_text, page_number_text))
end

M.systems = {
   NoteSystem,
   NoteInteractionSystem
}

M.interaction_callbacks = {}

function M.interaction_callbacks.read_note(state, note_name)
   local notes = TOML.parse("resources/rooms/notes.toml")

   local note = notes[note_name]

   if not note then
      error("Note " .. tostring(note) .. " not found")
   end

   local pages = { note }

   local note_name, note_number = note_name:match("(.+)(%d+)$")
   if note_number then
      note_number = tonumber(note_number) + 1

      local next_page = note_name .. note_number
      while notes[next_page] do
         table.insert(pages, notes[next_page])

         note_number = note_number + 1
         next_page = note_name .. note_number
      end
   end

   local mod = util.entities_mod()
   mod.instantiate_entity(
      "note_paper",
      {
         prefab = "note",
         note = { pages = pages }
      }
   )
end
debug_components.declare_callback_args( M.interaction_callbacks.read_note, {"string"})

return M
