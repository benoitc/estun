%% @doc Simple P2P peer using STUN hole punching
-module(simple_peer).
-export([start/2, send/2, stop/1]).

-include_lib("estun/include/estun.hrl").

%% Start a peer with a name and signaling server
start(Name, SignalingPid) ->
    Pid = spawn(fun() -> init(Name, SignalingPid) end),
    register(Name, Pid),
    {ok, Pid}.

%% Send data to the connected peer
send(Name, Data) when is_binary(Data) ->
    Name ! {send, Data},
    ok;
send(Name, Data) when is_list(Data) ->
    send(Name, list_to_binary(Data)).

%% Stop the peer
stop(Name) ->
    Name ! stop,
    ok.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

init(Name, SignalingPid) ->
    io:format("[~p] Starting...~n", [Name]),

    %% Start estun application
    application:ensure_all_started(estun),

    %% Add STUN server
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Open socket and discover public address
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    {ok, MyAddr} = estun:bind_socket(SocketRef, default),

    io:format("[~p] My public address: ~s~n", [Name, format_addr(MyAddr)]),

    %% Keep NAT binding alive
    ok = estun:start_keepalive(SocketRef, 25),

    %% Register with signaling server
    SignalingPid ! {register, Name, self(), MyAddr},

    %% Wait for peer info
    wait_for_peer(Name, SocketRef, MyAddr).

wait_for_peer(Name, SocketRef, MyAddr) ->
    io:format("[~p] Waiting for peer...~n", [Name]),
    receive
        {peer_info, PeerName, PeerAddr} ->
            io:format("[~p] Peer ~p at ~s~n", [Name, PeerName, format_addr(PeerAddr)]),
            connect_to_peer(Name, SocketRef, MyAddr, PeerName, PeerAddr)
    after 60000 ->
        io:format("[~p] Timeout waiting for peer~n", [Name]),
        estun:close_socket(SocketRef)
    end.

connect_to_peer(Name, SocketRef, MyAddr, PeerName, PeerAddr) ->
    io:format("[~p] Punching hole to ~p...~n", [Name, PeerName]),

    PeerIP = PeerAddr#stun_addr.address,
    PeerPort = PeerAddr#stun_addr.port,

    %% Attempt hole punch
    case estun:punch(SocketRef, PeerIP, PeerPort, #{
        timeout => 10000,
        attempts => 30,
        interval => 100
    }) of
        {ok, connected} ->
            io:format("[~p] Connected to ~p!~n", [Name, PeerName]),

            %% Transfer socket for direct use
            estun:stop_keepalive(SocketRef),
            {ok, Socket, _} = estun:transfer_socket(SocketRef),

            %% Enter messaging loop
            messaging_loop(Name, Socket, PeerAddr);

        {error, Reason} ->
            io:format("[~p] Hole punch failed: ~p~n", [Name, Reason]),
            estun:close_socket(SocketRef)
    end.

messaging_loop(Name, Socket, PeerAddr) ->
    Dest = #{
        family => inet,
        addr => PeerAddr#stun_addr.address,
        port => PeerAddr#stun_addr.port
    },

    %% Check for incoming messages (non-blocking)
    case socket:recvfrom(Socket, 0, [], 100) of
        {ok, {_Source, Data}} ->
            io:format("[~p] Received: ~s~n", [Name, Data]);
        {error, timeout} ->
            ok;
        {error, _} ->
            ok
    end,

    %% Check for outgoing messages
    receive
        {send, Data} ->
            case socket:sendto(Socket, Data, Dest) of
                ok ->
                    io:format("[~p] Sent: ~s~n", [Name, Data]);
                {error, Reason} ->
                    io:format("[~p] Send error: ~p~n", [Name, Reason])
            end,
            messaging_loop(Name, Socket, PeerAddr);

        stop ->
            io:format("[~p] Stopping~n", [Name]),
            socket:close(Socket);

        _Other ->
            messaging_loop(Name, Socket, PeerAddr)

    after 0 ->
        messaging_loop(Name, Socket, PeerAddr)
    end.

format_addr(#stun_addr{address = {A, B, C, D}, port = Port}) ->
    io_lib:format("~p.~p.~p.~p:~p", [A, B, C, D, Port]);
format_addr(#stun_addr{address = Addr, port = Port}) ->
    io_lib:format("~p:~p", [Addr, Port]).
