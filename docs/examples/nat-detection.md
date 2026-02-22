# NAT Type Detection Example

This example shows how to detect NAT type and make connectivity decisions.

## NAT Analyzer Module

```erlang
-module(nat_analyzer).
-export([analyze/0, analyze/1, get_recommendation/0]).

-include_lib("estun/include/estun.hrl").

%% Quick analysis using default server
analyze() ->
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}, default),
    analyze(default).

%% Analyze using specific server
analyze(ServerId) ->
    io:format("~n╔════════════════════════════════════════╗~n"),
    io:format("║         NAT Type Analysis              ║~n"),
    io:format("╚════════════════════════════════════════╝~n~n"),

    case estun:discover_nat(ServerId) of
        {ok, Behavior} ->
            print_results(Behavior),
            print_nat_type(Behavior),
            print_recommendation(Behavior),
            {ok, Behavior};
        {error, Reason} ->
            io:format("Analysis failed: ~p~n", [Reason]),
            io:format("~nNote: Full NAT analysis requires RFC 5780 server support.~n"),
            io:format("Falling back to basic discovery...~n~n"),
            basic_analysis(ServerId)
    end.

basic_analysis(ServerId) ->
    case estun:discover(ServerId) of
        {ok, Addr} ->
            io:format("Public Address: ~p:~p~n", [
                Addr#stun_addr.address,
                Addr#stun_addr.port
            ]),
            io:format("~nBasic discovery successful.~n"),
            io:format("For full NAT analysis, use an RFC 5780 compliant server.~n"),
            {ok, Addr};
        {error, Reason} ->
            io:format("Basic discovery also failed: ~p~n", [Reason]),
            {error, Reason}
    end.

print_results(#nat_behavior{} = B) ->
    io:format("┌─────────────────────────────────────────┐~n"),
    io:format("│ Discovery Results                       │~n"),
    io:format("├─────────────────────────────────────────┤~n"),

    %% Public Address
    case B#nat_behavior.mapped_address of
        #stun_addr{address = IP, port = Port} ->
            io:format("│ Public Address: ~s~n", [
                format_addr(IP, Port)
            ]);
        _ ->
            io:format("│ Public Address: Unknown~n")
    end,

    %% NAT Present
    io:format("│ Behind NAT: ~s~n", [
        format_bool(B#nat_behavior.nat_present)
    ]),

    %% Mapping Behavior
    io:format("│ Mapping: ~s~n", [
        format_behavior(B#nat_behavior.mapping_behavior)
    ]),

    %% Filtering Behavior
    io:format("│ Filtering: ~s~n", [
        format_behavior(B#nat_behavior.filtering_behavior)
    ]),

    %% Hairpin Support
    io:format("│ Hairpin: ~s~n", [
        format_bool(B#nat_behavior.hairpin_supported)
    ]),

    io:format("└─────────────────────────────────────────┘~n~n").

print_nat_type(#nat_behavior{mapping_behavior = M, filtering_behavior = F}) ->
    Type = classify_nat(M, F),
    io:format("┌─────────────────────────────────────────┐~n"),
    io:format("│ NAT Type: ~-29s │~n", [Type]),
    io:format("└─────────────────────────────────────────┘~n~n").

print_recommendation(#nat_behavior{mapping_behavior = M}) ->
    io:format("┌─────────────────────────────────────────┐~n"),
    io:format("│ Recommendation                          │~n"),
    io:format("├─────────────────────────────────────────┤~n"),

    case M of
        endpoint_independent ->
            io:format("│ ✓ Hole punching: HIGH success rate     │~n"),
            io:format("│ ✓ Direct P2P: Recommended              │~n"),
            io:format("│ ○ TURN relay: Not needed               │~n");
        address_dependent ->
            io:format("│ ○ Hole punching: MEDIUM success rate   │~n"),
            io:format("│ ○ Direct P2P: Possible with timing     │~n"),
            io:format("│ ○ TURN relay: Recommended as fallback  │~n");
        address_port_dependent ->
            io:format("│ ✗ Hole punching: LOW success rate      │~n"),
            io:format("│ ✗ Direct P2P: Difficult                │~n"),
            io:format("│ ✓ TURN relay: Strongly recommended     │~n");
        unknown ->
            io:format("│ ? Hole punching: Unknown               │~n"),
            io:format("│ ? Try direct connection first          │~n"),
            io:format("│ ? Have TURN relay ready as fallback    │~n")
    end,

    io:format("└─────────────────────────────────────────┘~n~n").

get_recommendation() ->
    case analyze() of
        {ok, #nat_behavior{mapping_behavior = M}} ->
            case M of
                endpoint_independent ->
                    {direct, "Use direct hole punching"};
                address_dependent ->
                    {direct_with_fallback, "Try direct, have TURN ready"};
                address_port_dependent ->
                    {relay, "Use TURN relay"};
                unknown ->
                    {try_direct, "Try direct first, fallback to TURN"}
            end;
        {ok, _} ->
            {try_direct, "Basic discovery only, try direct"};
        {error, _} ->
            {unknown, "Could not determine NAT type"}
    end.

%% Helpers

classify_nat(endpoint_independent, endpoint_independent) ->
    "Full Cone NAT";
classify_nat(endpoint_independent, address_dependent) ->
    "Restricted Cone NAT";
classify_nat(endpoint_independent, address_port_dependent) ->
    "Port Restricted Cone NAT";
classify_nat(address_dependent, _) ->
    "Address Dependent NAT";
classify_nat(address_port_dependent, _) ->
    "Symmetric NAT";
classify_nat(_, _) ->
    "Unknown".

format_addr({A,B,C,D}, Port) ->
    io_lib:format("~p.~p.~p.~p:~p", [A,B,C,D,Port]);
format_addr(IP, Port) when tuple_size(IP) == 8 ->
    io_lib:format("~p:~p", [IP, Port]).

format_bool(true) -> "Yes";
format_bool(false) -> "No";
format_bool(unknown) -> "Unknown";
format_bool(_) -> "Unknown".

format_behavior(endpoint_independent) -> "Endpoint Independent";
format_behavior(address_dependent) -> "Address Dependent";
format_behavior(address_port_dependent) -> "Address+Port Dependent";
format_behavior(unknown) -> "Unknown";
format_behavior(_) -> "Unknown".
```

## Usage

```erlang
1> nat_analyzer:analyze().

╔════════════════════════════════════════╗
║         NAT Type Analysis              ║
╚════════════════════════════════════════╝

┌─────────────────────────────────────────┐
│ Discovery Results                       │
├─────────────────────────────────────────┤
│ Public Address: 203.0.113.42:54321
│ Behind NAT: Yes
│ Mapping: Endpoint Independent
│ Filtering: Address+Port Dependent
│ Hairpin: Unknown
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ NAT Type: Port Restricted Cone NAT      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Recommendation                          │
├─────────────────────────────────────────┤
│ ✓ Hole punching: HIGH success rate     │
│ ✓ Direct P2P: Recommended              │
│ ○ TURN relay: Not needed               │
└─────────────────────────────────────────┘

{ok,{nat_behavior,...}}
```

## Programmatic Recommendations

```erlang
2> nat_analyzer:get_recommendation().
{direct, "Use direct hole punching"}

%% Use in application logic
case nat_analyzer:get_recommendation() of
    {direct, _} ->
        attempt_hole_punch();
    {direct_with_fallback, _} ->
        case attempt_hole_punch() of
            ok -> ok;
            _ -> use_turn_relay()
        end;
    {relay, _} ->
        use_turn_relay();
    _ ->
        %% Unknown - try direct first
        case attempt_hole_punch() of
            ok -> ok;
            _ -> use_turn_relay()
        end
end.
```

## Comparing Multiple Locations

```erlang
-module(multi_location_test).
-export([test/0]).

test() ->
    application:ensure_all_started(estun),

    %% Test from different perspectives
    Servers = [
        {google, #{host => "stun.l.google.com", port => 19302}},
        {google2, #{host => "stun1.l.google.com", port => 19302}}
    ],

    lists:foreach(fun({Id, Config}) ->
        estun:add_server(Config, Id)
    end, Servers),

    Results = lists:map(fun({Id, _}) ->
        case estun:discover(Id) of
            {ok, Addr} ->
                {Id, {ok, Addr#stun_addr.address, Addr#stun_addr.port}};
            Error ->
                {Id, Error}
        end
    end, Servers),

    io:format("~n=== Multi-Server Results ===~n"),
    lists:foreach(fun({Id, Result}) ->
        case Result of
            {ok, IP, Port} ->
                io:format("~p: ~p:~p~n", [Id, IP, Port]);
            {error, Reason} ->
                io:format("~p: ERROR - ~p~n", [Id, Reason])
        end
    end, Results),

    %% Check consistency
    Addrs = [Addr || {_, {ok, Addr, _}} <- Results],
    case lists:usort(Addrs) of
        [_SingleAddr] ->
            io:format("~n✓ Consistent mapping (Endpoint Independent)~n");
        _ ->
            io:format("~n✗ Inconsistent mapping (may indicate Symmetric NAT)~n")
    end.
```
