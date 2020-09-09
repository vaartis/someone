package = "someone"
version = "0.1-0"

dependencies = {
   "inspect==3.1.1",
   "lume==2.3.0",
   "lua-path==0.3.1",
   "lunajson==1.2.2",
   "bump==3.1.7",
   "liluat==1.2.0"
}

source = {
    url = ""
}

build = {
   type = "builtin",
   modules = {},
   install = {
      lua = {
         walking = "walking.lua",
         ["components.shared"] = "components/shared.lua",
         ["components.player"] = "components/player.lua",
         ["components.assets"] = "components/assets.lua",
         ["components.interaction"] = "components/interaction.lua",
         ["components.debug"] = "components/debug.lua",
         ["components.rooms"] = "components/rooms.lua",
         ["components.entities"] = "components/entities.lua",
         ["components.collider"] = "components/collider.lua",
         ["components.sound"] = "components/sound.lua",
         ["components.note"] = "components/note.lua",

         ["components.first_puzzle"] = "components/first_puzzle.lua",
         ["components.dial_puzzle"] = "components/dial_puzzle.lua",

         terminal = "terminal.lua",
         ["terminal.instance_menu"] = "terminal/instance_menu.lua",
         ["terminal.lines"] = "terminal/lines.lua",
         ["terminal.save_and_return_lines"] = "terminal/save_and_return_lines.lua",
         ["terminal.select_line"] = "terminal/select_line.lua",

         coroutines = "coroutines.lua",
         util = "util.lua",
      }
   }
}
