# Basic Usage

This guide covers the fundamental operations with estun.

## Managing STUN Servers

### Adding Servers

```erlang
%% Add with auto-generated ID
{ok, ServerId} = estun:add_server(#{
    host => "stun.l.google.com",
    port => 19302
}).

%% Add with custom ID
{ok, my_server} = estun:add_server(#{
    host => "stun.example.com",
    port => 3478
}, my_server).
```

### Listing Servers

```erlang
Servers = estun:list_servers().
%% Returns: [{ServerId, #stun_server{}}]

lists:foreach(fun({Id, Server}) ->
    io:format("~p: ~s:~p~n", [
        Id,
        Server#stun_server.host,
        Server#stun_server.port
    ])
end, Servers).
```

### Removing Servers

```erlang
ok = estun:remove_server(ServerId).
```

### Getting Server Details

```erlang
{ok, Server} = estun:get_server(ServerId).
io:format("Host: ~p~n", [Server#stun_server.host]).
```

## Discovering Your Public Address

### Simple Discovery

```erlang
%% Using default server
{ok, Addr} = estun:discover().

%% Using specific server
{ok, Addr} = estun:discover(ServerId).

%% Access address components
#stun_addr{
    family = Family,    %% ipv4 | ipv6
    address = IP,       %% {A,B,C,D} or {A,B,C,D,E,F,G,H}
    port = Port         %% 1-65535
} = Addr.
```

### Understanding the Result

The `#stun_addr{}` record contains:

| Field | Type | Description |
|-------|------|-------------|
| `family` | `ipv4 \| ipv6` | Address family |
| `address` | `inet:ip_address()` | Your public IP |
| `port` | `1..65535` | Your mapped port |

### Handling Errors

```erlang
case estun:discover() of
    {ok, Addr} ->
        io:format("Public: ~p:~p~n", [Addr#stun_addr.address, Addr#stun_addr.port]);
    {error, timeout} ->
        io:format("Request timed out~n");
    {error, {Code, Reason}} ->
        io:format("STUN error ~p: ~s~n", [Code, Reason]);
    {error, Reason} ->
        io:format("Error: ~p~n", [Reason])
end.
```

## Working with Sockets

For hole punching, you need persistent sockets:

### Opening a Socket

```erlang
%% Default options
{ok, SocketRef} = estun:open_socket().

%% With custom options
{ok, SocketRef} = estun:open_socket(#{
    family => inet,
    local_port => 5000,    %% Use specific port
    reuse_port => true
}).
```

### Binding to Discover Address

```erlang
%% Bind using default server
{ok, MappedAddr} = estun:bind_socket(SocketRef, default).

%% Bind using specific server
{ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId).

%% With timeout
{ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId, 10000).
```

### Getting Binding Information

```erlang
%% Get current mapped address
{ok, Addr} = estun:get_mapped_address(SocketRef).

%% Get full binding info
{ok, Info} = estun:get_binding_info(SocketRef).
%% Info = #{
%%     mapped_address => #stun_addr{},
%%     created_at => Timestamp,
%%     last_refresh => Timestamp,
%%     lifetime => Seconds | unknown,
%%     remaining => Seconds | unknown,
%%     server => #stun_server{}
%% }
```

### Closing a Socket

```erlang
ok = estun:close_socket(SocketRef).
```

## Maintaining NAT Bindings

NAT bindings expire over time. Use keepalive to maintain them:

```erlang
%% Start keepalive (interval in seconds)
ok = estun:start_keepalive(SocketRef, 25).

%% Stop keepalive
ok = estun:stop_keepalive(SocketRef).
```

!!! tip "Keepalive Interval"
    A 25-30 second interval works well for most NATs.
    Some aggressive NATs may require 15-20 seconds.

## Transferring Sockets

After hole punching, transfer the socket for direct use:

```erlang
%% Transfer ownership to calling process
{ok, RawSocket, MappedAddr} = estun:transfer_socket(SocketRef).

%% Now use the raw socket directly
socket:sendto(RawSocket, <<"Hello">>, #{addr => PeerIP, port => PeerPort}).
```

## Complete Example

```erlang
-module(basic_example).
-export([run/0]).

-include_lib("estun/include/estun.hrl").

run() ->
    %% Start application
    {ok, _} = application:ensure_all_started(estun),

    %% Add servers
    {ok, _} = estun:add_server(#{
        host => "stun.l.google.com",
        port => 19302
    }, google),

    %% Simple discovery
    io:format("~n=== Simple Discovery ===~n"),
    {ok, Addr1} = estun:discover(google),
    io:format("Public address: ~p:~p~n", [
        Addr1#stun_addr.address,
        Addr1#stun_addr.port
    ]),

    %% Socket-based discovery
    io:format("~n=== Socket Discovery ===~n"),
    {ok, SocketRef} = estun:open_socket(),
    {ok, Addr2} = estun:bind_socket(SocketRef, google),
    io:format("Mapped address: ~p:~p~n", [
        Addr2#stun_addr.address,
        Addr2#stun_addr.port
    ]),

    %% Get binding info
    {ok, Info} = estun:get_binding_info(SocketRef),
    io:format("Binding info: ~p~n", [Info]),

    %% Cleanup
    estun:close_socket(SocketRef),
    ok.
```
