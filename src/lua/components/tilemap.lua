local lume = require("lume")

local assets = require("components.assets")
local shared_components = require("components.shared")
local collider_components = require("components.collider")
local interaction_components = require("components.interaction")
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
         { "callback" }
      )
   }
}

function M.components.tilemap.process_component(new_ent, comp, entity_name)
   local tile_mapping = comp.map

   local sheet_json = shared_components.load_sheet_json(comp.sheet)
   local tile_frames = sheet_json["frames"]

   -- Trim leading/ending newlines
   local tile_string = lume.trim(comp.tiles)

   local lines = lume.split(tile_string, "\n")
   for y, line in ipairs(lines) do
      for x = 1, #line do
         local tile_symbol = line:sub(x, x)

         local tile_info = tile_mapping[tile_symbol]
         if not tile_info then
            error("Unknown tile " .. tile_symbol)
         end

         -- First process the base
         local frame = tile_frames[tile_info.sprites[1]].frame
         local tile_transformable = { position = { frame.w * (x - 1), frame.h * (y - 1) } }
         local template = {
            drawable = { kind = "sprite", texture_asset = comp.texture, texture_rect = frame, z = 1 },
            transformable = tile_transformable
         }
         -- Add a collider for walls
         if tile_info.type == "wall" then
            template.collider = { mode = "constant", size = { frame.w, frame.h } }
         elseif tile_info.type == "interaction" then
            template.collider = { mode = "constant", size = { frame.w, frame.h } }
            template.interaction_tile = { callback = tile_info.callback }
         end
         util.entities_mod().instantiate_entity(lume.format("tile_{1}_{2}", {x, y}), template)

         -- If there are more than 1 sprite, draw those on top
         if #tile_info.sprites > 1 then
            for additional_i = 2, #tile_info.sprites do
               local additional_sprite = tile_info.sprites[additional_i]
               local frame = tile_frames[additional_sprite].frame

               local template = {
                  drawable = { kind = "sprite", texture_asset = comp.texture, texture_rect = frame, z = additional_i },
                  transformable = tile_transformable
               }
               util.entities_mod().instantiate_entity(lume.format("tile_{1}_{2}_layer{3}", {x, y, additional_i}), template)
            end
         end

         -- Additionally, if the sprite is of type player, spawn the player there
         if tile_info.type == "player" then
            local frame = tile_frames[tile_info.player_sprite].frame
            local template = {
               drawable = { kind = "sprite", texture_asset = comp.texture, texture_rect = frame, z = 10 },
               transformable = tile_transformable,
               -- Hardcoded..
               tile_player = { footstep_sound_asset = "footstep" }
            }
            template.collider = { mode = "sprite" }

            util.entities_mod().instantiate_entity(lume.format("player", {x, y}), template)
          end
      end
   end

   -- new_ent:add(M.components.rotation.class(comp.rotation_speed))
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

   new_ent:add(M.components.interaction_tile.class(callback))
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

            local cols, len = physics_world:queryPoint(target_pos.x + 1, target_pos.y + 1)
            if len == 0 then
               player.target_pos = target_pos
               player.movement_progress = 0

               player.footstep_sound:play()
            else
               local interaction_tile = lume.match(
                  cols,
                  function (ent) return ent:has("InteractionTile") end
               )
               if interaction_tile and interaction_components.seconds_since_last_interaction > interaction_components.seconds_before_next_interaction then
                  interaction_components.seconds_since_last_interaction = 0
                  interaction_tile:get("InteractionTile").callback()
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

return M
