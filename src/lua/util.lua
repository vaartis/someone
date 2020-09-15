-- Calculates the amount of characters to fit into the specified width

local M = {}

function M.rect_max_text_width(rect_width)
   return math.floor(rect_width / (StaticFonts.font_size / 2.0))
end

function M.deep_merge(t1, t2)
   local result = {}

   for k, v in pairs(t1) do
      result[k] = v
   end

   for k, _ in pairs(t2) do
      if type(t1[k]) == "table" and type(t2[k]) == "table" then
         result[k] = M.deep_merge(t1[k], t2[k])
      else
         result[k] = t2[k] or t1[k]
      end
   end

   return result
end

local rooms, entities


function M.rooms_mod()
   if not rooms then
      rooms = require("components.rooms")
   end

   return rooms
end

function M.entities_mod()
   if not entities then
      entities = require("components.entities")
   end

   return entities
end

function M.debug_menu_process_state_variable_node(name, data, parent)
   if type(data) == "table" then
      if ImGui.TreeNode(name) then
         for k, v in pairs(data) do M.debug_menu_process_state_variable_node(tostring(k), v, data) end
         ImGui.TreePop()
      end
   elseif type(data) == "boolean" then
      parent[name] = ImGui.Checkbox(name, data)
   else
      ImGui.Text(name .. " = " .. tostring(data))
   end
end

-- Get the first element from the table/array
function M.first(tbl)
   for _, v in pairs(tbl) do
      return v
   end
end

return M
