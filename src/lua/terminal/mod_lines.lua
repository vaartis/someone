local class = require("middleclass")
local lume = require("lume")
local path = require("path")

local util = require("util")
local lines = require("terminal.lines")
local assets = require("components.assets")

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

      assets.unload_known_mod_assets()

      for _, module in pairs(_G.mod) do
         -- Update all_modules to remove mod lua files
         lume.remove(util.entities_mod().all_components, _G.mod)

         -- Stop the systems if there were any
         if module.systems then
            for _, sys in ipairs(module.systems) do
               util.rooms_mod().engine:stopSystem(sys.name)
            end
         end
      end

      for name, loaded in pairs(package.loaded) do
         if name:match("^mod.") then
            -- Unload the packages
            package.loaded[name] = nil
         end
      end

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
      -- Save the mod name for later use by other things
      setmetatable(_G.mod, { name = data.name })

      -- Load the assets now if there are any
      if fs.exists(lume.format("resources/mods/{1}/resources/rooms/assets.toml", {data.name})) then
         assets.load_assets()
      end

      local function traverse_into_namespace(namespace, into)
         for name, value in pairs(namespace) do
            if type(value) == "table" then
               into[name] = {}
               traverse_into_namespace(value, into[name])
            else
               local mod_filename = lume.format("resources/mods/{1}/{2}", {data.name, value})
               if path.extension(mod_filename) == ".fnl" then
                  local fennel = require("fennel")
                  debug.traceback = fennel.traceback

                  loaded = fennel.dofile(mod_filename)
               else
                  loaded, err = loadfile(mod_filename)
               end

               if not loaded then
                  error(err)
               end

               if type(loaded) == "function" then
                  into[name] = loaded()
               else
                  into[name] = loaded
               end

               setmetatable(into[name], {__module_name = "mod." .. name})
               -- Update all_modules with mod lua files
               table.insert(
                  util.entities_mod().all_components,
                  into[name]
               )

               package.loaded["mod." .. name] = into[name]
            end
         end
      end

      traverse_into_namespace(data.lua_files, _G.mod)

   end

   if data.first_room ~= "" and GLOBAL.get_current_state() ~= CurrentState.Walking then
      TerminalModule.switch_to_walking(data.first_room)
   end

   self._data = data
end
function M.ModWrapperLine:current_text() end
function M.ModWrapperLine:should_wait() return false end
function M.ModWrapperLine:next()
   if not self._next_instance then
      if self._data.first_line ~= "" then
         self._next_instance = lines.make_line(self._data.first_line, self._line_source)
      elseif self._data.first_room ~= "" then
         self._data.lines["__end"] = {
            __type = { name = "TerminalCustomLineData" },
            class = M.ModExitLine,
         }
         self._next_instance = lines.make_line("__end", self._data.lines)
      end
   end

   return self._next_instance
end

return M
