# P2P Connection Example

This example demonstrates establishing a direct peer-to-peer connection
using STUN and UDP hole punching.

## Overview

```
┌────────────┐         ┌──────────────┐         ┌────────────┐
│   Peer A   │◄───────►│  Signaling   │◄───────►│   Peer B   │
│            │         │   Server     │         │            │
└─────┬──────┘         └──────────────┘         └─────┬──────┘
      │                                               │
      │  1. Discover public addresses via STUN        │
      │  2. Exchange addresses via signaling          │
      │  3. Punch holes simultaneously                │
      │  4. Direct P2P communication                  │
      │◄─────────────────────────────────────────────►│
```

## Complete Implementation

### Peer Module

```erlang
-module(p2p_peer).
-export([start/2]).

-include_lib("estun/include/estun.hrl").

-record(state, {
    name,
    socket_ref,
    my_addr,
    peer_addr,
    signaling
}).

start(Name, SignalingPid) ->
    spawn(fun() -> init(Name, SignalingPid) end).

init(Name, SignalingPid) ->
    io:format("[~s] Starting...~n", [Name]),

    %% Start estun
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Open socket and discover address
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    {ok, MyAddr} = estun:bind_socket(SocketRef, default),

    io:format("[~s] My public address: ~p:~p~n", [
        Name,
        MyAddr#stun_addr.address,
        MyAddr#stun_addr.port
    ]),

    %% Start keepalive to maintain binding
    ok = estun:start_keepalive(SocketRef, 25),

    %% Register with signaling server
    SignalingPid ! {register, Name, self(), MyAddr},

    State = #state{
        name = Name,
        socket_ref = SocketRef,
        my_addr = MyAddr,
        signaling = SignalingPid
    },

    wait_for_peer(State).

wait_for_peer(#state{name = Name} = State) ->
    receive
        {peer_info, PeerName, PeerPid, PeerAddr} ->
            io:format("[~s] Peer ~s at ~p:~p~n", [
                Name, PeerName,
                PeerAddr#stun_addr.address,
                PeerAddr#stun_addr.port
            ]),

            %% Signal ready to punch
            PeerPid ! {ready, self()},
            NewState = State#state{peer_addr = PeerAddr},
            wait_for_ready(NewState)
    after 60000 ->
        io:format("[~s] Timeout waiting for peer~n", [Name]),
        cleanup(State)
    end.

wait_for_ready(#state{name = Name, socket_ref = SocketRef,
                      peer_addr = PeerAddr} = State) ->
    receive
        {ready, _PeerPid} ->
            io:format("[~s] Both peers ready, punching...~n", [Name]),

            %% Small random delay to avoid exact collision
            timer:sleep(rand:uniform(100)),

            %% Attempt hole punch
            PeerIP = PeerAddr#stun_addr.address,
            PeerPort = PeerAddr#stun_addr.port,

            case estun:punch(SocketRef, PeerIP, PeerPort, #{
                timeout => 15000,
                attempts => 30,
                interval => 50
            }) of
                {ok, connected} ->
                    io:format("[~s] Connected!~n", [Name]),
                    connected(State);
                {error, Reason} ->
                    io:format("[~s] Punch failed: ~p~n", [Name, Reason]),
                    cleanup(State)
            end
    after 10000 ->
        io:format("[~s] Timeout waiting for ready signal~n", [Name]),
        cleanup(State)
    end.

connected(#state{name = Name, socket_ref = SocketRef,
                 peer_addr = PeerAddr} = State) ->
    %% Stop keepalive and transfer socket
    estun:stop_keepalive(SocketRef),
    {ok, Socket, _} = estun:transfer_socket(SocketRef),

    %% Send greeting
    Dest = #{
        family => inet,
        addr => PeerAddr#stun_addr.address,
        port => PeerAddr#stun_addr.port
    },
    Greeting = iolist_to_binary(io_lib:format("Hello from ~s!", [Name])),
    socket:sendto(Socket, Greeting, Dest),

    %% Enter communication loop
    communicate(Name, Socket, PeerAddr).

communicate(Name, Socket, PeerAddr) ->
    Dest = #{
        family => inet,
        addr => PeerAddr#stun_addr.address,
        port => PeerAddr#stun_addr.port
    },

    receive
        {send, Data} ->
            socket:sendto(Socket, Data, Dest),
            communicate(Name, Socket, PeerAddr);
        stop ->
            socket:close(Socket)
    after 0 ->
        %% Check for incoming data
        case socket:recvfrom(Socket, 0, [], 100) of
            {ok, {_, Data}} ->
                io:format("[~s] Received: ~s~n", [Name, Data]),
                communicate(Name, Socket, PeerAddr);
            {error, timeout} ->
                communicate(Name, Socket, PeerAddr);
            {error, _} ->
                communicate(Name, Socket, PeerAddr)
        end
    end.

cleanup(#state{socket_ref = SocketRef}) ->
    estun:close_socket(SocketRef).
```

### Signaling Server

```erlang
-module(signaling_server).
-export([start/0]).

start() ->
    spawn(fun() -> loop(#{}) end).

loop(Peers) ->
    receive
        {register, Name, Pid, Addr} ->
            io:format("[Signaling] Registered: ~s~n", [Name]),
            NewPeers = maps:put(Name, {Pid, Addr}, Peers),

            %% If we have 2 peers, connect them
            case maps:size(NewPeers) of
                2 ->
                    connect_peers(NewPeers);
                _ ->
                    ok
            end,
            loop(NewPeers);

        _Other ->
            loop(Peers)
    end.

connect_peers(Peers) ->
    [{Name1, {Pid1, Addr1}}, {Name2, {Pid2, Addr2}}] = maps:to_list(Peers),

    io:format("[Signaling] Connecting ~s <-> ~s~n", [Name1, Name2]),

    %% Tell each peer about the other
    Pid1 ! {peer_info, Name2, Pid2, Addr2},
    Pid2 ! {peer_info, Name1, Pid1, Addr1}.
```

## Running the Example

### Terminal 1 - Start Signaling Server

```erlang
1> c(signaling_server).
2> c(p2p_peer).
3> Signaling = signaling_server:start().
<0.100.0>
```

### Terminal 2 - Start Peer A

```erlang
1> c(p2p_peer).
2> p2p_peer:start("Alice", <0.100.0>).  %% Use Signaling PID
[Alice] Starting...
[Alice] My public address: {203,0,113,42}:54321
```

### Terminal 3 - Start Peer B

```erlang
1> c(p2p_peer).
2> p2p_peer:start("Bob", <0.100.0>).  %% Use Signaling PID
[Bob] Starting...
[Bob] My public address: {198,51,100,1}:12345
```

### Expected Output

```
[Signaling] Registered: Alice
[Signaling] Registered: Bob
[Signaling] Connecting Alice <-> Bob

[Alice] Peer Bob at {198,51,100,1}:12345
[Bob] Peer Alice at {203,0,113,42}:54321
[Alice] Both peers ready, punching...
[Bob] Both peers ready, punching...
[Alice] Connected!
[Bob] Connected!
[Alice] Received: Hello from Bob!
[Bob] Received: Hello from Alice!
```

## Sending Messages After Connection

```erlang
%% Get the peer process
AlicePid = whereis(alice).  %% If registered

%% Send a message
AlicePid ! {send, <<"How are you?">>}.
```

## Production Considerations

1. **Signaling Server**: Use WebSocket or HTTP for real signaling
2. **Error Handling**: Implement reconnection logic
3. **Security**: Authenticate peers before connecting
4. **Fallback**: Use TURN relay if hole punching fails
5. **NAT Detection**: Check NAT type before attempting
