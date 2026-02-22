%% @doc STUN message codec (RFC 5389)
%%
%% Handles binary encoding and decoding of STUN messages.
%% Supports RFC 5389 (modern STUN) and RFC 3489 (classic) formats.
-module(estun_codec).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([encode/1, decode/1]).
-export([encode_binding_request/1, encode_binding_request/2]).
-export([make_transaction_id/0]).

%% Message type encoding/decoding
-export([encode_msg_type/2, decode_msg_type/1]).

%%====================================================================
%% API
%%====================================================================

-spec encode(#stun_msg{}) -> binary().
encode(#stun_msg{class = Class, method = Method,
                 transaction_id = TxnId, attributes = Attrs}) ->
    MsgType = encode_msg_type(Class, Method),
    AttrsData = estun_attrs:encode_all(Attrs),
    Length = byte_size(AttrsData),
    <<MsgType:16, Length:16, ?STUN_MAGIC:32, TxnId:12/binary, AttrsData/binary>>.

-spec decode(binary()) -> {ok, #stun_msg{}} | {error, term()}.
decode(<<MsgType:16, Length:16, ?STUN_MAGIC:32, TxnId:12/binary, Rest/binary>>)
  when byte_size(Rest) >= Length ->
    AttrsData = binary:part(Rest, 0, Length),
    {ok, Class, Method} = decode_msg_type(MsgType),
    case estun_attrs:decode_all(AttrsData) of
        {ok, Attrs} ->
            {ok, #stun_msg{
                class = Class,
                method = Method,
                transaction_id = TxnId,
                attributes = Attrs
            }};
        Error ->
            Error
    end;
%% RFC 3489 compatibility (no magic cookie)
decode(<<MsgType:16, Length:16, TxnId:16/binary, Rest/binary>>)
  when byte_size(Rest) >= Length ->
    AttrsData = binary:part(Rest, 0, Length),
    {ok, Class, Method} = decode_msg_type(MsgType),
    case estun_attrs:decode_all(AttrsData) of
        {ok, Attrs} ->
            {ok, #stun_msg{
                class = Class,
                method = Method,
                transaction_id = TxnId,
                attributes = Attrs
            }};
        Error ->
            Error
    end;
decode(<<_:16, Length:16, _/binary>> = Bin) when byte_size(Bin) < Length + 20 ->
    {error, incomplete};
decode(_) ->
    {error, invalid_stun_message}.

-spec encode_binding_request(binary()) -> binary().
encode_binding_request(TxnId) ->
    encode_binding_request(TxnId, []).

-spec encode_binding_request(binary(), [stun_attr()]) -> binary().
encode_binding_request(TxnId, ExtraAttrs) ->
    encode(#stun_msg{
        class = request,
        method = binding,
        transaction_id = TxnId,
        attributes = ExtraAttrs
    }).

-spec make_transaction_id() -> binary().
make_transaction_id() ->
    crypto:strong_rand_bytes(12).

%%====================================================================
%% Message Type Encoding
%%====================================================================

%% Message type format (RFC 5389):
%%   0                 1
%%   2  3  4 5 6 7 8 9 0 1 2 3 4 5
%%   +--+--+-+-+-+-+-+-+-+-+-+-+-+-+
%%   |M |M |M|M|M|C|M|M|M|C|M|M|M|M|
%%   |11|10|9|8|7|1|6|5|4|0|3|2|1|0|
%%   +--+--+-+-+-+-+-+-+-+-+-+-+-+-+

-spec encode_msg_type(atom(), atom()) -> 0..16#FFFF.
encode_msg_type(Class, Method) ->
    C = class_to_bits(Class),
    M = method_to_int(Method),
    %% C0 at bit 4, C1 at bit 8
    %% Method bits: M0-M3 at bits 0-3, M4-M6 at bits 5-7, M7-M11 at bits 9-13
    C0 = C band 1,
    C1 = (C bsr 1) band 1,
    M_0_3 = M band 16#F,
    M_4_6 = (M bsr 4) band 16#7,
    M_7_11 = (M bsr 7) band 16#1F,
    (M_7_11 bsl 9) bor (C1 bsl 8) bor (M_4_6 bsl 5) bor (C0 bsl 4) bor M_0_3.

-spec decode_msg_type(0..16#FFFF) -> {ok, atom(), atom() | non_neg_integer()}.
decode_msg_type(MsgType) ->
    C0 = (MsgType bsr 4) band 1,
    C1 = (MsgType bsr 8) band 1,
    C = (C1 bsl 1) bor C0,
    M_0_3 = MsgType band 16#F,
    M_4_6 = (MsgType bsr 5) band 16#7,
    M_7_11 = (MsgType bsr 9) band 16#1F,
    M = (M_7_11 bsl 7) bor (M_4_6 bsl 4) bor M_0_3,
    {ok, bits_to_class(C), int_to_method(M)}.

%%====================================================================
%% Internal
%%====================================================================

class_to_bits(request) -> ?STUN_CLASS_REQUEST;
class_to_bits(indication) -> ?STUN_CLASS_INDICATION;
class_to_bits(success) -> ?STUN_CLASS_SUCCESS;
class_to_bits(error) -> ?STUN_CLASS_ERROR.

bits_to_class(?STUN_CLASS_REQUEST) -> request;
bits_to_class(?STUN_CLASS_INDICATION) -> indication;
bits_to_class(?STUN_CLASS_SUCCESS) -> success;
bits_to_class(?STUN_CLASS_ERROR) -> error.

method_to_int(binding) -> ?STUN_METHOD_BINDING;
method_to_int(N) when is_integer(N) -> N.

int_to_method(?STUN_METHOD_BINDING) -> binding;
int_to_method(N) -> N.
