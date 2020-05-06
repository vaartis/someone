package = "someone"
version = "0.1-0"

dependencies = {
   "middleclass==4.1.1",
   "inspect==3.1.1",
   "lume==2.3.0",
   "lua-path==0.3.1",
   "lunajson==1.2.2",
   "moonscript==0.5.0",
   "bump==3.1.7"
}

source = {
    url = ""
}

build = {
   type = "builtin",
   modules = {},
   install = {
      lua = {
         ["components.shared"] = "components/shared.moon",
         ["components.player"] = "components/player.moon",
         ["components.assets"] = "components/assets.moon",
         terminal = "terminal.lua",
         walking = "walking.moon",
         coroutines = "coroutines.moon",

         ["components.first_puzzle"] = "components/first_puzzle.moon"
      }
   }
}
