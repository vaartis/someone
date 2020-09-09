local class = require("middleclass")
local lume = require("lume")

local lines = require("terminal.lines")

local M = {}

local saved_state_variables

M.ModExitLine = class("ModExitLine", lines.TerminalLine)
function M.ModExitLine:initialize()
   M.ModExitLine.super.initialize(self)

   -- If there's a script already, save it
   local original_script = self._script_after

   -- Restore state variables
   TerminalModule.state_variables = saved_state_variables
   saved_state_variables = nil

   self._script_after = function()
      -- Execute the original script first
      if original_script then original_script() end

      if _G.mod then _G.mod = nil end
   end

   self._next_instance = lines.make_line("instances/menu/exit", lines.native_lines)
end
function M.ModExitLine:current_text() end
function M.ModExitLine:should_wait() return false end
function M.ModExitLine:next()
      return self._next_instance
end

M.ModWrapperLine = class("ModWrapperLine", lines.TerminalLine)
function M.ModWrapperLine:initialize(data)
   M.ModWrapperLine.super.initialize(self)

   saved_state_variables = TerminalModule.state_variables
   TerminalModule.state_variables = {
      input_variables = {}
   }

   if data.lua_files then
      _G.mod = {}

      local function traverse_into_namespace(namespace, into)
         for name, value in pairs(namespace) do
            if type(value) == "table" then
               into[name] = {}
               traverse_into_namespace(value, into[name])
            else
               loaded, err = loadfile(lume.format("resources/mods/{1}/{2}", {data.name, value}))
               if err then error(err) end

               into[name] = loaded()
            end
         end
      end

      traverse_into_namespace(data.lua_files, _G.mod)
   end

   self._next_instance = lines.make_line(data.first_line, self._line_source)
end
function M.ModWrapperLine:current_text() end
function M.ModWrapperLine:should_wait() return false end
function M.ModWrapperLine:next() return self._next_instance end

return M
