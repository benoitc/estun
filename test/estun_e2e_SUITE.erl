%% @doc End-to-end tests for STUN client with local mock server
-module(estun_e2e_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("estun.hrl").
-include("estun_attrs.hrl").

%% CT callbacks
-export([all/0, groups/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([
    basic_binding/1,
    binding_with_retransmit/1,
    multiple_bindings/1,
    socket_transfer/1,
    event_handler_pid/1,
    event_handler_fun/1,
    keepalive_refresh/1,
    error_response/1,
    concurrent_clients/1,
    rebind_to_different_server/1
]).

%% Mock server
-export([mock_server_loop/2]).

-define(MOCK_PORT, 13478).
-define(MOCK_PORT2, 13479).
-define(MOCK_PORT_DELAYED, 13480).

%%====================================================================
%% CT Callbacks
%%====================================================================

all() ->
    [{group, local_tests}].

groups() ->
    [{local_tests, [sequence], [
        basic_binding,
        binding_with_retransmit,
        multiple_bindings,
        socket_transfer,
        event_handler_pid,
        event_handler_fun,
        keepalive_refresh,
        error_response,
        concurrent_clients,
        rebind_to_different_server
    ]}].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(estun),
    Config.

end_per_suite(_Config) ->
    application:stop(estun),
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(binding_with_retransmit, Config) ->
    {ok, Pid} = start_mock_server(?MOCK_PORT_DELAYED, delayed),
    {ok, _} = estun:add_server(#{host => {127,0,0,1}, port => ?MOCK_PORT_DELAYED}, mock_delayed),
    [{mock_server, Pid}, {server_id, mock_delayed} | Config];
init_per_testcase(error_response, Config) ->
    {ok, Pid} = start_mock_server(?MOCK_PORT, error),
    {ok, _} = estun:add_server(#{host => {127,0,0,1}, port => ?MOCK_PORT}, mock_error),
    [{mock_server, Pid}, {server_id, mock_error} | Config];
init_per_testcase(rebind_to_different_server, Config) ->
    {ok, Pid1} = start_mock_server(?MOCK_PORT, success),
    {ok, Pid2} = start_mock_server(?MOCK_PORT2, success),
    {ok, _} = estun:add_server(#{host => {127,0,0,1}, port => ?MOCK_PORT}, mock1),
    {ok, _} = estun:add_server(#{host => {127,0,0,1}, port => ?MOCK_PORT2}, mock2),
    [{mock_server, Pid1}, {mock_server2, Pid2} | Config];
init_per_testcase(_TestCase, Config) ->
    {ok, Pid} = start_mock_server(?MOCK_PORT, success),
    {ok, _} = estun:add_server(#{host => {127,0,0,1}, port => ?MOCK_PORT}, mock),
    [{mock_server, Pid}, {server_id, mock} | Config].

end_per_testcase(rebind_to_different_server, Config) ->
    stop_mock_server(?config(mock_server, Config)),
    stop_mock_server(?config(mock_server2, Config)),
    estun:remove_server(mock1),
    estun:remove_server(mock2),
    ok;
end_per_testcase(binding_with_retransmit, Config) ->
    stop_mock_server(?config(mock_server, Config)),
    estun:remove_server(mock_delayed),
    ok;
end_per_testcase(_TestCase, Config) ->
    stop_mock_server(?config(mock_server, Config)),
    ServerId = ?config(server_id, Config),
    estun:remove_server(ServerId),
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

basic_binding(Config) ->
    ServerId = ?config(server_id, Config),
    {ok, #stun_addr{family = ipv4, port = Port, address = Addr}} = estun:discover(ServerId),
    ct:log("Discovered: ~p:~p", [Addr, Port]),
    true = is_tuple(Addr),
    true = Port > 0,
    ok.

binding_with_retransmit(Config) ->
    %% Uses delayed mock server that responds after 600ms, forcing retransmit
    ServerId = ?config(server_id, Config),
    {ok, #stun_addr{}} = estun:discover(ServerId),
    ok.

multiple_bindings(Config) ->
    ServerId = ?config(server_id, Config),
    Results = [estun:discover(ServerId) || _ <- lists:seq(1, 5)],
    ct:log("Multiple bindings: ~p", [Results]),
    true = lists:all(fun({ok, #stun_addr{}}) -> true; (_) -> false end, Results),
    ok.

socket_transfer(Config) ->
    ServerId = ?config(server_id, Config),
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    {ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId),
    ct:log("Bound to: ~p", [MappedAddr]),

    %% Transfer socket ownership
    {ok, Socket, TransferredAddr} = estun:transfer_socket(SocketRef),
    ct:log("Transferred socket: ~p, addr: ~p", [Socket, TransferredAddr]),

    %% Verify transferred address matches bound address
    #stun_addr{address = Addr1, port = Port1} = MappedAddr,
    #stun_addr{address = Addr2, port = Port2} = TransferredAddr,
    true = Addr1 =:= Addr2,
    true = Port1 =:= Port2,

    %% Clean up - close the transferred socket directly
    estun_socket:close(Socket),
    ok.

event_handler_pid(Config) ->
    ServerId = ?config(server_id, Config),
    {ok, SocketRef} = estun:open_socket(#{family => inet}),
    ok = estun:set_event_handler(SocketRef, self()),

    {ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId),

    %% Should receive binding_created event
    receive
        {estun_event, SocketRef, {binding_created, MappedAddr}} ->
            ct:log("Received binding_created event"),
            ok
    after 1000 ->
        ct:fail("Did not receive binding_created event")
    end,

    estun:close_socket(SocketRef),
    ok.

event_handler_fun(Config) ->
    ServerId = ?config(server_id, Config),
    {ok, SocketRef} = estun:open_socket(#{family => inet}),

    Self = self(),
    Handler = fun(Event) -> Self ! {handler_event, Event} end,
    ok = estun:set_event_handler(SocketRef, Handler),

    {ok, _MappedAddr} = estun:bind_socket(SocketRef, ServerId),

    receive
        {handler_event, {binding_created, _}} ->
            ct:log("Received event via function handler"),
            ok
    after 1000 ->
        ct:fail("Did not receive event via function handler")
    end,

    estun:close_socket(SocketRef),
    ok.

keepalive_refresh(Config) ->
    ServerId = ?config(server_id, Config),
    {ok, SocketRef} = estun:open_socket(#{family => inet}),

    {ok, Addr1} = estun:bind_socket(SocketRef, ServerId),
    ct:log("Initial bind: ~p", [Addr1]),

    %% Start keepalive (1 second interval)
    ok = estun:start_keepalive(SocketRef, 1),

    %% Wait for keepalive to run
    timer:sleep(2500),

    %% Verify binding is still valid
    {ok, Info} = estun:get_binding_info(SocketRef),
    ct:log("Binding info after keepalive: ~p", [Info]),
    true = maps:is_key(mapped_address, Info),
    true = maps:is_key(last_refresh, Info),

    ok = estun:stop_keepalive(SocketRef),
    estun:close_socket(SocketRef),
    ok.

error_response(Config) ->
    ServerId = ?config(server_id, Config),
    {error, {400, _}} = estun:discover(ServerId),
    ok.

concurrent_clients(Config) ->
    ServerId = ?config(server_id, Config),
    Self = self(),

    %% Spawn 10 concurrent clients
    Pids = [spawn_link(fun() ->
        Result = estun:discover(ServerId),
        Self ! {done, self(), Result}
    end) || _ <- lists:seq(1, 10)],

    %% Collect results
    Results = [receive {done, Pid, R} -> R end || Pid <- Pids],
    ct:log("Concurrent results: ~p", [Results]),

    true = lists:all(fun({ok, #stun_addr{}}) -> true; (_) -> false end, Results),
    ok.

rebind_to_different_server(_Config) ->
    {ok, SocketRef} = estun:open_socket(#{family => inet}),

    %% Bind to first server
    {ok, Addr1} = estun:bind_socket(SocketRef, mock1),
    ct:log("First bind: ~p", [Addr1]),

    %% Rebind to second server
    {ok, Addr2} = estun:bind_socket(SocketRef, mock2),
    ct:log("Second bind: ~p", [Addr2]),

    %% Both should succeed (addresses may differ based on server response)
    true = is_record(Addr1, stun_addr),
    true = is_record(Addr2, stun_addr),

    estun:close_socket(SocketRef),
    ok.

%%====================================================================
%% Mock STUN Server
%%====================================================================

start_mock_server(Port, Mode) ->
    Parent = self(),
    Pid = spawn_link(fun() ->
        {ok, Socket} = socket:open(inet, dgram, udp),
        ok = socket:setopt(Socket, {socket, reuseaddr}, true),
        ok = socket:bind(Socket, #{family => inet, port => Port, addr => {127,0,0,1}}),
        Parent ! {started, self()},
        mock_server_loop(Socket, Mode)
    end),
    receive
        {started, Pid} -> {ok, Pid}
    after 5000 ->
        {error, timeout}
    end.

stop_mock_server(Pid) when is_pid(Pid) ->
    Pid ! stop,
    ok;
stop_mock_server(_) ->
    ok.

mock_server_loop(Socket, Mode) ->
    case socket:recvfrom(Socket, 0, [], 1000) of
        {ok, {Source, Data}} ->
            handle_mock_request(Socket, Source, Data, Mode),
            mock_server_loop(Socket, Mode);
        {error, timeout} ->
            receive
                stop -> socket:close(Socket)
            after 0 ->
                mock_server_loop(Socket, Mode)
            end;
        {error, _} ->
            receive
                stop -> socket:close(Socket)
            after 0 ->
                mock_server_loop(Socket, Mode)
            end
    end.

handle_mock_request(Socket, Source, Data, Mode) ->
    case estun_codec:decode(Data) of
        {ok, #stun_msg{class = request, method = binding, transaction_id = TxnId}} ->
            case Mode of
                success ->
                    send_success_response(Socket, Source, TxnId);
                error ->
                    send_error_response(Socket, Source, TxnId);
                delayed ->
                    timer:sleep(600),
                    send_success_response(Socket, Source, TxnId)
            end;
        _ ->
            ok
    end.

send_success_response(Socket, #{addr := ClientAddr, port := ClientPort} = Source, TxnId) ->
    MappedAddr = #stun_addr{
        family = ipv4,
        port = ClientPort,
        address = ClientAddr
    },
    Attrs = [{mapped_address, MappedAddr}],
    Response = estun_codec:encode(#stun_msg{
        class = success,
        method = binding,
        transaction_id = TxnId,
        attributes = Attrs
    }),
    socket:sendto(Socket, Response, Source).

send_error_response(Socket, Source, TxnId) ->
    Attrs = [{error_code, {400, <<"Bad Request">>}}],
    Response = estun_codec:encode(#stun_msg{
        class = error,
        method = binding,
        transaction_id = TxnId,
        attributes = Attrs
    }),
    socket:sendto(Socket, Response, Source).
