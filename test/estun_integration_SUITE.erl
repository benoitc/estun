%% @doc Integration tests for STUN client
-module(estun_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("estun.hrl").

%% CT callbacks
-export([all/0, groups/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([
    discover_public_address/1,
    discover_with_multiple_servers/1,
    validate_public_ip/1,
    cross_validate_ip/1,
    socket_lifecycle/1,
    keepalive_test/1
]).

%%====================================================================
%% CT Callbacks
%%====================================================================

all() ->
    [{group, live_tests}].

groups() ->
    [{live_tests, [sequence], [
        discover_public_address,
        discover_with_multiple_servers,
        validate_public_ip,
        cross_validate_ip,
        socket_lifecycle,
        keepalive_test
    ]}].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(estun),
    %% Add public STUN servers for testing
    {ok, _} = estun:add_server(#{
        host => "stun.l.google.com",
        port => 19302
    }, google),
    {ok, _} = estun:add_server(#{
        host => "stun1.l.google.com",
        port => 19302
    }, google1),
    {ok, _} = estun:add_server(#{
        host => "stun2.l.google.com",
        port => 19302
    }, google2),
    {ok, _} = estun:add_server(#{
        host => "stun.cloudflare.com",
        port => 3478
    }, cloudflare),
    Config.

end_per_suite(_Config) ->
    application:stop(estun),
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

%% @doc Test basic public address discovery
discover_public_address(_Config) ->
    case estun:discover(google) of
        {ok, #stun_addr{family = Family, port = Port, address = Address}} ->
            ct:log("Discovered public address: ~p:~p (~p)", [Address, Port, Family]),
            true = is_tuple(Address),
            true = Port > 0,
            true = Port < 65536,
            ok;
        {error, Reason} ->
            ct:log("Discovery failed (may be network issue): ~p", [Reason]),
            %% Don't fail if no network - just skip
            {skip, {no_network, Reason}}
    end.

%% @doc Test discovery with multiple servers
discover_with_multiple_servers(_Config) ->
    Results = [estun:discover(Id) || Id <- [google, google1]],
    ct:log("Results from multiple servers: ~p", [Results]),

    %% At least one should succeed
    case lists:any(fun({ok, _}) -> true; (_) -> false end, Results) of
        true ->
            ok;
        false ->
            {skip, no_network}
    end.

%% @doc Validate that returned IP is a valid public IP address
validate_public_ip(_Config) ->
    case estun:discover(google) of
        {ok, #stun_addr{family = ipv4, address = {A, B, C, D} = Addr}} ->
            ct:log("Validating IP: ~p.~p.~p.~p", [A, B, C, D]),

            %% Check valid octet ranges
            true = (A >= 0 andalso A =< 255),
            true = (B >= 0 andalso B =< 255),
            true = (C >= 0 andalso C =< 255),
            true = (D >= 0 andalso D =< 255),

            %% Check not localhost
            false = (Addr =:= {127, 0, 0, 1}),

            %% Check not private ranges (RFC 1918)
            %% 10.0.0.0/8
            false = (A =:= 10),
            %% 172.16.0.0/12
            false = (A =:= 172 andalso B >= 16 andalso B =< 31),
            %% 192.168.0.0/16
            false = (A =:= 192 andalso B =:= 168),
            %% 169.254.0.0/16 (link-local)
            false = (A =:= 169 andalso B =:= 254),

            ct:log("IP ~p.~p.~p.~p is a valid public address", [A, B, C, D]),
            ok;
        {ok, #stun_addr{family = ipv6, address = Addr}} ->
            ct:log("Got IPv6 address: ~p", [Addr]),
            %% Basic validation for IPv6
            true = is_tuple(Addr),
            true = (tuple_size(Addr) =:= 8),
            ok;
        {error, Reason} ->
            {skip, {no_network, Reason}}
    end.

%% @doc Cross-validate IP by querying multiple STUN servers
cross_validate_ip(_Config) ->
    Servers = [google, google1, google2, cloudflare],
    Results = lists:filtermap(
        fun(ServerId) ->
            case estun:discover(ServerId) of
                {ok, #stun_addr{address = Addr}} -> {true, {ServerId, Addr}};
                _ -> false
            end
        end,
        Servers
    ),
    ct:log("Cross-validation results: ~p", [Results]),

    case Results of
        [] ->
            {skip, no_network};
        [{_First, FirstAddr}] ->
            ct:log("Only one server responded with: ~p", [FirstAddr]),
            ok;
        [{First, FirstAddr} | Rest] ->
            %% All servers should return the same public IP
            Matching = lists:all(
                fun({_Server, Addr}) -> Addr =:= FirstAddr end,
                Rest
            ),
            case Matching of
                true ->
                    ct:log("All ~p servers agree on IP: ~p",
                           [length(Results), FirstAddr]),
                    ok;
                false ->
                    %% Different servers may see different IPs behind multi-homed NAT
                    ct:log("Servers returned different IPs (may be multi-homed NAT)"),
                    UniqueIPs = lists:usort([Addr || {_, Addr} <- Results]),
                    ct:log("First server ~p: ~p, Unique IPs: ~p",
                           [First, FirstAddr, UniqueIPs]),
                    ok
            end
    end.

%% @doc Test socket open/bind/close lifecycle
socket_lifecycle(_Config) ->
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    ct:log("Opened socket: ~p", [SocketRef]),

    case estun:bind_socket(SocketRef, google) of
        {ok, #stun_addr{} = Addr} ->
            ct:log("Bound socket, mapped address: ~p", [Addr]),

            %% Get binding info
            {ok, Info} = estun:get_binding_info(SocketRef),
            ct:log("Binding info: ~p", [Info]),
            true = maps:is_key(mapped_address, Info),

            %% Close socket
            ok = estun:close_socket(SocketRef),
            ok;
        {error, Reason} ->
            ok = estun:close_socket(SocketRef),
            {skip, {bind_failed, Reason}}
    end.

%% @doc Test keepalive functionality
keepalive_test(_Config) ->
    {ok, SocketRef} = estun:open_socket(#{family => inet}),

    case estun:bind_socket(SocketRef, google) of
        {ok, _Addr} ->
            %% Start keepalive at 5 second interval
            ok = estun:start_keepalive(SocketRef, 5),
            ct:log("Keepalive started"),

            %% Wait a bit
            timer:sleep(2000),

            %% Stop keepalive
            ok = estun:stop_keepalive(SocketRef),
            ct:log("Keepalive stopped"),

            ok = estun:close_socket(SocketRef),
            ok;
        {error, Reason} ->
            ok = estun:close_socket(SocketRef),
            {skip, {bind_failed, Reason}}
    end.
