# estun_nat_discovery Module

NAT behavior discovery (RFC 5780).

## Overview

This module implements RFC 5780 tests to determine NAT mapping and filtering
behavior, which helps predict hole punching success.

## Types

```erlang
-record(nat_behavior, {
    mapped_address      :: #stun_addr{} | undefined,
    mapping_behavior    :: endpoint_independent | address_dependent |
                           address_port_dependent | unknown,
    filtering_behavior  :: endpoint_independent | address_dependent |
                           address_port_dependent | unknown,
    nat_present         :: boolean() | unknown,
    hairpin_supported   :: boolean() | unknown,
    binding_lifetime    :: pos_integer() | unknown
}).
```

## Functions

### discover/2, discover/3

Discover NAT behavior.

```erlang
-spec discover(socket:socket(), #stun_server{}) ->
    {ok, #nat_behavior{}} | {error, term()}.
-spec discover(socket:socket(), #stun_server{}, map()) ->
    {ok, #nat_behavior{}} | {error, term()}.
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeout` | `pos_integer()` | 5000 | Test timeout (ms) |

**Example:**

```erlang
{ok, Socket} = estun_socket:open(#{family => inet}),
Server = #stun_server{host = "stun.example.com", port = 3478},

case estun_nat_discovery:discover(Socket, Server) of
    {ok, Behavior} ->
        io:format("Mapping: ~p~n", [Behavior#nat_behavior.mapping_behavior]),
        io:format("Filtering: ~p~n", [Behavior#nat_behavior.filtering_behavior]);
    {error, Reason} ->
        io:format("Discovery failed: ~p~n", [Reason])
end.
```

### discover_lifetime/2

Discover NAT binding lifetime.

```erlang
-spec discover_lifetime(socket:socket(), #stun_server{}) ->
    {ok, pos_integer()} | {error, term()}.
```

!!! warning "Long Running"
    Lifetime discovery can take several minutes as it uses
    binary search to find the actual binding timeout.

## RFC 5780 Tests

### Test I: Basic Binding

Initial binding request to determine:

- Public mapped address
- Whether OTHER-ADDRESS is available (RFC 5780 support)

### Test II: Alternate IP

Send to server's alternate IP (same port):

- Same mapping → Endpoint Independent
- Different mapping → Continue to Test III

### Test III: Alternate IP and Port

Send to server's alternate IP and port:

- Same as Test I → Address Dependent
- Different → Address and Port Dependent

### Test IV: Filtering (Change IP+Port)

Request server to respond from different IP and port:

- Response received → Endpoint Independent Filtering
- Timeout → Continue to Test V

### Test V: Filtering (Change Port Only)

Request server to respond from different port only:

- Response received → Address Dependent Filtering
- Timeout → Address and Port Dependent Filtering

## NAT Behavior Types

### Mapping Behavior

| Type | Description | Hole Punch |
|------|-------------|------------|
| Endpoint Independent | Same ext. port for all destinations | Easy |
| Address Dependent | Different port per dest. IP | Medium |
| Address+Port Dependent | Different port per dest. IP:port | Hard |

### Filtering Behavior

| Type | Description |
|------|-------------|
| Endpoint Independent | Accepts packets from any source |
| Address Dependent | Only from previously contacted IPs |
| Address+Port Dependent | Only from contacted IP:port pairs |

## Server Requirements

!!! important "RFC 5780 Support Required"
    NAT behavior discovery requires a STUN server that supports
    RFC 5780, indicated by the presence of `OTHER-ADDRESS` attribute.

    Most public STUN servers (including Google's) do NOT support RFC 5780.
    You may need to run your own compliant server.

### Checking Server Support

```erlang
check_rfc5780_support(ServerId) ->
    {ok, Socket} = estun_socket:open(#{family => inet}),
    {ok, Server} = estun:get_server(ServerId),

    %% Try discovery
    case estun_nat_discovery:discover(Socket, Server) of
        {ok, #nat_behavior{mapping_behavior = unknown,
                          filtering_behavior = unknown}} ->
            io:format("Server does NOT support RFC 5780~n");
        {ok, _} ->
            io:format("Server supports RFC 5780~n");
        {error, _} ->
            io:format("Could not determine support~n")
    end,

    estun_socket:close(Socket).
```

## Example: Full Analysis

```erlang
-module(nat_analyzer).
-export([analyze/1]).

-include_lib("estun/include/estun.hrl").

analyze(ServerId) ->
    {ok, Server} = estun:get_server(ServerId),
    {ok, Socket} = estun_socket:open(#{family => inet}),

    io:format("~n=== NAT Analysis ===~n"),
    io:format("Server: ~s:~p~n", [Server#stun_server.host, Server#stun_server.port]),

    case estun_nat_discovery:discover(Socket, Server) of
        {ok, B} ->
            io:format("~nResults:~n"),
            io:format("  Public Address: ~p:~p~n", [
                B#nat_behavior.mapped_address#stun_addr.address,
                B#nat_behavior.mapped_address#stun_addr.port
            ]),
            io:format("  Behind NAT: ~p~n", [B#nat_behavior.nat_present]),
            io:format("  Mapping: ~p~n", [B#nat_behavior.mapping_behavior]),
            io:format("  Filtering: ~p~n", [B#nat_behavior.filtering_behavior]),
            io:format("  Hairpin: ~p~n", [B#nat_behavior.hairpin_supported]),

            %% Recommendation
            io:format("~nRecommendation: ~s~n", [
                recommend(B#nat_behavior.mapping_behavior)
            ]);
        {error, Reason} ->
            io:format("Analysis failed: ~p~n", [Reason])
    end,

    estun_socket:close(Socket).

recommend(endpoint_independent) ->
    "Hole punching should work well";
recommend(address_dependent) ->
    "Hole punching possible with proper timing";
recommend(address_port_dependent) ->
    "Consider using TURN relay for reliability";
recommend(unknown) ->
    "Could not determine - server may not support RFC 5780".
```
