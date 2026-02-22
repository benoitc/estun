%% @doc STUN crypto tests
-module(estun_crypto_tests).

-include_lib("eunit/include/eunit.hrl").
-include("estun.hrl").

%%====================================================================
%% MESSAGE-INTEGRITY Tests (RFC 5769)
%%====================================================================

%% Test with RFC 5769 test vector password
message_integrity_short_term_test() ->
    Password = <<"VOkJxbRl1RmTxUk/WvJxBt">>,
    TxnId = <<16#b7, 16#e7, 16#a7, 16#01,
              16#bc, 16#34, 16#d6, 16#86,
              16#fa, 16#87, 16#df, 16#ae>>,

    %% Create a simple binding request
    Msg = estun_codec:encode_binding_request(TxnId),

    %% Compute HMAC
    HMAC = estun_crypto:compute_message_integrity(Msg, Password),
    ?assertEqual(20, byte_size(HMAC)).

%% Long-term credential test
message_integrity_long_term_test() ->
    Username = <<"user">>,
    Realm = <<"realm">>,
    Password = <<"pass">>,

    %% Compute key
    Key = estun_crypto:compute_key(Username, Realm, Password),
    ?assertEqual(16, byte_size(Key)),  %% MD5 produces 16 bytes

    %% Expected: MD5("user:realm:pass")
    ExpectedKey = crypto:hash(md5, <<"user:realm:pass">>),
    ?assertEqual(ExpectedKey, Key).

%%====================================================================
%% FINGERPRINT Tests
%%====================================================================

fingerprint_test() ->
    TxnId = crypto:strong_rand_bytes(12),
    Msg = estun_codec:encode_binding_request(TxnId),

    %% Compute fingerprint
    Fingerprint = estun_crypto:compute_fingerprint(Msg),
    ?assert(is_integer(Fingerprint)),
    ?assert(Fingerprint >= 0),
    ?assert(Fingerprint =< 16#FFFFFFFF).

%%====================================================================
%% XOR Address Tests
%%====================================================================

xor_ipv4_address_test() ->
    TxnId = <<0:96>>,
    %% XOR'd data for 192.0.2.1:32853
    %% Port XOR with magic cookie upper bits: 32853 XOR (0x2112A442 >> 16) = 0xa147
    %% Address XOR with magic cookie: 192.0.2.1 XOR 0x2112A442

    %% Create XOR'd values manually
    Port = 32853,
    XPort = Port bxor (16#2112A442 bsr 16),  %% = 0xa147

    %% Test decode
    Family = 1,  %% IPv4
    XAddr = <<16#e1, 16#12, 16#a6, 16#43>>,  %% XOR'd 192.0.2.1

    Addr = estun_crypto:decode_xor_address(Family, <<XPort:16, XAddr/binary>>, TxnId),
    ?assertEqual(ipv4, Addr#stun_addr.family),
    ?assertEqual(32853, Addr#stun_addr.port),
    ?assertEqual({192, 0, 2, 1}, Addr#stun_addr.address).

xor_ipv6_address_test() ->
    TxnId = <<16#b7, 16#e7, 16#a7, 16#01,
              16#bc, 16#34, 16#d6, 16#86,
              16#fa, 16#87, 16#df, 16#ae>>,

    %% From RFC 5769 IPv6 test
    Family = 2,  %% IPv6
    XPort = 16#a147,
    XAddr = <<16#01, 16#13, 16#a9, 16#fa,
              16#a5, 16#d3, 16#f1, 16#79,
              16#bc, 16#25, 16#f4, 16#b5,
              16#be, 16#d2, 16#b9, 16#d9>>,

    Addr = estun_crypto:decode_xor_address(Family, <<XPort:16, XAddr/binary>>, TxnId),
    ?assertEqual(ipv6, Addr#stun_addr.family),
    ?assertEqual(32853, Addr#stun_addr.port),
    ?assertEqual({16#2001, 16#db8, 16#1234, 16#5678,
                  16#11, 16#2233, 16#4455, 16#6677},
                 Addr#stun_addr.address).
