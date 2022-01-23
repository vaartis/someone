local inspect = require("inspect")
local lume = require("lume")
local coroutines = require("coroutines")
local util = require("util")

local instance_menu = require("terminal.instance_menu")
local lines = require("terminal.lines")

local first_line_on_screen

-- Data for environment images
local current_environment_name, current_environment_texture, current_environment_sprite

local M = {}

local info_message_coro
function show_info_message(message, params)
   if info_message_coro then
      coroutines.abandon_coroutine(info_message_coro)
      info_message_coro = nil
   end

   local font_size = StaticFonts.font_size
   local font_color = Color.new(0, 0, 0, 0)
   if params then
      if params.font_size then font_size = params.font_size end
      if params.font_color then font_color = params.font_color end
   end

   info_message_coro =
      coroutines.create_coroutine(
         function()
            local current_color = font_color
            local text = Text.new(message, StaticFonts.main_font, font_size)

            local win_size = GLOBAL.drawing_target.size
            local text_size = text.global_bounds
            local text_pos = Vector2f.new(win_size.x - 10 - text_size.width, win_size.y - 20 - text_size.height)
            text.position = text_pos

            -- Show the text
            while current_color.a < 255 do
               current_color.a = current_color.a + 5
               text.fill_color = current_color

               GLOBAL.drawing_target:draw(text)
               coroutine.yield()
            end

            local dt = 0
            -- Wait five seconds
            local timer = 0
            while timer < 5 do
               timer = timer + dt
               GLOBAL.drawing_target:draw(text)

               -- Update the delta time
               dt = coroutine.yield()
            end

            -- Hide the text
            while current_color.a > 0 do
               current_color.a = current_color.a - 5
               text.fill_color = current_color

               GLOBAL.drawing_target:draw(text)
               coroutine.yield()
            end
         end
   )
end

local function save_game(first_line, last_line)
   local lines_to_save = {}
   local current_line = first_line

   while true do
      table.insert(lines_to_save, current_line)
      if current_line._name == last_line._name then break end
      current_line = current_line:next()
   end

   -- Extract the data to save from the lines
   local saved_data = {
      lines = { first_line = first_line._name, last_line = last_line._name },
      variables = M.state_variables,
      environment = { name = current_environment_name },
   }
   for _, line in pairs(lines_to_save) do
      local line_saved_fields = {}
      for _, field_name in ipairs(line:fields_to_save()) do
         line_saved_fields[field_name] = line[field_name]
      end

      saved_data["lines"][line._name] = line_saved_fields
   end

   -- Encode and save the data
   local toml_encoded = TOML.encode(saved_data)
   local file, err = io.open("save.toml", "w")
   if err then
      show_info_message("Error while saving: \"" .. err .. "\"")

      return
   end

   file:write(toml_encoded)
   file:close()

   show_info_message("Game saved")
end

local function load_game()
   local file, err = io.open("save.toml", "r")
   if err then
      show_info_message("Error loading save data: \"" .. err .. "\"")
   end
   file:close()

   if file then
      local data, err = TOML.parse("save.toml")
      if err then
         show_info_message("Error decoding save data: \"" .. err .. "\"")

         return
      end

      local first_line_name = data["lines"]["first_line"]
      local last_line_name = data["lines"]["last_line"]

      local first_line = lines.make_line(first_line_name, lines.native_lines)
      local current_line = first_line
      while true do
         -- Copy the values, preserving the metatable
         for k, v in pairs(data["lines"][current_line._name]) do
            current_line[k] = v
         end

         if current_line._name == last_line_name then break end

         current_line = current_line:next()
      end

      -- Just in case, reset like after text input
      lines.reset_after_text_input()

      first_line_on_screen = first_line

      M.state_variables = util.deep_merge(M.state_variables, data["variables"])

      if data.environment then
         M.set_environment_image(data.environment.name)
      end

      show_info_message("Game loaded")
   end
end

local time_before_output = 0.5

-- Called from C++ to set native lines
function M.set_native_lines(in_lines)
   -- This replaces the native lines with data from C++, which also updates
   -- when updated from C++
   lines.native_lines = in_lines
end

-- Called from C++ to set up the first line on screen
function M.set_first_line_on_screen(name)
   -- Reset like after text input
   lines.reset_after_text_input()

   if type(name) == "string" and lines.native_lines[name] then
      first_line_on_screen = lines.make_line(name, lines.native_lines)
   elseif type(name) == "table" then
      first_line_on_screen = name
   else
      print("Line " .. name .. " not found")
   end
end

M.current_lines_to_draw = {}

local scroll_height_offset_subtract = 0

local width_offset, height_offset, rect_height, rect_width, rect, terminal_view

local terminal_initialized = false
function initialize_terminal()
   -- As the very first thing, draw the terminal background
   local win_size = GLOBAL.drawing_target.size

   width_offset, height_offset = win_size.x / 100, win_size.y / 100 * 2
   rect_height, rect_width = win_size.y / 100 * (80 - 10), win_size.x - (width_offset * 2)

   terminal_view = View.new()
   terminal_view:reset(FloatRect.new(width_offset, height_offset, rect_width, rect_height))
   terminal_view.viewport = FloatRect.new(
      width_offset / win_size.x, height_offset / win_size.y,
      rect_width / win_size.x, rect_height / win_size.y
   )

   -- Construct and draw the background rectangle
   rect = RectangleShape.new(Vector2f.new(rect_width, rect_height))
   rect.outline_thickness = 2.0
   rect.outline_color = Color.Black
   rect.fill_color = Color.Black
   rect.position = Vector2f.new(width_offset, height_offset)
end

function M.draw(dt)
   if not terminal_initialized then
      terminal_initialized = true

      initialize_terminal()
   end

   GLOBAL.drawing_target:draw(rect)

   -- If processing is active, reset and update current lines
   if M.active then
      -- Start processing which lines to draw

      M.current_lines_to_draw = {}

      local line = first_line_on_screen

      -- If some line changes the active status, stop processing the lines after it
      while true and M.active do
         local should_wait = line:should_wait()
         if should_wait then
            if line._time_since_started_output < time_before_output then
               line:tick_before_output_timer(dt)

               break
            end

            line:tick_letter_timer(dt)
            line:maybe_increment_letter_count()
         end

         -- If there's a script and it wasn't executed yet, do it
         if line._script and not line._script_executed then
            line._script()

            line._script_executed = true
         end

         -- Insert the line into the drawing queue now
         table.insert(M.current_lines_to_draw, line)

         if should_wait then
            break
         end

         -- Execute the script_after after the first time the line was finished
         if line._script_after and not line._script_after_executed then
            line._script_after()

            line._script_after_executed = true
         end

         if line:next() == nil then
            break
         end

         line = line:next()
      end
   end

   -- Draw the help text if it's active
   if lines.help_text_active then
      if not lines.help_text then lines.set_help_text(true, "") end

      local text_pos = Vector2f.new(width_offset, height_offset + rect_height + 30)
      lines.help_text.position = text_pos

      GLOBAL.drawing_target:draw(lines.help_text)
   end

   -- Offset for the first line to start at
   local first_line_height_offset = (height_offset * 2) - scroll_height_offset_subtract

   -- Actual offsets that will be used for line positioning
   local line_width_offset, line_height_offset = width_offset * 2, first_line_height_offset

   -- The total height of the text to compare it with the terminal rectangle
   local total_text_height = 0

   GLOBAL.drawing_target.view = terminal_view

   local first_height

   -- Use the current lines and draw those
   for _, line in pairs(M.current_lines_to_draw) do
      local text = line:current_text()
      if type(text) == "table" then
         -- It's more than one line

         for n, txt in pairs(text) do
            txt.position = Vector2f.new(line_width_offset, line_height_offset)

            local this_txt_height = line:max_line_height(n);

            total_text_height = total_text_height + this_txt_height + (StaticFonts.font_size / 2)
            line_height_offset = first_line_height_offset + total_text_height;

            GLOBAL.drawing_target:draw(txt)
         end
         -- Add a bit more after the last line
         total_text_height = total_text_height + StaticFonts.font_size / 2
         line_height_offset = first_line_height_offset + total_text_height
      elseif text == nil then
         -- Line doesn't output anything, just do nothing
      else
         -- It's a single line of text

         text.position = Vector2f.new(line_width_offset, line_height_offset)

         local line_height = line:max_line_height()
         total_text_height = total_text_height + line_height + (StaticFonts.font_size / 2)
         line_height_offset = first_line_height_offset + total_text_height

         GLOBAL.drawing_target:draw(text)
      end

      -- Save the height of the first line to use it if there's a need to scroll,
      -- so that the scrolling distance can be adjusted by this size after the line is deleted
      if line == first_line_on_screen then
         first_height = total_text_height
      end
   end

   GLOBAL.drawing_target.view = GLOBAL.drawing_target.default_view

   --[[
      Scroll the screen smoothly, until all the lines are on screen.
      If some are not, move the text up until the second line is on the place
      where the first was, and after that remove the first line and adjust the
      offset. This repeats every frame until all the lines are visible.
   ]]
   local scroll_step = 5
   if total_text_height > rect_height - (height_offset * 2) then
      local function top(line)
         local text = line:current_text()

         if type(text) == "table" then
            -- Return the first one's top
            return text[1].global_bounds.top
         elseif text == nil then
            -- Try getting the size of the next line instead
            return top(line:next())
         else
            -- It's a single line of text
            return text.global_bounds.top
         end
      end

      local second = first_line_on_screen:next()
      local second_pos = top(second)

      if second_pos + scroll_step > height_offset * 2 then
         scroll_height_offset_subtract = scroll_height_offset_subtract + scroll_step
      else
         first_line_on_screen = second

         scroll_height_offset_subtract = scroll_height_offset_subtract - first_height
      end
   end

   -- Draw the environment image if there is one
   if current_environment_sprite then
      local sprite_height_offset = (height_offset * 2) + rect_height
      local sprite_width_offset = width_offset + rect_width - current_environment_texture.size.x

      current_environment_sprite.position = Vector2f.new(sprite_width_offset, sprite_height_offset)
      GLOBAL.drawing_target:draw(current_environment_sprite)
   end
end

local time_since_last_interaction = 0
local time_between_interactions = 0.2

-- A function to track time between events
function M.update_event_timer(dt)
   time_since_last_interaction = time_since_last_interaction + dt
end

local main_instance_saved_first

function M.process_event(event, dt)
   local line = first_line_on_screen
   while true do
      local should_wait = line:should_wait()

      -- If line has an is_interactive function, use it
      if line.is_interactive then
         if line:should_wait() and line:is_interactive() and (lines.inputting_text or time_since_last_interaction > time_between_interactions) then
            if line:handle_interaction(event) then
               time_since_last_interaction = 0

               -- Stop anything else if an interaction has happened
               break
            end
         end
      end

      if should_wait then
         if time_since_last_interaction > time_between_interactions then
            if Keyboard.is_key_pressed(KeyboardKey.LControl) then
               -- Save the game
               if Keyboard.is_key_pressed(KeyboardKey.S) then
                  time_since_last_interaction = 0
                  -- Pass the first and the last line
                  save_game(first_line_on_screen, line)
               elseif Keyboard.is_key_pressed(KeyboardKey.L) then
                  time_since_last_interaction = 0
                  -- Pass the first and the last line
                  load_game()
               elseif Keyboard.is_key_pressed(KeyboardKey.Z) then
                  time_since_last_interaction = 0

                  if not main_instance_saved_first then
                     main_instance_saved_first = first_line_on_screen
                     M.set_first_line_on_screen("instances/menu/1")
                  else
                     -- Reset the text input in case it was used in the instance menu
                     lines.reset_after_text_input()

                     first_line_on_screen = main_instance_saved_first
                     main_instance_saved_first = nil
                  end
               end
            end
         end

         break
      end

      line = line:next()
      if line == nil then break end
   end
end

function M.set_environment_image(name)
   do return end

   -- Create the sprite if it doesn't exist yet
   if not current_environment_sprite then
      current_environment_sprite = Sprite.new()
   end

   local full_name = lume.format("resources/sprites/environments/{1}.png", {name})
   current_environment_texture = Texture.new()
   current_environment_texture:load_from_file(full_name)

   current_environment_sprite.texture = current_environment_texture

   current_environment_name = name
end

function M.switch_to_walking(room)
   -- Needs to be done as soon as possible to stop processing lines
   M.active = false

   local player_movement
   if not _G.mod then
      player_movement = util.rooms_mod().find_player()
      if player_movement then
         player_movement:get("PlayerMovement")
         player_movement.active = false
      end
   end

   -- Create a coroutine that blackens the screen with time
   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         WalkingModule.load_room(room, true)
         GLOBAL.set_current_state(CurrentState.Walking)
      end,
      function()
         if player_movement then player_movement.active = true end
      end
   )
end

-- Should the next line be shown
M.active = true

-- State variables for the story to set/get
M.state_variables = {
   input_variables = {
      p = "<p>"
   },
   day1 = {
      narra_house_hub = {
         living_room = false,
         kitchen = false,
         bathroom = false
      }
   },
   day2 = {
      road_questions = {
         computers = false,
         food = false,
         age = false,
         city = false,
         city_food = false,
         stay = false
      },
      flat = {
         laptop = false,
         kitchen = false,
         bathroom = false
      },
      club = {
         bar = false,
         dance_floor = false
      }
   },
   day3 = {
      village_hub = {
         walk_around = false,
         back_to_narras = false
      },
      forest_search = {
         time = 0,
         other_parts = {
            meadow = false,
            spring = false,
            caves = false
         },
         found_on = nil
      },
   },
   day4 = {
      currently_talking_with_maj = false,
      morning_talk_with_kiki = false,
      evening_note_talk = {
         outside = false,
         digitizing = false,
         memories = false,
         upper = false
      }
   },
   -- Instances that were decrypted
   decrypted_instances = {},
   -- Explored instances
   explored_instances = {
      hunger = false,
      forest = false,
   },
   talks = {
      narra = {
         found_lamp = false,
         -- Instances the player talked about
         instances = {
            hunger = false,
            forest = false
         },
         -- Day 4
         found_food = false,
         way_up_checked = false
      },
      maj = {
         tea = false,
         laptops = false,
         instances = false,
         visited_before = false
      },
      kiki = {
         instances = false
      }
   },
   talking_topics = {},
   walking = {
      first_puzzle = {
         first = "wrong",
         second = "wrong",
         third = "wrong",
         solved = false
      },
      first_puzzle_lamp = {
         taken = false,
         put = false,
      },
      dial_puzzle = {
         solved = false,
         music_played = false,
         combination = {}
      },
      food_room = {
         peach_can_taken = false
      },
      status_room = {
         way_up_checked = false
      },
      -- Day 4 cave from the terminal segment
      cave = {
         water = false,
         mountain = false,
         tight_corridors = false,
         bricks = false,
         dents = false
      }
   }
}

function M.talking_topic_known(topic)
   return lume.find(M.state_variables.talking_topics, topic) ~= nil
end

function M.add_talking_topic(topic)
   if not lume.find(M.state_variables.talking_topics, topic) then
      table.insert(M.state_variables.talking_topics, topic)
   end
end

local debug_menu_data = {
   select_line_text = "",
   add_topic_text = ""
}
function M.debug_menu()
   local submitted

   debug_menu_data.select_line_text, submitted = ImGui.InputText("Line selection", debug_menu_data.select_line_text)
   ImGui.SameLine()
   if ImGui.Button("Switch") or submitted then
      M.set_first_line_on_screen(debug_menu_data.select_line_text)
      debug_menu_data.select_line_text = ""
   end

   debug_menu_data.add_topic_text, submitted = ImGui.InputText("Add talking topic", debug_menu_data.add_topic_text)
   ImGui.SameLine()
   if ImGui.Button("Add") or submitted then
      M.add_talking_topic(debug_menu_data.add_topic_text)
      debug_menu_data.add_topic_text = ""
   end

   util.debug_menu_process_state_variable_node("State variables", M.state_variables)

   ImGui.Separator()
   if ImGui.Button("Switch to walking") then
      M.switch_to_walking("day1/computer_room")
   end
end

return M
