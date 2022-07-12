local collider_components = require("components.collider")
local assets = require("components.assets")
local path = require("path")

local pb = require("pb")
local protoc = require("protoc")

local pc = protoc.new()
pc:loadfile(path.join(assets.resources_root(), "protobuf/game.proto"))

M = {}

M.components = {
   hacking_match_server = {
      class = Component.create("HackingMatchServer", {"socket", "clients", "poll_group"})
   },

   hacking_match_client = {
      class = Component.create("HackingMatchClient", {"socket", "id"})
   },

   hacking_match_player = {
      class = Component.create("HackingMatchPlayer")
   },

   hacking_match_other_player = {
      class = Component.create("HackingMatchOtherPlayer")
   }
}

NETWORKING.init()
local server_addr = SteamNetworkingIPAddr.new()
server_addr:parse_string("127.0.0.1:12345")

local sockets = NETWORKING.sockets()

function M.components.hacking_match_server.process_component(new_ent, comp, entity_name)
   local server_clients = {}
   local poll_group = sockets:create_poll_group()

   local latest_id = 0
   local server_socket = sockets:create_listen_socket_ip(
      server_addr,
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
         end
      end
   )

   new_ent:add(M.components.hacking_match_server.class(server_socket, server_clients, poll_group))
end

function M.components.hacking_match_client.process_component(new_ent, comp, entity_name)
   local client_socket = sockets:connect_by_ip_address(
      server_addr,
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
   new_ent:add(M.components.hacking_match_player.class())
end

function M.components.hacking_match_other_player.process_component(new_ent, comp, entity_name)
   new_ent:add(M.components.hacking_match_other_player.class())
end

local HackingMatchServerSystem = class("HackingMatchServerSystem", System)
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
         --local player_data = pb.decode("Player", msg.data)

         for handle, client in pairs(server.clients) do
            sockets:send_message_to_connection(
               handle,
               msg.data,
               SteamNetworkingSend.Reliable
            )
         end

         msg:release()
      end
   end
end

local HackingMatchClientSystem = class("HackingMatchClientSystem", System)
function HackingMatchClientSystem:requires()
   return { client = {"HackingMatchClient"}, other_player = {"HackingMatchOtherPlayer"}}
end
function HackingMatchClientSystem:update()
   sockets:run_callbacks()

   for _, ent in pairs(self.targets.client) do
      local client = ent:get("HackingMatchClient")

      local n, msg = sockets:receive_messages_on_connection(client.socket.socket)
      if n > 0 then
         local player_data = pb.decode("Player", msg.data)

         local physics_world = collider_components.physics_world
         for _, other in pairs(self.targets.other_player) do
            local _, y = physics_world:getRect(other)
            physics_world:update(other, player_data.x, y)
         end

         msg:release()
      end
   end
end

local HackingMatchPlayerSystem = class("HackingMatchPlayerSystem", System)
function HackingMatchPlayerSystem:requires()
   return { player = {"HackingMatchPlayer"}, client = {"HackingMatchClient"} }
end
function HackingMatchPlayerSystem:update()
   sockets:run_callbacks()

   for _, ent in pairs(self.targets.player) do
      local tf = ent:get("Transformable")

      local x_movement_speed = 2

      local pos_diff
      if Keyboard.is_key_pressed(KeyboardKey.D) then
         pos_diff = Vector2f.new(x_movement_speed, 0.0)
      elseif Keyboard.is_key_pressed(KeyboardKey.A) then
         pos_diff = Vector2f.new(-x_movement_speed, 0.0)
      end

      if pos_diff then
         local physics_world = collider_components.physics_world

         local x, y = physics_world:getRect(ent)
         local expected_new_pos = Vector2f.new(x, y) + pos_diff

         local _, _, cols, col_count = physics_world:check(
            ent, expected_new_pos.x, expected_new_pos.y,
            function(item, other) if other:get("Collider").trigger then return "cross" else return "slide" end end
         )
         if col_count == 0 or not lume.any(cols, function(c) return c.type == "slide" end) then
            physics_world:update(ent, expected_new_pos.x, expected_new_pos.y)

            for _, client_ent in pairs(self.targets.client) do
               local client = client_ent:get("HackingMatchClient")

               sockets:send_message_to_connection(
                  client.socket.socket,
                  pb.encode("Player", { x = expected_new_pos.x, expected_new_pos.y }),
                  SteamNetworkingSend.Reliable
               )
            end
         end
      end
   end
end



M.systems = {
   HackingMatchServerSystem,
   HackingMatchClientSystem,
   HackingMatchPlayerSystem
}

return M
