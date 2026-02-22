%% @doc STUN client tests
-module(estun_client_tests).

-include_lib("eunit/include/eunit.hrl").
-include("estun.hrl").

%%====================================================================
%% Client State Machine Tests
%%====================================================================

start_stop_test() ->
    {ok, Pid} = estun_client:start_link(#{family => inet}),
    ?assert(is_process_alive(Pid)),
    ok = estun_client:stop(Pid),
    timer:sleep(100),
    ?assertNot(is_process_alive(Pid)).

get_socket_test() ->
    {ok, Pid} = estun_client:start_link(#{family => inet}),
    {ok, Socket} = estun_client:get_socket(Pid),
    %% OTP 28+ socket module returns an opaque socket type
    ?assertNotEqual(undefined, Socket),
    ok = estun_client:stop(Pid).

not_bound_test() ->
    {ok, Pid} = estun_client:start_link(#{family => inet}),
    ?assertEqual({error, not_bound}, estun_client:get_mapped_address(Pid)),
    ?assertEqual({error, not_bound}, estun_client:get_binding_info(Pid)),
    ok = estun_client:stop(Pid).

event_handler_test() ->
    {ok, Pid} = estun_client:start_link(#{family => inet}),
    ok = estun_client:set_event_handler(Pid, self()),
    %% Handler is set but no events yet since not bound
    ok = estun_client:stop(Pid).
