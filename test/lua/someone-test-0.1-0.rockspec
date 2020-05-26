package = "someone-test"
version = "0.1-0"

dependencies = {
   "cluacov==0.1.1",
   "busted==2.0.0",
   "luacov-coveralls==0.2.2"
}

source = {
    url = ""
}

build = {
   type = "builtin",
   modules = {},
   install = {
      lua = {
         ["test.walking"] = "walking.moon"
      }
   }
}