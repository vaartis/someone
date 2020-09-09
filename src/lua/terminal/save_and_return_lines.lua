local class = require("middleclass")
local lines = require("terminal.lines")

local M = {}

--[[
SaveLine / ReturnLine:

SaveLine saves the next position to the state_variables, from where it can be loaded by using
the same next value used in this line with ReturnLine.

Example usage:

1:
  custom:
    terminal.save_and_return_lines.SaveLine:
      next: !line-name 2
      return_to: !line-name 3

2:
  custom:
    terminal.save_and_return_lines.ReturnLine:
      next_was: !line-name 2

3:
  text: Result

When line 1 is encountered, execution jumps to line 2 (specified as next) and
line 3 (specified as return_to) is written into state_variables. When line 2
uses itself as next_was, that record is loaded from state_variables and is resolved
to refer to line 3 (as specified in return_to), so execution "returns" to that line.

This is particularly useful when you need to have a line executed in multiple places
and want to return back afterwards without knowing exactly where to return to. So you
just save your position and then go back to it.
]]

M.SaveLine = class("SaveLine", lines.TerminalLine)
function M.SaveLine:initialize(args)
   M.SaveLine.super.initialize(self)

   self._next_instance = lines.make_line(args.next, self._line_source)

   if not TerminalModule.state_variables.save_to_return_lines then
      TerminalModule.state_variables.saved_to_return_lines = {}
   end

   -- Use the target name as the ID for saving
   TerminalModule.state_variables.saved_to_return_lines[args.next] = args.return_to
end
function M.SaveLine:current_text() end
function M.SaveLine:should_wait() return false end
function M.SaveLine:next() return self._next_instance end

M.ReturnLine = class("ReturnLine", lines.TerminalLine)
function M.ReturnLine:initialize(args)
   M.ReturnLine.super.initialize(self)

   local return_to = TerminalModule.state_variables.saved_to_return_lines[args.next_was]

   self._next_instance = lines.make_line(return_to, self._line_source)
end
function M.ReturnLine:current_text() end
function M.ReturnLine:should_wait() return false end
function M.ReturnLine:next() return self._next_instance end

return M
