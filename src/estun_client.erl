%% @doc STUN client state machine (gen_statem)
%%
%% Manages STUN socket lifecycle: binding, keepalive, and socket transfer.
-module(estun_client).
-behaviour(gen_statem).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([start_link/1, start_link/2]).
-export([stop/1]).
-export([bind/2, bind/3]).
-export([get_mapped_address/1]).
-export([get_binding_info/1]).
-export([get_socket/1]).
-export([set_event_handler/2]).
-export([start_keepalive/2, stop_keepalive/1]).
-export([transfer/1]).

%% gen_statem callbacks
-export([init/1, callback_mode/0, terminate/3]).
-export([idle/3, binding/3, bound/3]).

%% Types
-type event_handler() :: pid() | fun((event()) -> any()) | {module(), atom()}.
-type event() ::
    {binding_created, #stun_addr{}} |
    {binding_refreshed, #stun_addr{}} |
    {binding_expiring, pos_integer()} |
    {binding_expired} |
    {binding_changed, #stun_addr{}, #stun_addr{}} |
    {error, term()}.

-export_type([event_handler/0, event/0]).

-record(data, {
    socket          :: estun_socket:socket() | undefined,
    socket_opts     :: map(),
    server          :: #stun_server{} | undefined,
    transactions    :: #{binary() => #transaction{}},
    mapped_addr     :: #stun_addr{} | undefined,
    owner           :: pid(),
    owner_mon       :: reference() | undefined,
    event_handler   :: event_handler() | undefined,
    binding_created :: integer() | undefined,
    last_refresh    :: integer() | undefined,
    lifetime        :: pos_integer() | unknown,
    keepalive_ref   :: reference() | undefined,
    expiry_timer    :: reference() | undefined
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(SocketOpts) ->
    start_link(SocketOpts, #{}).

-spec start_link(map(), map()) -> {ok, pid()} | {error, term()}.
start_link(SocketOpts, ClientOpts) ->
    gen_statem:start_link(?MODULE, {SocketOpts, ClientOpts, self()}, []).

-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_statem:stop(Pid).

-spec bind(pid(), #stun_server{}) -> {ok, #stun_addr{}} | {error, term()}.
bind(Pid, Server) ->
    bind(Pid, Server, 5000).

-spec bind(pid(), #stun_server{}, timeout()) -> {ok, #stun_addr{}} | {error, term()}.
bind(Pid, Server, Timeout) ->
    gen_statem:call(Pid, {bind, Server}, Timeout).

-spec get_mapped_address(pid()) -> {ok, #stun_addr{}} | {error, not_bound}.
get_mapped_address(Pid) ->
    gen_statem:call(Pid, get_mapped_address).

-spec get_binding_info(pid()) -> {ok, map()} | {error, not_bound}.
get_binding_info(Pid) ->
    gen_statem:call(Pid, get_binding_info).

-spec get_socket(pid()) -> {ok, estun_socket:socket()} | {error, term()}.
get_socket(Pid) ->
    gen_statem:call(Pid, get_socket).

-spec set_event_handler(pid(), event_handler()) -> ok.
set_event_handler(Pid, Handler) ->
    gen_statem:call(Pid, {set_event_handler, Handler}).

-spec start_keepalive(pid(), pos_integer()) -> ok.
start_keepalive(Pid, IntervalMs) ->
    gen_statem:call(Pid, {start_keepalive, IntervalMs}).

-spec stop_keepalive(pid()) -> ok.
stop_keepalive(Pid) ->
    gen_statem:call(Pid, stop_keepalive).

-spec transfer(pid()) -> {ok, estun_socket:socket(), #stun_addr{}} | {error, term()}.
transfer(Pid) ->
    gen_statem:call(Pid, transfer).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

callback_mode() ->
    [state_functions, state_enter].

init({SocketOpts, _ClientOpts, Owner}) ->
    process_flag(trap_exit, true),
    MonRef = monitor(process, Owner),
    Data = #data{
        socket_opts = SocketOpts,
        transactions = #{},
        owner = Owner,
        owner_mon = MonRef,
        lifetime = unknown
    },
    {ok, idle, Data}.

terminate(_Reason, _State, #data{socket = undefined}) ->
    ok;
terminate(_Reason, _State, #data{socket = Socket}) ->
    estun_socket:close(Socket),
    ok.

%%====================================================================
%% State: idle
%%====================================================================

idle(enter, _OldState, Data) ->
    {keep_state, Data};

idle({call, From}, {bind, Server}, Data) ->
    case ensure_socket(Data) of
        {ok, NewData} ->
            TxnId = estun_codec:make_transaction_id(),
            Msg = build_binding_request(TxnId, Server),
            Txn = estun_transaction:new(Msg, From, TxnId),
            case send_to_server(NewData#data.socket, Server, Msg) of
                ok ->
                    {next_state, binding,
                     NewData#data{
                         server = Server,
                         transactions = #{TxnId => Txn}
                     },
                     [{state_timeout, estun_transaction:next_timeout(Txn), {retransmit, TxnId}}]};
                Error ->
                    {keep_state, NewData, [{reply, From, Error}]}
            end;
        Error ->
            {keep_state, Data, [{reply, From, Error}]}
    end;

idle({call, From}, get_socket, #data{socket = Socket} = Data) when Socket =/= undefined ->
    {keep_state, Data, [{reply, From, {ok, Socket}}]};

idle({call, From}, get_socket, Data) ->
    case ensure_socket(Data) of
        {ok, NewData} ->
            {keep_state, NewData, [{reply, From, {ok, NewData#data.socket}}]};
        Error ->
            {keep_state, Data, [{reply, From, Error}]}
    end;

idle({call, From}, get_mapped_address, Data) ->
    {keep_state, Data, [{reply, From, {error, not_bound}}]};

idle({call, From}, get_binding_info, Data) ->
    {keep_state, Data, [{reply, From, {error, not_bound}}]};

idle({call, From}, {set_event_handler, Handler}, Data) ->
    {keep_state, Data#data{event_handler = Handler}, [{reply, From, ok}]};

idle(info, {'DOWN', MonRef, process, _, _}, #data{owner_mon = MonRef} = Data) ->
    {stop, normal, Data};

idle(info, _Msg, Data) ->
    {keep_state, Data}.

%%====================================================================
%% State: binding (waiting for response)
%%====================================================================

binding(enter, _OldState, _Data) ->
    keep_state_and_data;

binding(state_timeout, {retransmit, TxnId}, Data) ->
    case poll_for_response(Data) of
        {ok, ResponseData} ->
            ResponseData;
        continue ->
            case maps:find(TxnId, Data#data.transactions) of
                {ok, Txn} ->
                    case estun_transaction:is_expired(Txn) of
                        false ->
                            send_to_server(Data#data.socket, Data#data.server,
                                           estun_transaction:get_request(Txn)),
                            NewTxn = estun_transaction:increment_retries(Txn),
                            {keep_state,
                             Data#data{transactions = maps:put(TxnId, NewTxn, Data#data.transactions)},
                             [{state_timeout, estun_transaction:next_timeout(NewTxn), {retransmit, TxnId}}]};
                        true ->
                            gen_statem:reply(estun_transaction:get_from(Txn), {error, timeout}),
                            {next_state, idle, Data#data{transactions = #{}}}
                    end;
                error ->
                    {next_state, idle, Data}
            end
    end;

binding(info, {select, Socket, _, ready_input}, #data{socket = Socket} = Data) ->
    handle_socket_data(Data);

binding(info, {'$socket', Socket, select, _Info}, #data{socket = Socket} = Data) ->
    %% OTP 28 socket notification format
    handle_socket_data(Data);

binding({call, From}, get_socket, #data{socket = Socket} = Data) ->
    {keep_state, Data, [{reply, From, {ok, Socket}}]};

binding({call, From}, get_mapped_address, Data) ->
    {keep_state, Data, [{reply, From, {error, not_bound}}]};

binding({call, From}, {set_event_handler, Handler}, Data) ->
    {keep_state, Data#data{event_handler = Handler}, [{reply, From, ok}]};

binding(info, {'DOWN', MonRef, process, _, _}, #data{owner_mon = MonRef} = Data) ->
    {stop, normal, Data};

binding(info, _Msg, Data) ->
    {keep_state, Data}.

%%====================================================================
%% State: bound (have mapped address)
%%====================================================================

bound(enter, _OldState, Data) ->
    Now = erlang:monotonic_time(millisecond),
    NewData = Data#data{binding_created = Now, last_refresh = Now},
    notify_event({binding_created, Data#data.mapped_addr}, NewData),
    ExpiryTimer = schedule_expiry_warning(NewData),
    {keep_state, NewData#data{expiry_timer = ExpiryTimer}};

bound({call, From}, get_mapped_address, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.mapped_addr}}]};

bound({call, From}, get_binding_info, Data) ->
    Info = build_binding_info(Data),
    {keep_state, Data, [{reply, From, {ok, Info}}]};

bound({call, From}, get_socket, #data{socket = Socket} = Data) ->
    {keep_state, Data, [{reply, From, {ok, Socket}}]};

bound({call, From}, {set_event_handler, Handler}, Data) ->
    {keep_state, Data#data{event_handler = Handler}, [{reply, From, ok}]};

bound({call, From}, {start_keepalive, IntervalMs}, Data) ->
    cancel_timer(Data#data.keepalive_ref),
    Ref = erlang:send_after(IntervalMs, self(), {keepalive, IntervalMs}),
    {keep_state, Data#data{keepalive_ref = Ref}, [{reply, From, ok}]};

bound({call, From}, stop_keepalive, Data) ->
    cancel_timer(Data#data.keepalive_ref),
    {keep_state, Data#data{keepalive_ref = undefined}, [{reply, From, ok}]};

bound({call, From}, {bind, Server}, Data) ->
    TxnId = estun_codec:make_transaction_id(),
    Msg = build_binding_request(TxnId, Server),
    Txn = estun_transaction:new(Msg, From, TxnId),
    case send_to_server(Data#data.socket, Server, Msg) of
        ok ->
            {next_state, binding,
             Data#data{
                 server = Server,
                 transactions = #{TxnId => Txn}
             },
             [{state_timeout, estun_transaction:next_timeout(Txn), {retransmit, TxnId}}]};
        Error ->
            {keep_state, Data, [{reply, From, Error}]}
    end;

bound({call, From}, transfer, Data) ->
    cancel_timer(Data#data.keepalive_ref),
    cancel_timer(Data#data.expiry_timer),
    case estun_socket:controlling_process(Data#data.socket, element(1, From)) of
        ok ->
            {stop_and_reply, normal,
             [{reply, From, {ok, Data#data.socket, Data#data.mapped_addr}}],
             Data#data{socket = undefined}};
        Error ->
            {keep_state, Data, [{reply, From, Error}]}
    end;

bound(info, {keepalive, IntervalMs}, Data) ->
    TxnId = estun_codec:make_transaction_id(),
    Msg = build_binding_request(TxnId, Data#data.server),
    Txn = estun_transaction:new(Msg, undefined, TxnId),
    send_to_server(Data#data.socket, Data#data.server, Msg),
    Ref = erlang:send_after(IntervalMs, self(), {keepalive, IntervalMs}),
    {keep_state, Data#data{
        keepalive_ref = Ref,
        transactions = maps:put(TxnId, Txn, Data#data.transactions)
    }};

bound(info, binding_expiring, Data) ->
    Remaining = remaining_lifetime(Data),
    notify_event({binding_expiring, Remaining}, Data),
    keep_state_and_data;

bound(info, binding_expired, Data) ->
    notify_event({binding_expired}, Data),
    {next_state, idle, cleanup_binding(Data)};

bound(info, {select, Socket, _, ready_input}, #data{socket = Socket} = Data) ->
    handle_bound_socket_data(Data);

bound(info, {'$socket', Socket, select, _Info}, #data{socket = Socket} = Data) ->
    handle_bound_socket_data(Data);

bound(info, {'DOWN', MonRef, process, _, _}, #data{owner_mon = MonRef} = Data) ->
    {stop, normal, Data};

bound(info, _Msg, Data) ->
    {keep_state, Data}.

%%====================================================================
%% Internal - Socket handling
%%====================================================================

ensure_socket(#data{socket = undefined, socket_opts = Opts} = Data) ->
    case estun_socket:open(Opts) of
        {ok, Socket} ->
            {ok, Data#data{socket = Socket}};
        Error ->
            Error
    end;
ensure_socket(Data) ->
    {ok, Data}.

send_to_server(Socket, #stun_server{host = Host, port = Port}, Msg) ->
    Addr = resolve_host(Host),
    estun_socket:send(Socket, {Addr, Port}, Msg).

resolve_host(Host) when is_tuple(Host) ->
    Host;
resolve_host(Host) when is_atom(Host) ->
    resolve_host(atom_to_list(Host));
resolve_host(Host) when is_binary(Host) ->
    resolve_host(binary_to_list(Host));
resolve_host(Host) when is_list(Host) ->
    case inet:getaddr(Host, inet) of
        {ok, Addr} -> Addr;
        {error, _} ->
            case inet:getaddr(Host, inet6) of
                {ok, Addr6} -> Addr6;
                {error, Reason} -> error({resolve_failed, Host, Reason})
            end
    end.

%% Poll for incoming response with zero timeout (non-blocking)
poll_for_response(Data) ->
    case socket:recvfrom(Data#data.socket, 0, [], 0) of
        {ok, {#{addr := _Addr, port := _Port}, Bin}} ->
            {ok, handle_response(Bin, Data)};
        {error, timeout} ->
            continue;
        {error, eagain} ->
            continue;
        {error, _Reason} ->
            continue
    end.

handle_socket_data(Data) ->
    case estun_socket:recv(Data#data.socket, 0) of
        {ok, {_Addr, _Port}, Bin} ->
            handle_response(Bin, Data);
        {error, timeout} ->
            keep_state_and_data;
        {error, _Reason} ->
            keep_state_and_data
    end.

handle_response(Bin, Data) ->
    case decode_response(Bin, Data) of
        {ok, #stun_msg{class = success, transaction_id = TxnId} = Msg} ->
            case maps:find(TxnId, Data#data.transactions) of
                {ok, #transaction{from = From}} ->
                    MappedAddr = extract_mapped_address(Msg),
                    gen_statem:reply(From, {ok, MappedAddr}),
                    {next_state, bound,
                     Data#data{mapped_addr = MappedAddr, transactions = #{}}};
                error ->
                    keep_state_and_data
            end;
        {ok, #stun_msg{class = error, transaction_id = TxnId} = Msg} ->
            case maps:find(TxnId, Data#data.transactions) of
                {ok, #transaction{from = From}} ->
                    Error = estun_attrs:get_error(Msg),
                    gen_statem:reply(From, {error, Error}),
                    {next_state, idle, Data#data{transactions = #{}}};
                error ->
                    keep_state_and_data
            end;
        _ ->
            keep_state_and_data
    end.

handle_bound_socket_data(Data) ->
    case estun_socket:recv(Data#data.socket, 0) of
        {ok, {_Addr, _Port}, Bin} ->
            handle_bound_response(Bin, Data);
        {error, _} ->
            keep_state_and_data
    end.

handle_bound_response(Bin, Data) ->
    case decode_response(Bin, Data) of
        {ok, #stun_msg{class = success, transaction_id = TxnId} = Msg} ->
            NewAddr = extract_mapped_address(Msg),
            Now = erlang:monotonic_time(millisecond),
            NewData = Data#data{
                last_refresh = Now,
                transactions = maps:remove(TxnId, Data#data.transactions)
            },
            case NewAddr =:= Data#data.mapped_addr of
                true ->
                    notify_event({binding_refreshed, NewAddr}, NewData),
                    {keep_state, NewData};
                false ->
                    notify_event({binding_changed, Data#data.mapped_addr, NewAddr}, NewData),
                    {keep_state, NewData#data{mapped_addr = NewAddr}}
            end;
        _ ->
            keep_state_and_data
    end.

decode_response(Bin, _Data) ->
    case estun_codec:decode(Bin) of
        {ok, Msg} ->
            {ok, process_xor_addresses(Msg)};
        Error ->
            Error
    end.

process_xor_addresses(#stun_msg{transaction_id = TxnId, attributes = Attrs} = Msg) ->
    NewAttrs = lists:map(fun
        ({xor_mapped_address_raw, Family, Port, XAddr}) ->
            Addr = estun_crypto:decode_xor_address(Family, <<Port:16, XAddr/binary>>, TxnId),
            {xor_mapped_address, Addr};
        (Attr) ->
            Attr
    end, Attrs),
    Msg#stun_msg{attributes = NewAttrs}.

extract_mapped_address(Msg) ->
    case estun_attrs:get_xor_mapped_address(Msg) of
        undefined -> estun_attrs:get_mapped_address(Msg);
        Addr -> Addr
    end.

%%====================================================================
%% Internal - Request building
%%====================================================================

build_binding_request(TxnId, Server) ->
    AuthAttrs = estun_auth:build_auth_attrs(Server),
    Msg = estun_codec:encode_binding_request(TxnId, AuthAttrs),
    MsgWithIntegrity = estun_auth:add_message_integrity(Msg, Server, TxnId),
    case Server#stun_server.auth of
        none -> MsgWithIntegrity;
        _ -> estun_auth:add_fingerprint(MsgWithIntegrity)
    end.

%%====================================================================
%% Internal - Timers and events
%%====================================================================

notify_event(_Event, #data{event_handler = undefined}) ->
    ok;
notify_event(Event, #data{event_handler = Pid}) when is_pid(Pid) ->
    Pid ! {estun_event, self(), Event};
notify_event(Event, #data{event_handler = Fun}) when is_function(Fun, 1) ->
    Fun(Event);
notify_event(Event, #data{event_handler = {M, F}}) ->
    M:F(Event).

schedule_expiry_warning(#data{lifetime = unknown}) ->
    undefined;
schedule_expiry_warning(#data{lifetime = Lifetime}) ->
    %% Warn at 80% of lifetime
    WarnMs = Lifetime * 800,
    erlang:send_after(WarnMs, self(), binding_expiring).

cancel_timer(undefined) -> ok;
cancel_timer(Ref) -> erlang:cancel_timer(Ref).

build_binding_info(#data{} = Data) ->
    #{
        mapped_address => Data#data.mapped_addr,
        created_at => Data#data.binding_created,
        last_refresh => Data#data.last_refresh,
        lifetime => Data#data.lifetime,
        remaining => remaining_lifetime(Data),
        server => Data#data.server
    }.

remaining_lifetime(#data{lifetime = unknown}) -> unknown;
remaining_lifetime(#data{lifetime = L, last_refresh = LR}) ->
    Now = erlang:monotonic_time(millisecond),
    Elapsed = (Now - LR) div 1000,
    max(0, L - Elapsed).

cleanup_binding(Data) ->
    cancel_timer(Data#data.keepalive_ref),
    cancel_timer(Data#data.expiry_timer),
    Data#data{
        mapped_addr = undefined,
        binding_created = undefined,
        last_refresh = undefined,
        keepalive_ref = undefined,
        expiry_timer = undefined,
        transactions = #{}
    }.
