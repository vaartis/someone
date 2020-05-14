-- Calculates the amount of characters to fit into the specified width
rect_max_text_width = (rect_width) ->
  math.floor(rect_width / (StaticFonts.font_size / 2.0))

deep_merge = (t1, t2) ->
  result = {}
  for k, v in pairs t1
    result[k] = v

  for k, _ in pairs t2
    if type(t1[k]) == "table" and type(t2[k]) == "table"
      result[k] = deep_merge(t1[k], t2[k])
    else
      result[k] = t2[k] or t1[k]

  result

{:deep_merge, :rect_max_text_width}
