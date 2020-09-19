local lume = require("lume")

local coroutines = {}

local M = {}

function M.create_coroutine(fnc, ...)
   local cor = coroutine.create(fnc)

   table.insert(
      coroutines,
      {
         cor = cor, finish_callback = finish_callback,
         started = false, args = {...}
      }
   )

   return cor
end


function M.abandon_coroutine(cor)
   local _, n = lume.match(coroutines, function(c) return c.cor == cor end)

   if n ~= nil and coroutine.status(coroutines[n].cor) ~= "dead" then
      table.remove(coroutines, n)
   end
end

function M.run(dt)
   local to_remove = { }
   for n, cor in pairs(coroutines) do
      local _, err
      if not cor.started then
         _, err = coroutine.resume(cor.cor, table.unpack(cor.args))

         cor.started = true
      else
         _, err = coroutine.resume(cor.cor, dt)
      end

      if err then error(err) end

      if coroutine.status(cor.cor) == "dead" then
         table.insert(to_remove, n)

         -- Call the callback
         if cor.finish_callback then cor.finish_callback() end
      end
   end

   -- Clean up the dead coroutines
   lume.each(to_remove, function(n) table.remove(coroutines, n) end)
end

function M.black_screen_out(do_in, do_after)
   local screen_size = GLOBAL.drawing_target.size
   local black_rect = RectangleShape.new(
      Vector2f.new(screen_size.x, screen_size.y)
   )
   local color = Color.new(0, 0, 0, 0)

   while color.a < 255 do
      -- Need to be careful here, because color wraps around if it overflows
      color.a = color.a + 5
      black_rect.fill_color = color

      GLOBAL.drawing_target:draw(black_rect)

      if color.a == 255 and do_in then
         -- On the last iteration, do whatever requested in the end
         do_in()
      end

      coroutine.yield()
   end

   while color.a > 0 do
      color.a = color.a - 5
      black_rect.fill_color = color
      GLOBAL.drawing_target:draw(black_rect)

      coroutine.yield()
   end

   -- Do the thing requested after the drawing is done
   if do_after then do_after() end
end

return M
