%% @doc STUN attribute encoding/decoding (RFC 5389, RFC 5780)
-module(estun_attrs).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([encode_all/1, decode_all/1]).
-export([encode/1, decode/2]).
-export([get_mapped_address/1, get_xor_mapped_address/1]).
-export([get_error/1, get_other_address/1]).
-export([get_attr/2]).

%%====================================================================
%% API
%%====================================================================

-spec encode_all([stun_attr()]) -> binary().
encode_all(Attrs) ->
    lists:foldl(fun(Attr, Acc) ->
        AttrData = encode(Attr),
        <<Acc/binary, AttrData/binary>>
    end, <<>>, Attrs).

-spec decode_all(binary()) -> {ok, [stun_attr()]} | {error, term()}.
decode_all(Bin) ->
    decode_attrs(Bin, []).

-spec get_mapped_address(#stun_msg{}) -> #stun_addr{} | undefined.
get_mapped_address(#stun_msg{attributes = Attrs}) ->
    case get_attr(xor_mapped_address, Attrs) of
        {ok, Addr} -> Addr;
        error ->
            case get_attr(mapped_address, Attrs) of
                {ok, Addr} -> Addr;
                error -> undefined
            end
    end.

-spec get_xor_mapped_address(#stun_msg{}) -> #stun_addr{} | undefined.
get_xor_mapped_address(#stun_msg{attributes = Attrs}) ->
    case get_attr(xor_mapped_address, Attrs) of
        {ok, Addr} -> Addr;
        error -> undefined
    end.

-spec get_other_address(#stun_msg{}) -> #stun_addr{} | undefined.
get_other_address(#stun_msg{attributes = Attrs}) ->
    case get_attr(other_address, Attrs) of
        {ok, Addr} -> Addr;
        error -> undefined
    end.

-spec get_error(#stun_msg{}) -> {integer(), binary()} | undefined.
get_error(#stun_msg{attributes = Attrs}) ->
    case get_attr(error_code, Attrs) of
        {ok, Error} -> Error;
        error -> undefined
    end.

-spec get_attr(atom(), [stun_attr()]) -> {ok, term()} | error.
get_attr(Name, Attrs) ->
    case lists:keyfind(Name, 1, Attrs) of
        {Name, Value} -> {ok, Value};
        false -> error
    end.

%%====================================================================
%% Encoding
%%====================================================================

-spec encode(stun_attr()) -> binary().
%% MAPPED-ADDRESS (RFC 5389)
encode({mapped_address, #stun_addr{family = Family, port = Port, address = Addr}}) ->
    FamilyByte = family_to_byte(Family),
    AddrBin = encode_address(Family, Addr),
    Value = <<0:8, FamilyByte:8, Port:16, AddrBin/binary>>,
    encode_tlv(?ATTR_MAPPED_ADDRESS, Value);

%% XOR-MAPPED-ADDRESS (RFC 5389)
encode({xor_mapped_address, #stun_addr{family = Family, port = Port, address = Addr}, TxnId}) ->
    FamilyByte = family_to_byte(Family),
    XPort = Port bxor (?STUN_MAGIC bsr 16),
    XAddr = xor_address(Family, Addr, TxnId),
    Value = <<0:8, FamilyByte:8, XPort:16, XAddr/binary>>,
    encode_tlv(?ATTR_XOR_MAPPED_ADDRESS, Value);

%% USERNAME (RFC 5389)
encode({username, Username}) when is_binary(Username) ->
    encode_tlv(?ATTR_USERNAME, Username);

%% MESSAGE-INTEGRITY (RFC 5389)
encode({message_integrity, HMAC}) when byte_size(HMAC) =:= 20 ->
    encode_tlv(?ATTR_MESSAGE_INTEGRITY, HMAC);

%% FINGERPRINT (RFC 5389)
encode({fingerprint, CRC}) when is_integer(CRC) ->
    encode_tlv(?ATTR_FINGERPRINT, <<CRC:32>>);

%% ERROR-CODE (RFC 5389)
encode({error_code, {Code, Reason}}) when is_integer(Code), is_binary(Reason) ->
    Class = Code div 100,
    Number = Code rem 100,
    Value = <<0:21, Class:3, Number:8, Reason/binary>>,
    encode_tlv(?ATTR_ERROR_CODE, Value);

%% REALM (RFC 5389)
encode({realm, Realm}) when is_binary(Realm) ->
    encode_tlv(?ATTR_REALM, Realm);

%% NONCE (RFC 5389)
encode({nonce, Nonce}) when is_binary(Nonce) ->
    encode_tlv(?ATTR_NONCE, Nonce);

%% SOFTWARE (RFC 5389)
encode({software, Software}) when is_binary(Software) ->
    encode_tlv(?ATTR_SOFTWARE, Software);

%% CHANGE-REQUEST (RFC 5780)
encode({change_request, Flags}) when is_list(Flags) ->
    FlagBits = lists:foldl(fun
        (ip, Acc) -> Acc bor ?CHANGE_IP;
        (port, Acc) -> Acc bor ?CHANGE_PORT
    end, 0, Flags),
    encode_tlv(?ATTR_CHANGE_REQUEST, <<0:24, FlagBits:8>>);

%% RESPONSE-PORT (RFC 5780)
encode({response_port, Port}) when is_integer(Port) ->
    encode_tlv(?ATTR_RESPONSE_PORT, <<Port:16>>);

%% PADDING (RFC 5780)
encode({padding, Size}) when is_integer(Size) ->
    encode_tlv(?ATTR_PADDING, binary:copy(<<0>>, Size));

%% Unknown attribute (pass through)
encode({unknown, Type, Value}) when is_integer(Type), is_binary(Value) ->
    encode_tlv(Type, Value).

encode_tlv(Type, Value) ->
    Length = byte_size(Value),
    Padding = (4 - (Length rem 4)) rem 4,
    PadBytes = binary:copy(<<0>>, Padding),
    <<Type:16, Length:16, Value/binary, PadBytes/binary>>.

%%====================================================================
%% Decoding
%%====================================================================

decode_attrs(<<>>, Acc) ->
    {ok, lists:reverse(Acc)};
decode_attrs(<<Type:16, Length:16, Rest/binary>>, Acc) ->
    PadLength = (4 - (Length rem 4)) rem 4,
    case Rest of
        <<Value:Length/binary, _Padding:PadLength/binary, Remaining/binary>> ->
            Attr = decode(Type, Value),
            decode_attrs(Remaining, [Attr | Acc]);
        _ when byte_size(Rest) >= Length ->
            %% Handle case where padding is missing at end
            <<Value:Length/binary, Remaining/binary>> = Rest,
            Attr = decode(Type, Value),
            decode_attrs(Remaining, [Attr | Acc]);
        _ ->
            {error, {truncated_attribute, Type, Length, byte_size(Rest)}}
    end;
decode_attrs(Bin, _Acc) when byte_size(Bin) < 4 ->
    %% Trailing bytes (common in some implementations)
    {ok, []}.

-spec decode(integer(), binary()) -> stun_attr().
%% MAPPED-ADDRESS
decode(?ATTR_MAPPED_ADDRESS, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {mapped_address, decode_address(Family, Port, AddrBin)};

%% XOR-MAPPED-ADDRESS
%% Note: Returns raw XOR'd values - full decoding requires transaction ID
decode(?ATTR_XOR_MAPPED_ADDRESS, <<0:8, Family:8, XPort:16, XAddr/binary>>) ->
    {xor_mapped_address_raw, Family, XPort, XAddr};

%% USERNAME
decode(?ATTR_USERNAME, Username) ->
    {username, Username};

%% MESSAGE-INTEGRITY
decode(?ATTR_MESSAGE_INTEGRITY, HMAC) ->
    {message_integrity, HMAC};

%% FINGERPRINT
decode(?ATTR_FINGERPRINT, <<CRC:32>>) ->
    {fingerprint, CRC};

%% ERROR-CODE
decode(?ATTR_ERROR_CODE, <<0:21, Class:3, Number:8, Reason/binary>>) ->
    {error_code, {Class * 100 + Number, Reason}};

%% REALM
decode(?ATTR_REALM, Realm) ->
    {realm, Realm};

%% NONCE
decode(?ATTR_NONCE, Nonce) ->
    {nonce, Nonce};

%% SOFTWARE
decode(?ATTR_SOFTWARE, Software) ->
    {software, Software};

%% ALTERNATE-SERVER
decode(?ATTR_ALTERNATE_SERVER, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {alternate_server, decode_address(Family, Port, AddrBin)};

%% OTHER-ADDRESS (RFC 5780)
decode(?ATTR_OTHER_ADDRESS, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {other_address, decode_address(Family, Port, AddrBin)};

%% RESPONSE-ORIGIN (RFC 5780)
decode(?ATTR_RESPONSE_ORIGIN, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {response_origin, decode_address(Family, Port, AddrBin)};

%% CHANGE-REQUEST (RFC 5780 / RFC 3489)
decode(?ATTR_CHANGE_REQUEST, <<_:24, Flags:8>>) ->
    FlagList = lists:filtermap(fun
        (ip) -> (Flags band ?CHANGE_IP) =/= 0;
        (port) -> (Flags band ?CHANGE_PORT) =/= 0
    end, [ip, port]),
    {change_request, FlagList};

%% RESPONSE-PORT (RFC 5780)
decode(?ATTR_RESPONSE_PORT, <<Port:16, _/binary>>) ->
    {response_port, Port};

%% RFC 3489 compatibility attributes
decode(?ATTR_SOURCE_ADDRESS, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {source_address, decode_address(Family, Port, AddrBin)};

decode(?ATTR_CHANGED_ADDRESS, <<0:8, Family:8, Port:16, AddrBin/binary>>) ->
    {changed_address, decode_address(Family, Port, AddrBin)};

%% Unknown attribute
decode(Type, Value) ->
    {unknown, Type, Value}.

%%====================================================================
%% Address Helpers
%%====================================================================

family_to_byte(ipv4) -> ?ADDR_FAMILY_IPV4;
family_to_byte(ipv6) -> ?ADDR_FAMILY_IPV6.

byte_to_family(?ADDR_FAMILY_IPV4) -> ipv4;
byte_to_family(?ADDR_FAMILY_IPV6) -> ipv6.

encode_address(ipv4, {A, B, C, D}) ->
    <<A:8, B:8, C:8, D:8>>;
encode_address(ipv6, {A, B, C, D, E, F, G, H}) ->
    <<A:16, B:16, C:16, D:16, E:16, F:16, G:16, H:16>>.

decode_address(Family, Port, AddrBin) ->
    #stun_addr{
        family = byte_to_family(Family),
        port = Port,
        address = decode_ip(Family, AddrBin)
    }.

decode_ip(?ADDR_FAMILY_IPV4, <<A:8, B:8, C:8, D:8>>) ->
    {A, B, C, D};
decode_ip(?ADDR_FAMILY_IPV6, <<A:16, B:16, C:16, D:16, E:16, F:16, G:16, H:16>>) ->
    {A, B, C, D, E, F, G, H}.

xor_address(ipv4, {A, B, C, D}, _TxnId) ->
    <<Magic:32>> = <<?STUN_MAGIC:32>>,
    <<XA:8, XB:8, XC:8, XD:8>> = <<((A bsl 24 bor B bsl 16 bor C bsl 8 bor D) bxor Magic):32>>,
    <<XA:8, XB:8, XC:8, XD:8>>;
xor_address(ipv6, {A, B, C, D, E, F, G, H}, TxnId) ->
    AddrInt = (A bsl 112) bor (B bsl 96) bor (C bsl 80) bor (D bsl 64) bor
              (E bsl 48) bor (F bsl 32) bor (G bsl 16) bor H,
    <<MagicTxn:128>> = <<?STUN_MAGIC:32, TxnId/binary>>,
    XorInt = AddrInt bxor MagicTxn,
    <<XorInt:128>>.
