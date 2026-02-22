%% @doc STUN attribute encoding/decoding tests
-module(estun_attrs_tests).

-include_lib("eunit/include/eunit.hrl").
-include("estun.hrl").
-include("estun_attrs.hrl").

%%====================================================================
%% MAPPED-ADDRESS Tests
%%====================================================================

mapped_address_ipv4_test() ->
    Addr = #stun_addr{
        family = ipv4,
        port = 12345,
        address = {192, 168, 1, 1}
    },
    Encoded = estun_attrs:encode({mapped_address, Addr}),

    %% Decode
    <<Type:16, Length:16, Value:Length/binary, _Padding/binary>> = Encoded,
    ?assertEqual(?ATTR_MAPPED_ADDRESS, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({mapped_address, Addr}, Decoded).

mapped_address_ipv6_test() ->
    Addr = #stun_addr{
        family = ipv6,
        port = 54321,
        address = {16#2001, 16#db8, 0, 0, 0, 0, 0, 1}
    },
    Encoded = estun_attrs:encode({mapped_address, Addr}),

    <<Type:16, Length:16, Value:Length/binary, _Padding/binary>> = Encoded,
    ?assertEqual(?ATTR_MAPPED_ADDRESS, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({mapped_address, Addr}, Decoded).

%%====================================================================
%% ERROR-CODE Tests
%%====================================================================

error_code_400_test() ->
    Error = {400, <<"Bad Request">>},
    Encoded = estun_attrs:encode({error_code, Error}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_ERROR_CODE, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({error_code, Error}, Decoded).

error_code_401_test() ->
    Error = {401, <<"Unauthorized">>},
    Encoded = estun_attrs:encode({error_code, Error}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({error_code, Error}, Decoded).

error_code_420_test() ->
    Error = {420, <<"Unknown Attribute">>},
    Encoded = estun_attrs:encode({error_code, Error}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({error_code, Error}, Decoded).

%%====================================================================
%% USERNAME Tests
%%====================================================================

username_test() ->
    Username = <<"testuser:domain">>,
    Encoded = estun_attrs:encode({username, Username}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_USERNAME, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({username, Username}, Decoded).

%%====================================================================
%% REALM Tests
%%====================================================================

realm_test() ->
    Realm = <<"example.org">>,
    Encoded = estun_attrs:encode({realm, Realm}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_REALM, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({realm, Realm}, Decoded).

%%====================================================================
%% NONCE Tests
%%====================================================================

nonce_test() ->
    Nonce = <<"abcdef123456">>,
    Encoded = estun_attrs:encode({nonce, Nonce}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_NONCE, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({nonce, Nonce}, Decoded).

%%====================================================================
%% SOFTWARE Tests
%%====================================================================

software_test() ->
    Software = <<"ESTUN/0.1.0">>,
    Encoded = estun_attrs:encode({software, Software}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_SOFTWARE, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({software, Software}, Decoded).

%%====================================================================
%% CHANGE-REQUEST Tests (RFC 5780)
%%====================================================================

change_request_ip_port_test() ->
    Flags = [ip, port],
    Encoded = estun_attrs:encode({change_request, Flags}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_CHANGE_REQUEST, Type),
    {change_request, DecodedFlags} = estun_attrs:decode(Type, Value),
    ?assert(lists:member(ip, DecodedFlags)),
    ?assert(lists:member(port, DecodedFlags)).

change_request_ip_only_test() ->
    Flags = [ip],
    Encoded = estun_attrs:encode({change_request, Flags}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    {change_request, DecodedFlags} = estun_attrs:decode(Type, Value),
    ?assert(lists:member(ip, DecodedFlags)),
    ?assertNot(lists:member(port, DecodedFlags)).

change_request_port_only_test() ->
    Flags = [port],
    Encoded = estun_attrs:encode({change_request, Flags}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    {change_request, DecodedFlags} = estun_attrs:decode(Type, Value),
    ?assertNot(lists:member(ip, DecodedFlags)),
    ?assert(lists:member(port, DecodedFlags)).

%%====================================================================
%% RESPONSE-PORT Tests (RFC 5780)
%%====================================================================

response_port_test() ->
    Port = 54321,
    Encoded = estun_attrs:encode({response_port, Port}),

    <<Type:16, Length:16, Value:Length/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_RESPONSE_PORT, Type),
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({response_port, Port}, Decoded).

%%====================================================================
%% FINGERPRINT Tests
%%====================================================================

fingerprint_test() ->
    CRC = 16#12345678,
    Encoded = estun_attrs:encode({fingerprint, CRC}),

    <<Type:16, Length:16, Value:4/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_FINGERPRINT, Type),
    ?assertEqual(4, Length),
    {fingerprint, DecodedCRC} = estun_attrs:decode(Type, Value),
    ?assertEqual(CRC, DecodedCRC).

%%====================================================================
%% MESSAGE-INTEGRITY Tests
%%====================================================================

message_integrity_test() ->
    HMAC = crypto:strong_rand_bytes(20),
    Encoded = estun_attrs:encode({message_integrity, HMAC}),

    <<Type:16, Length:16, Value:20/binary, _/binary>> = Encoded,
    ?assertEqual(?ATTR_MESSAGE_INTEGRITY, Type),
    ?assertEqual(20, Length),
    {message_integrity, DecodedHMAC} = estun_attrs:decode(Type, Value),
    ?assertEqual(HMAC, DecodedHMAC).

%%====================================================================
%% Attribute List Tests
%%====================================================================

encode_decode_all_test() ->
    Attrs = [
        {username, <<"user">>},
        {realm, <<"realm">>},
        {software, <<"test">>}
    ],
    Encoded = estun_attrs:encode_all(Attrs),
    {ok, Decoded} = estun_attrs:decode_all(Encoded),
    ?assertEqual(3, length(Decoded)),
    ?assert(lists:keymember(username, 1, Decoded)),
    ?assert(lists:keymember(realm, 1, Decoded)),
    ?assert(lists:keymember(software, 1, Decoded)).

%%====================================================================
%% Padding Tests
%%====================================================================

padding_test() ->
    %% Test attribute with length not divisible by 4
    Username = <<"abc">>,  %% 3 bytes
    Encoded = estun_attrs:encode({username, Username}),

    %% Should be padded to 4-byte boundary
    ?assertEqual(0, byte_size(Encoded) rem 4).

%%====================================================================
%% Unknown Attribute Tests
%%====================================================================

unknown_attribute_test() ->
    Type = 16#FFFF,  %% Unknown type
    Value = <<"unknown data">>,
    Decoded = estun_attrs:decode(Type, Value),
    ?assertEqual({unknown, Type, Value}, Decoded).
