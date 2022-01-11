local lovetoys = require("lovetoys")
local lume = require("lume")

local terminal = require("terminal")
local coroutines = require("coroutines")
local util = require("util")

-- Another initialization because the module may be included early
lovetoys.initialize({
      debug = true,
      globals = true
})

local lovetoys_create = Component.create
function Component.create(name, fields, defaults)
   local result = lovetoys_create(name, fields, defaults)
   result.__defaults = defaults or {}

   return result
end

-- Need to do this afterwards because lovetoys has to initialize first
local collider_components = require("components.collider")
local assets = require("components.assets")
local debug_components = require("components.debug")

local M = {}

M.seconds_since_last_interaction = 0 -- Time tracked by dt, since last interaction
M.seconds_before_next_interaction = 0.3 -- A constant that represents how long to wait between interactions

M.components = {
   interaction = {
      class = Component.create(
         "Interaction",
         {"on_interaction", "is_activatable", "current_state", "state_map", "interaction_sound", "action_text",
          "touch_activated"},
         { touch_activated = false, action_text = "interact" }
      )
   }
}

local InteractionSystem = class("InteractionSystem", System)
function InteractionSystem:requires()
   return {
      objects = {"Interaction", "Collider"},
      interaction_text = {"InteractionTextTag"}
   }
end
function InteractionSystem:onStopSystem()
   local interaction_text_drawable = util.first(self.targets.interaction_text):get("Drawable")
   interaction_text_drawable.enabled = false
end
function InteractionSystem:update(dt)
   -- If there are any interactables, look up the interaction text entity
   local interaction_text_drawable

   if lume.count(self.targets.objects) > 0 then
      interaction_text_drawable = util.first(self.targets.interaction_text):get("Drawable")

      M.seconds_since_last_interaction = M.seconds_since_last_interaction + dt
   end

   local interactables_touched = {}
   for _, obj in pairs(self.targets.objects) do
      local interaction_comp = obj:get("Interaction")
      local physics_world = collider_components.physics_world

      local x, y, w, h = physics_world:getRect(obj)

      local cols = physics_world:queryRect(x, y, w, h)

      -- If the player is in the rectangle of the sprite, then check if the interaction button is pressed
      if lume.any(cols, function(e) return e:has("PlayerMovement") end) then

         if interaction_comp.is_activatable then
            if not interaction_comp.is_activatable(interaction_comp.current_state) then
               goto continue
            end
         end
         table.insert(interactables_touched, interaction_comp)
      end

      -- Update the current texture frame if there's a state map
      if interaction_comp.state_map then
         local anim = obj:get("Animation")
         anim.current_frame = interaction_comp.state_map[interaction_comp.current_state]
      end

      ::continue::
   end

   if interaction_text_drawable then
      interaction_text_drawable.enabled = #interactables_touched > 0
   end

   if #interactables_touched > 0 then
      local pressed_e, pressed_number
      for _, native_event in pairs(M.event_store.events) do
         local event = native_event.event
         if M.seconds_since_last_interaction > M.seconds_before_next_interaction then
            if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
               M.seconds_since_last_interaction = 0

               pressed_e = true
            elseif event.type == EventType.TextEntered then
               local ch = utf8.char(event.text.unicode)

               -- Convert the character to it's number equivalent
               pressed_number = tonumber(ch)
            end
         end
      end

      local interaction_to_execute
      local drawable_string
      if self._selecting_interactable then
         -- If the player is currently selecting an interactable from the list,
         -- collect the interaction strings and show all of the numbered
         local desc_texts = {}
         for n, interactable in ipairs(interactables_touched) do
            table.insert(desc_texts, lume.format("{1}. {2}", {n, interactable.action_text}))
         end

         drawable_string = table.concat(desc_texts, "\n")

         -- If any number was pressed, look it up in the touched list
         -- If a number is not in there, it will just be nil anyway
         if pressed_number then
            interaction_to_execute = interactables_touched[pressed_number]
         end
      else
         -- If not and there's more than one interactable, prompt to select one
         if #interactables_touched > 1 then
            drawable_string = "[E] to..."
            if pressed_e then
               self._selecting_interactable = true
            end
         else
            -- If there's only one interactable, just use that one
            local interactable = interactables_touched[1]

            if not interactable.touch_activated then
               drawable_string = "[E] to " .. interactable.action_text

               -- If action was pressed, mark it as the one to execute
               if pressed_e then
                  interaction_to_execute = interactable
               end
            elseif interactable.touch_activated and not interactable.was_touch_activated then
               -- Mark it as executed. In this room instance, it won't be executed anymore
               interactable.was_touch_activated = true
               --- Always execute it if it's touched. It will only be executed once.
               interaction_to_execute = interactable

               interaction_text_drawable.drawable.string = ""
            end
         end
      end

      if drawable_string then
         interaction_text_drawable.drawable.string = drawable_string
      end

      if interaction_to_execute then
         local interaction_res = interaction_to_execute.on_interaction(interaction_to_execute.current_state)

         -- If some kind of result was returned, use it as the new state
         if interaction_res ~= nil and interaction_res ~= interaction_to_execute.current_state then
            interaction_to_execute.current_state = interaction_res
            if interaction_to_execute.__editor_state then
               interaction_to_execute.__editor_state.current_state = interaction_res
            end

            -- Play the sound if there is one
            if interaction_to_execute.interaction_sound then
               interaction_to_execute.interaction_sound:play()
            end
         end
      end
   elseif self._selecting_interactable then
      self._selecting_interactable = false
   end
end

M.activatable_callbacks = {}

function M.activatable_callbacks.state_equal(curr_state, to)
   return curr_state == to
end

--- Ensures that the state variable at path can be placed at that path
--- after the call, by creating the tables up to the variable name and
--- returning the table to place the variable into and the name at which
--- the variable should be assigned
local function state_variable_ensure_path_up_to(variable_path)
   local containing_table = TerminalModule.state_variables.walking
   for n, var_name in ipairs(variable_path) do
      if n == #variable_path then
         -- If the current value is the last one, return the containing table
         return containing_table, var_name
      else
         -- Otherwise create them if needed or traverse them if they exist
         if containing_table[var_name] == nil then
            containing_table[var_name] = {}
         elseif type(containing_table[var_name]) ~= "table" then
            error(
               lume.format(
                  "Expected {1} in state variables to be a table, but it's {2}",
                  var_name, containing_table[var_name]
               )
            )
         end

         containing_table = containing_table[var_name]
      end
   end
end

--- Returns the state variable at the path priovided,
--- creating that path if needed and returning nil on undefined variables
local function state_variable_at_path(variable_path)
   local containing_table, var_name = state_variable_ensure_path_up_to(variable_path)

   return containing_table[var_name]
end

--- Checks if the state variable is equal to some provided value, handling
--- boolean values by converting the state variable to boolean and checking equality with that
function M.activatable_callbacks.state_variable_equal(_state, variable_path, value)
   local var = state_variable_at_path(variable_path)

   if type(value) == "boolean" then
      -- not not is a trick to convert a variable to boolean
      return (not not var) == value
   else
      return var == value
   end
end

M.interaction_callbacks = {}

-- A callback that does nothing, to be the default for the editor
function M.interaction_callbacks.identity() end

--- Sets the state variable at path to a new value, optionally setting the new state of the interactable
function M.interaction_callbacks.state_variable_set(_state, variable_path, value, new_state)
   local containing_table, var_name = state_variable_ensure_path_up_to(variable_path)

   containing_table[var_name] = value

   return new_state
end

function M.interaction_callbacks.computer_switch_to_terminal(curr_state)
   local player = util.rooms_mod().find_player()

   player:get("PlayerMovement").active = false

   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         GLOBAL.set_current_state(CurrentState.Terminal)
      end,
      function()
         terminal.active = true
      end
   )

   return "enabled"
end

local talking_speed = 0.02

function M.interaction_callbacks.player_talk(_curr_state, phrase, state_var)
   local engine = util.rooms_mod().engine

   if state_var then
      local containing, name = state_variable_ensure_path_up_to(state_var)
      containing[name] = true
   end

   M.disable_player(engine)

   coroutines.create_coroutine(function ()
         local interaction_text_drawable = util.first(engine:getEntitiesWithComponent("InteractionTextTag")):get("Drawable")

         local letter = 1
         local timer = 0

         interaction_text_drawable.enabled = true
         interaction_text_drawable.drawable.string = ""

         while interaction_text_drawable.drawable.string ~= phrase do
            if timer > talking_speed then
               interaction_text_drawable.drawable.string = phrase:sub(1, letter)
               letter = letter + 1
               timer = 0
            end

            timer = timer + coroutine.yield()
         end

         interaction_text_drawable.drawable.string = interaction_text_drawable.drawable.string ..
            "\n\n[E] to continue"

         local exited = false
         while not exited do
            M.update_seconds_since_last_interaction(coroutine.yield())

            M.if_key_pressed({
                  [KeyboardKey.E] = function()
                     exited = true
                  end
            }, true)
         end

         M.enable_player(engine)
   end)
end

--- @param fnc_data table Table that contains data about the looked-up function (particularly, the module and the name)
--- @param module_field string The field in the module where the function should be looked up
--- @param context table The context for error reporting
--- @return fun(...):bool The activatable function
function try_get_fnc_from_module(fnc_data, module_field, context)
   local full_name = lume.format("{1}.{2}", {context.entity_name, context.comp_name})

   local status, callback_module = pcall(require, fnc_data.module)
   if not status then
      -- Print the error first
      print(callback_module)
      error(
         lume.format(
            "{full_name} requires a module named '{module}' for its {needed_for} callback, but that module cannot be imported",
            { full_name = full_name, module = fnc_data.module, needed_for = context.needed_for }
         )
      )
   end

   local module_exported_table = callback_module[module_field]
   if not module_exported_table then
      error(
         lume.format(
            "{full_name} requires '{module_field}' in a module named '{module}' for its {needed_for} callback, but the module does not export that field",
            {full_name = full_name, module_field = module_field, module = fnc_data.module, needed_for = context.needed_for }
         )
      )
   end

   local callback_function = module_exported_table[fnc_data.name]
   if not callback_function then
      error(
         lume.format(
            "{full_name} requires a function named '{func_name}' from module '{module}' for its {needed_for} callback, but that function is not in the module's {module_field}",
            { full_name = full_name, func_name = fnc_data.name, module = fnc_data.module, needed_for = context.needed_for,
              module_field = module_field }
         )
      )
   end


   local declared_args = debug_components.declared_callback_arguments[callback_function]

   local args
   if fnc_data.args then
      -- Clone the arguments to ensure that functions are called with unmodified arguments when editor changes things
      args = util.deep_merge({}, fnc_data.args)
   end

   if fnc_data.self then
      if not context.entity then
         error("Tried using self on a callback, but no entity was passed in the context")
      end

      if args then
         if lume.isarray(args) then
            table.insert(args, 1, context.entity)
         else
            args.self = context.entity
         end
      else
         args = { context.entity }
      end
   end

   -- If there are args specified, put them after whatever is provided when calling.
   -- The functions here use self because of the stupid tandency of lua's __call to pass
   -- the table as the self parameter without a way to disable this and blocking
   -- normal argument passing unless a self parameter exists. So, have a dummy self parameter
   -- and don't use it.
   if args then
      if lume.isarray(args) then
         return function(self, ...)
            return callback_function(..., table.unpack(args))
         end, declared_args
      else
         return function(self, ...)
            return callback_function(..., args)
         end, declared_args
      end
   else
      return callback_function, declared_args
   end
end

function M.process_activatable(comp, field, context)
   local got_field = comp[field]

   -- Use true by default if there was no field
   if got_field == nil then return true end

   local result, declared_args
   if type(got_field) == "table" then
      if got_field["not"] then
         got_field = got_field["not"]

         local fnc
         fnc, declared_args = try_get_fnc_from_module(got_field, "activatable_callbacks", context)

         -- Invert whatever the function returns
         result = function(self, ...)
            return not fnc(self, ...)
         end
      elseif got_field["and"] then
         local conds = {}
         for _, cnd in ipairs(got_field["and"]) do
            -- When calling a function with something that returns more than one
            -- value, apparently all the values are passed as arguments. That is not
            -- what is supposed to happen in this case, so a variable is needed to
            -- ignore the second returned value
            local fnc = try_get_fnc_from_module(cnd, "activatable_callbacks", context)
            -- FIXME: Ignore declared args here for now
            table.insert(conds, fnc)
         end

         result = function(self, ...)
            local args = { self, ... }
            return lume.all(conds, function(f) return f(table.unpack(args)) end)
         end
      else
         result, declared_args = try_get_fnc_from_module(got_field, "activatable_callbacks", context)
      end
   else
      return got_field
   end

   local ret_result = { callback_data = got_field, declared_args = declared_args }
   setmetatable(ret_result, { __call = result })
   return ret_result
end

function M.process_interaction(comp, field, context)
   local got_field = comp[field]

   if got_field == nil then
      error(context.entity_name .. "." .. context.comp_name .. " does not have the required '" .. field .. "' field")
   end

   local result, declared_args = try_get_fnc_from_module(got_field, "interaction_callbacks", context)

   -- Return a callable table. Don't actually care about storing the function, the only thing that is needed from it is calling,
   -- and otherwise just storing it in a closure is fine
   local ret_result = { callback_data = got_field, declared_args = declared_args }
   setmetatable(ret_result, { __call = result })
   return ret_result
end

function M.components.interaction.process_component(new_ent, comp, entity_name)
   local comp_name = "interaction"

   local interaction_callback = M.process_interaction(
      comp,
      "callback",
      { entity_name = entity_name, comp_name = comp_name, needed_for = "interaction", entity = new_ent }
   )

   local activatable_callback
   if comp.activatable_callback then
      activatable_callback = M.process_activatable(
         comp,
         "activatable_callback",
         { entity_name = entity_name, comp_name = comp_name, needed_for =  "activatable", entity = new_ent }
      )
   end

   local interaction_sound
   if comp.interaction_sound_asset then
      interaction_sound = assets.create_sound_from_asset(comp.interaction_sound_asset)
   end

   local class = M.components.interaction.class(
      interaction_callback,
      activatable_callback,

      comp.initial_state,
      comp.state_map,
      interaction_sound,
      comp.action_text,

      comp.touch_activated
   )
   class.__initial_state = comp.initial_state

   new_ent:add(class)
end

function M.components.interaction.class:default_data(ent)
   return { callback = { module = "components.interaction", name = "identity" } }
end

function M.components.interaction.class:show_editor(ent)
   ImGui.Text("Interaction")

   if not self.__editor_state then
      -- Set up some default editor state
      self.__editor_state = {
         callback = util.deep_merge(
            { declared_args = self.on_interaction.declared_args },
            self.on_interaction.callback_data
         ),

         activatable_enabled = self.is_activatable ~= nil,
         -- "and" means if the value is not nil
         activatable_callback = self.is_activatable and
            util.deep_merge(
               { declared_args = self.is_activatable.declared_args },
               self.is_activatable.callback_data
            ),

         current_state = self.current_state
      }
   end

   local function show_callback(callback_parent, callback_name, original, module_source, installation_function)
      local callback = callback_parent[callback_name]
      if not callback then
         callback = { module = "", name = "" }
         callback_parent[callback_name] = callback
      end

      if callback["and"] then
      elseif callback["or"] then
      else
         debug_components.select_callback(module_source, callback)
      end

      debug_components.show_callback_args(callback, callback_name)

      local install = function()
         -- Try installing the new callback
         local is_ok, interaction_callback_or_err = pcall(
            installation_function,
            callback_parent,
            callback_name,
            { entity_name = ent:get("Name").name, comp_name = "interaction", needed_for = callback_name, entity = ent }
         )

         if not is_ok then
            self.__editor_state.last_error = interaction_callback_or_err

            return false
         else
            -- Else reset the error, hiding it
            self.__editor_state.last_error = nil

            -- And set the new interaction callback
            self.on_interaction = interaction_callback_or_err

            return true
         end
      end

      if ImGui.Button("Install##" .. callback_name) then
         install()
      end
      ImGui.SameLine()
      if ImGui.Button("Reset##" .. callback_name) then
         -- Reset to whatever is stored in current interaction data
         callback_parent[callback_name] = original
      end
      ImGui.SameLine()
      if ImGui.Button("Save##" .. callback_name) then
         if callback_parent[callback_name].self == false then
            callback_parent[callback_name].self = nil
         end

         -- When saving, remove the declared args property
         local saved_callback = lume.merge({}, callback)
         saved_callback.declared_args = nil

         if install() then
            TOML.save_entity_component(ent, "interaction", self, { callback_name }, { [callback_name] = saved_callback })
         end
      end
   end

   if ImGui.TreeNode("Callback") then
      show_callback(self.__editor_state, "callback", self.on_interaction.callback_data, "interaction_callbacks", M.process_interaction)
      ImGui.TreePop()
   end

   self.__editor_state.activatable_enabled = ImGui.Checkbox("Activatable callback", self.__editor_state.activatable_enabled)
   if self.__editor_state.activatable_enabled then
      if ImGui.TreeNode("Activatable callback##treenode") then
         show_callback(
            self.__editor_state, "activatable_callback",
            self.is_activatable and self.is_activatable.callback_data, "activatable_callbacks", M.process_activatable
         )
         ImGui.TreePop()
      end
   end

   self.touch_activated = ImGui.Checkbox("Touch activated", self.touch_activated)
   self.action_text = ImGui.InputText("Action text", self.action_text)

   if ImGui.BeginCombo("Interaction sound", (self.interaction_sound and assets.used_assets[self.interaction_sound]) or "(none)") then
      -- Special case for no sound
      if ImGui.Selectable("(none)", not self.interaction_sound) then
         self.interaction_sound = nil
      end
      for _, name in ipairs(assets.list_known_assets("sounds")) do
         -- not not is to basically a cast to boolean, as Selectable WANTS a boolean
         if ImGui.Selectable(name, not not (self.interaction_sound and assets.used_assets[self.interaction_sound] == name)) then
            self.interaction_sound = assets.create_sound_from_asset(name)
         end
      end

      ImGui.EndCombo()
   end

   if ImGui.TreeNode("State map") then
      debug_components.show_table("State map", self, "state_map", Vector2f.new(0, 70))
      ImGui.TreePop()
   end

   self.__initial_state = ImGui.InputText("Initial state", self.__initial_state or "")
   self.__editor_state.current_state = ImGui.InputText("Current state", self.__editor_state.current_state or "")

   if ImGui.Button("Save") then
      if lume.trim(self.action_text) == "" then
         self.action_text = self.__defaults.action_text
      end
      if lume.trim(self.__initial_state) == "" then
         self.__initial_state = nil
      end
      if lume.trim(self.__editor_state.current_state) == "" then
         self.__editor_state.current_state = nil
      end
      self.current_state = self.__editor_state.current_state

      local parts_to_save, part_values = {
         "touch_activated", "action_text", "interaction_sound_asset",
         "state_map", "initial_state"
      }, { touch_activated = self.touch_activated, action_text = self.action_text,
           interaction_sound_asset = self.interaction_sound and assets.used_assets[self.interaction_sound],
           state_map = self.state_map, initial_state = self.__initial_state }

      if not self.__editor_state.activatable_enabled then
         -- Mark that the part should be deleted
         table.insert(parts_to_save, "activatable_callback")

         -- Remove the activatable from the actual component
         self.is_activatable = nil
         self.__editor_state.activatable_callback = nil
      end

      TOML.save_entity_component(ent, "interaction", self, parts_to_save, part_values)
   end

   if self.__editor_state.last_error then
      ImGui.TextWrapped(self.__editor_state.last_error)
   end
end

function M.disable_player(engine)
   if engine.systemRegistry["InteractionSystem"].active then
      engine:stopSystem("InteractionSystem")
   end
   if engine.systemRegistry["PlayerMovementSystem"].active then
      engine:stopSystem("PlayerMovementSystem")

      util.rooms_mod().find_player():get("Animation").playing = false
   end
end

function M.enable_player(engine)
   if not engine.systemRegistry["InteractionSystem"].active then
      engine:startSystem("InteractionSystem")
   end
   if not engine.systemRegistry["PlayerMovementSystem"].active then
      engine:startSystem("PlayerMovementSystem")
   end
end

function M.update_seconds_since_last_interaction(dt)
   M.seconds_since_last_interaction = M.seconds_since_last_interaction + dt
end

--- A map is passed, and if a key from that map is pressed,
--- the value in the map is called
function M.if_key_pressed(keyboard_keys, is_down)
   for _, native_event in pairs(M.event_store.events) do
      local event = native_event.event

      -- is_down can be used to detect if key is pressed, instead of released.
      -- Useful for coroutines, in which the release event is hard to catch
      local needed_event = (is_down and event.type == EventType.KeyPressed) or
         (not is_down and event.type == EventType.KeyReleased)

      if M.seconds_since_last_interaction > M.seconds_before_next_interaction and needed_event
      and keyboard_keys[event.key.code] then
         M.seconds_since_last_interaction = 0

         -- Call the on-key function
         keyboard_keys[event.key.code]()
      end
   end
end

M.systems = {
   InteractionSystem
}

local NativeEvent = class("NativeEvent")
function NativeEvent:initialize(event)
   self.event = event
end

local EventStore = class("EventStore")
function EventStore:initialize()
   self.events = {}
end
function EventStore:add_event(event)
   if not self.events then self.events = {} end

   table.insert(self.events, event)
end
function EventStore:clear()
   self.events = {}
end

M.native_event_manager = EventManager()
M.event_store = EventStore()

M.native_event_manager:addListener("NativeEvent", M.event_store, M.event_store.add_event)

function M.add_event(event)
   M.native_event_manager:fireEvent(NativeEvent(event))
end

function M.clear_event_store()
   M.event_store:clear()
end

M.system_run_priority = 3

return M
