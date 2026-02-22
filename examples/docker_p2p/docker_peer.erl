%% @doc Docker P2P peer - discovers address via STUN and connects via signaling
-module(docker_peer).
-export([start/2]).

-include("estun.hrl").

-define(SIGNALING_PORT, 9999).

start(Name, SignalingIP) ->
    io:format("[~p] Starting...~n", [Name]),
    timer:sleep(2000),  %% Wait for signaling server

    %% Start estun
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Open socket and discover public address
    {ok, SocketRef} = estun:open_socket(#{family => inet}),

    io:format("[~p] Discovering public address...~n", [Name]),
    case estun:bind_socket(SocketRef, default) of
        {ok, PubAddr} ->
            io:format("[~p] Public: ~p:~p~n", [Name,
                PubAddr#stun_addr.address, PubAddr#stun_addr.port]),

            %% Get local address - use container's actual IP
            {ok, RawSocket, _} = estun:transfer_socket(SocketRef),
            {ok, #{port := LocalPort}} = socket:sockname(RawSocket),
            LocalIP = get_container_ip(),
            io:format("[~p] Local: ~p:~p~n", [Name, LocalIP, LocalPort]),

            %% Connect to signaling server
            register_with_signaling(Name, SignalingIP, PubAddr, LocalIP, LocalPort, RawSocket);
        {error, Reason} ->
            io:format("[~p] STUN failed: ~p~n", [Name, Reason]),
            io:format("[~p] Continuing with local address only...~n", [Name]),

            {ok, RawSocket, _} = estun:transfer_socket(SocketRef),
            {ok, #{port := LocalPort}} = socket:sockname(RawSocket),
            LocalIP = get_container_ip(),
            io:format("[~p] Local: ~p:~p~n", [Name, LocalIP, LocalPort]),

            PubAddr = #stun_addr{family = ipv4, address = LocalIP, port = LocalPort},
            register_with_signaling(Name, SignalingIP, PubAddr, LocalIP, LocalPort, RawSocket)
    end.

get_container_ip() ->
    %% Get the first non-loopback IPv4 address
    {ok, Addrs} = inet:getifaddrs(),
    find_ipv4(Addrs).

find_ipv4([]) -> {127,0,0,1};
find_ipv4([{_Name, Opts} | Rest]) ->
    %% Look for IPv4 addresses in this interface
    case find_ipv4_in_opts(Opts) of
        {ok, IP} -> IP;
        not_found -> find_ipv4(Rest)
    end.

find_ipv4_in_opts([]) -> not_found;
find_ipv4_in_opts([{addr, {A, _, _, _} = IP} | _]) when A =/= 127 -> {ok, IP};
find_ipv4_in_opts([_ | Rest]) -> find_ipv4_in_opts(Rest).

register_with_signaling(Name, SignalingIP, PubAddr, LocalIP, LocalPort, Socket) ->
    io:format("[~p] Connecting to signaling server ~s...~n", [Name, SignalingIP]),

    case gen_tcp:connect(SignalingIP, ?SIGNALING_PORT, [binary, {packet, 4}, {active, false}], 5000) of
        {ok, Sock} ->
            io:format("[~p] Connected to signaling~n", [Name]),

            %% Register with signaling
            Msg = term_to_binary({register, Name,
                PubAddr#stun_addr.address, PubAddr#stun_addr.port,
                LocalIP, LocalPort}),
            ok = gen_tcp:send(Sock, Msg),

            %% Wait for peer info
            wait_for_peer(Name, Sock, Socket);
        {error, Reason} ->
            io:format("[~p] Failed to connect to signaling: ~p~n", [Name, Reason])
    end.

wait_for_peer(Name, TcpSock, UdpSocket) ->
    io:format("[~p] Waiting for peer...~n", [Name]),

    case gen_tcp:recv(TcpSock, 0, 30000) of
        {ok, Data} ->
            {peer_info, PeerName, PeerPubIP, PeerPubPort, PeerLocalIP, PeerLocalPort} =
                binary_to_term(Data),

            io:format("[~p] Peer ~p info received:~n", [Name, PeerName]),
            io:format("  Public: ~p:~p~n", [PeerPubIP, PeerPubPort]),
            io:format("  Local:  ~p:~p~n", [PeerLocalIP, PeerLocalPort]),

            gen_tcp:close(TcpSock),

            %% Connect to peer using their local (container) address
            connect_to_peer(Name, UdpSocket, PeerName, PeerLocalIP, PeerLocalPort);
        {error, Reason} ->
            io:format("[~p] Error waiting for peer: ~p~n", [Name, Reason]),
            gen_tcp:close(TcpSock)
    end.

connect_to_peer(Name, Socket, PeerName, PeerIP, PeerPort) ->
    io:format("[~p] Connecting to ~p at ~p:~p...~n", [Name, PeerName, PeerIP, PeerPort]),

    Dest = #{family => inet, addr => PeerIP, port => PeerPort},

    %% Send punch packets
    io:format("[~p] Sending packets...~n", [Name]),
    lists:foreach(fun(I) ->
        Packet = <<"MSG_", (atom_to_binary(Name))/binary, "_", (integer_to_binary(I))/binary>>,
        socket:sendto(Socket, Packet, Dest),
        timer:sleep(200)
    end, lists:seq(1, 5)),

    %% Receive packets
    io:format("[~p] Receiving packets...~n", [Name]),
    receive_loop(Name, Socket, PeerIP, PeerPort, 10).

receive_loop(Name, Socket, PeerIP, PeerPort, Remaining) when Remaining > 0 ->
    case socket:recvfrom(Socket, 0, [], 2000) of
        {ok, {#{addr := FromIP, port := FromPort}, Data}} ->
            io:format("[~p] RECEIVED: ~s from ~p:~p~n", [Name, Data, FromIP, FromPort]),

            %% Send response
            Dest = #{family => inet, addr => FromIP, port => FromPort},
            Response = <<"REPLY_", (atom_to_binary(Name))/binary>>,
            socket:sendto(Socket, Response, Dest),
            io:format("[~p] Sent reply~n", [Name]),

            receive_loop(Name, Socket, PeerIP, PeerPort, Remaining - 1);
        {error, timeout} ->
            io:format("[~p] Timeout, remaining: ~p~n", [Name, Remaining]),
            receive_loop(Name, Socket, PeerIP, PeerPort, Remaining - 1);
        {error, Reason} ->
            io:format("[~p] Receive error: ~p~n", [Name, Reason])
    end;
receive_loop(Name, Socket, _PeerIP, _PeerPort, 0) ->
    io:format("[~p] === TEST COMPLETE ===~n", [Name]),
    socket:close(Socket),
    timer:sleep(1000),
    init:stop().
