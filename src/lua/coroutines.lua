local lume = require("lume")

local coroutines = {}

local M = {}

function M.create_coroutine(fnc, ...)
   local cor = coroutine.create(fnc)

   table.insert(
      coroutines,
      {
         cor = cor,
         started = false, args = {...},
         wait = {}
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

--- If there are something for the coroutine to wait on,
--- return true. Otherwise return false.
local function need_to_wait(cor)
   if cor.wait.coroutine then
      if coroutine.status(cor.wait.coroutine) == "dead" then
         cor.wait.coroutine = nil

         return false
      else
         return true
      end
   end

   return false
end

function M.run(dt)
   local to_remove = { }
   for n, cor in pairs(coroutines) do
      if need_to_wait(cor) then goto continue end

      local results
      if not cor.started then
         results = { coroutine.resume(cor.cor, table.unpack(cor.args)) }

         cor.started = true
      else
         results = { coroutine.resume(cor.cor, dt) }
      end

      local was_ok, results = results[1], lume.slice(results, 2)

      -- If there was an error, the only result will be the error message
      if not was_ok then
         local err = "Coroutine exited with \"" .. results[1] .. "\"\n  " .. debug.traceback(cor.cor) .. "\n\n"
         error(err)
      end

      -- If a function was returned, create a coroutine from it and add it as a
      -- waiting condition, and pass it all the other arguments returned
      if type(results[1]) == "function" then
         cor.wait.coroutine = M.create_coroutine(results[1], table.unpack(lume.slice(results, 2)))
      end

      if coroutine.status(cor.cor) == "dead" then
         table.insert(to_remove, n)
      end

      ::continue::
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
