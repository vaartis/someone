local class = require("middleclass")
local lines = require("terminal.lines")
local util = require("util")
local lume = require("lume")

local M = {}

M.InstanceMenuLine = class("InstanceMenuLine", lines.TerminalLine)
function M.InstanceMenuLine:initialize(name, args)
   M.InstanceMenuLine.super:initialize(name)

   local line_counter = 1

   self._instances = args.instance_menu
   self._decrypted_lines_texts = {}

   local pwd_input_text = "Password: "
   self._password_input_text = {
      initial_length = #pwd_input_text,
      text = pwd_input_text,
      text_object = Text.new(pwd_input_text, StaticFonts.main_font, StaticFonts.font_size)
   }
   self._done_input = false

   for _, instance in ipairs(self._instances) do
      if lume.find(TerminalModule.state_variables.decrypted_instances, instance.name) then
         local text = lume.format("{1}. {2}", {line_counter, instance.name})
         line_counter = line_counter + 1

         table.insert(
            self._decrypted_lines_texts,
            {
               text = text,
               text_object = Text.new("", StaticFonts.main_font, StaticFonts.font_size),
               next = instance.next
            }
         )
      end
   end

   self:calculate_longest_line()
end

function M.InstanceMenuLine:update_for_character()
   for _, line in ipairs(self._decrypted_lines_texts) do
      line.text_object.fill_color = self._character.color
      line.text_object.character_size = self._character.font_size
   end

   self._password_input_text.text_object.fill_color = self._character.color
   self._password_input_text.text_object.character_size = self._character.font_size
end

function M.InstanceMenuLine:calculate_longest_line()
   -- -1 = password line is the longest one
   self._longest_line_n = -1
   self._longest_line_length = #self._password_input_text.text
   for _, line in ipairs(self._decrypted_lines_texts) do
      if #line.text > self._longest_line_length then
         self._longest_line_length = #text
         self._longest_line_n = line_counter
      end
   end
end

function M.InstanceMenuLine:current_text()
   local max_width = lines.max_text_width()

   local output = {}

   local longest_line
   -- If the password line is the longest one, use it
   if self._longest_line_n == -1 then
      longest_line = self._password_input_text.text_object
   else
      longset_line = self._decrypted_lines_texts[self._longest_line_n].text_object
   end
   local longest_done = #longest_line.string == self._letters_output

   for n, line in ipairs(self._decrypted_lines_texts) do
      if not longest_done then
         line.text_object.string = lume.wordwrap(line.text:sub(0, self._letters_output), max_width)
      end

      table.insert(output, line.text_object)
   end

   if not longest_done then
      self._password_input_text.text_object.string =
         lume.wordwrap(self._password_input_text.text:sub(0, self._letters_output), max_width)
   end

   table.insert(output, self._password_input_text.text_object)

   return output
end

function M.InstanceMenuLine:is_interactive()
   -- An interaction could happen at any time, when printing it's
   return self._letters_output == self._longest_line_length and not self._done_input
end

function M.InstanceMenuLine:should_wait()
   return not self._done_input
end

function M.InstanceMenuLine:handle_interaction(event)
   if not lines.inputing_text then lines.inputting_text = true end

   if event.type == EventType.TextEntered then
      local char = string.char(event.text.unicode)

      if GLOBAL.isalpha(event.text.unicode) then
         self._password_input_text.text = self._password_input_text.text .. char
         self._letters_output = self._letters_output + 1

         self:calculate_longest_line()

         return true
      else
         local num = tonumber(char)
         if num and num >= 1 and num <= #self._decrypted_lines_texts then
            self._selected_instance_n = num

            -- Finish input
            lines.reset_after_text_input()
            self._done_input = true

            return true
         end
      end
   elseif event.type == EventType.KeyPressed then
      if event.key.code == KeyboardKey.Backspace and #self._password_input_text.text > self._password_input_text.initial_length then
         -- Remove the last character
         self._password_input_text.text = self._password_input_text.text:sub(1, -2)
         self._letters_output = self._letters_output - 1

         self:calculate_longest_line()

         return true
      elseif event.key.code == KeyboardKey.Return and #self._password_input_text.text > self._password_input_text.initial_length then
         -- Finish input
         lines.reset_after_text_input()
         self._done_input = true

         return true
      end
   end
end

function M.InstanceMenuLine:next()
   if not self._next_instance then
      -- If the line was NOT selected, it means that the password was input
      -- Try and use the password
      if not self._selected_instance_n then
         local password = self._password_input_text.text:sub(self._password_input_text.initial_length + 1, -1)

         for _, instance in ipairs(self._instances) do
            if instance.password == password then
               table.insert(TerminalModule.state_variables.decrypted_instances, instance.name)

               GLOBAL.story_parser:maybe_parse_referenced_file(instance.next)
               self._next_instance = lines.make_line(instance.next, lines.native_lines[instance.next])
            end
         end

         -- If not password matched, direct to the error line
         if not self._next_instance then
            local err_line_name = "instances/menu/wrong_password"
            self._next_instance = lines.make_line(err_line_name, lines.native_lines[err_line_name])
         end
      else
         -- If an already known instance was selected, direct to it
         local instance_next = self._decrypted_lines_texts[self._selected_instance_n].next

         GLOBAL.story_parser:maybe_parse_referenced_file(instance_next)
         self._next_instance = lines.make_line(instance_next, lines.native_lines[instance_next])
      end
   end

   return self._next_instance
end

function M.InstanceMenuLine:maybe_increment_letter_count()
   if self._letters_output < self._longest_line_length and self._time_since_last_letter >= lines.time_per_letter then
      self._time_since_last_letter = 0.0
      self._letters_output = self._letters_output + 1
   end
end


function M.InstanceMenuLine:max_line_height(n)
   -- The password line is always the one after the decrypted lines
   if n == #self._decrypted_lines_texts + 1 then
      return lines.max_string_height(self._password_input_text.text, self._character.font_size)
   else
      return lines.max_string_height(self._decrypted_lines_texts[n].text, self._character.font_size)
   end
end

return M
