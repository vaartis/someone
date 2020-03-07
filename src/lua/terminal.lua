local class = require("middleclass")
local inspect = require("inspect")
local lume = require("lume")
local coroutines = require("coroutines")

-- Calculates the maximum text width in the terminal
function max_text_width()
   local win_size = GLOBAL.drawing_target.size

   local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2

   local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   return math.floor((rect_width - (width_offset * 2)) / (StaticFonts.font_size / 2.0))
end

-- Native lines, data received from C++
local native_lines = {}

-- First line to be shown on screen every frame
local first_line_on_screen

local time_per_letter = 0.01

local TerminalLine = class("TerminalLine")
function TerminalLine:initialize(name)
   self._name = name
   self._character = nil

   self._letters_output = 0
   self._time_since_last_letter = 0.0

   -- The script to execute on first line evaluation and whether it was executed already or not
   self._script = nil
   self._script_executed = false

   self._script_after = nil
   self._script_after_executed = false
end

function TerminalLine:tick_letter_timer(dt)
   self._time_since_last_letter = self._time_since_last_letter + dt
end

local OutputLine = class("OutputLine", TerminalLine)
function OutputLine:initialize(name, text, next_line_name)
   TerminalLine.initialize(self, name)

   self._text = text
   -- The name of the next line to be retreived and instantiated by next()
   self._next_line_name = next_line_name
   -- A place to store the next line instance when it's needed
   self._next_line = nil
end

function OutputLine:max_line_height()
   local term_width = max_text_width()

   local fit_str = lume.wordwrap(self._text, term_width)

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
   local substr = lume.wordwrap(
      self._text:sub(0, self._letters_output),
      max_text_width()
   )

   local txt = Text.new(substr, StaticFonts.main_font, StaticFonts.font_size)
   txt.fill_color = self._character.color

   return txt
end

function OutputLine:next()
   -- Create the next line if there is one and only do it if one wasn't created already
   if self._next_line_name ~= "" and not self._next_line then
      self._next_line = make_line(self._next_line_name, native_lines[self._next_line_name])
   end

   return self._next_line
end

local InputWaitLine = class("InputWaitLine", OutputLine)
function InputWaitLine:initialize(name, text, next_line)
   OutputLine.initialize(self, name, text, next_line)

   self._space_pressed = false
end

function InputWaitLine:current_text()
   local final_text = self._text:sub(0, self._letters_output)
   if (self._letters_output == #self._text and not self._space_pressed) then
      final_text = final_text .. "\n[Press Space to continue]"
   end

   local substr = lume.wordwrap(
      final_text,
      max_text_width()
   )

   local txt = Text.new(substr, StaticFonts.main_font, StaticFonts.font_size)
   txt.fill_color = self._character.color

   return txt
end

function InputWaitLine:should_wait()
   return OutputLine.should_wait(self) or not self._space_pressed
end

function InputWaitLine:is_interactive()
   return self._letters_output == #self._text and not self._space_pressed
end

function InputWaitLine:handle_interaction(event)
   if event.type == EventType.KeyReleased then
      local key = event.key.code

      if key == KeyboardKey.Space then
         self._space_pressed = true
      end
   end
end

local VariantInputLine = class("VariantInputLine", TerminalLine)
function VariantInputLine:initialize(name, variants)
   TerminalLine.initialize(self, name)

   -- Same as if it was unset. Just to have the name mentioned somewhere beforehand
   self._selected_variant = nil
   -- A place to store the next line instance when the variant is selected
   self._selected_variant_next_instance = nil

   -- All possible variants
   self._variants = {}
   -- Variants that are currently visible
   self._visible_variants = {}

   -- Process native variants into data
   for _, var in pairs(variants) do
      local inserted_variant = { text = var.text, next = var.next }

      if var.condition then
         -- Compile the condition if it exists
         inserted_variant.condition, err = load(var.condition, lume.format("{1}.condition", {self._name}))
         if err then error(err) end
      end

      table.insert(self._variants, inserted_variant)
   end

   -- Find the longest variant to base text printing on
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

   -- Get the text of the selected visible variant
   local fit_str = lume.wordwrap(self._visible_variants[variant].text, term_width)

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

   -- If the line is the current line, allow updating the visible variants for it
   if self:should_wait() then
      local visible_vars = {}
      for n, var in pairs(self._variants) do
         -- If there's a condition, try checking it
         if var.condition then
            local condition_result = var.condition()
            if type(condition_result) ~= "boolean" then
               error(lume.format("The condition '{2}' (number {3}) in {1} doesn't return a boolean", {self._name, var.text, n}))
            end

            -- If the condition is successfull, continue with execution and add the line to the result
            -- Otherwise, skip it and it won't be visible
            if not condition_result then goto skip end
         end

         -- Add to visible variants
         table.insert(visible_vars, var)

         ::skip::
      end

      self._visible_variants = visible_vars
   end

   -- Form the result from the visible variants
   local result = {}
   for n, var in ipairs(self._visible_variants) do
      local var_str = var.text

      local substr = lume.format("{num}.  {text}", { num = n, text = lume.wordwrap(var_str:sub(0, self._letters_output), max_width) })
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

   -- If the next line wasn't instantiated yet, create it
   if not self._selected_variant_next_instance then
      local nxt_name = self._visible_variants[self._selected_variant].next

      self._selected_variant_next_instance = make_line(nxt_name, native_lines[nxt_name])
   end

   return self._selected_variant_next_instance
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
      -- Only use visible variants here, not all variants
      if chnum and chnum >= 1 and chnum < #self._visible_variants + 1 then
         self._selected_variant = chnum
      end
   end
end

local M = {}

local current_environment_texture, current_environment_sprite

-- A function to create lines from their name and the native line data
function make_line(name, line)
   local tp = line.__type.name

   local to_insert
   if tp == "TerminalOutputLineData" then
      to_insert = OutputLine(name, line.text, line.next, line.character_config)
   elseif tp == "TerminalInputWaitLineData" then
      to_insert = InputWaitLine(name, line.text, line.next, line.character_config)
   elseif tp == "TerminalVariantInputLineData" then
      to_insert = VariantInputLine(name, line.variants, line.character_config)
   else
      error(lume.format("Unknown line type {1}", {tp}))
   end

   to_insert._character = line.character_config

   if line.script then
      -- Compile the script (if it exists)
      to_insert._script, err = load(line.script, lume.format("{1}.script", {name}))
      if err then error(err) end
   end
   if line.script_after then
      -- Compile the script_after (if it exists)
      to_insert._script_after, err = load(line.script_after, lume.format("{1}.script_after", {name}))
      if err then error(err) end
   end

   return to_insert
end

-- Called from C++ to add native lines
function M.add_native_lines(in_lines)
   -- Setting them by key allows merging
   for name, line in pairs(in_lines) do
      native_lines[name] = line
   end
end

-- Called from C++ to set up the first line on screen
function M.set_first_line_on_screen(name)
   first_line_on_screen = make_line(name, native_lines[name])
end

M.current_lines_to_draw = {}

function M.draw(dt)
   -- If processing is active, reset and update current lines
   if M.active then
      M.current_lines_to_draw = {}

      local line = first_line_on_screen

      -- If some line changes the active status, stop processing the lines after it
      while true and M.active do
         if not line then
            error(string.format("Line %s does not exist", line._name))
         end

         local should_wait = line:should_wait()
         if should_wait then
            line:tick_letter_timer(dt)
            line:maybe_increment_letter_count()
         end

         -- If there's a script and it wasn't executed yet, do it
         if line._script and not line._script_executed then
            line._script()

            line._script_executed = true
         end

         -- Insert the line into the drawing queue now
         table.insert(M.current_lines_to_draw, line)

         if should_wait or line:next() == nil then
            break
         end

         -- Execute the script_after after the first time the line was finished
         if line._script_after and not line._script_after_executed then
            line._script_after()

            line._script_after_executed = true
         end

         line = line:next()
      end
   end

   local win_size = GLOBAL.drawing_target.size

   local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2
   local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   local term_max_text_width = max_text_width()

   -- Construct and draw the background rectangle
   local rect = RectangleShape.new(Vector2f.new(rect_width, rect_height))
   rect.outline_thickness = 2.0
   rect.outline_color = Color.Black
   rect.fill_color = Color.Black
   rect.position = Vector2f.new(width_offset, height_offset)
   GLOBAL.drawing_target:draw(rect)

   -- Offset for the first line to start at
   local first_line_height_offset = height_offset * 2

   -- Actual offsets that will be used for line positioning
   local line_width_offset, line_height_offset = width_offset * 2, first_line_height_offset

   -- The total height of the text to compare it with the terminal rectangle
   local total_text_height = 0

   -- Use the current lines and draw those
   for _, line in pairs(M.current_lines_to_draw) do
      local text = line:current_text()
      if type(text) == "table" then
         -- It's more than one line

         for n, txt in pairs(text) do
            txt.position = Vector2f.new(line_width_offset, line_height_offset)

            local this_txt_height = line:max_line_height(n);

            total_text_height = total_text_height + this_txt_height + (StaticFonts.font_size / 2)
            line_height_offset = first_line_height_offset + total_text_height;

            GLOBAL.drawing_target:draw(txt);
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

         GLOBAL.drawing_target:draw(text)
      end
   end

   --[[
      If there are too many lines to fit into the screen rectangle,
      remove the currently first line and put the next one it its place.
      Since this happens every frame, it should work itself out even if there
      are multiple lines to remove.
   ]]
   if total_text_height > rect_height - (height_offset * 2) then
      local curr_first_line = first_line_on_screen

      local maybe_next = curr_first_line:next()
      if maybe_next ~= nil then
         first_line_on_screen = maybe_next
      end
   end

   -- Draw the environment image if there is one
   if current_environment_sprite then
      local sprite_height_offset = (height_offset * 2) + rect_height
      local sprite_width_offset = width_offset + rect_width - current_environment_texture.size.x

      current_environment_sprite.position = Vector2f.new(sprite_width_offset, sprite_height_offset)
      GLOBAL.drawing_target:draw(current_environment_sprite)
   end
end

function M.process_event(event)
   local line = first_line_on_screen
   while true do
      local should_wait = line:should_wait()

      -- If line has an is_interactive function, use it
      if line.is_interactive then
         if line:should_wait() and line:is_interactive() then
            line:handle_interaction(event)
         end
      end

      if should_wait or line:next() == nil then
         break
      end

      line = line:next()
   end
end

function M.set_environment_image(name)
   -- Create the sprite if it doesn't exist yet
   if not current_environment_sprite then
      current_environment_sprite = Sprite.new()
   end

   local full_name = lume.format("resources/sprites/environments/{1}.png", {name})
   current_environment_texture = Texture.new()
   current_environment_texture:load_from_file(full_name)

   current_environment_sprite.texture = current_environment_texture
end

function M.switch_to_walking(room)
   -- Needs to be done as soon as possible to stop processing lines
   M.active = false

   -- Create a coroutine that blackens the screen with time
   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         WalkingModule.load_room(room)
         GLOBAL.set_current_state(CurrentState.Walking)
      end
   )
end

-- Should the next line be shown
M.active = true

-- State variables for the story to set/get
M.state_variables = {}

return M
