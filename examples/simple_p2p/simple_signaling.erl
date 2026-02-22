%% @doc Simple signaling server for P2P address exchange
%% Exchanges both public (STUN) and local addresses for same-network support
-module(simple_signaling).
-export([start/0]).

%% Start the signaling server
start() ->
    spawn(fun() ->
        io:format("[Signaling] Started~n"),
        loop(#{})
    end).

loop(Peers) ->
    receive
        %% Extended registration with local address
        {register, Name, Pid, PublicAddr, LocalAddr} ->
            io:format("[Signaling] ~p registered~n", [Name]),
            io:format("  Public: ~p, Local: ~p~n", [PublicAddr, LocalAddr]),
            NewPeers = Peers#{Name => {Pid, PublicAddr, LocalAddr}},
            case maps:size(NewPeers) of
                2 -> connect_peers(NewPeers);
                _ -> ok
            end,
            loop(NewPeers);
        %% Legacy registration (public address only)
        {register, Name, Pid, Addr} ->
            io:format("[Signaling] ~p registered from ~p~n", [Name, Addr]),
            NewPeers = Peers#{Name => {Pid, Addr, undefined}},
            case maps:size(NewPeers) of
                2 -> connect_peers(NewPeers);
                _ -> ok
            end,
            loop(NewPeers);
        {unregister, Name} ->
            io:format("[Signaling] ~p unregistered~n", [Name]),
            loop(maps:remove(Name, Peers));
        stop ->
            io:format("[Signaling] Stopped~n"),
            ok
    end.

connect_peers(Peers) ->
    [{Name1, {Pid1, Pub1, Local1}}, {Name2, {Pid2, Pub2, Local2}}] = maps:to_list(Peers),
    io:format("[Signaling] Connecting ~p <-> ~p~n", [Name1, Name2]),
    %% Send both public and local addresses
    Pid1 ! {peer_info, Name2, Pub2, Local2},
    Pid2 ! {peer_info, Name1, Pub1, Local1}.
