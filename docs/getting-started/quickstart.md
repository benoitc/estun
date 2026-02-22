# Quick Start

This guide will get you up and running with estun in 5 minutes.

## Step 1: Start the Application

```erlang
application:ensure_all_started(estun).
```

## Step 2: Add a STUN Server

```erlang
{ok, ServerId} = estun:add_server(#{
    host => "stun.l.google.com",
    port => 19302
}).
```

## Step 3: Discover Your Public Address

```erlang
{ok, #stun_addr{family = ipv4, address = IP, port = Port}} = estun:discover().
io:format("Your public address: ~p:~p~n", [IP, Port]).
```

That's it! You've discovered your public IP address as seen from the internet.

## Complete Example

Here's a complete example module:

```erlang
-module(stun_example).
-export([discover_my_address/0]).

-include_lib("estun/include/estun.hrl").

discover_my_address() ->
    %% Ensure application is started
    application:ensure_all_started(estun),

    %% Add Google's public STUN server
    {ok, _} = estun:add_server(#{
        host => "stun.l.google.com",
        port => 19302
    }),

    %% Discover public address
    case estun:discover() of
        {ok, #stun_addr{address = IP, port = Port}} ->
            io:format("Public IP: ~p~n", [IP]),
            io:format("Public Port: ~p~n", [Port]),
            {ok, {IP, Port}};
        {error, Reason} ->
            io:format("Discovery failed: ~p~n", [Reason]),
            {error, Reason}
    end.
```

## Using Multiple STUN Servers

For reliability, add multiple servers:

```erlang
%% Add multiple servers
estun:add_server(#{host => "stun.l.google.com", port => 19302}, google1),
estun:add_server(#{host => "stun1.l.google.com", port => 19302}, google2),
estun:add_server(#{host => "stun2.l.google.com", port => 19302}, google3),

%% List all servers
Servers = estun:list_servers(),
io:format("Configured servers: ~p~n", [Servers]).

%% Discover using a specific server
{ok, Addr} = estun:discover(google2).
```

## What's Next?

- [Configuration Guide](configuration.md) - Learn about all configuration options
- [NAT Discovery](../guide/nat-discovery.md) - Determine your NAT type
- [Hole Punching](../guide/hole-punching.md) - Establish P2P connections
- [API Reference](../api/estun.md) - Complete API documentation
