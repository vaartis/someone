rooms = require("components.rooms")
interaction_components = require("components.interaction")

state_variables = {}

-- Load the room
--rooms.load_room "day3/first_puzzle_room"

update = (dt) ->
  rooms.engine\update(dt)

  interaction_components.update(dt)

draw = () ->
  rooms.engine\draw()

draw_overlay = () ->
  rooms.engine\draw("overlay")

{
  load_room: rooms.load_room,
  room_shaders: rooms.room_shaders
  add_event: interaction_components.add_event

  :update, :draw, :draw_overlay
  :state_variables
}
