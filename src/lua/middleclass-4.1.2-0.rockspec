package = "middleclass"
version = "4.1.2-0"
source = {
  url = "git+https://github.com/vaartis/middleclass",
  branch = "master"
}
description = {
   summary = "A simple OOP library for Lua",
   detailed = "It has inheritance, metamethods (operators), class variables and weak mixin support",
   homepage = "https://github.com/kikito/middleclass",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      middleclass = "middleclass.lua"
   }
}
