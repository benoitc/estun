%% @doc Docker signaling server - TCP-based for cross-network communication
-module(docker_signaling).
-export([start/0]).

-define(PORT, 9999).

start() ->
    io:format("[Signaling] Starting on port ~p...~n", [?PORT]),
    {ok, LSock} = gen_tcp:listen(?PORT, [
        binary,
        {packet, 4},
        {reuseaddr, true},
        {active, false}
    ]),
    io:format("[Signaling] Listening...~n"),
    accept_loop(LSock, #{}).

accept_loop(LSock, Peers) ->
    case gen_tcp:accept(LSock, 1000) of
        {ok, Sock} ->
            io:format("[Signaling] New connection~n"),
            NewPeers = handle_client(Sock, Peers),
            accept_loop(LSock, NewPeers);
        {error, timeout} ->
            accept_loop(LSock, Peers);
        {error, Reason} ->
            io:format("[Signaling] Accept error: ~p~n", [Reason]),
            accept_loop(LSock, Peers)
    end.

handle_client(Sock, Peers) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, Data} ->
            case binary_to_term(Data) of
                {register, Name, PubIP, PubPort, LocalIP, LocalPort} ->
                    io:format("[Signaling] ~p registered~n", [Name]),
                    io:format("  Public: ~p:~p~n", [PubIP, PubPort]),
                    io:format("  Local:  ~p:~p~n", [LocalIP, LocalPort]),
                    NewPeers = Peers#{Name => {Sock, PubIP, PubPort, LocalIP, LocalPort}},
                    case maps:size(NewPeers) of
                        2 -> connect_peers(NewPeers);
                        _ -> ok
                    end,
                    NewPeers;
                Other ->
                    io:format("[Signaling] Unknown message: ~p~n", [Other]),
                    Peers
            end;
        {error, Reason} ->
            io:format("[Signaling] Recv error: ~p~n", [Reason]),
            Peers
    end.

connect_peers(Peers) ->
    [{Name1, {Sock1, Pub1, Port1, Local1, LPort1}},
     {Name2, {Sock2, Pub2, Port2, Local2, LPort2}}] = maps:to_list(Peers),

    io:format("[Signaling] Connecting ~p <-> ~p~n", [Name1, Name2]),

    %% Tell each peer about the other
    Msg1 = term_to_binary({peer_info, Name2, Pub2, Port2, Local2, LPort2}),
    Msg2 = term_to_binary({peer_info, Name1, Pub1, Port1, Local1, LPort1}),

    gen_tcp:send(Sock1, Msg1),
    gen_tcp:send(Sock2, Msg2),

    io:format("[Signaling] Peers notified~n").
