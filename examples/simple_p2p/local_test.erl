%% @doc Local test - run both peers in the same shell
%%
%% Usage:
%%   1> c(local_test).
%%   2> local_test:run().
%%
-module(local_test).
-export([run/0]).

-include_lib("estun/include/estun.hrl").

run() ->
    io:format("~n=== Simple P2P Test ===~n~n"),

    %% Start estun
    application:ensure_all_started(estun),
    estun:add_server(#{host => "stun.l.google.com", port => 19302}),

    %% Create two sockets and discover addresses
    io:format("Creating sockets and discovering addresses...~n"),

    {ok, SocketA} = estun:open_socket(#{family => inet}),
    {ok, PublicA} = estun:bind_socket(SocketA, default),
    {ok, RawA, _} = estun:transfer_socket(SocketA),
    {ok, #{port := LocalPortA}} = socket:sockname(RawA),

    {ok, SocketB} = estun:open_socket(#{family => inet}),
    {ok, PublicB} = estun:bind_socket(SocketB, default),
    {ok, RawB, _} = estun:transfer_socket(SocketB),
    {ok, #{port := LocalPortB}} = socket:sockname(RawB),

    io:format("~n  Alice:~n"),
    io:format("    Public: ~p:~p~n", [PublicA#stun_addr.address, PublicA#stun_addr.port]),
    io:format("    Local:  127.0.0.1:~p~n", [LocalPortA]),

    io:format("~n  Bob:~n"),
    io:format("    Public: ~p:~p~n", [PublicB#stun_addr.address, PublicB#stun_addr.port]),
    io:format("    Local:  127.0.0.1:~p~n", [LocalPortB]),

    %% Determine if same network (same public IP)
    SameNetwork = PublicA#stun_addr.address =:= PublicB#stun_addr.address,

    io:format("~n  Same network: ~p~n", [SameNetwork]),

    %% Choose addresses based on network topology
    {DestAddrA, DestAddrB} = case SameNetwork of
        true ->
            io:format("  Using LOCAL addresses for communication~n"),
            {{127,0,0,1}, {127,0,0,1}};
        false ->
            io:format("  Using PUBLIC addresses for communication~n"),
            {PublicA#stun_addr.address, PublicB#stun_addr.address}
    end,

    {DestPortA, DestPortB} = case SameNetwork of
        true -> {LocalPortA, LocalPortB};
        false -> {PublicA#stun_addr.port, PublicB#stun_addr.port}
    end,

    DestB = #{family => inet, addr => DestAddrB, port => DestPortB},
    DestA = #{family => inet, addr => DestAddrA, port => DestPortA},

    io:format("~n--- Messaging Test ---~n"),

    %% Alice sends to Bob
    io:format("~n  Alice -> Bob: \"Hello Bob!\"~n"),
    ok = socket:sendto(RawA, <<"Hello Bob!">>, DestB),

    case socket:recvfrom(RawB, 0, [], 2000) of
        {ok, {Source1, Data1}} ->
            io:format("  Bob received: ~s (from ~p)~n", [Data1, Source1]);
        {error, Err1} ->
            io:format("  Bob receive error: ~p~n", [Err1])
    end,

    %% Bob sends to Alice
    io:format("~n  Bob -> Alice: \"Hi Alice!\"~n"),
    ok = socket:sendto(RawB, <<"Hi Alice!">>, DestA),

    case socket:recvfrom(RawA, 0, [], 2000) of
        {ok, {Source2, Data2}} ->
            io:format("  Alice received: ~s (from ~p)~n", [Data2, Source2]);
        {error, Err2} ->
            io:format("  Alice receive error: ~p~n", [Err2])
    end,

    %% Cleanup
    socket:close(RawA),
    socket:close(RawB),

    io:format("~n=== Test Complete ===~n"),
    ok.
