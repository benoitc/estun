%% @doc NAT behavior discovery (RFC 5780)
%%
%% Implements NAT behavior discovery tests per RFC 5780.
-module(estun_nat_discovery).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([discover/2, discover/3]).
-export([discover_lifetime/2]).

%% Test timeout
-define(TEST_TIMEOUT, 5000).

%%====================================================================
%% API
%%====================================================================

-spec discover(estun_socket:socket(), #stun_server{}) ->
    {ok, #nat_behavior{}} | {error, term()}.
discover(Socket, Server) ->
    discover(Socket, Server, #{}).

-spec discover(estun_socket:socket(), #stun_server{}, map()) ->
    {ok, #nat_behavior{}} | {error, term()}.
discover(Socket, Server, Opts) ->
    Timeout = maps:get(timeout, Opts, ?TEST_TIMEOUT),
    case binding_request(Socket, Server, [], Timeout) of
        {ok, MappedAddr1, OtherAddr} when OtherAddr =/= undefined ->
            {ok, {LocalAddr, _LocalPort}} = estun_socket:sockname(Socket),
            NatPresent = not addresses_equal(LocalAddr, MappedAddr1#stun_addr.address),
            Mapping = test_mapping_behavior(Socket, Server, MappedAddr1, OtherAddr, Timeout),
            Filtering = test_filtering_behavior(Socket, Server, Timeout),
            Hairpin = test_hairpin(Socket, Server, MappedAddr1, Timeout),

            {ok, #nat_behavior{
                mapped_address = MappedAddr1,
                mapping_behavior = Mapping,
                filtering_behavior = Filtering,
                nat_present = NatPresent,
                hairpin_supported = Hairpin,
                binding_lifetime = unknown
            }};

        {ok, MappedAddr1, undefined} ->
            {ok, {LocalAddr, _LocalPort}} = estun_socket:sockname(Socket),
            NatPresent = not addresses_equal(LocalAddr, MappedAddr1#stun_addr.address),
            {ok, #nat_behavior{
                mapped_address = MappedAddr1,
                mapping_behavior = unknown,
                filtering_behavior = unknown,
                nat_present = NatPresent,
                hairpin_supported = unknown,
                binding_lifetime = unknown
            }};

        {error, Reason} ->
            {error, Reason}
    end.

-spec discover_lifetime(estun_socket:socket(), #stun_server{}) ->
    {ok, pos_integer()} | {error, term()}.
discover_lifetime(Socket, Server) ->
    case binding_request(Socket, Server, [], ?TEST_TIMEOUT) of
        {ok, MappedAddr1, _} ->
            find_lifetime(Socket, Server, MappedAddr1, 30, 600);
        Error ->
            Error
    end.

%%====================================================================
%% Internal - Mapping Behavior Tests (RFC 5780 Section 4.3)
%%====================================================================

test_mapping_behavior(Socket, Server, MappedAddr1, OtherAddr, Timeout) ->
    AltServer1 = Server#stun_server{host = OtherAddr#stun_addr.address},
    case binding_request(Socket, AltServer1, [], Timeout) of
        {ok, MappedAddr2, _} ->
            case addresses_equal_port(MappedAddr1, MappedAddr2) of
                true ->
                    endpoint_independent;
                false ->
                    test_mapping_address_dependent(Socket, Server, MappedAddr1,
                                                   OtherAddr, Timeout)
            end;
        {error, _} ->
            unknown
    end.

test_mapping_address_dependent(Socket, Server, MappedAddr1, OtherAddr, Timeout) ->
    AltServer2 = Server#stun_server{
        host = OtherAddr#stun_addr.address,
        port = OtherAddr#stun_addr.port
    },
    case binding_request(Socket, AltServer2, [], Timeout) of
        {ok, MappedAddr3, _} ->
            case addresses_equal_port(MappedAddr1, MappedAddr3) of
                true ->
                    address_dependent;
                false ->
                    address_port_dependent
            end;
        {error, _} ->
            unknown
    end.

%%====================================================================
%% Internal - Filtering Behavior Tests (RFC 5780 Section 4.4)
%%====================================================================

test_filtering_behavior(Socket, Server, Timeout) ->
    case binding_request_change(Socket, Server, [ip, port], Timeout) of
        {ok, _, _} ->
            endpoint_independent;
        {error, timeout} ->
            test_filtering_address_dependent(Socket, Server, Timeout);
        {error, _} ->
            unknown
    end.

test_filtering_address_dependent(Socket, Server, Timeout) ->
    case binding_request_change(Socket, Server, [port], Timeout) of
        {ok, _, _} ->
            address_dependent;
        {error, timeout} ->
            address_port_dependent;
        {error, _} ->
            unknown
    end.

%%====================================================================
%% Internal - Hairpin Test
%%====================================================================

test_hairpin(_Socket, _Server, _MappedAddr, _Timeout) ->
    unknown.

%%====================================================================
%% Internal - Lifetime Discovery
%%====================================================================

find_lifetime(Socket, Server, MappedAddr, Low, High) when High - Low > 10 ->
    Mid = (Low + High) div 2,
    timer:sleep(Mid * 1000),
    case binding_request(Socket, Server, [], ?TEST_TIMEOUT) of
        {ok, NewAddr, _} ->
            case addresses_equal_port(MappedAddr, NewAddr) of
                true ->
                    find_lifetime(Socket, Server, MappedAddr, Mid, High);
                false ->
                    find_lifetime(Socket, Server, NewAddr, Low, Mid)
            end;
        {error, _} ->
            {ok, Low}
    end;
find_lifetime(_Socket, _Server, _MappedAddr, Low, _High) ->
    {ok, Low}.

%%====================================================================
%% Internal - Request Helpers
%%====================================================================

binding_request(Socket, Server, ExtraAttrs, Timeout) ->
    TxnId = estun_codec:make_transaction_id(),
    Msg = estun_codec:encode_binding_request(TxnId, ExtraAttrs),
    Addr = resolve_host(Server#stun_server.host),
    case estun_socket:send(Socket, {Addr, Server#stun_server.port}, Msg) of
        ok ->
            wait_response(Socket, TxnId, Timeout);
        Error ->
            Error
    end.

binding_request_change(Socket, Server, Flags, Timeout) ->
    TxnId = estun_codec:make_transaction_id(),
    Attrs = [{change_request, Flags}],
    Msg = estun_codec:encode_binding_request(TxnId, Attrs),
    Addr = resolve_host(Server#stun_server.host),
    case estun_socket:send(Socket, {Addr, Server#stun_server.port}, Msg) of
        ok ->
            wait_response(Socket, TxnId, Timeout);
        Error ->
            Error
    end.

wait_response(Socket, TxnId, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    wait_response_loop(Socket, TxnId, Deadline).

wait_response_loop(Socket, TxnId, Deadline) ->
    Now = erlang:monotonic_time(millisecond),
    Remaining = max(0, Deadline - Now),
    case estun_socket:recv(Socket, Remaining) of
        {ok, {_Addr, _Port}, Bin} ->
            case estun_codec:decode(Bin) of
                {ok, #stun_msg{transaction_id = TxnId, class = success} = Msg} ->
                    ProcessedMsg = process_xor_addresses(Msg, TxnId),
                    MappedAddr = estun_attrs:get_mapped_address(ProcessedMsg),
                    OtherAddr = estun_attrs:get_other_address(ProcessedMsg),
                    {ok, MappedAddr, OtherAddr};
                {ok, #stun_msg{transaction_id = TxnId, class = error} = Msg} ->
                    {error, estun_attrs:get_error(Msg)};
                {ok, _OtherMsg} ->
                    wait_response_loop(Socket, TxnId, Deadline);
                {error, _} ->
                    wait_response_loop(Socket, TxnId, Deadline)
            end;
        {error, timeout} ->
            {error, timeout};
        {error, Reason} ->
            {error, Reason}
    end.

process_xor_addresses(#stun_msg{attributes = Attrs} = Msg, TxnId) ->
    NewAttrs = lists:map(fun
        ({xor_mapped_address_raw, Family, Port, XAddr}) ->
            Addr = estun_crypto:decode_xor_address(Family, <<Port:16, XAddr/binary>>, TxnId),
            {xor_mapped_address, Addr};
        (Attr) ->
            Attr
    end, Attrs),
    Msg#stun_msg{attributes = NewAttrs}.

%%====================================================================
%% Internal - Address Helpers
%%====================================================================

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

addresses_equal(Addr1, Addr2) when is_tuple(Addr1), is_tuple(Addr2) ->
    Addr1 =:= Addr2;
addresses_equal(_, _) ->
    false.

addresses_equal_port(#stun_addr{address = Addr1, port = Port1},
                     #stun_addr{address = Addr2, port = Port2}) ->
    Addr1 =:= Addr2 andalso Port1 =:= Port2.
