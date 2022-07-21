local util = require("util")
local path = require("path")
local lume = require("lume")

local collider_components = require("components.collider")
local assets = require("components.assets")
local interaction_components = require("components.interaction")
local coroutines = require("coroutines")

local pb = require("pb")
local protoc = require("protoc")

local pc = protoc.new()
pc:loadfile(path.join(assets.resources_root(), "protobuf/game.proto"))

M = {}

M.components = {
   hacking_match_server = {
      class = Component.create("HackingMatchServer", {"socket", "clients", "poll_group", "game_state"})
   },

   hacking_match_client = {
      class = Component.create("HackingMatchClient", {"socket"})
   },

   hacking_match_player = {
      class = Component.create("HackingMatchPlayer", {"position", "time_since_movement", "time_since_action"})
   },

   hacking_match_other_player = {
      class = Component.create("HackingMatchOtherPlayer", {"id", "position", "base_position"})
   },

   hacking_match_block_manager = {
      class = Component.create("HackingMatchBlockManager", {"seed", "player", "offset", "break_pause"})
   },

   hacking_match_block = {
      class = Component.create("HackingMatchBlock", {"color", "currently_swapping"})
   }
}


local HackingMatchServerSystem = class("HackingMatchServerSystem", System)
local HackingMatchBlockManagerSystem = class("HackingMatchBlockManagerSystem", System)
local HackingMatchClientSystem = class("HackingMatchClientSystem", System)
local HackingMatchPlayerSystem = class("HackingMatchPlayerSystem", System)

NETWORKING.init()

local sockets = NETWORKING.sockets()

local server_identity
if NETWORKING.IS_STEAM then
   server_identity = sockets:identity()
else
   server_identity = SteamNetworkingIPAddr.new()
   server_identity:parse_string("127.0.0.1:12345")
end

local function send_to_all(clients, msg, except)
   for handle, client in pairs(clients) do
      if client.id ~= except then
         sockets:send_message_to_connection(
            handle,
            msg,
            SteamNetworkingSend.Reliable
         )
      end
   end
end

function M.components.hacking_match_server.process_component(new_ent, comp, entity_name)
   local server_clients = {}
   local poll_group = sockets:create_poll_group()

   local latest_id = 0
   local server_socket = sockets:create_listen_socket_p2p(
      comp.server_identity,
      {},
      function(info)
         local state = info.info.state

         if state == ESteamNetworkingConnectionState.Connecting then
            print("[SERVER] Connection from " .. info.info.connection_description)

            if sockets:accept_connection(info.handle) ~= EResult.Ok then
               print("[SERVER] Could not accept connection")
               sockets:close_connection(info.handle, 0, "Could not accept", false);
            end

            server_clients[info.handle] = { id = latest_id }
            latest_id = latest_id + 1

            sockets:set_connection_poll_group(info.handle, poll_group)

            -- Send info about this client to everyone
            send_to_all(
               server_clients,
               pb.encode("Player", { id = server_clients[info.handle].id, event = "Joined" }),
               server_clients[info.handle].id
            )
            -- Send info about other clients to this client
            for _, other in pairs(server_clients) do
               if other.id ~= server_clients[info.handle].id then
                  sockets:send_message_to_connection(
                     info.handle,
                     pb.encode("Player", { id = other.id, event = "Joined" }),
                     SteamNetworkingSend.Reliable
                  )
               end
            end
         elseif state == ESteamNetworkingConnectionState.ClosedByPeer or state == ESteamNetworkingConnectionStateProblemDetectedLocally then
            print("[SERVER] Disconnected " .. info.info.connection_description)
            sockets:close_connection(info.handle, 0, "Disconnected", false);

            server_clients[info.handle] = nil
         end
      end
   )

   new_ent:add(M.components.hacking_match_server.class(server_socket, server_clients, poll_group, "lobby"))
end

function M.components.hacking_match_client.process_component(new_ent, comp, entity_name)
   local client_socket = sockets:connect_p2p(
      comp.server_identity,
      {},
      function(info)
         if info.info.state == ESteamNetworkingConnectionState.Connected then
            print("[CLIENT] Connected!")
         end
      end
   )

   new_ent:add(M.components.hacking_match_client.class(client_socket))
end

function M.components.hacking_match_player.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.hacking_match_player.class(0, 0, 0))
end

function M.components.hacking_match_other_player.process_component(new_ent, comp, entity_name)
   new_ent:add(
      M.components.hacking_match_other_player.class(
         comp.id,
         0,
         Vector2f.new(comp.base_position[1], comp.base_position[2])
      )
   )
end

function M.components.hacking_match_block_manager.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.hacking_match_block_manager.class(comp.seed, comp.player, 0, false))
end

function M.components.hacking_match_block.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.hacking_match_block.class(comp.color, false))
   new_ent:get("HackingMatchBlock").bomb = comp.bomb
end

function HackingMatchServerSystem:requires()
   return {"HackingMatchServer"}
end
function HackingMatchServerSystem:update()
   sockets:run_callbacks()

   for _, ent in pairs(self.targets) do
      local server = ent:get("HackingMatchServer")

      local n, msg = sockets:receive_messages_on_poll_group(server.poll_group)
      if n > 0 then

         local id = server.clients[msg.connection].id
         -- TODO: validate client data
         local player_data = pb.decode("Player", msg.data)
         player_data.id = id

         if server.game_state == "lobby" and player_data.event == "IAmReady" then
            server.clients[msg.connection].ready = true

            if lume.all(server.clients, function(c) return c.ready end) then
               print("[SERVER] Everyone is ready")
               send_to_all(server.clients, pb.encode("Player", { event = "EveryoneIsReady" }))

               server.game_state = "game"
            end
         elseif server.game_state == "game" then
            -- Replicate messages to other clients
            send_to_all(server.clients, pb.encode("Player", player_data), id)
         end

         msg:release()
      end
   end
end

function HackingMatchClientSystem:requires()
   return { client = {"HackingMatchClient"}, other_player = {"HackingMatchOtherPlayer"}, player = {"HackingMatchPlayer"} }
end
function HackingMatchClientSystem:update()
   sockets:run_callbacks()

   for _, ent in pairs(self.targets.client) do
      local client = ent:get("HackingMatchClient")

      local n, msg = sockets:receive_messages_on_connection(client.socket.socket)
      if n > 0 then
         local player_data = pb.decode("Player", msg.data)

         if player_data.event == "Joined" then
            local pos = {500, 500}
            util.entities_mod().instantiate_entity(
               "other_player",
               { drawable = { kind = "sprite", texture_asset = "mod.player", z = 1 },
                 transformable = { position = pos },
                 hacking_match_other_player = { id = player_data.id, base_position = pos } })
         elseif player_data.event == "Left" then
            for _, player_ent in pairs(self.targets.other_player) do
               if player_ent:get("HackingMatchOtherPlayer").id == player_data.id then
                  util.rooms_mod().engine:removeEntity(player_ent)
                  break
               end
            end
         elseif player_data.move then
            for _, other in pairs(self.targets.other_player) do
               local other_player = other:get("HackingMatchOtherPlayer")
               local other_drawable = other:get("Drawable")
               local other_tf = other:get("Transformable")

               if other_player.id == player_data.id then
                  if player_data.move.action == "Movement" then
                     other_player.position = player_data.move.position

                     other_tf.transformable.position =
                        other_player.base_position +  Vector2f.new(other_drawable.drawable.global_bounds.width * other_player.position, 0)
                  elseif player_data.move.action == "TakeOrPut" then
                     HackingMatchBlockManagerSystem.take_or_put(other_player.block_manager, other_player.position + 1)
                  elseif player_data.move.action == "Swap" then
                     HackingMatchBlockManagerSystem.swap_at(other_player.block_manager, other_player.position + 1)
                  end
               end
            end
         elseif player_data.block_manager_setup then
            client.block_manager_setup = player_data.block_manager_setup

            -- We got our block manager info, tell the server we're ready
            sockets:send_message_to_connection(
               client.socket.socket,
               pb.encode("Player", { event = "IAmReady" }),
               SteamNetworkingSend.Reliable
            )
            print("[CLIENT] Ready")
         elseif player_data.event == "EveryoneIsReady" then
            for _, player in pairs(self.targets.player) do
               local block_manager_ent = util.entities_mod().instantiate_entity(
                  "block_manager",
                  { hacking_match_block_manager = { seed = client.block_manager_setup.seed, player = player },
                    transformable = { position = { 50, 64 } }})
               -- Set the block manager for the local player
               local pl = player:get("HackingMatchPlayer")
               pl.block_manager = block_manager_ent
               pl.ready = true
            end
            for i, player in pairs(self.targets.other_player) do
               local block_manager_ent = util.entities_mod().instantiate_entity(
                  "block_manager_" .. i,
                  { hacking_match_block_manager = { seed = client.block_manager_setup.seed, player = player },
                    transformable = { position = { 500, 64 } }})
               -- Set the block manager for the other player
               player:get("HackingMatchOtherPlayer").block_manager = block_manager_ent
            end

            print("[CLIENT] Everyone is ready, starting the game")
         end

         msg:release()
      end
   end
end

function HackingMatchPlayerSystem:requires()
   return { player = {"HackingMatchPlayer"}, client = {"HackingMatchClient"} }
end
function HackingMatchPlayerSystem:update(dt)
   sockets:run_callbacks()

   for _, ent in pairs(self.targets.player) do
      local tf = ent:get("Transformable")
      local player = ent:get("HackingMatchPlayer")
      local drawable = ent:get("Drawable")

      if not player.ready then
         return
      end

      if not player.base_position then
         player.base_position = tf.transformable.position:copy()
      end

      local moved = false
      player.time_since_movement = player.time_since_movement + dt
      player.time_since_action = player.time_since_action + dt

      if player.time_since_movement >= 0.18 then
         if Keyboard.is_key_pressed(KeyboardKey.D) then
            if player.position < 5 then
               player.position = player.position + 1
               moved = true
            end
            player.time_since_movement = 0
         elseif Keyboard.is_key_pressed(KeyboardKey.A) then
            if player.position > 0 then
               player.position = player.position - 1
               moved = true
            end
            player.time_since_movement = 0
         end
      end
      if player.time_since_action >= 0.18 then
         if Keyboard.is_key_pressed(KeyboardKey.K) then
            HackingMatchBlockManagerSystem.swap_at(player.block_manager, player.position + 1)

            for _, client_ent in pairs(self.targets.client) do
               -- Notify the server about movement
               sockets:send_message_to_connection(
                  client_ent:get("HackingMatchClient").socket.socket,
                  pb.encode("Player", { move = { action = "Swap" } }),
                  SteamNetworkingSend.Reliable
               )
            end

            player.time_since_action = 0
         elseif Keyboard.is_key_pressed(KeyboardKey.J) then
            HackingMatchBlockManagerSystem.take_or_put(player.block_manager, player.position + 1)

            for _, client_ent in pairs(self.targets.client) do
               -- Notify the server about movement
               sockets:send_message_to_connection(
                  client_ent:get("HackingMatchClient").socket.socket,
                  pb.encode("Player", { move = { action = "TakeOrPut" } }),
                  SteamNetworkingSend.Reliable
               )
            end

            player.time_since_action = 0
         end
      end

      if moved then
         tf.transformable.position = player.base_position + Vector2f.new((drawable.drawable.global_bounds.width * player.position), 0)

         for _, client_ent in pairs(self.targets.client) do
            local client = client_ent:get("HackingMatchClient")

            -- Notify the server about movement
            sockets:send_message_to_connection(
               client.socket.socket,
               pb.encode("Player", { move = { action = "Movement", position = player.position } }),
               SteamNetworkingSend.Reliable
            )
         end
      end
   end
end

local function block_y_pos(manager_ent, line_n)
   return manager_ent:get("Transformable").transformable.position.y - ((line_n - 1) * 64) + manager_ent:get("HackingMatchBlockManager").offset
end

local block_combo_min = 4
local bomb_combo_min = 2
local bomb_chance = 0.98

local function is_breakable_combo(maybe_combo)
   local bomb_combo = maybe_combo[1] and maybe_combo[1].bomb

   return (not bomb_combo and #maybe_combo >= block_combo_min) or (bomb_combo and #maybe_combo >= bomb_combo_min)
end

function HackingMatchBlockManagerSystem:requires()
   return { manager = {"HackingMatchBlockManager"} }
end
function HackingMatchBlockManagerSystem:update(dt)
   for _, ent in pairs(self.targets.manager) do
      local manager = ent:get("HackingMatchBlockManager")
      local tf = ent:get("Transformable")

      if not manager.block_entities or #manager.block_entities < 10 then
         if not manager.block_entities then
            -- Only set the seed once
            math.randomseed(manager.seed)
            manager.block_entities = {}
         end

         local max_bombs = 1
         local bomb_counter = 0

         local blocks = {}
         for line = 1, 20 do
            blocks[line] = {}
            for block = 1, 6 do
               blocks[line][block] = { color = math.random(1, 5) }
               if math.random() > bomb_chance and max_bombs < bomb_counter then
                  bomb_counter = bomb_counter + 1
                  blocks[line][block].bomb = true
               else
                  blocks[line][block].bomb = false
               end
            end
         end

         local block_entities = manager.block_entities
         -- Number of existing lines
         local line_n_count = #block_entities
         for line_n, line in ipairs(blocks) do
            line_n = line_n_count + line_n
            block_entities[line_n] = {}

            for block_n, block_tbl in ipairs(line) do
               local block = block_tbl.color
               local block_pos = {tf.transformable.position.x + (block_n - 1) * 64, tf.transformable.position.y - (line_n - 1) * 64}

               local block_texture
               if block_tbl.bomb then
                  block_texture = "mod.bomb"
               else
                  block_texture = "mod.block"
               end

               local block_ent = util.entities_mod().instantiate_entity(
                  "block_" .. tostring(line_n) .. "_" .. tostring(block_n),
                  { drawable = { kind = "sprite", texture_asset = block_texture, z = 1 },
                    transformable = { position = block_pos },
                    hacking_match_block = { color = block, bomb = block_tbl.bomb }})

               -- 1 - Red, 2 - Yellow, 3 - Pink, 4 - Turquoise, 5 - Blue

               block_entities[line_n][block_n] = block_ent

               -- Break the initial-generation combo
               while is_breakable_combo(self:combo(manager, line_n, block_n)) do
                  block = math.random(1, 5)
                  block_ent:get("HackingMatchBlock").color = block
               end

               local new_color
               if block == 1 then
                  new_color = Color.Red
               elseif block == 2 then
                  new_color = Color.Yellow
               elseif block == 3 then
                  -- Pink
                  new_color = Color.new(246, 191, 255, 255)
               elseif block == 4 then
                  -- Turquoise
                  new_color = Color.new(64, 224, 208, 255)
               elseif block == 5 then
                  -- Blue
                  new_color = Color.new(0, 0, 255, 255)
               end
               block_ent:get("Drawable").drawable.color = new_color
            end
         end
      end

      if manager.held then
         local held_tf = manager.held:get("Transformable")

         local player_tf = manager.player:get("Transformable")
         local drawable = manager.player:get("Drawable")

         held_tf.transformable.position.x = player_tf.transformable.position.x
         held_tf.transformable.position.y = player_tf.transformable.position.y - drawable.drawable.global_bounds.height
      end

      if manager.break_pause then
         return
      end
      if Keyboard.is_key_pressed(KeyboardKey.L) then
         manager.offset = manager.offset + 0.4
      else
         manager.offset = manager.offset + 0.2
      end

      local found_combos = {}

      for line_n, line in ipairs(manager.block_entities) do
         local any_blocks = false
         -- Blocks can be nil
         for block_n = 1, 6 do
            local block = line[block_n]

            if block then
               any_blocks = true
               local block_tf = block:get("Transformable")

               if not block.currently_swapping then
                  block_tf.transformable.position.y = block_y_pos(ent, line_n)
               end

               local maybe_combo = self:combo(manager, line_n, block_n)
               if is_breakable_combo(maybe_combo) then
                  table.insert(found_combos, maybe_combo)

                  -- Also add every block of the color to the combo if it's a bomb
                  if maybe_combo[1].bomb then
                     local bomb_color = maybe_combo[1].block:get("HackingMatchBlock").color
                     for line_n, line in ipairs(manager.block_entities) do
                        for block_n, block in ipairs(line) do
                           -- Only blow up the blocks visible on the screen, plus a bit upwards
                           if block and block:get("Transformable").transformable.position.y < tf.transformable.position.y - (64 * 2) then
                              goto bombdone
                           end

                           local tested_block = block and block:get("HackingMatchBlock")
                           if tested_block and tested_block.color == bomb_color and not tested_block.bomb then
                              table.insert(maybe_combo, { line_n = line_n, block_n = block_n, block = block, bomb = tested_block.bomb })
                           end
                        end
                     end
                  end
                  ::bombdone::

                  for _, combo_block in ipairs(maybe_combo) do
                     -- Remove the block from the list so the next combo check would not try it,
                     -- but don't destroy the entity yet. This will happen later, when processing all the combos

                     manager.block_entities[combo_block.line_n][combo_block.block_n] = nil
                  end
               end
            end
         end
      end
      if #found_combos > 0 then
         coroutines.create_coroutine(
            function()
               manager.break_pause = true

               for _, combo in ipairs(found_combos) do
                  for _, combo_block in ipairs(combo) do
                     util.rooms_mod().engine:removeEntity(combo_block.block)
                  end

                  local timer = 0.3
                  local dt = 0

                  while timer > 0 do
                     dt = coroutine.yield()
                     timer = timer - dt
                  end

                  local falling_blocks = self:process_fallthrough(manager, combo)
                  for _, t in ipairs({0.2, 0.9, 1}) do
                     for _, falling in ipairs(falling_blocks) do
                        falling.block:get("Transformable").transformable.position.y =
                           lume.lerp(block_y_pos(ent, falling.from), block_y_pos(ent, falling.to), t)
                     end
                     coroutine.yield()
                  end

                  timer = 0.2
                  while timer > 0 do
                     dt = coroutine.yield()
                     timer = timer - dt
                  end
               end

               manager.break_pause = false
            end
         )
      end

      if manager.block_entities[1] and lume.count(manager.block_entities[1]) == 0 then
         table.remove(manager.block_entities, 1)
         manager.offset = manager.offset - 64
      end
   end
end
function HackingMatchBlockManagerSystem.swap_at(manager_ent, pos)
   local manager = manager_ent:get("HackingMatchBlockManager")
   for line_n, line in ipairs(manager.block_entities) do
      local block = line[pos]

      if block ~= nil and manager.block_entities[line_n + 1] and manager.block_entities[line_n + 1][pos] ~= nil then
         local other = manager.block_entities[line_n + 1][pos]

         coroutines.create_coroutine(
            function()
               block.currently_swapping = true
               other.currently_swapping = true

               local block_tf = block:get("Transformable").transformable
               local other_tf = other:get("Transformable").transformable

               local block_original = block_tf.position:copy()
               local other_original = other_tf.position:copy()

               for _, t in ipairs({0.2, 0.5, 1}) do
                  block_tf.position.y =
                     lume.lerp(block_y_pos(manager_ent, line_n), block_y_pos(manager_ent, line_n + 1), t)
                  other_tf.position.y =
                     lume.lerp(block_y_pos(manager_ent, line_n + 1), block_y_pos(manager_ent, line_n), t)
                  coroutine.yield()
               end

               manager.block_entities[line_n + 1][pos] = block
               line[pos] = other

               block.currently_swapping = false
               other.currently_swapping = false
            end
         )

         break
      end
   end
end
function HackingMatchBlockManagerSystem.take_or_put(manager_ent, pos)
   local manager = manager_ent:get("HackingMatchBlockManager")

   if not manager.held then
      for line_n, line in ipairs(manager.block_entities) do
         for block_n = 1, 6 do
            local block = line[block_n]

            if block_n == pos and block ~= nil then
               manager.held = block
               line[block_n] = nil

               goto done
            end
         end
      end
   else
      for line_n = #manager.block_entities, 1, -1  do
         local line = manager.block_entities[line_n]

         for block_n = 1, 6 do
            local block = line[block_n]

            if block_n == pos and block == nil then
               line[block_n] = manager.held
               manager.held = nil

               goto done
            end
         end
      end

         -- No space anywhere, add a new empty line
      table.insert(manager.block_entities, 1, { [pos] = manager.held })
      manager.held = nil
      manager.offset = manager.offset + 64
   end

   ::done::
end
function HackingMatchBlockManagerSystem:combo(manager, line_n, block_n, known_combo)
   local block = manager.block_entities[line_n][block_n]
   local this_block = block:get("HackingMatchBlock")

   if known_combo == nil then
      known_combo = { { line_n = line_n, block_n = block_n, block = block, bomb = this_block.bomb } }
   end

   local function check(l, b)
      local maybe_other = manager.block_entities[l][b]
      local maybe_other_block = maybe_other and maybe_other:get("HackingMatchBlock")
      if maybe_other and maybe_other_block.color == this_block.color and maybe_other_block.bomb == this_block.bomb then
         -- If we already know this block is part of the combo, don't do anything
         if lume.match(known_combo, function(known) return known.block == maybe_other end) then
            return
         end

         -- Mark as known combo
         table.insert(known_combo, { line_n = l, block_n = b, block = maybe_other, bomb = maybe_other_block.bomb })

         self:combo(manager, l, b, known_combo)
      end
   end

   -- Check to the left, right, up and down
   check(line_n, block_n - 1)
   check(line_n, block_n + 1)
   if manager.block_entities[line_n - 1] then
      check(line_n - 1, block_n)
   end
   if manager.block_entities[line_n + 1] then
      check(line_n + 1, block_n)
   end

   return known_combo
end
function HackingMatchBlockManagerSystem:process_fallthrough(manager, combo_blocks)
   local highest_line = math.max(
      table.unpack(
         lume.map(combo_blocks, function (b) return b.line_n end)
      )
   )
   local fallthrough_numbers = lume.unique(lume.map(combo_blocks, function (b) return b.block_n end))

   local falling_blocks = {}

   ::restart::
   for fall_line_n = #manager.block_entities, 1, -1 do
      for _, block_n in ipairs(fallthrough_numbers) do
         -- There's a line and a block on that line
         if manager.block_entities[fall_line_n] and manager.block_entities[fall_line_n + 1]
            and manager.block_entities[fall_line_n][block_n] and not manager.block_entities[fall_line_n + 1][block_n] then
            local fall_to = fall_line_n
            -- Find the deepest the block can fall
            while manager.block_entities[fall_to + 1] and not manager.block_entities[fall_to + 1][block_n] do
               fall_to = fall_to + 1
            end

            local falling_block = manager.block_entities[fall_line_n][block_n]
            manager.block_entities[fall_line_n][block_n] = nil
            -- Place the block into the empty place
            manager.block_entities[fall_to][block_n] = falling_block

            table.insert(falling_blocks, { from = fall_line_n, to = fall_to, block = falling_block })

            goto restart
         end
      end
   end

   return falling_blocks
end

M.interaction_callbacks = { }

local setup_info = {
   seed = os.time(),
   server_addr = "127.0.0.1:12345",

   friend_list = nil,
   friend_selected = -1
}

local function create_identity()
   local server_identity
   if NETWORKING.IS_STEAM then
      server_identity = sockets:identity()
   else
      server_identity = SteamNetworkingIPAddr.new()
      server_identity:parse_string(setup_info.server_addr)
   end

   return server_identity
end

function M.interaction_callbacks.draw_gui()
   ImGui.Begin("Hacking Match")

   if not NETWORKING.IS_STEAM then
      setup_info.server_addr = ImGui.InputText("Server address", setup_info.server_addr)
   else
      local friends = STEAM.Friends()
      if not setup_info.friend_list then
         setup_info.friend_list = {}
         for _, friend in ipairs(friends:GetFriends()) do
            if friends:GetFriendPersonaState(friend) == EPersonaState.Online then
               table.insert(setup_info.friend_list, { id = friend, name = friends:GetFriendPersonaName(friend) })
            end
         end
      end

      local friend_names = lume.map(setup_info.friend_list, function(f) return f.name end)

      ImGui.SetNextItemWidth(150)
      setup_info.friend_selected = ImGui.ListBox("Connect to a friend", setup_info.friend_selected, friend_names)
   end

   setup_info.seed = ImGui.InputInt("Seed", setup_info.seed)

   if ImGui.Button("Start server") then
      local ident = create_identity()
      util.entities_mod().instantiate_entity(
         "server",
         { hacking_match_server = { server_identity = ident } } )
      util.entities_mod().instantiate_entity(
         "client",
         { hacking_match_client = { server_identity = ident } } )
   end

   if not NETWORKING.IS_STEAM then
      if ImGui.Button("Connect to server") then
         local ent = util.entities_mod().instantiate_entity(
            "client",
            { hacking_match_client = { server_identity = create_identity() } } )
      end
   else
      if setup_info.friend_selected == -1 then ImGui.BeginDisabled(true) end

      if ImGui.Button("Connect to friend") then
         local ident = SteamNetworkingIdentity.new()
         ident:SetSteamID(setup_info.friend_list[setup_info.friend_selected].id)

         local ent = util.entities_mod().instantiate_entity(
            "client",
            { hacking_match_client = { server_identity = ident } } )
      end

      if setup_info.friend_selected == -1 then ImGui.EndDisabled() end
   end

   if ImGui.Button("Start game") then
      local server = util.first(util.rooms_mod().engine:getEntitiesWithComponent("HackingMatchServer")):get("HackingMatchServer")
      -- Ask everyone if they're ready
      send_to_all(
         server.clients,
         pb.encode("Player", { block_manager_setup = { setup_info.seed } })
      )
   end

   ImGui.End()
end

M.systems = {
   HackingMatchServerSystem,
   HackingMatchClientSystem,
   HackingMatchPlayerSystem,
   HackingMatchBlockManagerSystem
}

return M
