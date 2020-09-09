local class = require("middleclass")
local lines = require("terminal.lines")
local lume = require("lume")

local M = {}

--[[
SelectLine is used to select the next line from multiple possibilities based on some condition.
When the condition matches, the control transfers to the line specified there and others are not checked.
If the line doesn't have a condition, it will always be selected when encountered, therefore such a line should only
be placed at the end.

Example usage:

1:
  custom:
    terminal.select_line.SelectLine:
    - condition: |-
          return TerminalModule.state_variables.know_about_stuff
      next: !line-name know-about-stuff
    - next: !line-name dont-know

Here, if the condition is satisfied and the player "knows about stuff", control will transfer to know-about-stuff.
Otherwise, the no-condition line matches and control transfers to dont-know. Note that it is an error if no variant is matched.
]]

M.SelectLine = class("SelectLine", lines.TerminalLine)
function M.SelectLine:initialize(args)
   M.SelectLine.super.initialize(self)

   local selected_next
   for n, var in ipairs(args) do
      local should_accept = true

      -- If there is no condition, then should_accept will accept the line by default (as it is the catch-all line)
      -- and this will stop the search. Otherwise the condition will be checked and it will dictate the value of should_accept
      if var.condition then
         local condition, err = load(var.condition, lume.format("{1}.condition", {self._name}))
         if err then error(err) end

         should_accept = condition()
         if type(should_accept) ~= "boolean" then
            error(lume.format("The condition number {2} in {1} doesn't return a boolean, but a {4}", {self._name, n, type(cond_result)}))
         end
      end

      if should_accept then
         selected_next = var.next
         break
      end
   end
   if not selected_next then
      error(lume.format("No branch matches in {1}", {self._name}))
   end

   self._next_instance = lines.make_line(selected_next, lines.native_lines[selected_next])
end
function M.SelectLine:current_text() end
function M.SelectLine:should_wait() return false end
function M.SelectLine:next() return self._next_instance end

return M
