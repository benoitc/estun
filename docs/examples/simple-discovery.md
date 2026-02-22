# Simple Discovery Example

This example shows basic public IP discovery using STUN.

## Basic Discovery

```erlang
-module(simple_discovery).
-export([main/0]).

-include_lib("estun/include/estun.hrl").

main() ->
    %% Start application
    {ok, _} = application:ensure_all_started(estun),

    %% Add STUN servers
    {ok, _} = estun:add_server(#{
        host => "stun.l.google.com",
        port => 19302
    }, google),

    %% Discover public address
    case estun:discover(google) of
        {ok, #stun_addr{family = Family, address = IP, port = Port}} ->
            io:format("~n=== STUN Discovery Results ===~n"),
            io:format("Family: ~p~n", [Family]),
            io:format("Public IP: ~s~n", [format_ip(IP)]),
            io:format("Mapped Port: ~p~n", [Port]),
            {ok, {IP, Port}};
        {error, Reason} ->
            io:format("Discovery failed: ~p~n", [Reason]),
            {error, Reason}
    end.

format_ip({A, B, C, D}) ->
    io_lib:format("~p.~p.~p.~p", [A, B, C, D]);
format_ip({A, B, C, D, E, F, G, H}) ->
    io_lib:format("~.16B:~.16B:~.16B:~.16B:~.16B:~.16B:~.16B:~.16B",
                  [A, B, C, D, E, F, G, H]).
```

## Multiple Servers for Reliability

```erlang
-module(reliable_discovery).
-export([discover/0]).

-include_lib("estun/include/estun.hrl").

discover() ->
    application:ensure_all_started(estun),

    %% Add multiple servers
    Servers = [
        {google1, #{host => "stun.l.google.com", port => 19302}},
        {google2, #{host => "stun1.l.google.com", port => 19302}},
        {google3, #{host => "stun2.l.google.com", port => 19302}}
    ],

    lists:foreach(fun({Id, Config}) ->
        estun:add_server(Config, Id)
    end, Servers),

    %% Try servers until one succeeds
    try_servers([google1, google2, google3]).

try_servers([]) ->
    {error, all_servers_failed};
try_servers([Server | Rest]) ->
    case estun:discover(Server) of
        {ok, Addr} ->
            io:format("Discovered via ~p: ~p:~p~n", [
                Server,
                Addr#stun_addr.address,
                Addr#stun_addr.port
            ]),
            {ok, Addr};
        {error, _Reason} ->
            io:format("Server ~p failed, trying next...~n", [Server]),
            try_servers(Rest)
    end.
```

## Periodic Discovery

```erlang
-module(periodic_discovery).
-export([start/1, stop/1]).

-include_lib("estun/include/estun.hrl").

-record(state, {
    server_id,
    interval,
    last_addr,
    callback
}).

start(Opts) ->
    ServerId = maps:get(server, Opts, default),
    Interval = maps:get(interval, Opts, 60000),  %% 1 minute
    Callback = maps:get(callback, Opts, fun default_callback/2),

    spawn_link(fun() ->
        application:ensure_all_started(estun),
        loop(#state{
            server_id = ServerId,
            interval = Interval,
            last_addr = undefined,
            callback = Callback
        })
    end).

stop(Pid) ->
    Pid ! stop.

loop(#state{server_id = ServerId, interval = Interval,
            last_addr = LastAddr, callback = Callback} = State) ->
    case estun:discover(ServerId) of
        {ok, Addr} ->
            case Addr =:= LastAddr of
                true ->
                    ok;  %% No change
                false ->
                    Callback(address_changed, {LastAddr, Addr})
            end,
            NewState = State#state{last_addr = Addr};
        {error, Reason} ->
            Callback(error, Reason),
            NewState = State
    end,

    receive
        stop -> ok
    after Interval ->
        loop(NewState)
    end.

default_callback(address_changed, {undefined, New}) ->
    io:format("Initial address: ~p:~p~n", [
        New#stun_addr.address, New#stun_addr.port
    ]);
default_callback(address_changed, {Old, New}) ->
    io:format("Address changed!~n"),
    io:format("  Old: ~p:~p~n", [Old#stun_addr.address, Old#stun_addr.port]),
    io:format("  New: ~p:~p~n", [New#stun_addr.address, New#stun_addr.port]);
default_callback(error, Reason) ->
    io:format("Discovery error: ~p~n", [Reason]).
```

## Usage

```erlang
%% Basic
1> simple_discovery:main().
=== STUN Discovery Results ===
Family: ipv4
Public IP: 203.0.113.42
Mapped Port: 54321
{ok,{{203,0,113,42},54321}}

%% Reliable
2> reliable_discovery:discover().
Discovered via google1: {203,0,113,42}:54322
{ok,{stun_addr,ipv4,54322,{203,0,113,42}}}

%% Periodic
3> Pid = periodic_discovery:start(#{interval => 30000}).
Initial address: {203,0,113,42}:54323
<0.123.0>

%% Later if address changes...
Address changed!
  Old: {203,0,113,42}:54323
  New: {203,0,113,42}:54324

4> periodic_discovery:stop(Pid).
ok
```

## IPv6 Discovery

```erlang
discover_ipv6() ->
    application:ensure_all_started(estun),

    %% Add IPv6 server
    {ok, _} = estun:add_server(#{
        host => "stun.example.com",
        port => 3478,
        family => inet6
    }, ipv6_server),

    case estun:discover(ipv6_server) of
        {ok, #stun_addr{family = ipv6, address = IP, port = Port}} ->
            io:format("IPv6 address: ~p~n", [IP]),
            io:format("Port: ~p~n", [Port]);
        {error, Reason} ->
            io:format("IPv6 discovery failed: ~p~n", [Reason])
    end.
```
