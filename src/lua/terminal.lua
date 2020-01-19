local tiny = require("tiny")
local class = require("middleclass")
local inspect = require("inspect")

-- Calculates the maximum text width in the terminal
function max_text_width()
   local win_size = DRAWING_TARGET.size

   local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2

   local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   return math.floor((rect_width - (width_offset * 2)) / (StaticFonts.font_size / 2.0))
end

local time_per_letter = 0.01

local TerminalLine = class("TerminalLine")
function TerminalLine:initialize()
   self._character = nil

   self._letters_output = 0
   self._time_since_last_letter = 0.0

   -- The script to execute on first line evaluation and whether it was executed already or not
   self._script = nil
   self._script_executed = false
end

function TerminalLine:tick_letter_timer(dt)
   self._time_since_last_letter = self._time_since_last_letter + dt
end

local OutputLine = class("OutputLine", TerminalLine)
function OutputLine:initialize(text, next_line)
   TerminalLine.initialize(self)

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

function OutputLine:next()
   return self._next_line
end

local DescriptionLine = class("DescriptionLine", OutputLine)
function DescriptionLine:initialize(text, next_line)
   OutputLine.initialize(self, text, next_line)

   self._space_pressed = false
end

function DescriptionLine:current_text()
   local final_text = self._text:sub(0, self._letters_output)
   if (self._letters_output == #self._text and not self._space_pressed) then
      final_text = final_text .. "\n[Press Space to continue]"
   end
   
   local substr = StringUtils.wrap_words_at(
      final_text,
      max_text_width()
   )

   local txt = Text.new(substr, StaticFonts.main_font, StaticFonts.font_size)
   txt.fill_color = self._character.color
   
   return txt
end

function DescriptionLine:should_wait()
   return OutputLine.should_wait(self) or not self._space_pressed
end

function DescriptionLine:is_interactive()
   return self._letters_output == #self._text and not self._space_pressed
end

function DescriptionLine:handle_interaction(event)
   if event.type == EventType.KeyReleased then
      local key = event.key.code

      if key == KeyboardKey.Space then
         self._space_pressed = true
      end
   end
end

local VariantInputLine = class("VariantInputLine", TerminalLine)
function VariantInputLine:initialize(variants)
   TerminalLine.initialize(self)
   
   -- Same as if it was unset. Just to have the name mentioned somewhere beforehand
   self._selected_variant = nil

   self._variants = {}
   for _, text, nxt in pairs(variants) do
      table.insert(self._variants, { text = text, next = nxt })
   end

   self._longest_var_length = -1
   for n, var in ipairs(self._variants) do
      local len = #var.text
      if len > self._longest_var_length then
         self._longest_var_length = len
      end
   end
end

function VariantInputLine:max_line_height(variant)
   local term_width = max_text_width()

   local fit_str = StringUtils.wrap_words_at(self._variants[variant].text, term_width)

   local tmp_text = Text.new(fit_str, StaticFonts.main_font, StaticFonts.font_size)

   return tmp_text.global_bounds.height
end

function VariantInputLine:should_wait()
   return (self._letters_output < self._longest_var_length and self._time_since_last_letter < time_per_letter) or not self._selected_variant;
end

function VariantInputLine:maybe_increment_letter_count()
    if self._letters_output < self._longest_var_length and self._time_since_last_letter >= time_per_letter then
       self._time_since_last_letter = 0.0;

       self._letters_output = self._letters_output + 1
    end
end

function VariantInputLine:current_text()
   local max_width = max_text_width()

   local result = {}
   for n, var in ipairs(self._variants) do
      local var_str = var.text

      local substr = n .. ". " .. StringUtils.wrap_words_at(var_str:sub(0, self._letters_output), max_width)
      local txt = Text.new(substr, StaticFonts.main_font, StaticFonts.font_size)
      txt.fill_color = self._character.color

      if (self._selected_variant == n) then
         txt.style = TextStyle.Underlined
      end

      table.insert(result, txt)
   end

   return result
end

function VariantInputLine:next()
   if not self._selected_variant then
      return "";
   end

   return self._variants[self._selected_variant].next
end

function VariantInputLine:is_interactive()
   return self._letters_output == self._longest_var_length and not self._selected_variant
end

function VariantInputLine:handle_interaction(event)
   if event.type == EventType.TextEntered then
      local ch = string.char(event.text.unicode)

      -- Convert the character to it's number equivalent
      local chnum = tonumber(ch)
      
      -- Add 1 because indexes start at 1 in lua
      if chnum and chnum >= 1 and chnum < #self._variants + 1 then
         self._selected_variant = chnum
      end
   end
end

local lines = {}

local first_line_on_screen = "prologue/1"

local current_environment_texture, current_environment_sprite

function add(in_lines)
   for name, line in pairs(in_lines) do
      local tp = line.__type.name

      local to_insert      
      if tp == "TerminalOutputLineData" then
         to_insert = OutputLine(line.text, line.next, line.character_config)
      elseif tp == "TerminalDescriptionLineData" then
         to_insert = DescriptionLine(line.text, line.next, line.character_config)
      elseif tp == "TerminalVariantInputLineData" then
         to_insert = VariantInputLine(line.variants, line.character_config)
      else
         error("Unknown line type " .. tp)
      end
      to_insert._character = line.character_config
      to_insert._script = line.script     

      lines[name] = to_insert
   end
end

function draw(dt)
   local win_size = DRAWING_TARGET.size

   local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2
   local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   local term_max_text_width = max_text_width()

   -- Construct and draw the background rectangle
   local rect = RectangleShape.new(Vector2f.new(rect_width, rect_height))
   rect.outline_thickness = 2.0
   rect.outline_color = Color.Black
   rect.fill_color = Color.Black
   rect.position = Vector2f.new(width_offset, height_offset)
   DRAWING_TARGET:draw(rect)

   -- Offset for the first line to start at
   local first_line_height_offset = height_offset * 2

   -- Actual offsets that will be used for line positioning
   local line_width_offset, line_height_offset = width_offset * 2, first_line_height_offset

   -- The total height of the text to compare it with the terminal rectangle
   local total_text_height = 0

   local current_line_name = first_line_on_screen
   while true do
      local line = lines[current_line_name]

      if not line then
         error(current_line_name .. " does not exist")
      end

      local should_wait = line:should_wait()
      if should_wait then
         line:tick_letter_timer(dt)
         line:maybe_increment_letter_count()
      end

      local text = line:current_text()
      if type(text) == "table" then
         -- It's more than one line

         for n, txt in pairs(text) do
            txt.position = Vector2f.new(line_width_offset, line_height_offset)

            local this_txt_height = line:max_line_height(n);

            total_text_height = total_text_height + this_txt_height + (StaticFonts.font_size / 2)
            line_height_offset = first_line_height_offset + total_text_height;

            DRAWING_TARGET:draw(txt);
         end
         -- Add a bit more after the last line
         total_text_height = total_text_height + StaticFonts.font_size / 2
         line_height_offset = first_line_height_offset + total_text_height         
      else
         -- It's a single line of text

         text.position = Vector2f.new(line_width_offset, line_height_offset)
         
         local line_height = line:max_line_height()
         total_text_height = total_text_height + line_height + (StaticFonts.font_size / 2)
         line_height_offset = first_line_height_offset + total_text_height

         DRAWING_TARGET:draw(text)
      end

      --[[
         If there are too many lines to fit into the screen rectangle,
         remove the currently first line and put the next one it its place.
         Since this happens every frame, it should work itself out even if there
         are multiple lines to remove.
      ]]
      if total_text_height > rect_height - (height_offset * 2) then
         local curr_first_line = lines[first_line_on_screen]

         local maybe_next = curr_first_line:next()
         if maybe_next ~= "" then
            first_line_on_screen = maybe_next
         end
      end

      -- If there's a script and it wasn't executed yet, do it
      if line._script and not line._script_executed then         
         local script_f = load(line._script, current_line_name .. ".script")
         script_f()
         
         line._script_executed = true
      end

      if (should_wait or line:next() == "") then
         break
      end

      current_line_name = line:next()
   end

   -- Draw the environment image if there is one
   if current_environment_sprite then
      local sprite_height_offset = (height_offset * 2) + rect_height
      local sprite_width_offset = width_offset + rect_width - current_environment_texture.size.x

      current_environment_sprite.position = Vector2f.new(sprite_width_offset, sprite_height_offset)
      DRAWING_TARGET:draw(current_environment_sprite)
   end
end

function process_event(event)
   local current_line_name = first_line_on_screen

   while true do
      local line = lines[current_line_name]

      local should_wait = line:should_wait()

      -- If line has an is_interactive function, use it
      if line.is_interactive then
         if line:should_wait() and line:is_interactive() then
            line:handle_interaction(event)
         end
      end

      if should_wait or line:next() == "" then
         break
      end

      current_line_name = line:next()
   end
end

function set_environment_image(name)
   -- Create the sprite if it doesn't exist yet
   if not current_environment_sprite then      
      current_environment_sprite = Sprite.new()      
   end
   
   local full_name = "resources/sprites/environments/" .. name .. ".png"
   current_environment_texture = Texture.new()
   current_environment_texture:load_from_file(full_name)
   
   current_environment_sprite.texture = current_environment_texture
end

return {
   add = add,  
   draw = draw,
   process_event = process_event,
   set_environment_image = set_environment_image
}
