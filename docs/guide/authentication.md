# Authentication

estun supports STUN authentication mechanisms defined in RFC 5389.

## Authentication Types

### No Authentication

Most public STUN servers don't require authentication:

```erlang
estun:add_server(#{
    host => "stun.l.google.com",
    port => 19302,
    auth => none  %% Default
}).
```

### Short-Term Authentication

Used for single-session credentials (common in ICE):

```erlang
estun:add_server(#{
    host => "stun.example.com",
    port => 3478,
    auth => short_term,
    username => <<"session:abc123">>,
    password => <<"temp_password">>
}).
```

Short-term credentials are typically:

- Generated per session
- Short-lived (minutes to hours)
- Shared out-of-band before the session

### Long-Term Authentication

Used for persistent credentials:

```erlang
estun:add_server(#{
    host => "stun.example.com",
    port => 3478,
    auth => long_term,
    username => <<"alice">>,
    password => <<"secret">>,
    realm => <<"example.com">>
}).
```

Long-term credentials use MD5 hashing:

```
key = MD5(username:realm:password)
```

## How Authentication Works

### Request Flow

1. **Unauthenticated Request**: Client sends initial request
2. **401 Response**: Server responds with `realm` and `nonce`
3. **Authenticated Request**: Client resends with credentials
4. **Success**: Server verifies and responds

### MESSAGE-INTEGRITY

Requests include HMAC-SHA1 of the message:

```erlang
%% estun handles this automatically when auth is configured
HMAC = crypto:mac(hmac, sha, Key, Message)
```

### FINGERPRINT

Optional CRC-32 for message integrity:

```erlang
CRC = erlang:crc32(Message) bxor 16#5354554e
```

## Handling 401 Responses

estun automatically handles authentication challenges:

```erlang
%% First request may return 401 with realm/nonce
%% estun automatically retries with credentials

{ok, Addr} = estun:discover(authenticated_server).
```

## Updating Credentials

For servers that rotate nonces:

```erlang
%% Update nonce after receiving stale nonce error
{ok, Server} = estun:get_server(ServerId),
UpdatedServer = Server#stun_server{nonce = NewNonce},
%% Re-add server (or implement update function)
```

## Credential Security

!!! warning "Security Best Practices"

    - Never hardcode credentials in source code
    - Use environment variables or secure config
    - Rotate credentials regularly
    - Use TLS for credential exchange

```erlang
%% Load credentials from environment
Username = list_to_binary(os:getenv("STUN_USER", "")),
Password = list_to_binary(os:getenv("STUN_PASS", "")),

estun:add_server(#{
    host => "stun.example.com",
    auth => long_term,
    username => Username,
    password => Password,
    realm => <<"example.com">>
}).
```

## Example: Authenticated Server

```erlang
-module(auth_example).
-export([connect/0]).

-include_lib("estun/include/estun.hrl").

connect() ->
    application:ensure_all_started(estun),

    %% Add authenticated server
    {ok, _} = estun:add_server(#{
        host => "turn.example.com",
        port => 3478,
        auth => long_term,
        username => <<"alice">>,
        password => <<"secret123">>,
        realm => <<"example.com">>
    }, my_server),

    %% Discover - authentication handled automatically
    case estun:discover(my_server) of
        {ok, Addr} ->
            io:format("Success! Address: ~p:~p~n", [
                Addr#stun_addr.address,
                Addr#stun_addr.port
            ]);
        {error, {401, _}} ->
            io:format("Authentication failed~n");
        {error, Reason} ->
            io:format("Error: ~p~n", [Reason])
    end.
```

## OAuth Authentication (RFC 7635)

!!! note "Future Feature"
    OAuth authentication (RFC 7635) is planned for a future release.

OAuth allows using third-party identity providers for STUN/TURN authentication:

```erlang
%% Future API (not yet implemented)
estun:add_server(#{
    host => "turn.example.com",
    auth => oauth,
    access_token => <<"eyJ...">>,
    token_type => <<"Bearer">>
}).
```
