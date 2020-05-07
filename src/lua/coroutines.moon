lume = require("lume")

coroutines = {}

create_coroutine = (fnc, finish_callback) ->
  cor = coroutine.create fnc

  table.insert coroutines, {
    cor: cor,
    finish_callback: finish_callback
  }

  cor

abandon_coroutine = (cor) ->
  _, n = lume.match(coroutines, (c) -> c.cor == cor)
  if n ~= nil
    if coroutine.status(coroutines[n].cor) ~= "dead"
      table.remove(coroutines, n)

run = (dt) ->
  to_remove = {}
  for n, cor in pairs coroutines
    _, err = coroutine.resume(cor.cor, dt)
    if err then error(err)

    if coroutine.status(cor.cor) == "dead"
      table.insert to_remove, n

      -- Call the callback
      if cor.finish_callback then cor.finish_callback()

  -- Clean up the dead coroutines
  lume.each to_remove, (n) -> table.remove(coroutines, n)

black_screen_out = ->
  screen_size = GLOBAL.drawing_target.size
  black_rect = RectangleShape.new(
    Vector2f.new(screen_size.x, screen_size.y)
  )
  color = Color.new(0, 0, 0, 0)

  while color.a < 255
    -- Need to be careful here, because color wraps around if it overflows
    color.a = color.a + 5
    black_rect.outline_color = color
    black_rect.fill_color = color

    coroutine.yield!

    GLOBAL.drawing_target\draw(black_rect)

{ :create_coroutine, :abandon_coroutine, :run, :black_screen_out }
