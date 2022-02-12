local path = require("path")
local fs = require("path.fs")
local class = require("middleclass")
local lume = require("lume")

local lines = require("terminal.lines")

local M = {}

M.known_slots = {}

M.SaveSlotsLine = class("SaveSlotsLine", lines.TerminalLine)
function M.SaveSlotsLine:initialize(args)
   M.SaveSlotsLine.super.initialize(self)

   -- Reset known slots
   M.known_slots = {}

   local slots = {}
   local i = 0

   if not fs.exists("saves") then fs.mkdir("saves") end
   for slot in fs.each({ file = "saves/*.toml" }) do
      i = i + 1

      local slot_name = path.splitext(path.basename(slot))

      local slot_line_text = lume.format("{1}. {2}", { i, slot_name })

      local text_object = Text.new(slot_line_text, StaticFonts.main_font, self._character.font_size)
      text_object.fill_color = self._character.color

      table.insert(slots, { text = slot_line_text, text_object = text_object, file_path = slot })
      -- Save the slot paths for usage from save_game
      table.insert(M.known_slots, slot)
   end
   self._slots = slots

   self._longest_line_length = 0
   for _, line in ipairs(slots) do
      if #line.text > self._longest_line_length then
         self._longest_line_length = #line.text
      end
   end
   self._longest_line_length = self._longest_line_length + 1

   self._next = lines.make_line(args.next, lines.native_lines)
end

function M.SaveSlotsLine:current_text()
   local max_width = lines.max_text_width()

   local output = {}

   local longest_done = self._longest_line_length == self._letters_output
   for _, slot in ipairs(self._slots) do
      if not longest_done then
         slot.text_object.string = lume.wordwrap(slot.text:sub(0, self._letters_output), max_width)
      end

      table.insert(output, slot.text_object)
   end

   return output
end

function M.SaveSlotsLine:next()
   return self._next
end

function M.SaveSlotsLine:should_wait()
   return self._letters_output < self._longest_line_length
end

function M.SaveSlotsLine:maybe_increment_letter_count()
   if self._letters_output < self._longest_line_length and self._time_since_last_letter >= lines.time_per_letter then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   end
end

function M.SaveSlotsLine:max_line_height(n)
   return lines.max_string_height(self._slots[n].text_object.string, self._character.font_size)
end

return M
