local tiny = require("tiny")
local class = require("middleclass")
local inspect = require("inspect")

--[[ Calculates the maximum text width in the terminal ]]
function max_text_width()
   local win_size = DRAWING_TARGET.size

   local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2

   local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   return math.floor((rect_width - (width_offset * 2)) / (StaticFonts.font_size / 2.0))
end

local time_per_letter = 0.1


local TerminalLine = class("TerminalLine")
function TerminalLine:initialize(character_config)
   self._character = character_config

   self._letters_output = 0
   self._time_since_last_letter = 0.0
end

local OutputLine = class("OutputLine", TerminalLine)
function OutputLine:initialize(text, next_line, character_config)
   TerminalLine.initialize(self, character_config)

   self._text = text
   self._next_line = next_line
end

function OutputLine:max_line_height()
   local term_width = max_text_width()

   local fit_str = StringUtils.wrap_words_at(self._text, term_width)

   local tmp_text = Text.new(fit_str, StaticFonts.main_font, StaticFonts.font_size)

   return tmp_text.global_bounds.height
end

function OutputLine:should_wait()
   return self._letters_output < #self._text and self._time_since_last_letter < 0.1
end

function OutputLine:tick_letter_timer(dt)
   self._time_since_last_letter = self._time_since_last_letter + dt
end

function OutputLine:maybe_increment_letter_count()
   if self._letters_output < #self._text and self._time_since_last_letter >= time_per_letter then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   end
end

function OutputLine:current_text()
   local substr = StringUtils.wrap_words_at(
      self._text:sub(0, self._letters_output),
      max_text_width()
   )


   local txt = Text.new(substr, StaticFonts.main_font, StaticFonts.font_size)
   txt.fill_color = self._character.color
   
   return txt
end

-- classic.strict(OutputLine)

--[[
local updateLines = tiny.system()
updateLines.filter = tiny.requireAll("text")
function updateLines:update(dt)
   for _, ent in pairs(self.entities) do
      print(ent.text)
   end
end

local world = tiny.world(test_line, orderLinesSystem)
]]

local lines = {}

return {
   add = function(text, nxt, char)      
      local l = OutputLine:new(text, nxt, char)
      
      table.insert(lines, OutputLine(text, nxt, char))
   end,
   
   draw = function(dt)
      for _, line in pairs(lines) do         
         local should_wait = line:should_wait()
         if should_wait then
            line:tick_letter_timer(dt)
            line:maybe_increment_letter_count()
         end

         local text = line:current_text()
         text.position = Vector2f.new(200, 200)

         DRAWING_TARGET:draw(text)
      end
   end
}
