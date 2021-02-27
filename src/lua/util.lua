local lume = require("lume")

local M = {}

-- Calculates the amount of characters to into the specified width
function M.rect_max_text_width(rect_width)
   return math.floor(rect_width / (StaticFonts.font_size / 2.0))
end

function M.deep_equal(t1, t2)
   if type(t1) == "table" and type(t2) == "table" then
      if lume.count(t1) == lume.count(t2) then
         for k, v in pairs(t1) do
            if type(v) == "table" then
               if not M.deep_equal(v, t2[k]) then return false end
            else
               if v ~= t2[k] then return false end
            end
         end
      else return false end
   else
      if t1 ~= t2 then return false end
   end

   return true
end

function M.deep_merge(t1, t2)
   local result = {}

   for k, v in pairs(t1) do
      if type(v) == "table" then
         result[k] = M.deep_merge({}, v)
      else
         result[k] = v
      end
   end

   for k, _ in pairs(t2) do
      if type(t1[k]) == "table" and type(t2[k]) == "table" then
         result[k] = M.deep_merge(t1[k], t2[k])
      elseif type(t1[k]) ~= "table" and type(t2[k]) == "table" then
         result[k] = M.deep_merge({}, t2[k])
      else
         if t2[k] ~= nil then
            result[k] = t2[k]
         end
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

-- Get the value on the path or return a default
function M.get_or_default(tbl, path, default)
   local curr = tbl
   for _, elem in ipairs(path) do
      if curr[elem] then
         curr = curr[elem]
      else
         return default
      end
   end

   return curr
end

return M
