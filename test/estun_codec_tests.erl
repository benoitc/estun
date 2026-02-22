%% @doc STUN codec tests including RFC 5769 test vectors
-module(estun_codec_tests).

-include_lib("eunit/include/eunit.hrl").
-include("estun.hrl").
-include("estun_attrs.hrl").

%%====================================================================
%% RFC 5769 Test Vectors
%%====================================================================

%% RFC 5769 Section 2.1 - Sample Request
%% Software: "STUN test client"
%% Username: "evtj:h6vY"
%% Password: "VOkJxbRl1RmTxUk/WvJxBt"
rfc5769_sample_request_test() ->
    %% Expected request bytes from RFC 5769
    Expected = <<
        16#00, 16#01, 16#00, 16#58,  %% Binding Request, length 88
        16#21, 16#12, 16#a4, 16#42,  %% Magic cookie
        16#b7, 16#e7, 16#a7, 16#01,  %% Transaction ID (12 bytes)
        16#bc, 16#34, 16#d6, 16#86,
        16#fa, 16#87, 16#df, 16#ae,
        16#80, 16#22, 16#00, 16#10,  %% SOFTWARE attribute header
        16#53, 16#54, 16#55, 16#4e,  %% "STUN test client"
        16#20, 16#74, 16#65, 16#73,
        16#74, 16#20, 16#63, 16#6c,
        16#69, 16#65, 16#6e, 16#74,
        16#00, 16#24, 16#00, 16#04,  %% PRIORITY attribute
        16#6e, 16#00, 16#01, 16#ff,
        16#80, 16#29, 16#00, 16#08,  %% ICE-CONTROLLED attribute
        16#93, 16#2f, 16#f9, 16#b1,
        16#51, 16#26, 16#3b, 16#36,
        16#00, 16#06, 16#00, 16#09,  %% USERNAME
        16#65, 16#76, 16#74, 16#6a,  %% "evtj:h6vY"
        16#3a, 16#68, 16#36, 16#76,
        16#59, 16#20, 16#20, 16#20,
        16#00, 16#08, 16#00, 16#14,  %% MESSAGE-INTEGRITY
        16#9a, 16#ea, 16#a7, 16#0c,
        16#bf, 16#d8, 16#cb, 16#56,
        16#78, 16#1e, 16#f2, 16#b5,
        16#b2, 16#d3, 16#f2, 16#49,
        16#c1, 16#b5, 16#71, 16#a2,
        16#80, 16#28, 16#00, 16#04,  %% FINGERPRINT
        16#e5, 16#7a, 16#3b, 16#cf
    >>,

    %% Decode and verify structure
    {ok, Msg} = estun_codec:decode(Expected),
    ?assertEqual(request, Msg#stun_msg.class),
    ?assertEqual(binding, Msg#stun_msg.method),

    %% Transaction ID
    ExpectedTxnId = <<16#b7, 16#e7, 16#a7, 16#01,
                      16#bc, 16#34, 16#d6, 16#86,
                      16#fa, 16#87, 16#df, 16#ae>>,
    ?assertEqual(ExpectedTxnId, Msg#stun_msg.transaction_id).

%% RFC 5769 Section 2.2 - Sample IPv4 Response
rfc5769_ipv4_response_test() ->
    Expected = <<
        16#01, 16#01, 16#00, 16#3c,  %% Binding Success, length 60
        16#21, 16#12, 16#a4, 16#42,  %% Magic cookie
        16#b7, 16#e7, 16#a7, 16#01,  %% Transaction ID
        16#bc, 16#34, 16#d6, 16#86,
        16#fa, 16#87, 16#df, 16#ae,
        16#80, 16#22, 16#00, 16#0b,  %% SOFTWARE
        16#74, 16#65, 16#73, 16#74,  %% "test vector"
        16#20, 16#76, 16#65, 16#63,
        16#74, 16#6f, 16#72, 16#20,
        16#00, 16#20, 16#00, 16#08,  %% XOR-MAPPED-ADDRESS
        16#00, 16#01, 16#a1, 16#47,  %% IPv4, XOR'd port
        16#e1, 16#12, 16#a6, 16#43,  %% XOR'd address
        16#00, 16#08, 16#00, 16#14,  %% MESSAGE-INTEGRITY
        16#2b, 16#91, 16#f5, 16#99,
        16#fd, 16#9e, 16#90, 16#c3,
        16#8c, 16#74, 16#89, 16#f9,
        16#2a, 16#f9, 16#ba, 16#53,
        16#f0, 16#6b, 16#e7, 16#d7,
        16#80, 16#28, 16#00, 16#04,  %% FINGERPRINT
        16#c0, 16#7d, 16#4c, 16#96
    >>,

    {ok, Msg} = estun_codec:decode(Expected),
    ?assertEqual(success, Msg#stun_msg.class),
    ?assertEqual(binding, Msg#stun_msg.method),

    %% Check XOR-MAPPED-ADDRESS decode
    %% Expected: 192.0.2.1:32853 (after XOR)
    TxnId = <<16#b7, 16#e7, 16#a7, 16#01,
              16#bc, 16#34, 16#d6, 16#86,
              16#fa, 16#87, 16#df, 16#ae>>,

    case lists:keyfind(xor_mapped_address_raw, 1, Msg#stun_msg.attributes) of
        {xor_mapped_address_raw, Family, Port, XAddr} ->
            Addr = estun_crypto:decode_xor_address(Family, <<Port:16, XAddr/binary>>, TxnId),
            ?assertEqual({192, 0, 2, 1}, Addr#stun_addr.address),
            ?assertEqual(32853, Addr#stun_addr.port);
        false ->
            ?assert(false)
    end.

%% RFC 5769 Section 2.3 - Sample IPv6 Response
rfc5769_ipv6_response_test() ->
    Expected = <<
        16#01, 16#01, 16#00, 16#48,  %% Binding Success, length 72
        16#21, 16#12, 16#a4, 16#42,  %% Magic cookie
        16#b7, 16#e7, 16#a7, 16#01,  %% Transaction ID
        16#bc, 16#34, 16#d6, 16#86,
        16#fa, 16#87, 16#df, 16#ae,
        16#80, 16#22, 16#00, 16#0b,  %% SOFTWARE
        16#74, 16#65, 16#73, 16#74,  %% "test vector"
        16#20, 16#76, 16#65, 16#63,
        16#74, 16#6f, 16#72, 16#20,
        16#00, 16#20, 16#00, 16#14,  %% XOR-MAPPED-ADDRESS
        16#00, 16#02, 16#a1, 16#47,  %% IPv6, XOR'd port
        16#01, 16#13, 16#a9, 16#fa,  %% XOR'd address (16 bytes)
        16#a5, 16#d3, 16#f1, 16#79,
        16#bc, 16#25, 16#f4, 16#b5,
        16#be, 16#d2, 16#b9, 16#d9,
        16#00, 16#08, 16#00, 16#14,  %% MESSAGE-INTEGRITY
        16#a3, 16#82, 16#95, 16#4e,
        16#4b, 16#e6, 16#7b, 16#f1,
        16#17, 16#84, 16#c9, 16#7c,
        16#82, 16#92, 16#c2, 16#75,
        16#bf, 16#e3, 16#ed, 16#41,
        16#80, 16#28, 16#00, 16#04,  %% FINGERPRINT
        16#c8, 16#fb, 16#0b, 16#4c
    >>,

    {ok, Msg} = estun_codec:decode(Expected),
    ?assertEqual(success, Msg#stun_msg.class),
    ?assertEqual(binding, Msg#stun_msg.method),

    %% Check XOR-MAPPED-ADDRESS decode for IPv6
    %% Expected: 2001:db8:1234:5678:11:2233:4455:6677:32853
    TxnId = <<16#b7, 16#e7, 16#a7, 16#01,
              16#bc, 16#34, 16#d6, 16#86,
              16#fa, 16#87, 16#df, 16#ae>>,

    case lists:keyfind(xor_mapped_address_raw, 1, Msg#stun_msg.attributes) of
        {xor_mapped_address_raw, Family, Port, XAddr} ->
            Addr = estun_crypto:decode_xor_address(Family, <<Port:16, XAddr/binary>>, TxnId),
            ?assertEqual({16#2001, 16#db8, 16#1234, 16#5678,
                          16#11, 16#2233, 16#4455, 16#6677},
                         Addr#stun_addr.address),
            ?assertEqual(32853, Addr#stun_addr.port);
        false ->
            ?assert(false)
    end.

%%====================================================================
%% Codec Tests
%%====================================================================

encode_decode_binding_request_test() ->
    TxnId = crypto:strong_rand_bytes(12),
    Msg = #stun_msg{
        class = request,
        method = binding,
        transaction_id = TxnId,
        attributes = []
    },
    Encoded = estun_codec:encode(Msg),
    {ok, Decoded} = estun_codec:decode(Encoded),
    ?assertEqual(request, Decoded#stun_msg.class),
    ?assertEqual(binding, Decoded#stun_msg.method),
    ?assertEqual(TxnId, Decoded#stun_msg.transaction_id).

encode_decode_success_response_test() ->
    TxnId = crypto:strong_rand_bytes(12),
    Msg = #stun_msg{
        class = success,
        method = binding,
        transaction_id = TxnId,
        attributes = [{mapped_address, #stun_addr{
            family = ipv4,
            port = 12345,
            address = {192, 168, 1, 1}
        }}]
    },
    Encoded = estun_codec:encode(Msg),
    {ok, Decoded} = estun_codec:decode(Encoded),
    ?assertEqual(success, Decoded#stun_msg.class),
    ?assertEqual(binding, Decoded#stun_msg.method).

encode_decode_error_response_test() ->
    TxnId = crypto:strong_rand_bytes(12),
    Msg = #stun_msg{
        class = error,
        method = binding,
        transaction_id = TxnId,
        attributes = [{error_code, {400, <<"Bad Request">>}}]
    },
    Encoded = estun_codec:encode(Msg),
    {ok, Decoded} = estun_codec:decode(Encoded),
    ?assertEqual(error, Decoded#stun_msg.class),
    {error_code, {400, Reason}} = lists:keyfind(error_code, 1, Decoded#stun_msg.attributes),
    ?assertEqual(<<"Bad Request">>, Reason).

message_type_encoding_test() ->
    %% Test all class/method combinations
    ?assertEqual(16#0001, estun_codec:encode_msg_type(request, binding)),
    ?assertEqual(16#0011, estun_codec:encode_msg_type(indication, binding)),
    ?assertEqual(16#0101, estun_codec:encode_msg_type(success, binding)),
    ?assertEqual(16#0111, estun_codec:encode_msg_type(error, binding)),

    %% Verify roundtrip
    ?assertEqual({ok, request, binding}, estun_codec:decode_msg_type(16#0001)),
    ?assertEqual({ok, indication, binding}, estun_codec:decode_msg_type(16#0011)),
    ?assertEqual({ok, success, binding}, estun_codec:decode_msg_type(16#0101)),
    ?assertEqual({ok, error, binding}, estun_codec:decode_msg_type(16#0111)).

invalid_message_test() ->
    %% Too short
    ?assertEqual({error, invalid_stun_message}, estun_codec:decode(<<1, 2, 3>>)),

    %% Wrong magic
    WrongMagic = <<0, 1, 0, 0, 0, 0, 0, 0, 0:96>>,
    %% This should still parse as RFC 3489 format
    Result = estun_codec:decode(WrongMagic),
    ?assertMatch({ok, _}, Result).

%%====================================================================
%% Transaction ID Tests
%%====================================================================

transaction_id_uniqueness_test() ->
    Ids = [estun_codec:make_transaction_id() || _ <- lists:seq(1, 100)],
    UniqueIds = lists:usort(Ids),
    ?assertEqual(100, length(UniqueIds)).

transaction_id_length_test() ->
    TxnId = estun_codec:make_transaction_id(),
    ?assertEqual(12, byte_size(TxnId)).
