%% @doc STUN cryptographic functions (RFC 5389)
%%
%% Implements MESSAGE-INTEGRITY (HMAC-SHA1) and FINGERPRINT (CRC-32).
-module(estun_crypto).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([compute_message_integrity/2]).
-export([verify_message_integrity/3]).
-export([compute_fingerprint/1]).
-export([verify_fingerprint/1]).
-export([compute_key/3]).

%% XOR decoding
-export([decode_xor_address/3]).

%% CRC-32 XOR constant (RFC 5389)
-define(FINGERPRINT_XOR, 16#5354554e).

%%====================================================================
%% API
%%====================================================================

%% @doc Compute MESSAGE-INTEGRITY for a message
%% Key is either raw binary or {username, realm, password} for long-term
-spec compute_message_integrity(binary(), binary() | {binary(), binary(), binary()}) -> binary().
compute_message_integrity(MsgBin, Key) when is_binary(Key) ->
    %% Adjust length to include MESSAGE-INTEGRITY attribute (24 bytes)
    <<Type:16, Length:16, Rest/binary>> = MsgBin,
    AdjustedLength = Length + 24,  %% 4 header + 20 HMAC
    AdjustedMsg = <<Type:16, AdjustedLength:16, Rest/binary>>,
    crypto:mac(hmac, sha, Key, AdjustedMsg);
compute_message_integrity(MsgBin, {Username, Realm, Password}) ->
    Key = compute_key(Username, Realm, Password),
    compute_message_integrity(MsgBin, Key).

%% @doc Verify MESSAGE-INTEGRITY attribute
-spec verify_message_integrity(binary(), binary(), binary()) -> boolean().
verify_message_integrity(MsgBin, ReceivedHMAC, Key) ->
    %% Find MESSAGE-INTEGRITY position and truncate message
    case find_message_integrity_pos(MsgBin) of
        {ok, Pos} ->
            TruncatedMsg = binary:part(MsgBin, 0, Pos),
            %% Adjust length to end at MESSAGE-INTEGRITY
            <<Type:16, _Length:16, Rest/binary>> = TruncatedMsg,
            NewLength = byte_size(Rest) + 24,
            AdjustedMsg = <<Type:16, NewLength:16, Rest/binary>>,
            Expected = crypto:mac(hmac, sha, Key, AdjustedMsg),
            constant_time_compare(Expected, ReceivedHMAC);
        error ->
            false
    end.

%% @doc Compute FINGERPRINT (CRC-32 XOR'd with constant)
-spec compute_fingerprint(binary()) -> integer().
compute_fingerprint(MsgBin) ->
    %% Adjust length to include FINGERPRINT attribute (8 bytes)
    <<Type:16, Length:16, Rest/binary>> = MsgBin,
    AdjustedLength = Length + 8,
    AdjustedMsg = <<Type:16, AdjustedLength:16, Rest/binary>>,
    CRC = erlang:crc32(AdjustedMsg),
    CRC bxor ?FINGERPRINT_XOR.

%% @doc Verify FINGERPRINT attribute
-spec verify_fingerprint(binary()) -> boolean().
verify_fingerprint(MsgBin) ->
    case find_fingerprint(MsgBin) of
        {ok, ReceivedCRC, Pos} ->
            TruncatedMsg = binary:part(MsgBin, 0, Pos),
            %% Adjust length for FINGERPRINT
            <<Type:16, _Length:16, Rest/binary>> = TruncatedMsg,
            NewLength = byte_size(Rest) + 8,
            AdjustedMsg = <<Type:16, NewLength:16, Rest/binary>>,
            CRC = erlang:crc32(AdjustedMsg),
            Expected = CRC bxor ?FINGERPRINT_XOR,
            Expected =:= ReceivedCRC;
        error ->
            false
    end.

%% @doc Compute long-term credential key (RFC 5389 Section 15.4)
-spec compute_key(binary(), binary(), binary()) -> binary().
compute_key(Username, Realm, Password) ->
    crypto:hash(md5, <<Username/binary, ":", Realm/binary, ":", Password/binary>>).

%% @doc Decode XOR-MAPPED-ADDRESS value
-spec decode_xor_address(integer(), binary(), binary()) -> #stun_addr{}.
decode_xor_address(?ADDR_FAMILY_IPV4, <<XPort:16, XAddr:4/binary>>, _TxnId) ->
    Port = XPort bxor (?STUN_MAGIC bsr 16),
    <<XA:8, XB:8, XC:8, XD:8>> = XAddr,
    <<MA:8, MB:8, MC:8, MD:8>> = <<?STUN_MAGIC:32>>,
    #stun_addr{
        family = ipv4,
        port = Port,
        address = {XA bxor MA, XB bxor MB, XC bxor MC, XD bxor MD}
    };
decode_xor_address(?ADDR_FAMILY_IPV6, <<XPort:16, XAddr:16/binary>>, TxnId) ->
    Port = XPort bxor (?STUN_MAGIC bsr 16),
    <<XorInt:128>> = XAddr,
    <<MagicTxn:128>> = <<?STUN_MAGIC:32, TxnId/binary>>,
    AddrInt = XorInt bxor MagicTxn,
    <<A:16, B:16, C:16, D:16, E:16, F:16, G:16, H:16>> = <<AddrInt:128>>,
    #stun_addr{
        family = ipv6,
        port = Port,
        address = {A, B, C, D, E, F, G, H}
    }.

%%====================================================================
%% Internal
%%====================================================================

find_message_integrity_pos(Bin) ->
    find_attr_pos(Bin, ?ATTR_MESSAGE_INTEGRITY, ?STUN_HEADER_SIZE).

find_fingerprint(Bin) ->
    case find_attr_pos(Bin, ?ATTR_FINGERPRINT, ?STUN_HEADER_SIZE) of
        {ok, Pos} ->
            <<_:Pos/binary, ?ATTR_FINGERPRINT:16, 4:16, CRC:32, _/binary>> = Bin,
            {ok, CRC, Pos};
        error ->
            error
    end.

find_attr_pos(Bin, TargetType, Pos) when Pos < byte_size(Bin) - 3 ->
    <<_:Pos/binary, Type:16, Length:16, _/binary>> = Bin,
    case Type of
        TargetType ->
            {ok, Pos};
        _ ->
            PadLength = (4 - (Length rem 4)) rem 4,
            NextPos = Pos + 4 + Length + PadLength,
            find_attr_pos(Bin, TargetType, NextPos)
    end;
find_attr_pos(_, _, _) ->
    error.

%% Constant-time comparison to prevent timing attacks
constant_time_compare(A, B) when byte_size(A) =/= byte_size(B) ->
    false;
constant_time_compare(A, B) ->
    constant_time_compare(A, B, 0).

constant_time_compare(<<>>, <<>>, Acc) ->
    Acc =:= 0;
constant_time_compare(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (X bxor Y)).
