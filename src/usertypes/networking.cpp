#include <limits>

#include "sol/object.hpp"
#ifdef SOMEONE_NETWORKING_STEAM
#include <steam/steam_api_flat.h>
#else
#include <steam/steamnetworkingsockets_flat.h>
#include <steam/isteamnetworkingutils.h>
#endif

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
    SteamAPI_SteamNetworkingConfigValue_t_SetInt32(&userdataOption, k_ESteamNetworkingConfig_ConnectionUserData, id_for_this);

    SteamNetworkingConfigValue_t statusChangedOption;
    SteamAPI_SteamNetworkingConfigValue_t_SetPtr(
        &statusChangedOption,
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
#ifdef SOMEONE_NETWORKING_STEAM
            SteamAPI_Init();
	    SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(SteamNetworkingUtils());

	    SteamAPI_ISteamUtils_SetWarningMessageHook(
		SteamAPI_SteamUtils(),
		[](int type, const char *msg) {
		  spdlog::warn("{}", msg);
		}
	    );
#else
            SteamDatagramErrMsg errMsg;
            if (!GameNetworkingSockets_Init( nullptr, errMsg))
                spdlog::error("{}", errMsg);
#endif
            SteamAPI_ISteamNetworkingUtils_SetDebugOutputFunction(
                SteamNetworkingUtils(),
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
        "sockets", &SteamNetworkingSockets_SteamAPI,
        "set_connection_status_changed_callback",
        [](uint32 conn, sol::protected_function callback) {
            connection_status_changed_callbacks[conn] = callback;
        },

        "INVALID_CONNECTION", k_HSteamNetConnection_Invalid
#ifdef SOMEONE_NETWORKING_STEAM
        , "IS_STEAM", true
#endif
    );

    lua.new_usertype<SteamNetworkingIPAddr>(
        "SteamNetworkingIPAddr", sol::constructors<SteamNetworkingIPAddr()>(),
        "clear", &SteamAPI_SteamNetworkingIPAddr_Clear,
        "parse_string", &SteamAPI_SteamNetworkingIPAddr_ParseString,
        "port", &SteamNetworkingIPAddr::m_port
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
        "create_listen_socket_p2p", [](ISteamNetworkingSockets *self,
#ifdef SOMEONE_NETWORKING_STEAM
                                       SteamNetworkingIdentity &unused_ident,
#else
                                       SteamNetworkingIPAddr &addr,
#endif
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
#ifdef SOMEONE_NETWORKING_STEAM
                .socket = SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P(self, 0, resulting_options.size(), resulting_options.data())
#else
                .socket = SteamAPI_ISteamNetworkingSockets_CreateListenSocketIP(self, addr, resulting_options.size(), resulting_options.data())
#endif
            };
        },
        "connect_p2p", [](ISteamNetworkingSockets *self,
#ifdef SOMEONE_NETWORKING_STEAM
                          SteamNetworkingIdentity &ident,
#else
                          SteamNetworkingIPAddr &ident,
#endif
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
#ifdef SOMEONE_NETWORKING_STEAM
                .socket = SteamAPI_ISteamNetworkingSockets_ConnectP2P(self, ident, 0, resulting_options.size(), resulting_options.data())
#else
                .socket = SteamAPI_ISteamNetworkingSockets_ConnectByIPAddress(self, ident, resulting_options.size(), resulting_options.data())
#endif
            };
        },
        "close_listen_socket", &SteamAPI_ISteamNetworkingSockets_CloseListenSocket,
        "accept_connection", &SteamAPI_ISteamNetworkingSockets_AcceptConnection,
        "close_connection", &SteamAPI_ISteamNetworkingSockets_CloseConnection,
        "send_message_to_connection", [](ISteamNetworkingSockets *self,
                                         HSteamNetConnection conn,
                                         std::string message, int networking_send) {
            return SteamAPI_ISteamNetworkingSockets_SendMessageToConnection(self, conn, message.data(), message.length(), networking_send, nullptr);
        },
        "run_callbacks", &SteamAPI_ISteamNetworkingSockets_RunCallbacks,
        "receive_messages_on_connection", [](ISteamNetworkingSockets *self, HSteamNetConnection conn) {
            SteamNetworkingMessage_t *outMessage = nullptr;
            auto n = SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnConnection(self, conn, &outMessage, 1);

            return std::make_tuple(n, outMessage);
        },

        "create_poll_group", &SteamAPI_ISteamNetworkingSockets_CreatePollGroup,
        "destroy_poll_group", &SteamAPI_ISteamNetworkingSockets_DestroyPollGroup,
        "set_connection_poll_group", &SteamAPI_ISteamNetworkingSockets_SetConnectionPollGroup,
        "receive_messages_on_poll_group", [](ISteamNetworkingSockets *self, HSteamNetPollGroup group) {
            SteamNetworkingMessage_t *outMessage = nullptr;
            auto n =  SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnPollGroup(self, group, &outMessage, 1);

            return std::make_tuple(n, outMessage);
        },
        "identity", [](ISteamNetworkingSockets *self) {
            SteamNetworkingIdentity ident;
            SteamAPI_ISteamNetworkingSockets_GetIdentity(self, &ident);

            return ident;
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
        "release", &SteamAPI_SteamNetworkingMessage_t_Release
    );

    lua.new_enum(
        "ESteamNetworkingConnectionState",
        "Connecting", k_ESteamNetworkingConnectionState_Connecting,
        "Connected", k_ESteamNetworkingConnectionState_Connected,
        "ClosedByPeer", k_ESteamNetworkingConnectionState_ClosedByPeer,
        "ProblemDetectedLocally", k_ESteamNetworkingConnectionState_ProblemDetectedLocally
    );

    lua.new_usertype<SteamNetworkingIdentity>(
        "SteamNetworkingIdentity", sol::default_constructor,
        "SetSteamID", &SteamAPI_SteamNetworkingIdentity_SetSteamID,
        sol::meta_function::to_string, [](SteamNetworkingIdentity *ident) {
            return SteamNetworkingIdentityRender(*ident).c_str();
        }
    );

#ifdef SOMEONE_NETWORKING_STEAM
    lua["STEAM"] = lua.create_table_with(
	"Friends", &SteamFriends,
        "run_callbacks", &SteamAPI_RunCallbacks
    );

    lua.new_usertype<ISteamFriends>(
        "ISteamFriends",
        "GetFriends", [&lua](ISteamFriends *self) {
            auto count = SteamAPI_ISteamFriends_GetFriendCount(self, k_EFriendFlagImmediate);

            if (count == -1)
                return sol::make_object(lua, std::make_tuple(sol::lua_nil, "Count returned -1, probably not logged in"));

            std::vector<uint64_steamid> result;
            for (int i = 0; i < count; i++) {
                result.push_back(SteamAPI_ISteamFriends_GetFriendByIndex(self, i, k_EFriendFlagImmediate));
            }

            return sol::make_object(lua, result);
        },
        "GetFriendPersonaState", &SteamAPI_ISteamFriends_GetFriendPersonaState,
        "GetFriendPersonaName", &SteamAPI_ISteamFriends_GetFriendPersonaName
    );

    lua.new_enum(
        "EPersonaState",
        "Online", k_EPersonaStateOnline,
        "Offline", k_EPersonaStateOffline
    );
#endif
}
