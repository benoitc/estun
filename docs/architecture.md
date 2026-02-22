# Architecture

This document describes the internal architecture of estun.

## Module Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         estun.erl                               │
│                     (Public API Facade)                         │
└─────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  estun_pool   │     │ estun_client_sup│     │estun_nat_       │
│  (Server Pool)│     │  (Supervisor)   │     │discovery        │
└───────────────┘     └────────┬────────┘     └─────────────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │  estun_client   │
                      │  (gen_statem)   │
                      └────────┬────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌───────────────┐     ┌─────────────────┐     ┌───────────────┐
│ estun_socket  │     │  estun_codec    │     │ estun_punch   │
│ (Socket Wrap) │     │  (Protocol)     │     │(Hole Punch)   │
└───────────────┘     └────────┬────────┘     └───────────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
        ┌───────────┐  ┌─────────────┐  ┌───────────┐
        │estun_attrs│  │estun_crypto │  │estun_auth │
        │(Attributes│  │(HMAC/CRC)   │  │(Auth)     │
        └───────────┘  └─────────────┘  └───────────┘
```

## Supervision Tree

```
estun_sup (one_for_one)
    │
    ├── estun_pool (worker)
    │       Server pool management
    │
    └── estun_client_sup (simple_one_for_one)
            │
            ├── estun_client (worker)
            ├── estun_client (worker)
            └── ... (dynamic)
```

## Core Modules

### estun.erl

The public API facade. All external interactions go through this module.

**Responsibilities:**

- Server management (add, remove, list)
- Simple discovery operations
- Socket lifecycle management
- Hole punching coordination

### estun_pool.erl

Manages configured STUN servers.

**Responsibilities:**

- Store server configurations
- Provide default server selection
- Server health tracking (future)

**State:**

```erlang
-record(state, {
    servers = #{} :: #{term() => #stun_server{}},
    default_id :: term() | undefined,
    next_id = 1 :: pos_integer()
}).
```

### estun_client.erl

`gen_statem` implementation for STUN client operations.

**States:**

| State | Description |
|-------|-------------|
| `idle` | Initial state, socket may be open |
| `binding` | Waiting for STUN response |
| `bound` | Have valid binding |

**State Transitions:**

```
          bind
idle ──────────► binding
  ▲                 │
  │   timeout       │ success
  │   error         │
  └─────────────────┴───────► bound
                                │
                                │ transfer
                                ▼
                              (stop)
```

**Key Features:**

- Retransmission with exponential backoff
- Keepalive management
- Event notification
- Socket ownership transfer

### estun_socket.erl

Wrapper around OTP 28+ `socket` module.

**Responsibilities:**

- Socket creation with proper options
- Platform-agnostic SO_REUSEPORT
- Unified send/receive interface

**Why not gen_udp?**

1. Modern `socket` module has better performance
2. Required for proper async/select mode
3. Better control over socket options
4. Needed for reliable hole punching

### estun_codec.erl

STUN message binary encoding/decoding.

**Message Format (RFC 5389):**

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|0 0|     STUN Message Type     |         Message Length        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Magic Cookie                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                     Transaction ID (96 bits)                  |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          Attributes                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### estun_attrs.erl

STUN attribute encoding/decoding.

**Supported Attributes:**

| Attribute | Type | RFC |
|-----------|------|-----|
| MAPPED-ADDRESS | 0x0001 | 5389 |
| XOR-MAPPED-ADDRESS | 0x0020 | 5389 |
| USERNAME | 0x0006 | 5389 |
| MESSAGE-INTEGRITY | 0x0008 | 5389 |
| ERROR-CODE | 0x0009 | 5389 |
| FINGERPRINT | 0x8028 | 5389 |
| CHANGE-REQUEST | 0x0003 | 5780 |
| OTHER-ADDRESS | 0x802c | 5780 |

### estun_crypto.erl

Cryptographic functions for STUN.

**Responsibilities:**

- MESSAGE-INTEGRITY (HMAC-SHA1)
- FINGERPRINT (CRC-32)
- XOR address decoding
- Long-term credential key derivation

### estun_punch.erl

UDP hole punching implementation.

**Algorithm:**

1. Send punch packet with magic + nonce
2. Wait for response (short timeout)
3. Check if from expected peer
4. Repeat until connected or timeout

**Punch Packet Format:**

```
┌────────────────────────────┐
│ "ESTUN_PUNCH_" (12 bytes)  │
├────────────────────────────┤
│ Random Nonce (8 bytes)     │
└────────────────────────────┘
```

### estun_nat_discovery.erl

RFC 5780 NAT behavior discovery.

**Tests Performed:**

1. Basic binding (Test I)
2. Alternate IP (Test II)
3. Alternate IP+Port (Test III)
4. Change IP+Port filtering (Test IV)
5. Change Port filtering (Test V)

## Data Flow

### Discovery Flow

```
User                estun           estun_client      estun_socket
  │                   │                   │                │
  │ discover()        │                   │                │
  │──────────────────►│                   │                │
  │                   │ open()            │                │
  │                   │───────────────────┼───────────────►│
  │                   │                   │          {ok,S}│
  │                   │◄──────────────────┼────────────────│
  │                   │ send(Request)     │                │
  │                   │───────────────────┼───────────────►│
  │                   │                   │            ok  │
  │                   │◄──────────────────┼────────────────│
  │                   │ recv()            │                │
  │                   │───────────────────┼───────────────►│
  │                   │                   │   {ok,Response}│
  │                   │◄──────────────────┼────────────────│
  │                   │ decode(Response)  │                │
  │                   │──────────────────►│                │
  │    {ok,Addr}      │                   │                │
  │◄──────────────────│                   │                │
```

### Hole Punching Flow

```
Peer A                                              Peer B
  │                                                    │
  │ discover via STUN                                  │
  │────────────────►                ◄──────────────────│
  │     Addr A                           Addr B        │
  │                                                    │
  │ exchange via signaling server                      │
  │◄──────────────────────────────────────────────────►│
  │                                                    │
  │ punch(Addr B)                        punch(Addr A) │
  │─────────────────────►  ◄───────────────────────────│
  │                  │  X  │                           │
  │                  │    NAT creates mapping          │
  │                  │     │                           │
  │─────────────────────►  │───────────────────────────│
  │                  │     │                           │
  │◄─────────────────│     │◄──────────────────────────│
  │                        │                           │
  │◄═══════════════════════╪══════════════════════════►│
  │            Direct P2P Connection                   │
```

## Configuration

### Application Environment

```erlang
[
    {estun, [
        {default_servers, []},
        {default_timeout, 5000},
        {default_retries, 7}
    ]}
]
```

### Client Configuration

```erlang
SocketOpts = #{
    family => inet,
    local_port => 0,
    reuse_port => true
}.

{ok, SocketRef} = estun:open_socket(SocketOpts).
```

## Error Handling

### Retransmission

Following RFC 5389:

- Initial RTO: 500ms
- RTO doubles each retry (up to 8000ms)
- Maximum 7 retries
- Total timeout: ~39.5 seconds

### Error Events

Errors are propagated via:

1. Return values: `{error, Reason}`
2. Event handler: `{error, Reason}`
3. Process crashes for fatal errors

## Testing Strategy

### Unit Tests

- Codec: RFC 5769 test vectors
- Attributes: Encode/decode roundtrip
- Crypto: Known answer tests

### Integration Tests

- Live server connectivity
- Socket lifecycle
- Keepalive functionality

### Future: Property-Based Tests

```erlang
%% With PropEr
prop_codec_roundtrip() ->
    ?FORALL(Msg, stun_msg(),
        begin
            Encoded = estun_codec:encode(Msg),
            {ok, Decoded} = estun_codec:decode(Encoded),
            Msg =:= Decoded
        end).
```
