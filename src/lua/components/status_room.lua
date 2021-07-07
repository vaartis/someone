local interaction_components = require("components.interaction")

local M = {}

M.interaction_callbacks = {}

function M.interaction_callbacks.check_way_up(_state, phrase)
   interaction_components.interaction_callbacks.player_talk(_state, phrase)
   interaction_components.interaction_callbacks.state_variable_set(_state, {"status_room", "way_up_checked"}, true)
end

return M
