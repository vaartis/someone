local json = require("lunajson")
local lume = require("lume")
local path = require("path")

local terminal = require("terminal")
local assets = require("components.assets")
local shared_components = require("components.shared")
local collider_components = require("components.collider")
local interaction_components = require("components.interaction")
local passage_components = require("components.passage")
local util = require("util")
local coroutines = require("coroutines")

local M = {}

M.components = {
   tilemap = {
      class = Component.create("Tilemap", { "tiles", "map" })
   },
   tile_player = {
      class = Component.create(
         "TilePlayer",
         { "time_since_last_step", "footstep_sound", "walking" },
         { walking = false }
      )
   },
   interaction_tile = {
      class = Component.create(
         "InteractionTile",
         { "callback", "activatable_callback" }
      )
   }
}

function M.components.tilemap.process_component(new_ent, comp, entity_name)
   if not comp.tilemap then error("Tilemap path is not set in " .. entity_name) end

   local map_file = io.open(comp.tilemap, "r")
   local map = json.decode(map_file:read("*all"))
   map_file:close()

   -- Load the tileset image

   local sets, paths_to_names = {}, {}
   for _, tset_info in ipairs(map.tilesets) do
      local tset_path = path.join(path.dirname(comp.tilemap), tset_info.source)

      local set_file = io.open(tset_path, "r")
      local set = json.decode(set_file:read("*all"))
      set_file:close()
      sets[set.name] = set
      paths_to_names[tset_info.source] = set.name

      local image_path = path.join(path.dirname(tset_path), set.image)
      local image_name = path.splitext(set.image)

      -- Load the texture into known assets
      assets.add_to_known_assets("textures", image_name, image_path)
      set.image = image_name
      set.firstgid = tset_info.firstgid
   end

   local function gid_to_tile(tile)
      local from_tileset
      for _, set in lume.ripairs(map.tilesets) do
         if set.firstgid <= tile then
            tile = tile - set.firstgid

            local tile_val = tile
            tile = lume.match(sets[paths_to_names[set.source]].tiles, function(til) return til.id == tile end)
            if tile == nil then
               -- Tile has no special properties, so not in the tilemap
               tile = { id = tile_val }
            end
            tile.tileset = paths_to_names[set.source]

            break
         end
      end

      return tile
   end

   local function tile_to_frame(tile)
      local tset = sets[tile.tileset]

      -- Width/Height of the tileset in tile number
      local tset_w = tset.imagewidth / tset.tilewidth
      local tset_h = tset.imageheight / tset.tileheight
      -- Position in tileset
      local ts_x = math.floor(tile.id % tset_w)
      local ts_y = math.floor(tile.id / tset_w)

      return { x = ts_x * tset.tilewidth, y = ts_y * tset.tileheight, w = tset.tilewidth, h = tset.tileheight }
   end

   local FLIPPED_HORIZONTALLY_FLAG = 0x80000000
   local FLIPPED_VERTICALLY_FLAG = 0x40000000
   local FLIPPED_DIAGONALLY_FLAG = 0x20000000
   local ROTATED_HEXAGONAL_120_FLAG = 0x10000000
   for layer_n, layer in ipairs(map.layers) do
      if layer.type == "tilelayer" then
         if layer.compression == "zlib" then
            layer.data = decode_base64_and_decompress_zlib(layer.data, layer.width * layer.height)
         end

         for n, tile in ipairs(layer.data) do
            -- 0 = no tile
            if tile == 0 then
               goto next
            end

            local flipped_horizontally = (tile & FLIPPED_HORIZONTALLY_FLAG) ~= 0
            local flipped_vertically = (tile & FLIPPED_VERTICALLY_FLAG) ~= 0
            local flipped_diagonally = (tile & FLIPPED_DIAGONALLY_FLAG) ~= 0
            local rotated_hex120 = (tile & ROTATED_HEXAGONAL_120_FLAG) ~= 0
            tile = tile & ~(FLIPPED_HORIZONTALLY_FLAG |
                            FLIPPED_VERTICALLY_FLAG |
                            FLIPPED_DIAGONALLY_FLAG |
                            ROTATED_HEXAGONAL_120_FLAG)

            tile = gid_to_tile(tile)

            local tset = sets[tile.tileset]

            local x = (n - 1) % layer.width
            local y = math.floor((n - 1) / layer.width)
            local w, h = tset.tilewidth, tset.tileheight

            local frame = tile_to_frame(tile)

            local scale = { 1, 1 }
            if flipped_diagonally then
               scale[1], scale[2] = scale[2], scale[1]
            end
            if flipped_horizontally then scale[1] = -scale[1] end
            if flipped_vertically then scale[2] = -scale[2] end

            local tile_transformable = { position = { (w * x) + (w / 2), (h * y) + (h / 2) },
                                         origin = {math.floor(w / 2), math.floor(h / 2)},
                                         scale = scale }
            local template = {
               drawable = { kind = "sprite", texture_asset = sets[tile.tileset].image, texture_rect = frame, z = layer_n },
               transformable = tile_transformable
            }
            -- Add a collider for walls
            if tile.type == "Wall" then
               template.collider = { mode = "constant", size = { tset.tilewidth, tset.tileheight } }
            elseif tile.type == "Player" then
               template.tile_player = { footstep_sound_asset = "footstep" }
               template.collider = { mode = "sprite" }
            end
            util.entities_mod().instantiate_entity(lume.format("tile_{1}_{2}_{3}", {layer_n, x, y}), template)

            ::next::
         end
      elseif layer.type == "objectgroup" then
         for n, obj in ipairs(layer.objects) do
            local props = {}
            for _, prop in ipairs(obj.properties) do
               props[prop.name] = prop.value
            end
            obj.properties = props

            local template = {
               transformable = {
                  position = { obj.x, obj.y }
               }
            }
            if obj.properties.interaction then
               template.interaction_tile = comp.interactions[obj.properties.interaction]
               template.collider = { mode = "constant", size = { obj.width, obj.height }, trigger = obj.properties.trigger }
            end
            if obj.gid then
               local tile = gid_to_tile(obj.gid)
               local frame = tile_to_frame(tile)
               template.drawable = { kind = "sprite", texture_asset = sets[tile.tileset].image, texture_rect = frame, z = layer_n }
               -- Adjust position, but why does this happen?
               template.transformable.position[2] = template.transformable.position[2] - obj.height
            end

            util.entities_mod().instantiate_entity(lume.format("object_{1}_{2}_{3}", {layer_n, obj.x, obj.y}), template)
         end
      end
   end
end

function M.components.tile_player.process_component(new_ent, comp, entity_name)
   local sound = assets.create_sound_from_asset(comp.footstep_sound_asset)

   new_ent:add(M.components.tile_player.class(0, sound))
end

function M.components.interaction_tile.process_component(new_ent, comp, entity_name)
   local callback = interaction_components.process_interaction(
      comp,
      "callback",
      { entity_name = entity_name, comp_name = "interaction_tile", needed_for = "interaction", entity = new_ent }
   )
   local activatable_callback
   if comp.activatable_callback then
      activatable_callback = interaction_components.process_activatable(
         comp,
         "activatable_callback",
         { entity_name = entity_name, comp_name = "interaction_tile", needed_for = "interaction", entity = new_ent }
      )
   end

   new_ent:add(M.components.interaction_tile.class(callback, activatable_callback))
end


local TilePlayerSystem = class("TilePlayerSystem", System)
TilePlayerSystem.requires = function(self)
   return { "TilePlayer" }
end
TilePlayerSystem.update = function(self, dt)
   local movement_speed = 0.1

   for _, entity in pairs(self.targets) do
      interaction_components.update_seconds_since_last_interaction(dt)

      local tf = entity:get("Transformable")
      local player = entity:get("TilePlayer")

      player.time_since_last_step = player.time_since_last_step + dt

      local physics_world = collider_components.physics_world

      local x, y, w, h = physics_world:getRect(entity)
      if not player.target_pos then
         local pos_diff = { x = 0, y = 0 }
         if Keyboard.is_key_pressed(KeyboardKey.D) then pos_diff.x = 1 end
         if Keyboard.is_key_pressed(KeyboardKey.A) then pos_diff.x = -1 end
         if Keyboard.is_key_pressed(KeyboardKey.W) then pos_diff.y = -1 end
         if Keyboard.is_key_pressed(KeyboardKey.S) then pos_diff.y = 1 end

         if pos_diff.x ~= 0 or pos_diff.y ~= 0 then
            local target_pos = { x = x + (pos_diff.x * w), y = y + (pos_diff.y * h) }

            local function start_movement()
               player.target_pos = target_pos
               player.movement_progress = 0

               player.footstep_sound:play()
            end

            local cols, len = physics_world:queryPoint(target_pos.x + 1, target_pos.y + 1)
            if len == 0 then
               start_movement()
            else
               local interaction_tile = lume.match(cols, function (ent) return ent:has("InteractionTile") end)
               if interaction_tile and interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction then
                  local function run_callback()
                     local interaction_tile_data = interaction_tile:get("InteractionTile")
                     if interaction_tile_data.activatable_callback == nil or interaction_tile_data.activatable_callback() then
                        interaction_components.seconds_since_last_interaction = 0
                        interaction_tile_data.callback()
                     end
                  end
                  if interaction_tile:get("Collider").trigger then
                     start_movement()
                     -- Wait until finished moving
                     player.movement_finished_callback = run_callback
                  else
                     -- Run now
                     run_callback()
                  end
               end
            end
         end
      else
         local target_pos = player.target_pos

         local expected_new_pos = { x = lume.lerp(x, target_pos.x, player.movement_progress),
                                    y = lume.lerp(y, target_pos.y, player.movement_progress) }
         physics_world:update(entity, expected_new_pos.x, expected_new_pos.y)

         player.movement_progress = player.movement_progress + 0.05
         if player.movement_progress > 1 then
            player.target_pos = nil
            if player.movement_finished_callback then
               player.movement_finished_callback()
               player.movement_finished_callback = nil
            end
         end
      end
   end
end

M.systems = {
   TilePlayerSystem
}

M.interaction_callbacks = {}
M.interaction_callbacks.player_light_position = function()
   local ents = util.rooms_mod().engine:getEntitiesWithComponent("TilePlayer")
   for _, player in pairs(ents) do
      local position = player:get("Transformable").transformable.position
      local _, _, w, h = collider_components.physics_world:getRect(player)

      return { position.x + w / 2, position.y + h / 2 }
   end

   return { 0, 0 }
end

M.interaction_callbacks.tilemap_talk = function(_state, args)
   if args.state_variable then
      interaction_components.interaction_callbacks.state_variable_set(_state, args.state_variable, true)
   end

   local phrases = args.phrases

   local engine = util.rooms_mod().engine

   engine:stopSystem("TilePlayerSystem")

   coroutines.create_coroutine(function ()
         local text_drawable = util.first(engine:getEntitiesWithComponent("TileTalkTextTag")):get("Drawable")

         local talking_speed = 0.02

         text_drawable.enabled = true

         for _, phrase_data in ipairs(phrases) do
            local letter = 1
            local timer = 0

            if phrase_data.sound then
               local sound = assets.create_sound_from_asset(phrase_data.sound.asset)
               if phrase_data.sound.volume then
                  sound.volume = phrase_data.sound.volume
               end
               sound:play()
            end

            text_drawable.drawable.fill_color = Color.new(phrase_data.color[1], phrase_data.color[2], phrase_data.color[3], 255)
            text_drawable.drawable.string = ""

            local phrase = phrase_data.text
            while text_drawable.drawable.string ~= phrase do
               if timer > talking_speed then
                  text_drawable.drawable.string = phrase:sub(1, letter)
                  letter = letter + 1
                  timer = 0
               end

               timer = timer + coroutine.yield()
            end

            text_drawable.drawable.string = text_drawable.drawable.string ..
               "\n\n[E] to continue"

            local exited = false
            while not exited do
               interaction_components.update_seconds_since_last_interaction(coroutine.yield())

               interaction_components.if_key_pressed({
                     [KeyboardKey.E] = function()
                        exited = true
                     end
              }, true)
            end
         end

         text_drawable.enabled = false
         engine:startSystem("TilePlayerSystem")
   end)
end

function M.interaction_callbacks.switch_room(_current_state, room)
   local rooms = util.rooms_mod()
   local engine = rooms.engine
   engine:stopSystem("TilePlayerSystem")

   local final_room_name = passage_components.get_final_room_name({ to = room })

   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         -- When the screen in blacked out, change the room

         rooms.load_room(final_room_name)
      end,
      function()
         -- Enable the player back when the room has changed
         engine:startSystem("TilePlayerSystem")
      end
   )
end

function M.interaction_callbacks.switch_to_terminal(curr_state)
   local engine = util.rooms_mod().engine
   engine:stopSystem("TilePlayerSystem")

   coroutines.create_coroutine(
      coroutines.black_screen_out,
      function()
         -- Just resume it since the player doesn't have control now
         engine:startSystem("TilePlayerSystem")

         GLOBAL.set_current_state(CurrentState.Terminal)
      end,
      function()
         terminal.active = true
      end
   )
end

return M
