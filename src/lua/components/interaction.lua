local lovetoys = require("lovetoys")
local lume = require("lume")

local terminal = require("terminal")
local coroutines = require("coroutines")
local util = require("util")

local assets = require("components.assets")

local M = {}

-- Another initialization because the module may be included early
lovetoys.initialize({
      debug = true,
      globals = true
})

M.seconds_since_last_interaction = 0 -- Time tracked by dt, since last interaction
M.seconds_before_next_interaction = 0.3 -- A constant that represents how long to wait between interactions

local InteractionComponent = Component.create(
   "Interaction",
   {"on_interaction", "is_activatable", "current_state", "state_map", "interaction_sound", "action_text"}
)

local InteractionSystem = class("InteractionSystem", System)
function InteractionSystem:requires()
   return {
      objects = {"Interaction", "Collider"},
      interaction_text = {"InteractionTextTag"}
   }
end
function InteractionSystem:onStopSystem()
   local interaction_text_key = lume.first(lume.keys(self.targets.interaction_text))
   if not interaction_text_key then error("No interaction text entity found") end
   local interaction_text_drawable = self.targets.interaction_text[interaction_text_key]:get("Drawable")
   interaction_text_drawable.enabled = false
end
function InteractionSystem:update(dt)
   -- If there are any interactables, look up the interaction text entity
   local interaction_text_drawable

   if lume.count(self.targets.objects) > 0 then
      local interaction_text_key = lume.first(lume.keys(self.targets.interaction_text))
      if not interaction_text_key then error("No interaction text entity found") end
      interaction_text_drawable = self.targets.interaction_text[interaction_text_key]:get("Drawable")

      M.seconds_since_last_interaction = M.seconds_since_last_interaction + dt
   end

   local interactables_touched = {}
   local any_interactables_touched = false
   for _, obj in pairs(self.targets.objects) do
      local interaction_comp = obj:get("Interaction")
      local physics_world = obj:get("Collider").physics_world

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

   interaction_text_drawable.enabled = #interactables_touched > 0
   if #interactables_touched > 0 then
      local pressed_e, pressed_number
      for _, native_event in pairs(M.event_store.events) do
         local event = native_event.event
         if M.seconds_since_last_interaction > M.seconds_before_next_interaction then
            if event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
               M.seconds_since_last_interaction = 0

               pressed_e = true
            elseif event.type == EventType.TextEntered then
               local ch = string.char(event.text.unicode)

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
            local action_name
            if interactable.action_text then
               action_name = interactable.action_text
            else
               action_name = "interact"
            end

            table.insert(desc_texts, lume.format("{1}. {2}", {n, action_name}))
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

            if interactable.action_text then
               action_name = interactable.action_text
            else
               action_name = "interact"
            end

            drawable_string = "[E] to " .. action_name

            -- If action was pressed, mark it as the one to execute
            if pressed_e then
               interaction_to_execute = interactable
            end
         end
      end

      interaction_text_drawable.drawable.string = drawable_string

      if interaction_to_execute then
         local interaction_res = interaction_to_execute.on_interaction(interaction_to_execute.current_state)

         -- If some kind of result was returned, use it as the new state
         if interaction_res ~= nil and interaction_res ~= interaction_to_execute.current_state then
            interaction_to_execute.current_state = interaction_res

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
   local containing_table = WalkingModule.state_variables
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
         terminal.active = true
      end
   )

   return "enabled"
end

function M.interaction_callbacks.switch_room(curr_state, args)
   local room, player_pos = args.room, args.player_pos

   util.rooms_mod().load_room(room)

   if player_pos then
      local player = util.rooms_mod().find_player()

      local physics_world = player:get("Collider").physics_world
      return physics_world:update(player, player_pos[1], player_pos[2])
   end
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

   -- If there are args specified, put them after whatever is provided when calling
   if fnc_data.args then
      if lume.isarray(fnc_data.args) then
         return function(...)
            return callback_function(..., table.unpack(fnc_data.args))
         end
      else
         return function(...)
            return callback_function(..., fnc_data.args)
         end
      end
   else
      return callback_function
   end
end

function M.process_activatable(comp, field, context)
   local got_field = comp[field]

   -- Use true by default if there was no field
   if got_field == nil then return true end

   if type(got_field) == "table" then
      if got_field["not"] then
         got_field = got_field["not"]

         local fnc = try_get_fnc_from_module(got_field, "activatable_callbacks", context)

         -- Invert whatever the function returns
         return function(...)
            return not fnc(...)
         end
      else
         return try_get_fnc_from_module(got_field, "activatable_callbacks", context)
      end
   else
      return got_field
   end
end

function M.process_interaction(comp, field, context)
   local got_field = comp[field]

   if got_field == nil then
      error(context.entity_name .. "." .. context.comp_name .. " does not have the required '" .. field .. "' field")
   end

   return try_get_fnc_from_module(got_field, "interaction_callbacks", context)
end

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "interaction" then
      local interaction_callback = M.process_interaction(
         comp,
         "callback",
         { entity_name = entity_name, comp_name = comp_name, needed_for = "interaction" }
      )

      local activatable_callback
      if comp.activatable_callback then
         activatable_callback = M.process_activatable(
            comp,
            "activatable_callback",
            { entity_name = entity_name, comp_name = comp_name, needed_for =  "activatable" }
         )
      end

      local interaction_sound
      if comp.interaction_sound_asset then
         interaction_sound = Sound.new()
         interaction_sound.buffer = assets.assets.sounds[comp.interaction_sound_asset]
      end

      new_ent:add(
         InteractionComponent(
            interaction_callback,
            activatable_callback,

            comp.initial_state,
            comp.state_map,
            interaction_sound,
            comp.action_text
         )
      )

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(InteractionSystem())
end

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

function M.update(dt)
   M.event_store:clear()
end

return M
