local util = require("util")
local lume = require("lume")

local rooms = require("components.rooms")
local interaction_components = require("components.interaction")
local debug_components = require("components.debug")

-- Load the room
rooms.load_room("day1/computer_room")

local function update(dt)
   rooms.engine:update(dt)
end

local function draw()
   rooms.engine:draw()
end

local function draw_overlay()
   rooms.engine:draw("overlay")
end

return {
   load_room = rooms.load_room,
   room_shaders = rooms.room_shaders,
   add_event = interaction_components.add_event,

   update = update, draw = draw, draw_overlay = draw_overlay,
   clear_event_store = interaction_components.clear_event_store,

   debug_menu = debug_components.debug_menu
}
