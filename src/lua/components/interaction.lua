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
   {"on_interaction", "interaction_args", "is_activatable" , "activatable_args", "current_state", "state_map", "interaction_sound", "action_text"}
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

   local any_interactables_touched = false
   for _, obj in pairs(self.targets.objects) do

      -- If the entity has a drawable and it's not enabled, do not process interactions with it
      local maybe_drawable = obj:get("Drawable")
      if not maybe_drawable.enabled then goto continue end

      local interaction_comp = obj:get("Interaction")
      local physics_world = obj:get("Collider").physics_world

      local x, y, w, h = physics_world:getRect(obj)
      local cols = physics_world:queryRect(x, y, w, h)

      -- If the player is in the rectangle of the sprite, then check if the interaction button is pressed
      if lume.any(cols, function(e) return e:has("PlayerMovement") end) then
         if interaction_comp.is_activatable then
            local is_activatable = interaction_comp.is_activatable(
               interaction_comp.current_state,
               (function()
                     if interaction_comp.activatable_args then
                        if lume.isarray(interaction_comp.activatable_args) then
                           return table.unpack(interaction_comp.activatable_args)
                        else
                           return interaction_comp.activatable_args
                        end
                     end
               end)())

            if not is_activatable then goto continue end
         end
         any_interactables_touched = true

         local action_name
         if interaction_comp.action_text then
            action_name = interaction_comp.action_text
         else
            action_name "interact"
         end
         interaction_text_drawable.drawable.string = "[E] to " .. action_name

         for _, native_event in pairs(M.event_store.events) do
            local event = native_event.event
            if M.seconds_since_last_interaction > M.seconds_before_next_interaction and
            event.type == EventType.KeyReleased and event.key.code == KeyboardKey.E then
               M.seconds_since_last_interaction = 0

               local interaction_res = interaction_comp.on_interaction(
                  interaction_comp.current_state,
                  (function()
                        if interaction_comp.interaction_args then
                           if lume.isarray(interaction_comp.interaction_args) then
                              return table.unpack(interaction_comp.interaction_args)
                           else
                              return interaction_comp.interaction_args
                           end
                        end
                  end)()
               )

               -- If some kind of result was returned, use it as the new state
               if interaction_res ~= nil and interaction_res ~= interaction_comp.current_state then
                  interaction_comp.current_state = interaction_res

                  -- Play the sound if there is one
                  if interaction_comp.interaction_sound then
                     interaction_comp.interaction_sound:play()
                  end
               end
            end
         end
      end

      interaction_text_drawable.enabled = any_interactables_touched

      -- Update the current texture frame if there's a state map
      if interaction_comp.state_map then
         local anim = obj:get("Animation")
         anim.current_frame = interaction_comp.state_map[interaction_comp.current_state]
      end

      ::continue::
   end
end

M.activatable_callbacks = {}

function M.activatable_callbacks.first_button_pressed()
   return WalkingModule.state_variables.first_button_pressed
end

function M.activatable_callbacks.state_equal(curr_state, to)
   return curr_state == to
end

M.interaction_callbacks = {}
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

function M.interaction_callbacks.activate_computer(curr_state)
   WalkingModule.state_variables.first_button_pressed = true

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
            { full_name = full_name, module = fnc_data.module, context.needed_for }
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

   return callback_function
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
      local interaction_args
      if comp.callback.args then
         interaction_args = comp.callback.args
      end

      local activatable_callback, activatable_args
      if comp.activatable_callback then
         activatable_callback = M.process_activatable(
            comp,
            "activatable_callback",
            { entity_name = entity_name, comp_name = comp_name, needed_for =  "activatable" }
         )
         activatable_args = comp.activatable_callback.args
      end

      local interaction_sound
      if comp.interaction_sound_asset then
         interaction_sound = Sound.new()
         interaction_sound.buffer = assets.assets.sounds[comp.interaction_sound_asset]
      end

      new_ent:add(
         InteractionComponent(
            interaction_callback,
            interaction_args,

            activatable_callback,
            activatable_args,

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
