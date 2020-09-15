return {
   prefab = { name = "day2/computer_room" },
   entities = {
      table = {
         interaction = {
            activatable_callback = {
               module = "components.interaction", name = "state_variable_equal", args = { {"dial_puzzle", "solved"}, true }
            },
            callback = { module = "components.interaction", name = "computer_switch_to_terminal" }
         },
      },

      lamp_placement = {
         collider = {
            mode = "constant",
            size = {50, 50},
            trigger = true
         },
         transformable = {
            position = {350, 750}
         },
         interaction = {
            activatable_callback = {
               ["and"] = {
                  { module = "components.interaction", name = "state_variable_equal", args = { {"first_puzzle_lamp", "taken"}, true } },
                  { module = "components.interaction", name = "state_variable_equal", args = { {"first_puzzle_lamp", "put"}, false } },
               }
            },
            callback = {
               module = "components.interaction", name = "state_variable_set", args = { {"first_puzzle_lamp", "put"}, true }
            },
            action_text = "put the lamp down"
         }
      },

      lamp = {
         drawable = {
            enabled = { module = "components.interaction", name = "state_variable_equal", args = { {"first_puzzle_lamp", "put"}, true } },
            kind = "sprite",
            texture_asset = "table_lamp",
            z = 2
         },
         transformable = {
            position = {230, 750},
            scale = {-1, 1}
         }
      }
   }
}
