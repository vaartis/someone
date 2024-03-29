local lume = require("lume")
local class = require("middleclass")
local util = require("util")
local liluat = require("liluat")

local M = {
   -- This is used to not make the events not throttle when text is being input
   inputting_text = false,
   -- Native lines, data received from C++
   native_lines = {},

   time_per_letter = 0.01
}

local render_env
local function insert_variables(name, str)
   local compiled = liluat.compile(
      str,
      {
         start_tag = "<",
         end_tag = ">"
      },
      name
   )

   if WalkingModule and not render_env then
      render_env = lume.merge(
         TerminalModule,
         {
            lume = lume,
         }
      )
   end

   -- Just reference the whole environment
   return liluat.render(compiled, render_env, { reference = true })
end

-- Text object used for max_string_height calculation
local max_string_height_text

function M.max_string_height(str, font_size)
   local term_width = M.max_text_width()
   local fit_str = lume.wordwrap(str, term_width)

   if not max_string_height_text then
      max_string_height_text = Text.new(fit_str, StaticFonts.main_font, font_size)
   else
      max_string_height_text.string = fit_str
      max_string_height_text.character_size = font_size
   end

   return max_string_height_text.global_bounds.height
end

-- Cache data for max_text_width
local last_win_size, last_max_text_width

-- Calculates the maximum text width in the terminal
function M.max_text_width()
   local win_size = GLOBAL.drawing_target.size

   if not last_win_size or last_win_size.x ~= win_size.x or last_win_size.y ~= win_size.y then
      last_win_size = win_size

      local width_offset = win_size.x / 100
      local rect_width = win_size.x - (width_offset * 2)

      last_max_text_width = util.rect_max_text_width(rect_width - (width_offset * 2))
   end

   return last_max_text_width
end

function M.reset_after_text_input()
   M.inputting_text = false
end

M.TerminalLine = class("TerminalLine")

function M.TerminalLine.static:allocate(name, character, line_source)
   local created = {}

   created._name = name
   created._line_source = line_source
   created._character = character

   return created
end

function M.TerminalLine:initialize()
   self._letters_output = 0
   self._time_since_last_letter = 0.0
   self._time_since_started_output = 0.0

   -- The script to execute on first line evaluation and whether it was executed already or not
   self._script = nil
   self._script_executed = false

   self._script_after = nil
   self._script_after_executed = false
end

function M.TerminalLine:tick_letter_timer(dt)
   self._time_since_last_letter = self._time_since_last_letter + dt
end

function M.TerminalLine:tick_before_output_timer(dt)
   self._time_since_started_output = self._time_since_started_output + dt
end

function M.TerminalLine:fields_to_save()
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

M.OutputLine = class("OutputLine", M.TerminalLine)
function M.OutputLine:initialize(text, next_line_name)
   M.OutputLine.super.initialize(self)

   self._text = insert_variables(name, text)
   -- The name of the next line to be retreived and instantiated by next()
   self._next_line_name = next_line_name
   -- A place to store the next line instance when it's needed
   self._next_line = nil

   self._text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size)

   self._text_object.fill_color = self._character.color
   self._text_object.character_size = self._character.font_size
end

function M.OutputLine:max_line_height()
   return M.max_string_height(self._text, self._character.font_size)
end

function M.OutputLine:should_wait()
   local script_done = true
   if self._script_after then
      script_done = self._script_after_executed
   end

   return self._letters_output < #self._text and script_done
end

function M.OutputLine:maybe_increment_letter_count()
   if self._letters_output < #self._text and self._time_since_last_letter >= M.time_per_letter then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   end
end

function M.OutputLine:current_text()
   local txt = self._text_object

   if #txt.string ~= self._letters_output then
      local substr = lume.wordwrap(
         self._text:sub(0, self._letters_output),
         M.max_text_width()
      )
      txt.string = substr
   end

   return txt
end

function M.OutputLine:next()
   -- Create the next line if there is one and only do it if one wasn't created already
   if self._next_line_name ~= "" and not self._next_line then
      self._next_line = M.make_line(self._next_line_name, self._line_source)
   end

   return self._next_line
end

function M.OutputLine:is_interactive()
   return self._letters_output < #self._text
end

function M.OutputLine:handle_interaction(event)
   if event.type == EventType.KeyPressed then
      -- Skip by pressing 1
      local key = event.key.code

      if key == KeyboardKey.Num1 then
         self._letters_output = #self._text

         return true
      end
   end
end

M.InputWaitLine = class("InputWaitLine", M.OutputLine)
function M.InputWaitLine:initialize(text, next_line)
   M.InputWaitLine.super.initialize(self, text, next_line)

   self._1_pressed = false
end

function M.set_help_text(active, text)
   M.help_text_active = active

   if active then
      if not M.help_text then
         M.help_text = Text.new(text, StaticFonts.main_font, 24)
         M.help_text.fill_color = Color.Black
      else
         M.help_text.string = text
      end
   end
end

function M.InputWaitLine:current_text()
   local txt = M.OutputLine.current_text(self)

   if self._letters_output == #self._text and not self._1_pressed then
      M.set_help_text(true, "[Press 1 to continue]")
   else
      M.set_help_text(false)
   end

   return txt
end

function M.InputWaitLine:should_wait()
   return M.OutputLine.should_wait(self) or not self._1_pressed
end

function M.InputWaitLine:is_interactive()
   return self._letters_output < #self._text or not self._1_pressed
end

function M.InputWaitLine:handle_interaction(event)
   if event.type == EventType.KeyPressed then
      local key = event.key.code

      if key == KeyboardKey.Num1 then
         -- Allow skipping by pressing 1
         if self._letters_output < #self._text then
            self._letters_output = #self._text
         else
            self._1_pressed = true
         end

         return true
      end
   end
end

function M.InputWaitLine:fields_to_save()
   local parent = M.InputWaitLine.super.fields_to_save(self)
   return lume.concat(parent, {"_1_pressed"})
end

M.VariantInputLine = class("VariantInputLine", M.TerminalLine)
function M.VariantInputLine:initialize(variants)
   M.VariantInputLine.super.initialize(self)

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
            error(lume.format("The condition '{2}' (number {3}) in {1} doesn't return a boolean, but a {4}", {self._name, var.text, n, type(cond_result)}))
         end

         -- If the condition does not evaluate to truth, skip the line
         if not cond_result then goto skip end
      end

      var_num = var_num + 1
      -- Add the variant number before the text
      local formatted_text = lume.format(
         "{num}.  {text}",
         { num = var_num, text = insert_variables(name, var.text) }
      )
      local inserted_variant = {
         text = formatted_text,
         text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size),
         next = var.next,
      }
      inserted_variant.text_object.fill_color = self._character.color
      inserted_variant.text_object.character_size = self._character.font_size

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

function M.VariantInputLine:max_line_height(variant)
   return M.max_string_height(self._variants[variant].text, self._character.font_size)
end

function M.VariantInputLine:should_wait()
   return (self._letters_output < self._longest_var_length) or not self._selected_variant;
end

function M.VariantInputLine:maybe_increment_letter_count()
   if self._letters_output < self._longest_var_length and self._time_since_last_letter >= M.time_per_letter then
      self._time_since_last_letter = 0.0;

      self._letters_output = self._letters_output + 1
   end
end

function M.VariantInputLine:current_text()
   local max_width = M.max_text_width()

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

function M.VariantInputLine:next()
   -- If the next line wasn't instantiated yet, create it
   if not self._selected_variant_next_instance then
      local nxt_name = self._variants[self._selected_variant].next

      self._selected_variant_next_instance = M.make_line(nxt_name, self._line_source)
   end

   return self._selected_variant_next_instance
end

function M.VariantInputLine:is_interactive()
   return not self._selected_variant
end

function M.VariantInputLine:handle_interaction(event)
   if event.type == EventType.TextEntered then
      local ch = event.text.unicode
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

function M.VariantInputLine:fields_to_save()
   local parent = M.VariantInputLine.super.fields_to_save(self)
   return lume.concat(parent, {"_selected_variant"})
end

M.TextInputLine = class("TextInputLine", M.TerminalLine)
function M.TextInputLine:initialize(before, after, variable, max_length, filters, nxt)
   M.TextInputLine.super.initialize(self)

   self._next = nxt
   self._next_line = nil

   self._before = insert_variables(name, before)
   self._after = insert_variables(name, after)
   self._variable = variable
   self._max_length = max_length
   self._filters = filters

   self._done_input = false
   self._input_text = ""

   self._text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size)
   self._text_object.fill_color = self._character.color
   self._text_object.character_size = self._character.font_size
end

function M.TextInputLine:max_line_height()
   return M.max_string_height(self._before .. string.rep(" ", self._max_length) .. self._after, self._character.font_size)
end

function M.TextInputLine:should_wait()
   return not self._done_input or self._letters_output < #self._before + #self._input_text + #self._after
end

function M.TextInputLine:maybe_increment_letter_count()
   if self._time_since_last_letter >= M.time_per_letter then
      if not self._done_input and self._letters_output < #self._before then
         self._time_since_last_letter = 0.0
         self._letters_output = self._letters_output + 1
      elseif self._done_input and self._letters_output < #self._before + #self._input_text + #self._after then
         self._time_since_last_letter = 0.0
         self._letters_output = self._letters_output + 1
      end
   end
end

function M.TextInputLine:current_text()
   local txt = self._text_object

   -- Show help when input is not done
   M.set_help_text(not self._done_input and self._letters_output >= #self._before, "[Input text with keyboard]")

   if #self._text_object.string ~= self._letters_output then
      local substr
      if not self._done_input then
         local str = (self._before .. self._input_text):sub(1, self._letters_output)
         if self._letters_output >= #self._before then
            str = str .. "_"
         end

         substr = lume.wordwrap(str, M.max_text_width())
      else
         substr = lume.wordwrap(
            (self._before .. self._input_text .. self._after):sub(0, self._letters_output),
            M.max_text_width()
         )
      end

      txt.string = substr
   end

   return txt
end

function M.TextInputLine:is_interactive()
   return self._letters_output >= #self._before and not self._done_input
end

function M.TextInputLine:handle_interaction(event)
   if self._letters_output >= #self._before and not self._done_input then
      if not M.inputting_text then
         M.inputting_text = true
         -- Add 1 to the letters output when starting text input,
         -- so that the number aligns correctly and draws the inputted
         -- letters as needed
         self._letters_output = self._letters_output + 1
      end

      if event.type == EventType.KeyPressed then
         if event.key.code == KeyboardKey.Backspace and #self._input_text > 0 then
            -- Remove the last character
            self._input_text = self._input_text:sub(1, -2)
            self._letters_output = self._letters_output - 1

            return true
         elseif event.key.code == KeyboardKey.Return and #self._input_text > 0 then
            -- Finish input
            M.reset_after_text_input()
            self._done_input = true

            -- Set the variable
            if self._variable:find("%.") then
               -- If there's a dot it's a global variable

               local _, lastdot = self._variable:find(".*%.")
               local path = self._variable:sub(0, lastdot - 1)
               local var_name = self._variable:sub(lastdot + 1)

               require(path)[var_name] = self._input_text
            else
               TerminalModule.state_variables.input_variables[self._variable] = self._input_text
            end

            return true
         end
      elseif event.type == EventType.TextEntered then
         local char = event.text.unicode

         local allowed = false
         for _, filter in ipairs(self._filters) do
            if filter == "alpha" then
               allowed = GLOBAL.isalpha(event.text.unicode)
            elseif filter == "numeric" then
               allowed = tonumber(char) ~= nil
            elseif filter == "path" then
               allowed = lume.find({ ".", "/", "\\", "%" }, char) == nil and not GLOBAL.iscntrl(event.text.unicode)
            end

            if allowed then break end
         end

         if allowed and #self._input_text < self._max_length then
            self._input_text = self._input_text .. char
            self._letters_output = self._letters_output + 1

            return true
         end
      end
   end
end

function M.TextInputLine:next()
   -- Create the next line if there is one and only do it if one wasn't created already
   if self._next ~= "" and not self._next_line then
      self._next_line = M.make_line(self._next, self._line_source)
   end

   return self._next_line
end

function M.TextInputLine:fields_to_save()
   local parent = M.TextInputLine.super.fields_to_save(self)
   return lume.concat(parent, {"_done_input", "_input_text"})
end

-- A function to create lines from their name and the native line data
function M.make_line(name, line_source)
   local line = line_source[name]
   if not line then
      error("Could not find line " .. name)
   end

   local tp = line.__type.name

   local to_insert = M.TerminalLine:allocate(name, line.character_config, line_source)

   if tp == "TerminalOutputLineData" then
      to_insert = M.OutputLine:newFromAllocated(to_insert, line.text, line.next)
   elseif tp == "TerminalInputWaitLineData" then
      to_insert = M.InputWaitLine:newFromAllocated(to_insert, line.text, line.next)
   elseif tp == "TerminalVariantInputLineData" then
      to_insert = M.VariantInputLine:newFromAllocated(to_insert, line.variants)
   elseif tp == "TerminalTextInputLineData" then
      to_insert = M.TextInputLine:newFromAllocated(to_insert, line.before, line.after, line.variable, line.max_length, line.filters, line.next)
   elseif tp == "TerminalCustomLineData" then
      to_insert = line.class:newFromAllocated(to_insert, line.data)
   else
      error(lume.format("Unknown line type {1}", {tp}))
   end

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

return M
