local class = require("middleclass")
local inspect = require("inspect")
local lume = require("lume")
local coroutines = require("coroutines")
local toml = require("toml")
local util = require("util")

local first_line_on_screen

-- This is used to not make the events not throttle when text is being inputted
local inputting_text = false

function reset_after_text_input()
   inputting_text = false
end

-- Native lines, data received from C++
local native_lines = {}

local M = {}

local info_message_coro
function show_info_message(message)
   if info_message_coro then
      coroutines.abandon_coroutine(info_message_coro)
      info_message_coro = nil
   end

   info_message_coro =
      coroutines.create_coroutine(
         function(dt)
            local current_color = Color.new(0, 0, 0, 0)
            local text = Text.new(message, StaticFonts.main_font, StaticFonts.font_size)

            local win_size = GLOBAL.drawing_target.size
            local text_size = text.global_bounds
            local text_pos = Vector2f.new(win_size.x - 10 - text_size.width, win_size.y - 10 - text_size.height)
            text.position = text_pos

            -- Show the text
            while current_color.a < 255 do
               current_color.a = current_color.a + 5
               text.fill_color = current_color

               GLOBAL.drawing_target:draw(text)
               coroutine.yield()
            end

            -- Wait five seconds
            local timer = 0
            while timer < 5 do
               timer = timer + dt
               GLOBAL.drawing_target:draw(text)
               coroutine.yield()
            end

            -- Hide the text
            while current_color.a > 0 do
               current_color.a = current_color.a - 5
               text.fill_color = current_color

               GLOBAL.drawing_target:draw(text)
               coroutine.yield()
            end
         end
   )
end

function save_game(first_line, last_line)
   local lines_to_save = {}
   local current_line = first_line

   while true do
      table.insert(lines_to_save, current_line)
      if current_line._name == last_line._name then break end
      current_line = current_line:next()
   end

   -- Extract the data to save from the lines
   local saved_data = {
      lines = { first_line = first_line._name, last_line = last_line._name },
      variables = M.state_variables
   }
   for _, line in pairs(lines_to_save) do
      local line_saved_fields = {}
      for _, field_name in ipairs(line:fields_to_save()) do
         line_saved_fields[field_name] = line[field_name]
      end

      saved_data["lines"][line._name] = line_saved_fields
   end

   -- Encode and save the data
   local toml_encoded = toml.encode(saved_data)
   local file = io.open("save.toml", "w")
   file:write(toml_encoded)
   file:close()

   show_info_message("Game saved")
end

function load_game()
   local file = io.open("save.toml", "r")
   if file then
      local data, err = toml.parse(file:read("*all"))
      if err then
         error("Error decoding save data: " .. err)
      end

      file:close()

      local first_line_name = data["lines"]["first_line"]
      local last_line_name = data["lines"]["last_line"]

      local first_line = make_line(first_line_name, native_lines[first_line_name])
      local current_line = first_line
      while true do
         -- Copy the values, preserving the metatable
         for k, v in pairs(data["lines"][current_line._name]) do
            current_line[k] = v
         end

         if current_line._name == last_line_name then break end

         current_line = current_line:next()
      end

      -- Just in case, reset like after text input
      reset_after_text_input()

      first_line_on_screen = first_line

      M.state_variables = util.deep_merge(M.state_variables, data["variables"])

      show_info_message("Game loaded")
   end
end

-- Cache data for max_text_width
local last_win_size, last_max_text_width

-- Calculates the maximum text width in the terminal
function max_text_width()
   local win_size = GLOBAL.drawing_target.size

   if not last_win_size or last_win_size.x ~= win_size.x or last_win_size.y ~= win_size.y then
      last_win_size = win_size

      local width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2

      local rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

      last_max_text_width = math.floor((rect_width - (width_offset * 2)) / (StaticFonts.font_size / 2.0))
   end

   return last_max_text_width
end

-- Text object used for max_string_height calculation
local max_string_height_text

function max_string_height(str)
   local term_width = max_text_width()
   local fit_str = lume.wordwrap(str, term_width)

   if not max_string_height_text then
      max_string_height_text = Text.new(fit_str, StaticFonts.main_font, StaticFonts.font_size)
   else
      max_string_height_text.string = fit_str
   end

   return max_string_height_text.global_bounds.height
end

local time_before_output = 0.5
local time_per_letter = 0.01

function insert_variables(str)
   return str:gsub(
      "<(.)>",
      function(name)
         return M.state_variables.input_variables[name]
      end
   )
end

local TerminalLine = class("TerminalLine")
function TerminalLine:initialize(name)
   self._name = name
   self._character = nil

   self._letters_output = 0
   self._time_since_last_letter = 0.0
   self._time_since_started_output = 0.0

   -- The script to execute on first line evaluation and whether it was executed already or not
   self._script = nil
   self._script_executed = false

   self._script_after = nil
   self._script_after_executed = false
end

function TerminalLine:tick_letter_timer(dt)
   self._time_since_last_letter = self._time_since_last_letter + dt
end

function TerminalLine:tick_before_output_timer(dt)
   self._time_since_started_output = self._time_since_started_output + dt
end

function TerminalLine:fields_to_save()
   local result = { "_letters_output" }

   -- Save whether the script ran if there is a script
   if self._script then
      table.insert(result, "_script_executed")
   end
   if self._script_after then
      table.insert(result, "_script_after_executed")
   end

   return result
end

local OutputLine = class("OutputLine", TerminalLine)
function OutputLine:initialize(name, text, next_line_name)
   TerminalLine.initialize(self, name)

   self._text = insert_variables(text)
   -- The name of the next line to be retreived and instantiated by next()
   self._next_line_name = next_line_name
   -- A place to store the next line instance when it's needed
   self._next_line = nil

   self._text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
end

-- The character is set after initialization, so character-specific things need to be done after
function OutputLine:update_for_character()
   self._text_object.fill_color = self._character.color
end

function OutputLine:max_line_height()
   return max_string_height(self._text)
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
   local txt = self._text_object

   if #txt.string ~= self._letters_output then
      local substr = lume.wordwrap(
         self._text:sub(0, self._letters_output),
         max_text_width()
      )
      txt.string = substr
   end

   return txt
end

function OutputLine:next()
   -- Create the next line if there is one and only do it if one wasn't created already
   if self._next_line_name ~= "" and not self._next_line then
      self._next_line = make_line(self._next_line_name, native_lines[self._next_line_name])
   end

   return self._next_line
end

function OutputLine:is_interactive()
   return self._letters_output < #self._text
end

function OutputLine:handle_interaction(event)
   if event.type == EventType.KeyPressed then
      -- Skip by pressing 1
      local key = event.key.code

      if key == KeyboardKey.Num1 then
         self._letters_output = #self._text

         return true
      end
   end
end

local InputWaitLine = class("InputWaitLine", OutputLine)
function InputWaitLine:initialize(name, text, next_line)
   OutputLine.initialize(self, name, text, next_line)

   self._1_pressed = false
end

local help_text, help_text_active

function set_help_text(active, text)
   help_text_active = active

   if active then
      if not help_text then
         help_text = Text.new(text, StaticFonts.main_font, 24)
         help_text.fill_color = Color.Black
      else
         help_text.string = text
      end
   end
end

function InputWaitLine:current_text()
   local txt = OutputLine.current_text(self)

   if self._letters_output == #self._text and not self._1_pressed then
      set_help_text(true, "[Press 1 to continue]")
   else
      set_help_text(false)
   end

   return txt
end

function InputWaitLine:should_wait()
   return OutputLine.should_wait(self) or not self._1_pressed
end

function InputWaitLine:is_interactive()
   return not self._1_pressed
end

function InputWaitLine:handle_interaction(event)
   if event.type == EventType.KeyReleased then
      local key = event.key.code

      if key == KeyboardKey.Num1 then
         self._1_pressed = true

         return true
      end
   elseif self._letters_output < #self._text and event.type == EventType.KeyPressed then
      -- Allow skipping by pressing 1
      local key = event.key.code

      if key == KeyboardKey.Num1 then
         self._letters_output = #self._text

         return true
      end
   end
end

function InputWaitLine:fields_to_save()
   local parent = InputWaitLine.super.fields_to_save(self)
   return lume.concat(parent, {"_1_pressed"})
end

local VariantInputLine = class("VariantInputLine", TerminalLine)
function VariantInputLine:initialize(name, variants)
   TerminalLine.initialize(self, name)

   -- Same as if it was unset. Just to have the name mentioned somewhere beforehand
   self._selected_variant = nil
   -- A place to store the next line instance when the variant is selected
   self._selected_variant_next_instance = nil

   -- Possible variants, filtered by whether their condition is satisfied
   self._variants = {}

   local var_num = 0
   -- Process native variants into data
   for n, var in pairs(variants) do
      -- Filter out variants with conditions if they're not satisfied
      if var.condition then
         -- Compile the condition if it exists
         local condition, err = load(var.condition, lume.format("{1}.condition", {self._name}))
         if err then error(err) end

         local cond_result = condition()
         if type(cond_result) ~= "boolean" then
            error(lume.format("The condition '{2}' (number {3}) in {1} doesn't return a boolean", {self._name, var.text, n}))
         end

         -- If the condition does not evaluate to truth, skip the line
         if not cond_result then goto skip end
      end

      var_num = var_num + 1
      -- Add the variant number before the text
      local formatted_text = lume.format(
         "{num}.  {text}",
         { num = var_num, text = insert_variables(var.text) }
      )
      local inserted_variant = {
         text = formatted_text,
         text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size),
         next = var.next,
      }
      table.insert(self._variants, inserted_variant)

      ::skip::
   end

   -- Find the longest variant to base text printing on
   self._longest_var_length = -1
   self._longest_var_n = -1
   for n, var in ipairs(self._variants) do
      local len = #var.text
      if len > self._longest_var_length then
         self._longest_var_length = len
         self._longest_var_n = n
      end
   end
end

function VariantInputLine:update_for_character()
   for _, v in pairs(self._variants) do
      v.text_object.fill_color = self._character.color
   end
end

function VariantInputLine:max_line_height(variant)
   return max_string_height(self._variants[variant].text)
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

   local longest_var_done = #self._variants[self._longest_var_n].text_object.string == self._letters_output

   -- Form the result from the variants
   local result = {}
   for n, var in ipairs(self._variants) do
      local txt = var.text_object
      -- If the longest variant hasn't been fully output yet, keep updaing
      if not longest_var_done then
         local substr = lume.wordwrap(var.text:sub(0, self._letters_output), max_width)
         txt.string = substr
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
      local nxt_name = self._variants[self._selected_variant].next

      self._selected_variant_next_instance = make_line(nxt_name, native_lines[nxt_name])
   end

   return self._selected_variant_next_instance
end

function VariantInputLine:is_interactive()
   return not self._selected_variant
end

function VariantInputLine:handle_interaction(event)
   if event.type == EventType.TextEntered then
      local ch = string.char(event.text.unicode)

      -- Convert the character to it's number equivalent
      local chnum = tonumber(ch)

      -- Add 1 because indexes start at 1 in lua
      if chnum and chnum >= 1 and chnum < #self._variants + 1 then
         -- If the text has already bean output, set the answer,
         -- if not, then skip all the printing and show the whole thing
         if self._letters_output == self._longest_var_length then
            self._selected_variant = chnum

            self._variants[self._selected_variant].text_object.style = TextStyle.Underlined
         else
            self._letters_output = self._longest_var_length
         end

         return true
      end
   end
end

function VariantInputLine:fields_to_save()
   local parent = VariantInputLine.super.fields_to_save(self)
   return lume.concat(parent, {"_selected_variant"})
end

local TextInputLine = class("TextInputLine", TerminalLine)

function TextInputLine:initialize(name, before, after, variable, max_length, nxt)
   TerminalLine.initialize(self, name)

   self._next = nxt
   self._next_line = nil

   self._before = insert_variables(before)
   self._after = insert_variables(after)
   self._variable = variable
   self._max_length = max_length

   self._done_input = false
   self._input_text = ""

   self._text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
end

function TextInputLine:update_for_character()
   self._text_object.fill_color = self._character.color
end

function TextInputLine:max_line_height()
   return max_string_height(self._before .. string.rep(" ", self._max_length) .. self._after)
end

function TextInputLine:should_wait()
   return not self._done_input or self._letters_output < #self._before + #self._input_text + #self._after
end

function TextInputLine:maybe_increment_letter_count()
   if not self._done_input and self._letters_output < #self._before then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   elseif self._done_input and self._letters_output < #self._before + #self._input_text + #self._after then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   end
end

function TextInputLine:current_text()
   local txt = self._text_object

   -- Show help when input is not done
   set_help_text(not self._done_input and self._letters_output >= #self._before, "[Input text with keyboard]")

   if #self._text_object.string ~= self._letters_output then
      local substr
      if not self._done_input then
         local str = (self._before .. self._input_text):sub(0, self._letters_output)
         if self._letters_output >= #self._before then
            str = str .. "_"
         end

         substr = lume.wordwrap(str,max_text_width())
      else
         substr = lume.wordwrap(
            (self._before .. self._input_text .. self._after):sub(0, self._letters_output),
            max_text_width()
         )
      end

      txt.string = substr
   end

   return txt
end

function TextInputLine:is_interactive()
   return self._letters_output >= #self._before and not self._done_input
end

function TextInputLine:handle_interaction(event)
   if self._letters_output >= #self._before and not self._done_input then
      inputting_text = true

      if event.type == EventType.KeyPressed then
         if event.key.code == KeyboardKey.Backspace and #self._input_text > 0 then
            -- Remove the last character
            self._input_text = self._input_text:sub(1, -2)
            self._letters_output = self._letters_output - 1

            return true
         elseif event.key.code == KeyboardKey.Return then
            -- Finish input
            reset_after_text_input()
            self._done_input = true

            -- Set the variable
            M.state_variables.input_variables[self._variable] = self._input_text

            return true
         end
      elseif event.type == EventType.TextEntered then
         if GLOBAL.isalpha(event.text.unicode) and #self._input_text < self._max_length then
            local char = string.char(event.text.unicode)
            self._input_text = self._input_text .. char
            self._letters_output = self._letters_output + 1

            return true
         end
      end
   end
end

function TextInputLine:next()
   -- Create the next line if there is one and only do it if one wasn't created already
   if self._next ~= "" and not self._next_line then
      self._next_line = make_line(self._next, native_lines[self._next])
   end

   return self._next_line
end

function TextInputLine:fields_to_save()
   local parent = TextInputLine.super.fields_to_save(self)
   return lume.concat(parent, {"_done_input", "_input_text"})
end

local current_environment_texture, current_environment_sprite

-- A function to create lines from their name and the native line data
function make_line(name, line)
   local tp = line.__type.name

   local to_insert
   if tp == "TerminalOutputLineData" then
      to_insert = OutputLine(name, line.text, line.next)
   elseif tp == "TerminalInputWaitLineData" then
      to_insert = InputWaitLine(name, line.text, line.next)
   elseif tp == "TerminalVariantInputLineData" then
      to_insert = VariantInputLine(name, line.variants)
   elseif tp == "TerminalTextInputLineData" then
      to_insert = TextInputLine(name, line.before, line.after, line.variable, line.max_length, line.next)
   else
      error(lume.format("Unknown line type {1}", {tp}))
   end

   to_insert._character = line.character_config
   to_insert:update_for_character()

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
   -- Reset like after text input
   reset_after_text_input()

   if native_lines[name] then
      first_line_on_screen = make_line(name, native_lines[name])
   else
      print("Line " .. name .. " not found")
   end
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
            if line._time_since_started_output < time_before_output then
               line:tick_before_output_timer(dt)

               break
            end

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

         if should_wait then
            break
         end

         -- Execute the script_after after the first time the line was finished
         if line._script_after and not line._script_after_executed then
            line._script_after()

            line._script_after_executed = true
         end

         if line:next() == nil then
            break
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

   -- Draw the help text if it's active
   if help_text_active then
      if not help_text then
         help_text = Text.new("", StaticFonts.main_font, 24)
         help_text.fill_color = Color.Black
      end
      local text_pos = Vector2f.new(width_offset, height_offset + rect_height + 30)
      help_text.position = text_pos

      GLOBAL.drawing_target:draw(help_text)
   end

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

local time_since_last_interaction = 0
local time_between_interactions = 0.2

-- A function to track time between events
function M.update_event_timer(dt)
   time_since_last_interaction = time_since_last_interaction + dt
end

function M.process_event(event, dt)
   local line = first_line_on_screen
   while true do
      local should_wait = line:should_wait()

      -- If line has an is_interactive function, use it
      if line.is_interactive then
         if line:should_wait() and line:is_interactive() and (inputting_text or time_since_last_interaction > time_between_interactions) then
            if line:handle_interaction(event) then
               time_since_last_interaction = 0
            end
         end
      end

      if should_wait or line:next() == nil then
         if time_since_last_interaction > time_between_interactions then
            if Keyboard.is_key_pressed(KeyboardKey.LControl) then
               -- Save the game
               if Keyboard.is_key_pressed(KeyboardKey.S) then
                  time_since_last_interaction = 0
                  -- Pass the first and the last line
                  save_game(first_line_on_screen, line)
               elseif Keyboard.is_key_pressed(KeyboardKey.L) then
                  time_since_last_interaction = 0
                  -- Pass the first and the last line
                  load_game()
               end
            end
         end

         break
      end

      line = line:next()
   end
end

function M.set_environment_image(name)
   do return end

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
M.state_variables = {
   input_variables = {
      p = "<p>"
   },
   day1 = {
      narra_house_hub = {
         living_room = false,
         kitchen = false,
         bathroom = false
      }
   },
   day2 = {
      road_questions = {
         computers = false,
         food = false,
         age = false,
         city = false,
         city_food = false,
         stay = false
      },
      flat = {
         laptop = false,
         kitchen = false,
         bathroom = false
      },
      club = {
         bar = false,
         dance_floor = false
      }
   },
   talking_topics = {}
}

function M.talking_topic_known(topic)
   return lume.find(M.state_variables.talking_topics, topic) ~= nil
end

function M.add_talking_topic(topic)
   if not lume.find(M.state_variables.talking_topics, topic) then
      table.insert(M.state_variables.talking_topics, topic)
   end
end

local debug_menu_data = {
   select_line_text = ""
}
function M.debug_menu()
   local submitted
   debug_menu_data.select_line_text, submitted = ImGui.InputText("Line selection", debug_menu_data.select_line_text)
   ImGui.SameLine()
   if ImGui.Button("Switch") or submitted then
      M.set_first_line_on_screen(debug_menu_data.select_line_text)
      debug_menu_data.select_line_text = ""
   end

   local process_node
   process_node = function(name, data, parent)
      if type(data) == "table" then
         if ImGui.TreeNode(name) then
            for k, v in pairs(data) do process_node(tostring(k), v, data) end
            ImGui.TreePop()
         end
      elseif type(data) == "boolean" then
         parent[name] = ImGui.Checkbox(name, data)
      else
         ImGui.Text(name .. " = " .. tostring(data))
      end
   end
   process_node("State variables", M.state_variables)
end

return M
