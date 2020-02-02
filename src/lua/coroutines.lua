local lume = require("lume")



local coroutines = {}

local M = {}

function M.create_coroutine(fnc, finish_callback)
   local cor = coroutine.create(fnc)

   table.insert(
      coroutines,
      {
         cor = cor,
         finish_callback = finish_callback
      }
   )
end

function M.run()
   local to_remove = {}
   for n, cor in pairs(coroutines) do
      _, err = coroutine.resume(cor.cor)
      if err then
         error(err)
      end

      if coroutine.status(cor.cor) == "dead" then
         table.insert(to_remove, n)

         -- Call the callback
         if cor.finish_callback then
            cor.finish_callback()
         end
      end
   end

   -- Clean up the dead coroutines
   lume.each(to_remove, function(n) table.remove(coroutines, n) end)
end

function M.black_screen_out()
   local screen_size = GLOBAL.drawing_target.size
   local black_rect = RectangleShape.new(
      Vector2f.new(screen_size.x, screen_size.y)
   )
   local color = Color.new(0, 0, 0, 0)

   while color.a < 255 do
      -- Need to be careful here, because color wraps around if it overflows
      color.a = color.a + 5
      black_rect.outline_color = color
      black_rect.fill_color = color

      coroutine.yield()

      GLOBAL.drawing_target:draw(black_rect)
   end
end

return M
