# estun_codec Module

STUN message encoding and decoding (RFC 5389).

## Types

```erlang
-record(stun_msg, {
    class           :: request | indication | success | error,
    method          :: binding | atom() | non_neg_integer(),
    transaction_id  :: binary(),
    attributes = [] :: [stun_attr()]
}).

-type stun_attr() :: {atom(), term()}.
```

## Functions

### encode/1

Encode a STUN message to binary.

```erlang
-spec encode(#stun_msg{}) -> binary().
```

**Example:**

```erlang
Msg = #stun_msg{
    class = request,
    method = binding,
    transaction_id = crypto:strong_rand_bytes(12),
    attributes = []
},
Binary = estun_codec:encode(Msg).
```

### decode/1

Decode a binary STUN message.

```erlang
-spec decode(binary()) -> {ok, #stun_msg{}} | {error, term()}.
```

**Example:**

```erlang
case estun_codec:decode(Binary) of
    {ok, #stun_msg{class = success} = Msg} ->
        io:format("Success response~n");
    {ok, #stun_msg{class = error} = Msg} ->
        io:format("Error response~n");
    {error, Reason} ->
        io:format("Decode failed: ~p~n", [Reason])
end.
```

### encode_binding_request/1, encode_binding_request/2

Create an encoded binding request.

```erlang
-spec encode_binding_request(binary()) -> binary().
-spec encode_binding_request(binary(), [stun_attr()]) -> binary().
```

**Example:**

```erlang
TxnId = estun_codec:make_transaction_id(),
Request = estun_codec:encode_binding_request(TxnId).

%% With attributes
Request = estun_codec:encode_binding_request(TxnId, [
    {software, <<"MyApp/1.0">>}
]).
```

### make_transaction_id/0

Generate a random 12-byte transaction ID.

```erlang
-spec make_transaction_id() -> binary().
```

### encode_msg_type/2

Encode message class and method to 16-bit type.

```erlang
-spec encode_msg_type(atom(), atom()) -> 0..16#FFFF.
```

### decode_msg_type/1

Decode 16-bit message type to class and method.

```erlang
-spec decode_msg_type(0..16#FFFF) -> {ok, atom(), atom()} | {error, invalid_msg_type}.
```

## Message Classes

| Class | Value | Description |
|-------|-------|-------------|
| `request` | 0b00 | Client request |
| `indication` | 0b01 | No response expected |
| `success` | 0b10 | Successful response |
| `error` | 0b11 | Error response |

## Message Methods

| Method | Value | Description |
|--------|-------|-------------|
| `binding` | 0x001 | Binding request/response |

## RFC 5769 Test Vectors

The codec is verified against RFC 5769 test vectors:

```erlang
%% Section 2.1 - Sample Request
%% Section 2.2 - Sample IPv4 Response
%% Section 2.3 - Sample IPv6 Response

%% Run tests
rebar3 eunit --module=estun_codec_tests
```
