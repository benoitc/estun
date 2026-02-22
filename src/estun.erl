%% @doc ESTUN - Erlang STUN Client
%%
%% Public API facade for STUN operations including NAT discovery
%% and UDP hole punching.
%%
%% == Quick Start ==
%% ```
%% %% Add a STUN server
%% {ok, ServerId} = estun:add_server(#{host => "stun.l.google.com", port => 19302}).
%%
%% %% Discover public address
%% {ok, MappedAddr} = estun:discover().
%%
%% %% For hole punching
%% {ok, SocketRef} = estun:open_socket().
%% {ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId).
%% ok = estun:start_keepalive(SocketRef, 25).
%% {ok, connected} = estun:punch(SocketRef, PeerIP, PeerPort).
%% '''
-module(estun).

-include("estun.hrl").

%% Server management
-export([add_server/1, add_server/2]).
-export([remove_server/1]).
-export([list_servers/0]).
-export([get_server/1]).

%% Simple discovery
-export([discover/0, discover/1]).
-export([bind/1, bind/2]).

%% NAT behavior discovery (RFC 5780)
-export([discover_nat/1, discover_nat/2]).

%% Socket management for hole punching
-export([open_socket/0, open_socket/1]).
-export([bind_socket/2, bind_socket/3]).
-export([get_mapped_address/1]).
-export([get_binding_info/1]).
-export([transfer_socket/1]).
-export([close_socket/1]).

%% Keepalive
-export([start_keepalive/2]).
-export([stop_keepalive/1]).

%% Event handling
-export([set_event_handler/2]).

%% Hole punching
-export([punch/3, punch/4]).

%% Types
-type server_id() :: term().
-type socket_ref() :: pid().
-type server_config() :: #{
    host := inet:hostname() | inet:ip_address(),
    port => inet:port_number(),
    transport => udp | tcp | tls,
    family => inet | inet6,
    auth => none | short_term | long_term,
    username => binary(),
    password => binary(),
    realm => binary()
}.
-type socket_opts() :: #{
    family => inet | inet6,
    local_addr => inet:ip_address(),
    local_port => inet:port_number(),
    reuse_port => boolean()
}.
-type punch_opts() :: #{
    timeout => pos_integer(),
    attempts => pos_integer(),
    interval => pos_integer()
}.

-export_type([server_id/0, socket_ref/0, server_config/0, socket_opts/0, punch_opts/0]).

%%====================================================================
%% Server Management
%%====================================================================

%% @doc Add a STUN server to the pool
-spec add_server(server_config()) -> {ok, server_id()} | {error, term()}.
add_server(Config) ->
    estun_pool:add_server(Config).

%% @doc Add a STUN server with a specific ID
-spec add_server(server_config(), server_id()) -> {ok, server_id()} | {error, term()}.
add_server(Config, Id) ->
    estun_pool:add_server(Config, Id).

%% @doc Remove a STUN server from the pool
-spec remove_server(server_id()) -> ok | {error, not_found}.
remove_server(Id) ->
    estun_pool:remove_server(Id).

%% @doc List all configured STUN servers
-spec list_servers() -> [{server_id(), #stun_server{}}].
list_servers() ->
    estun_pool:list_servers().

%% @doc Get a STUN server by ID
-spec get_server(server_id()) -> {ok, #stun_server{}} | {error, not_found}.
get_server(Id) ->
    estun_pool:get_server(Id).

%%====================================================================
%% Simple Discovery
%%====================================================================

%% @doc Discover public address using default server
-spec discover() -> {ok, #stun_addr{}} | {error, term()}.
discover() ->
    case estun_pool:get_default_server() of
        {ok, Server} ->
            discover(Server#stun_server.id);
        Error ->
            Error
    end.

%% @doc Discover public address using specified server
-spec discover(server_id()) -> {ok, #stun_addr{}} | {error, term()}.
discover(ServerId) ->
    case estun_pool:get_server(ServerId) of
        {ok, Server} ->
            case estun_socket:open(#{family => Server#stun_server.family}) of
                {ok, Socket} ->
                    try
                        do_binding(Socket, Server)
                    after
                        estun_socket:close(Socket)
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Perform a binding request (alias for discover/1)
-spec bind(server_id()) -> {ok, #stun_addr{}} | {error, term()}.
bind(ServerId) ->
    discover(ServerId).

%% @doc Perform a binding request with options
-spec bind(server_id(), map()) -> {ok, #stun_addr{}} | {error, term()}.
bind(ServerId, _Opts) ->
    %% Options reserved for future use (timeout, retries, etc.)
    discover(ServerId).

%%====================================================================
%% NAT Discovery
%%====================================================================

%% @doc Discover NAT behavior using RFC 5780 tests
-spec discover_nat(server_id()) -> {ok, #nat_behavior{}} | {error, term()}.
discover_nat(ServerId) ->
    discover_nat(ServerId, #{}).

%% @doc Discover NAT behavior with options
-spec discover_nat(server_id(), map()) -> {ok, #nat_behavior{}} | {error, term()}.
discover_nat(ServerId, Opts) ->
    case estun_pool:get_server(ServerId) of
        {ok, Server} ->
            case estun_socket:open(#{family => Server#stun_server.family}) of
                {ok, Socket} ->
                    try
                        estun_nat_discovery:discover(Socket, Server, Opts)
                    after
                        estun_socket:close(Socket)
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%%====================================================================
%% Socket Management (for hole punching)
%%====================================================================

%% @doc Open a socket for STUN operations
-spec open_socket() -> {ok, socket_ref()} | {error, term()}.
open_socket() ->
    open_socket(#{}).

%% @doc Open a socket with options
-spec open_socket(socket_opts()) -> {ok, socket_ref()} | {error, term()}.
open_socket(Opts) ->
    SocketOpts = maps:merge(#{
        family => inet,
        type => dgram,
        protocol => udp,
        reuse_addr => true,
        reuse_port => true
    }, Opts),
    estun_client_sup:start_client(SocketOpts).

%% @doc Bind socket to discover public address
-spec bind_socket(socket_ref(), server_id() | default) ->
    {ok, #stun_addr{}} | {error, term()}.
bind_socket(SocketRef, default) ->
    case estun_pool:get_default_server() of
        {ok, Server} ->
            estun_client:bind(SocketRef, Server);
        Error ->
            Error
    end;
bind_socket(SocketRef, ServerId) ->
    case estun_pool:get_server(ServerId) of
        {ok, Server} ->
            estun_client:bind(SocketRef, Server);
        Error ->
            Error
    end.

%% @doc Bind socket with timeout
-spec bind_socket(socket_ref(), server_id() | default, timeout()) ->
    {ok, #stun_addr{}} | {error, term()}.
bind_socket(SocketRef, default, Timeout) ->
    case estun_pool:get_default_server() of
        {ok, Server} ->
            estun_client:bind(SocketRef, Server, Timeout);
        Error ->
            Error
    end;
bind_socket(SocketRef, ServerId, Timeout) ->
    case estun_pool:get_server(ServerId) of
        {ok, Server} ->
            estun_client:bind(SocketRef, Server, Timeout);
        Error ->
            Error
    end.

%% @doc Get current mapped address
-spec get_mapped_address(socket_ref()) -> {ok, #stun_addr{}} | {error, not_bound}.
get_mapped_address(SocketRef) ->
    estun_client:get_mapped_address(SocketRef).

%% @doc Get binding info including lifetime
-spec get_binding_info(socket_ref()) -> {ok, map()} | {error, not_bound}.
get_binding_info(SocketRef) ->
    estun_client:get_binding_info(SocketRef).

%% @doc Transfer socket ownership for direct use
-spec transfer_socket(socket_ref()) ->
    {ok, estun_socket:socket(), #stun_addr{}} | {error, term()}.
transfer_socket(SocketRef) ->
    estun_client:transfer(SocketRef).

%% @doc Close a socket
-spec close_socket(socket_ref()) -> ok.
close_socket(SocketRef) ->
    estun_client:stop(SocketRef).

%%====================================================================
%% Keepalive
%%====================================================================

%% @doc Start keepalive to maintain NAT binding
-spec start_keepalive(socket_ref(), pos_integer()) -> ok.
start_keepalive(SocketRef, IntervalSecs) ->
    estun_client:start_keepalive(SocketRef, IntervalSecs * 1000).

%% @doc Stop keepalive
-spec stop_keepalive(socket_ref()) -> ok.
stop_keepalive(SocketRef) ->
    estun_client:stop_keepalive(SocketRef).

%%====================================================================
%% Event Handling
%%====================================================================

%% @doc Set event handler for binding lifecycle notifications
-spec set_event_handler(socket_ref(), estun_client:event_handler()) -> ok.
set_event_handler(SocketRef, Handler) ->
    estun_client:set_event_handler(SocketRef, Handler).

%%====================================================================
%% Hole Punching
%%====================================================================

%% @doc Attempt UDP hole punch to peer
-spec punch(socket_ref(), inet:ip_address(), inet:port_number()) ->
    {ok, connected} | {error, term()}.
punch(SocketRef, PeerIP, PeerPort) ->
    punch(SocketRef, PeerIP, PeerPort, #{}).

%% @doc Attempt UDP hole punch with options
-spec punch(socket_ref(), inet:ip_address(), inet:port_number(), punch_opts()) ->
    {ok, connected} | {error, term()}.
punch(SocketRef, PeerIP, PeerPort, Opts) ->
    Timeout = maps:get(timeout, Opts, 5000),
    Attempts = maps:get(attempts, Opts, 10),
    Interval = maps:get(interval, Opts, 50),
    case estun_client:get_socket(SocketRef) of
        {ok, Socket} ->
            estun_punch:start(Socket, {PeerIP, PeerPort}, Attempts, Interval, Timeout);
        Error ->
            Error
    end.

%%====================================================================
%% Internal
%%====================================================================

do_binding(Socket, Server) ->
    TxnId = estun_codec:make_transaction_id(),
    Msg = estun_codec:encode_binding_request(TxnId),
    Addr = resolve_host(Server#stun_server.host),
    case estun_socket:send(Socket, {Addr, Server#stun_server.port}, Msg) of
        ok ->
            wait_binding_response(Socket, TxnId, 5000, 0);
        Error ->
            Error
    end.

wait_binding_response(Socket, TxnId, Timeout, Retries) when Retries < 7 ->
    RTO = min(500 bsl Retries, 8000),
    WaitTime = min(RTO, Timeout),
    case estun_socket:recv(Socket, WaitTime) of
        {ok, {_Addr, _Port}, Bin} ->
            case estun_codec:decode(Bin) of
                {ok, #stun_msg{transaction_id = TxnId, class = success} = Msg} ->
                    ProcessedMsg = process_xor_addresses(Msg, TxnId),
                    {ok, estun_attrs:get_mapped_address(ProcessedMsg)};
                {ok, #stun_msg{transaction_id = TxnId, class = error} = Msg} ->
                    {error, estun_attrs:get_error(Msg)};
                _ ->
                    wait_binding_response(Socket, TxnId, Timeout - WaitTime, Retries)
            end;
        {error, timeout} when Retries < 6 ->
            wait_binding_response(Socket, TxnId, Timeout - WaitTime, Retries + 1);
        {error, timeout} ->
            {error, timeout};
        Error ->
            Error
    end;
wait_binding_response(_Socket, _TxnId, _Timeout, _Retries) ->
    {error, timeout}.

process_xor_addresses(#stun_msg{attributes = Attrs} = Msg, TxnId) ->
    NewAttrs = lists:map(fun
        ({xor_mapped_address_raw, Family, Port, XAddr}) ->
            Addr = estun_crypto:decode_xor_address(Family, <<Port:16, XAddr/binary>>, TxnId),
            {xor_mapped_address, Addr};
        (Attr) ->
            Attr
    end, Attrs),
    Msg#stun_msg{attributes = NewAttrs}.

resolve_host(Host) when is_tuple(Host) ->
    Host;
resolve_host(Host) when is_atom(Host) ->
    resolve_host(atom_to_list(Host));
resolve_host(Host) when is_binary(Host) ->
    resolve_host(binary_to_list(Host));
resolve_host(Host) when is_list(Host) ->
    case inet:getaddr(Host, inet) of
        {ok, Addr} -> Addr;
        {error, _} ->
            case inet:getaddr(Host, inet6) of
                {ok, Addr6} -> Addr6;
                {error, Reason} -> error({resolve_failed, Host, Reason})
            end
    end.
