# NAT Discovery

This guide explains how to use estun to discover your NAT type and behavior.

## Understanding NAT Types

NAT devices are classified by two behaviors:

### Mapping Behavior

How the NAT creates external mappings:

| Type | Description | Hole Punching |
|------|-------------|---------------|
| **Endpoint Independent** | Same external IP:port for all destinations | Easy |
| **Address Dependent** | Different mapping per destination IP | Medium |
| **Address+Port Dependent** | Different mapping per destination IP:port | Hard |

### Filtering Behavior

Which incoming packets the NAT allows:

| Type | Description |
|------|-------------|
| **Endpoint Independent** | Accepts from any source |
| **Address Dependent** | Only from contacted IPs |
| **Address+Port Dependent** | Only from contacted IP:port pairs |

## Classic NAT Types

The combination of behaviors creates classic NAT types:

| NAT Type | Mapping | Filtering |
|----------|---------|-----------|
| Full Cone | Endpoint Independent | Endpoint Independent |
| Restricted Cone | Endpoint Independent | Address Dependent |
| Port Restricted Cone | Endpoint Independent | Address+Port Dependent |
| Symmetric | Address+Port Dependent | Address+Port Dependent |

## Discovering NAT Behavior

!!! note "Server Requirements"
    NAT behavior discovery requires a STUN server that supports
    RFC 5780 (has alternate IP/port). Google's public servers
    don't support this. You may need to run your own server.

### Basic Discovery

```erlang
%% Add an RFC 5780 compatible server
{ok, _} = estun:add_server(#{
    host => "stun.example.com",  %% Must support RFC 5780
    port => 3478
}, rfc5780_server).

%% Discover NAT behavior
{ok, Behavior} = estun:discover_nat(rfc5780_server).
```

### Interpreting Results

```erlang
-include_lib("estun/include/estun.hrl").

analyze_nat(ServerId) ->
    case estun:discover_nat(ServerId) of
        {ok, #nat_behavior{
            mapped_address = Addr,
            mapping_behavior = Mapping,
            filtering_behavior = Filtering,
            nat_present = NatPresent,
            hairpin_supported = Hairpin
        }} ->
            io:format("~n=== NAT Analysis ===~n"),
            io:format("Public Address: ~p:~p~n", [
                Addr#stun_addr.address,
                Addr#stun_addr.port
            ]),
            io:format("Behind NAT: ~p~n", [NatPresent]),
            io:format("Mapping Behavior: ~p~n", [Mapping]),
            io:format("Filtering Behavior: ~p~n", [Filtering]),
            io:format("Hairpin Support: ~p~n", [Hairpin]),

            %% Determine NAT type
            NatType = classify_nat(Mapping, Filtering),
            io:format("NAT Type: ~s~n", [NatType]),

            %% Hole punching feasibility
            Feasibility = assess_hole_punching(Mapping, Filtering),
            io:format("Hole Punching: ~s~n", [Feasibility]);

        {error, Reason} ->
            io:format("Discovery failed: ~p~n", [Reason])
    end.

classify_nat(endpoint_independent, endpoint_independent) ->
    "Full Cone NAT";
classify_nat(endpoint_independent, address_dependent) ->
    "Restricted Cone NAT";
classify_nat(endpoint_independent, address_port_dependent) ->
    "Port Restricted Cone NAT";
classify_nat(address_port_dependent, _) ->
    "Symmetric NAT";
classify_nat(_, _) ->
    "Unknown".

assess_hole_punching(endpoint_independent, _) ->
    "High success probability";
assess_hole_punching(address_dependent, _) ->
    "Medium success probability";
assess_hole_punching(address_port_dependent, _) ->
    "Low success probability - consider TURN relay".
```

## NAT Behavior Record

The `#nat_behavior{}` record contains:

```erlang
-record(nat_behavior, {
    %% Your public address
    mapped_address :: #stun_addr{},

    %% How NAT creates mappings
    mapping_behavior :: endpoint_independent |
                        address_dependent |
                        address_port_dependent |
                        unknown,

    %% How NAT filters incoming packets
    filtering_behavior :: endpoint_independent |
                          address_dependent |
                          address_port_dependent |
                          unknown,

    %% Whether you're behind a NAT
    nat_present :: boolean() | unknown,

    %% Whether NAT supports hairpinning
    hairpin_supported :: boolean() | unknown,

    %% NAT binding lifetime in seconds
    binding_lifetime :: pos_integer() | unknown
}).
```

## Checking if Behind NAT

```erlang
is_behind_nat() ->
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    {ok, SocketRef} = estun:open_socket(),
    {ok, MappedAddr} = estun:bind_socket(SocketRef, default),

    %% Get local address from binding info
    {ok, Info} = estun:get_binding_info(SocketRef),
    estun:close_socket(SocketRef),

    %% Compare local IP with mapped IP
    %% Note: A full check would get the local socket address
    io:format("Public address: ~p:~p~n", [
        MappedAddr#stun_addr.address,
        MappedAddr#stun_addr.port
    ]),

    %% Check if address is private (RFC 1918)
    case MappedAddr#stun_addr.address of
        {10, _, _, _} -> false;
        {172, B, _, _} when B >= 16, B =< 31 -> false;
        {192, 168, _, _} -> false;
        _ ->
            io:format("Behind NAT (public IP differs from local)~n"),
            true
    end.
```

## Practical Recommendations

### Based on NAT Type

```erlang
recommend_strategy(Mapping, Filtering) ->
    case {Mapping, Filtering} of
        {endpoint_independent, _} ->
            %% Best case - standard hole punching works
            #{
                strategy => direct_hole_punch,
                success_rate => high,
                notes => "Use simultaneous open technique"
            };

        {address_dependent, endpoint_independent} ->
            %% Good - need to send first
            #{
                strategy => direct_hole_punch,
                success_rate => medium,
                notes => "Initiator must send packets first"
            };

        {address_dependent, _} ->
            %% Moderate difficulty
            #{
                strategy => direct_hole_punch,
                success_rate => medium,
                notes => "May require multiple attempts"
            };

        {address_port_dependent, _} ->
            %% Symmetric NAT - hardest case
            #{
                strategy => turn_relay,
                success_rate => low_for_direct,
                notes => "Consider TURN relay for reliability"
            };

        _ ->
            #{
                strategy => unknown,
                success_rate => unknown,
                notes => "Could not determine NAT behavior"
            }
    end.
```

## Complete Example

```erlang
-module(nat_analysis).
-export([analyze/0]).

-include_lib("estun/include/estun.hrl").

analyze() ->
    application:ensure_all_started(estun),

    %% Try multiple servers
    Servers = [
        #{host => "stun.l.google.com", port => 19302}
    ],

    lists:foreach(fun(Config) ->
        {ok, Id} = estun:add_server(Config),
        io:format("~nTesting server: ~p~n", [Config]),

        case estun:discover_nat(Id) of
            {ok, Behavior} ->
                print_behavior(Behavior);
            {error, Reason} ->
                io:format("  Error: ~p~n", [Reason])
        end
    end, Servers).

print_behavior(#nat_behavior{} = B) ->
    io:format("  Mapped Address: ~p:~p~n", [
        B#nat_behavior.mapped_address#stun_addr.address,
        B#nat_behavior.mapped_address#stun_addr.port
    ]),
    io:format("  NAT Present: ~p~n", [B#nat_behavior.nat_present]),
    io:format("  Mapping: ~p~n", [B#nat_behavior.mapping_behavior]),
    io:format("  Filtering: ~p~n", [B#nat_behavior.filtering_behavior]).
```
