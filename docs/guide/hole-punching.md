# UDP Hole Punching

This guide explains how to establish direct P2P connections through NAT using UDP hole punching.

## Overview

UDP hole punching allows two peers behind NAT to establish a direct connection without a relay server. The technique works by having both peers simultaneously send packets to each other's public addresses.

```
┌─────────┐                                      ┌─────────┐
│  Peer A │                                      │  Peer B │
│ 192.168.│                                      │ 10.0.0. │
│  1.100  │                                      │   50    │
└────┬────┘                                      └────┬────┘
     │                                                │
     │  NAT A                              NAT B      │
     │  ┌─────┐                          ┌─────┐     │
     └──│     │──────────────────────────│     │─────┘
        │203.0│                          │198.51│
        │113.1│◄────── Internet ────────►│100.1 │
        │:5000│                          │:6000 │
        └─────┘                          └─────┘
             │                                │
             └──────────────────────────────┘
                    Direct P2P Traffic
```

## The Process

1. **Discovery**: Both peers use STUN to discover their public addresses
2. **Exchange**: Peers exchange addresses via a signaling server
3. **Punch**: Both peers simultaneously send packets to each other
4. **Connect**: NAT mappings are created, allowing bidirectional traffic

## Implementation

### Step 1: Setup and Discovery

```erlang
-module(p2p_peer).
-export([start/1]).

-include_lib("estun/include/estun.hrl").

start(SignalingPid) ->
    %% Start estun
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Open socket and discover public address
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    {ok, MyAddr} = estun:bind_socket(SocketRef, default),

    io:format("My public address: ~p:~p~n", [
        MyAddr#stun_addr.address,
        MyAddr#stun_addr.port
    ]),

    %% Continue with exchange...
    {SocketRef, MyAddr}.
```

### Step 2: Exchange Addresses

You need a signaling mechanism to exchange addresses. This can be:

- WebSocket server
- HTTP API
- Message queue
- Any reliable channel

```erlang
exchange_addresses(SignalingPid, MyAddr) ->
    %% Send our address to signaling server
    SignalingPid ! {register, self(), MyAddr},

    %% Wait for peer's address
    receive
        {peer_address, PeerAddr} ->
            io:format("Peer address: ~p:~p~n", [
                PeerAddr#stun_addr.address,
                PeerAddr#stun_addr.port
            ]),
            {ok, PeerAddr}
    after 30000 ->
        {error, timeout}
    end.
```

### Step 3: Maintain NAT Binding

Start keepalive to prevent NAT binding expiration:

```erlang
%% Refresh binding every 25 seconds
ok = estun:start_keepalive(SocketRef, 25).
```

### Step 4: Punch Through

```erlang
punch_to_peer(SocketRef, PeerAddr) ->
    PeerIP = PeerAddr#stun_addr.address,
    PeerPort = PeerAddr#stun_addr.port,

    %% Attempt hole punch
    case estun:punch(SocketRef, PeerIP, PeerPort, #{
        timeout => 10000,   %% 10 second total timeout
        attempts => 20,     %% 20 punch attempts
        interval => 100     %% 100ms between attempts
    }) of
        {ok, connected} ->
            io:format("Hole punch successful!~n"),
            ok;
        {error, timeout} ->
            io:format("Hole punch failed - timeout~n"),
            {error, timeout};
        {error, Reason} ->
            io:format("Hole punch failed: ~p~n", [Reason]),
            {error, Reason}
    end.
```

### Step 5: Transfer and Use Socket

```erlang
use_connection(SocketRef, PeerAddr) ->
    %% Stop keepalive (we'll handle it ourselves now)
    ok = estun:stop_keepalive(SocketRef),

    %% Transfer socket for direct use
    {ok, Socket, _MyAddr} = estun:transfer_socket(SocketRef),

    %% Now use the socket directly for P2P traffic
    Dest = #{
        family => inet,
        addr => PeerAddr#stun_addr.address,
        port => PeerAddr#stun_addr.port
    },

    %% Send a message
    ok = socket:sendto(Socket, <<"Hello P2P!">>, Dest),

    %% Receive messages
    receive_loop(Socket, PeerAddr).

receive_loop(Socket, PeerAddr) ->
    case socket:recvfrom(Socket, 0, [], 5000) of
        {ok, {_Source, Data}} ->
            io:format("Received: ~p~n", [Data]),
            receive_loop(Socket, PeerAddr);
        {error, timeout} ->
            receive_loop(Socket, PeerAddr);
        {error, Reason} ->
            io:format("Socket error: ~p~n", [Reason])
    end.
```

## Complete Example: Two Peers

### Peer A (Initiator)

```erlang
-module(peer_a).
-export([start/1]).

-include_lib("estun/include/estun.hrl").

start(SignalingServer) ->
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Setup
    {ok, SocketRef} = estun:open_socket(),
    {ok, MyAddr} = estun:bind_socket(SocketRef, default),
    ok = estun:start_keepalive(SocketRef, 25),

    io:format("[A] My address: ~p:~p~n", [
        MyAddr#stun_addr.address, MyAddr#stun_addr.port
    ]),

    %% Exchange addresses
    SignalingServer ! {from_a, self(), MyAddr},
    PeerAddr = receive {to_a, Addr} -> Addr after 30000 -> error(timeout) end,

    io:format("[A] Peer address: ~p:~p~n", [
        PeerAddr#stun_addr.address, PeerAddr#stun_addr.port
    ]),

    %% Small delay to ensure peer B is ready
    timer:sleep(100),

    %% Punch!
    case estun:punch(SocketRef, PeerAddr#stun_addr.address,
                     PeerAddr#stun_addr.port, #{timeout => 10000}) of
        {ok, connected} ->
            io:format("[A] Connected!~n"),
            {ok, Socket, _} = estun:transfer_socket(SocketRef),
            communicate(Socket, PeerAddr);
        Error ->
            estun:close_socket(SocketRef),
            Error
    end.

communicate(Socket, PeerAddr) ->
    Dest = #{family => inet,
             addr => PeerAddr#stun_addr.address,
             port => PeerAddr#stun_addr.port},
    socket:sendto(Socket, <<"Hello from A!">>, Dest),
    case socket:recvfrom(Socket, 0, [], 5000) of
        {ok, {_, Data}} -> io:format("[A] Received: ~s~n", [Data]);
        _ -> ok
    end,
    socket:close(Socket).
```

### Peer B (Responder)

```erlang
-module(peer_b).
-export([start/1]).

-include_lib("estun/include/estun.hrl").

start(SignalingServer) ->
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Setup
    {ok, SocketRef} = estun:open_socket(),
    {ok, MyAddr} = estun:bind_socket(SocketRef, default),
    ok = estun:start_keepalive(SocketRef, 25),

    io:format("[B] My address: ~p:~p~n", [
        MyAddr#stun_addr.address, MyAddr#stun_addr.port
    ]),

    %% Exchange addresses
    SignalingServer ! {from_b, self(), MyAddr},
    PeerAddr = receive {to_b, Addr} -> Addr after 30000 -> error(timeout) end,

    io:format("[B] Peer address: ~p:~p~n", [
        PeerAddr#stun_addr.address, PeerAddr#stun_addr.port
    ]),

    %% Punch!
    case estun:punch(SocketRef, PeerAddr#stun_addr.address,
                     PeerAddr#stun_addr.port, #{timeout => 10000}) of
        {ok, connected} ->
            io:format("[B] Connected!~n"),
            {ok, Socket, _} = estun:transfer_socket(SocketRef),
            communicate(Socket, PeerAddr);
        Error ->
            estun:close_socket(SocketRef),
            Error
    end.

communicate(Socket, PeerAddr) ->
    Dest = #{family => inet,
             addr => PeerAddr#stun_addr.address,
             port => PeerAddr#stun_addr.port},
    case socket:recvfrom(Socket, 0, [], 5000) of
        {ok, {_, Data}} ->
            io:format("[B] Received: ~s~n", [Data]),
            socket:sendto(Socket, <<"Hello from B!">>, Dest);
        _ -> ok
    end,
    socket:close(Socket).
```

### Simple Signaling Server

```erlang
-module(signaling).
-export([start/0]).

start() ->
    spawn(fun() -> loop(#{}) end).

loop(Peers) ->
    receive
        {from_a, Pid, Addr} ->
            NewPeers = Peers#{a => {Pid, Addr}},
            maybe_connect(NewPeers),
            loop(NewPeers);
        {from_b, Pid, Addr} ->
            NewPeers = Peers#{b => {Pid, Addr}},
            maybe_connect(NewPeers),
            loop(NewPeers)
    end.

maybe_connect(#{a := {PidA, AddrA}, b := {PidB, AddrB}}) ->
    PidA ! {to_a, AddrB},
    PidB ! {to_b, AddrA};
maybe_connect(_) ->
    ok.
```

Update the peer modules to register with PID:

```erlang
%% In peer_a.erl, change:
SignalingServer ! {from_a, self(), MyAddr},

%% In peer_b.erl, change:
SignalingServer ! {from_b, self(), MyAddr},
```

## Punch Options

```erlang
estun:punch(SocketRef, PeerIP, PeerPort, #{
    %% Total timeout for the punch operation (default: 5000ms)
    timeout => 10000,

    %% Number of punch packet attempts (default: 10)
    attempts => 20,

    %% Interval between attempts in ms (default: 50ms)
    interval => 100
}).
```

## Troubleshooting

### Hole Punch Fails

1. **Symmetric NAT**: Both peers have symmetric NAT - use TURN relay
2. **Firewall**: Local firewall blocking UDP - check settings
3. **Timing**: Peers not punching simultaneously - ensure coordination
4. **Binding expired**: Start keepalive before exchanging addresses

### Tips for Success

- Start keepalive immediately after binding
- Exchange addresses quickly (within seconds)
- Both peers should start punching at nearly the same time
- Use multiple punch attempts with short intervals
- Consider fallback to TURN if direct connection fails
