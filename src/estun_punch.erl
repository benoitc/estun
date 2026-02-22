%% @doc UDP hole punching implementation
%%
%% Implements simultaneous open (hole punching) for NAT traversal.
%% Includes same-network detection for NATs without hairpin support.
-module(estun_punch).

-include("estun.hrl").

%% API
-export([start/5]).
-export([start_async/5]).

%% Punch packet magic (12 bytes)
-define(PUNCH_MAGIC, <<"ESTUN_PUNCH_">>).
-define(PUNCH_MAGIC_SIZE, 12).

%% Extended punch with local port (for same-network fallback)
-define(PUNCH_EXT_MAGIC, <<"ESTUN_PUNCHX">>).

%%====================================================================
%% API
%%====================================================================

%% @doc Start hole punching to peer (blocking)
-spec start(estun_socket:socket(), {inet:ip_address(), inet:port_number()},
            pos_integer(), pos_integer(), pos_integer()) ->
    {ok, connected} | {ok, connected, {inet:ip_address(), inet:port_number()}} | {error, term()}.
start(Socket, PeerAddr, Attempts, Interval, Timeout) ->
    %% Get our local port for same-network fallback
    {ok, {_LocalAddr, LocalPort}} = estun_socket:sockname(Socket),
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    punch_loop(Socket, PeerAddr, LocalPort, Attempts, Interval, Deadline, undefined).

%% @doc Start hole punching asynchronously
-spec start_async(estun_socket:socket(), {inet:ip_address(), inet:port_number()},
                  pos_integer(), pos_integer(), pos_integer()) ->
    {ok, pid()}.
start_async(Socket, PeerAddr, Attempts, Interval, Timeout) ->
    Parent = self(),
    Pid = spawn_link(fun() ->
        Result = start(Socket, PeerAddr, Attempts, Interval, Timeout),
        Parent ! {punch_result, self(), Result}
    end),
    {ok, Pid}.

%%====================================================================
%% Internal
%%====================================================================

punch_loop(Socket, {PeerIP, PeerPort} = PeerAddr, MyLocalPort, AttemptsLeft, Interval, Deadline, PeerLocalPort) ->
    Now = erlang:monotonic_time(millisecond),
    case Now >= Deadline of
        true ->
            %% Timeout - try local fallback if we learned peer's local port
            try_local_fallback(Socket, PeerLocalPort);
        false when AttemptsLeft =< 0 ->
            try_local_fallback(Socket, PeerLocalPort);
        false ->
            Nonce = crypto:strong_rand_bytes(8),
            %% Send extended packet with our local port for same-network detection
            Packet = <<?PUNCH_EXT_MAGIC/binary, MyLocalPort:16, Nonce/binary>>,
            ok = estun_socket:send(Socket, PeerAddr, Packet),
            WaitTime = min(Interval, Deadline - Now),
            case estun_socket:recv(Socket, WaitTime) of
                %% Extended punch from peer (includes their local port)
                {ok, {FromIP, FromPort}, <<Magic:?PUNCH_MAGIC_SIZE/binary, _TheirLocalPort:16, _Rest/binary>>}
                  when Magic =:= ?PUNCH_EXT_MAGIC, FromIP =:= PeerIP, FromPort =:= PeerPort ->
                    %% Direct hit via public address
                    {ok, connected};

                {ok, {FromIP, _FromPort}, <<Magic:?PUNCH_MAGIC_SIZE/binary, _TheirLocalPort:16, _Rest/binary>>}
                  when Magic =:= ?PUNCH_EXT_MAGIC, FromIP =:= PeerIP ->
                    %% Same IP, different port (symmetric NAT) - connected
                    {ok, connected};

                {ok, {FromIP, FromPort}, <<Magic:?PUNCH_MAGIC_SIZE/binary, TheirLocalPort:16, _Rest/binary>>}
                  when Magic =:= ?PUNCH_EXT_MAGIC ->
                    %% Received from different IP - might be local address
                    %% Store peer's local port for potential fallback
                    case is_local_address(FromIP) of
                        true ->
                            %% Received via local network - respond and connect
                            AckPacket = <<?PUNCH_EXT_MAGIC/binary, MyLocalPort:16, (crypto:strong_rand_bytes(8))/binary>>,
                            ok = estun_socket:send(Socket, {FromIP, FromPort}, AckPacket),
                            {ok, connected, {FromIP, FromPort}};
                        false ->
                            punch_loop(Socket, PeerAddr, MyLocalPort, AttemptsLeft - 1, Interval, Deadline, TheirLocalPort)
                    end;

                %% Legacy punch packet (no local port)
                {ok, {FromIP, _FromPort}, <<Magic:?PUNCH_MAGIC_SIZE/binary, _Rest/binary>>}
                  when Magic =:= ?PUNCH_MAGIC, FromIP =:= PeerIP ->
                    {ok, connected};

                {ok, {_FromIP, _FromPort}, _OtherData} ->
                    punch_loop(Socket, PeerAddr, MyLocalPort, AttemptsLeft - 1, Interval, Deadline, PeerLocalPort);

                {error, timeout} ->
                    punch_loop(Socket, PeerAddr, MyLocalPort, AttemptsLeft - 1, Interval, Deadline, PeerLocalPort);

                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% Try connecting via localhost if we know peer's local port (same machine/network)
try_local_fallback(_Socket, undefined) ->
    {error, timeout};
try_local_fallback(Socket, PeerLocalPort) ->
    %% Try localhost - peer might be on same machine
    LocalAddr = {127, 0, 0, 1},
    Packet = <<?PUNCH_EXT_MAGIC/binary, 0:16, "FALLBACK">>,
    ok = estun_socket:send(Socket, {LocalAddr, PeerLocalPort}, Packet),
    case estun_socket:recv(Socket, 500) of
        {ok, {FromIP, FromPort}, _} ->
            {ok, connected, {FromIP, FromPort}};
        {error, _} ->
            {error, timeout}
    end.

%% Check if address is local/private
is_local_address({127, _, _, _}) -> true;
is_local_address({10, _, _, _}) -> true;
is_local_address({172, B, _, _}) when B >= 16, B =< 31 -> true;
is_local_address({192, 168, _, _}) -> true;
is_local_address({169, 254, _, _}) -> true;
is_local_address(_) -> false.
