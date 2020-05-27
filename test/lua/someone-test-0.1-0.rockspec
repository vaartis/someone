package = "someone-test"
version = "0.1-0"

dependencies = {
   "moonscript==0.5.0",
   "cluacov==0.1.1",
   "busted==2.0.0"
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
