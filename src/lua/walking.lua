local util = require("util")

local rooms = require("components.rooms")
local interaction_components = require("components.interaction")

local state_variables = {}

-- Load the room
--rooms.load_room("day3/first_puzzle_room")

local function update(dt)
   rooms.engine:update(dt)
end

local function draw()
   rooms.engine:draw()
end


local function draw_overlay()
   rooms.engine:draw("overlay")
end

local function debug_menu()
   util.debug_menu_process_state_variable_node("State variables", state_variables)
end

return {
   load_room = rooms.load_room,
   room_shaders = rooms.room_shaders,
   add_event = interaction_components.add_event,

   update = update, draw = draw, draw_overlay = draw_overlay,
   state_variables = state_variables,
   clear_event_store = interaction_components.clear_event_store,

   debug_menu = debug_menu
}
