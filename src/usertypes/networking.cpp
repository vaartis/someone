#include <steam/steamnetworkingsockets.h>
#include <steam/isteamnetworkingutils.h>

#include "sol/forward.hpp"
#include "sol/raii.hpp"
#include "sol/types.hpp"
#include "steam/isteamnetworkingsockets.h"
#include "steam/steamclientpublic.h"
#include "steam/steamnetworkingtypes.h"
#include "usertypes.hpp"

// Keep an internal ID for all created callbacks and save them to userdata
uint32 callback_id = 0;
std::map<uint32, sol::protected_function> connection_status_changed_callbacks;

std::vector<SteamNetworkingConfigValue_t> socket_opts(uint32 id_for_this) {
    std::vector<SteamNetworkingConfigValue_t> resulting_options;

    SteamNetworkingConfigValue_t userdataOption;
    userdataOption.SetInt32(k_ESteamNetworkingConfig_ConnectionUserData, id_for_this);

    SteamNetworkingConfigValue_t statusChangedOption;
    statusChangedOption.SetPtr(
        k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,
        (void*)+[](SteamNetConnectionStatusChangedCallback_t *info) {
            auto userdata_id = (uint32)info->m_info.m_nUserData;

            connection_status_changed_callbacks[userdata_id](info);
        }
    );
    resulting_options.push_back(userdataOption);
    resulting_options.push_back(statusChangedOption);

    return resulting_options;
};

struct SocketWrapper {
    uint32 callback_id;
    uint32 socket;
};

void register_networking_usertypes(sol::state &lua) {
    lua["NETWORKING"] = lua.create_table_with(
        "init", []() {
            SteamDatagramErrMsg errMsg;
            if (!GameNetworkingSockets_Init( nullptr, errMsg))
                spdlog::error("{}", errMsg);

            SteamNetworkingUtils()->SetDebugOutputFunction(
                k_ESteamNetworkingSocketsDebugOutputType_Everything,
                [](ESteamNetworkingSocketsDebugOutputType type, const char *msg) {
                    switch (type) {
                    case k_ESteamNetworkingSocketsDebugOutputType_Error:
                        spdlog::error("{}", msg);
                        break;
                    default:
                        spdlog::debug("{}", msg);
                        break;
                    }
                }
            );
        },
        "sockets", &SteamNetworkingSockets,
        "set_connection_status_changed_callback",
        [](uint32 conn, sol::protected_function callback) {
            connection_status_changed_callbacks[conn] = callback;
        },

        "INVALID_CONNECTION", k_HSteamNetConnection_Invalid
    );

    lua.new_usertype<SteamNetworkingIPAddr>(
        "SteamNetworkingIPAddr", sol::constructors<SteamNetworkingIPAddr()>(),
        "clear", &SteamNetworkingIPAddr::Clear,
        "port", &SteamNetworkingIPAddr::m_port,
        "parse_string", &SteamNetworkingIPAddr::ParseString
    );

    lua.new_usertype<SocketWrapper>(
        "SocketWrapper",
        "socket", &SocketWrapper::socket,
        sol::meta_function::garbage_collect, sol::destructor([](SocketWrapper *self) {
            connection_status_changed_callbacks.erase(self->callback_id);
        })
    );

    lua.new_usertype<ISteamNetworkingSockets>(
        "ISteamNetworkingSockets",
        "create_listen_socket_ip", [](ISteamNetworkingSockets *self,
                                      SteamNetworkingIPAddr &addr,
                                      sol::table options,
                                      sol::protected_function connection_state_changed) {
            auto id_for_this = callback_id++;
            connection_status_changed_callbacks[id_for_this] = connection_state_changed;

            std::vector<SteamNetworkingConfigValue_t> resulting_options = socket_opts(id_for_this);
            for (auto [k,v] : options) {
                resulting_options.push_back(v.as<SteamNetworkingConfigValue_t>());
            }

            return SocketWrapper {
                .callback_id = id_for_this,
                .socket = self->CreateListenSocketIP(addr, resulting_options.size(), resulting_options.data())
            };
        },
        "connect_by_ip_address", [](ISteamNetworkingSockets *self,
                                    SteamNetworkingIPAddr &addr,
                                    sol::table options,
                                    sol::protected_function connection_state_changed) {
            auto id_for_this = callback_id++;
            connection_status_changed_callbacks[id_for_this] = connection_state_changed;

            std::vector<SteamNetworkingConfigValue_t> resulting_options = socket_opts(id_for_this);
            for (auto [k,v] : options) {
                resulting_options.push_back(v.as<SteamNetworkingConfigValue_t>());
            }

            return SocketWrapper {
                .callback_id = id_for_this,
                .socket = self->ConnectByIPAddress(addr, resulting_options.size(), resulting_options.data())
            };
        },
        "close_listen_socket", &ISteamNetworkingSockets::CloseListenSocket,
        "accept_connection", &ISteamNetworkingSockets::AcceptConnection,
        "close_connection", &ISteamNetworkingSockets::CloseConnection,
        "send_message_to_connection", [](ISteamNetworkingSockets *self,
                                         HSteamNetConnection conn,
                                         std::string message, int networking_send) {
            return self->SendMessageToConnection(conn, message.data(), message.length(), networking_send, nullptr);
        },
        "run_callbacks", &ISteamNetworkingSockets::RunCallbacks,
        "receive_messages_on_connection", [](ISteamNetworkingSockets *self, HSteamNetConnection conn) {
            SteamNetworkingMessage_t *outMessage = nullptr;
            auto n = self->ReceiveMessagesOnConnection(conn, &outMessage, 1);

            return std::make_tuple(n, outMessage);
        },

        "create_poll_group", &ISteamNetworkingSockets::CreatePollGroup,
        "destroy_poll_group", &ISteamNetworkingSockets::DestroyPollGroup,
        "set_connection_poll_group", &ISteamNetworkingSockets::SetConnectionPollGroup,
        "receive_messages_on_poll_group", [](ISteamNetworkingSockets *self, HSteamNetPollGroup group) {
            SteamNetworkingMessage_t *outMessage = nullptr;
            auto n = self->ReceiveMessagesOnPollGroup(group, &outMessage, 1);

            return std::make_tuple(n, outMessage);
        }
    );

    lua.new_enum(
        "EResult",
        "Ok", k_EResultOK
    );

    lua.new_enum(
        "ESteamNetworkingConfigValue",
        "Callback_ConnectionStatusChanged", k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged
    );

    lua.new_enum(
        "SteamNetworkingSend",
        "Reliable", k_nSteamNetworkingSend_Reliable,
        "Unreliable", k_nSteamNetworkingSend_Unreliable
    );

    lua.new_usertype<SteamNetworkingConfigValue_t>(
        "SteamNetworkingConfigValue", sol::constructors<SteamNetworkingConfigValue_t()>()
    );

    lua.new_usertype<SteamNetConnectionStatusChangedCallback_t>(
        "SteamNetConnectionStatusChangedCallback",
        "info", &SteamNetConnectionStatusChangedCallback_t::m_info,
        "old_state", &SteamNetConnectionStatusChangedCallback_t::m_eOldState,
        "handle", &SteamNetConnectionStatusChangedCallback_t::m_hConn
    );

    lua.new_usertype<SteamNetConnectionInfo_t>(
        "SteamNetConnectionInfo",
        "state", &SteamNetConnectionInfo_t::m_eState,
        "connection_description", &SteamNetConnectionInfo_t::m_szConnectionDescription
    );

    lua.new_usertype<SteamNetworkingMessage_t>(
        "SteamNetworkingMessage",
        "data", sol::property([](SteamNetworkingMessage_t *self) {
            return std::string((char*)self->m_pData, self->m_cbSize);
        }),
        "connection", &SteamNetworkingMessage_t::m_conn,
        "release", &SteamNetworkingMessage_t::Release
    );

    lua.new_enum(
        "ESteamNetworkingConnectionState",
        "Connecting", k_ESteamNetworkingConnectionState_Connecting,
        "Connected", k_ESteamNetworkingConnectionState_Connected,
        "ClosedByPeer", k_ESteamNetworkingConnectionState_ClosedByPeer,
        "ProblemDetectedLocally", k_ESteamNetworkingConnectionState_ProblemDetectedLocally
    );
}