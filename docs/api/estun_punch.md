# estun_punch Module

UDP hole punching implementation.

## Overview

This module implements UDP hole punching for NAT traversal,
enabling direct peer-to-peer connections through NAT devices.

## How It Works

```
1. Both peers send packets to each other's public address
2. Outgoing packets create NAT mappings
3. Once mappings exist, incoming packets are accepted
4. Connection is established when both sides receive packets

Peer A                    NAT A      NAT B                    Peer B
  │                         │          │                         │
  │──── punch packet ──────►│          │                         │
  │                         │──────────┼────────────────────────►│
  │                         │          │◄──── punch packet ──────│
  │◄────────────────────────┼──────────│                         │
  │                         │          │                         │
  │◄════════ P2P Connection Established ════════►│
```

## Functions

### start/5

Start hole punching (blocking).

```erlang
-spec start(socket:socket(), {inet:ip_address(), inet:port_number()},
            pos_integer(), pos_integer(), pos_integer()) ->
    {ok, connected} | {error, term()}.
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Socket | `socket:socket()` | Open UDP socket |
| PeerAddr | `{ip_address(), port()}` | Peer's public address |
| Attempts | `pos_integer()` | Number of punch attempts |
| Interval | `pos_integer()` | Interval between attempts (ms) |
| Timeout | `pos_integer()` | Total timeout (ms) |

**Example:**

```erlang
{ok, Socket} = estun_socket:open(#{}),
PeerAddr = {{198, 51, 100, 1}, 54321},

case estun_punch:start(Socket, PeerAddr, 10, 50, 5000) of
    {ok, connected} ->
        io:format("Hole punch successful!~n");
    {error, timeout} ->
        io:format("Hole punch failed~n")
end.
```

### start_async/5

Start hole punching asynchronously.

```erlang
-spec start_async(socket:socket(), {inet:ip_address(), inet:port_number()},
                  pos_integer(), pos_integer(), pos_integer()) ->
    {ok, pid()}.
```

**Returns:**

The function spawns a linked process that performs the punch.
Result is sent as `{punch_result, Pid, Result}`.

**Example:**

```erlang
{ok, PunchPid} = estun_punch:start_async(Socket, PeerAddr, 10, 50, 5000),

receive
    {punch_result, PunchPid, {ok, connected}} ->
        io:format("Connected!~n");
    {punch_result, PunchPid, {error, Reason}} ->
        io:format("Failed: ~p~n", [Reason])
after 10000 ->
    io:format("Overall timeout~n")
end.
```

## Punch Protocol

### Packet Format

```
┌──────────────────────────────────────┐
│ Magic: "ESTUN_PUNCH_" (12 bytes)     │
├──────────────────────────────────────┤
│ Nonce: random (8 bytes)              │
└──────────────────────────────────────┘
```

### Detection Logic

1. Send punch packet with random nonce
2. Wait for response (short interval)
3. If punch packet received from expected peer → connected
4. If punch packet from same IP, different port → symmetric NAT handling
5. Repeat until timeout or success

## Usage with estun

The high-level API is typically used instead of direct module calls:

```erlang
%% Setup
{ok, SocketRef} = estun:open_socket(),
{ok, MyAddr} = estun:bind_socket(SocketRef, default),
ok = estun:start_keepalive(SocketRef, 25),

%% Exchange MyAddr with peer...

%% Punch (uses estun_punch internally)
case estun:punch(SocketRef, PeerIP, PeerPort, #{
    timeout => 10000,
    attempts => 20,
    interval => 100
}) of
    {ok, connected} ->
        {ok, Socket, _} = estun:transfer_socket(SocketRef),
        use_socket(Socket);
    {error, Reason} ->
        handle_failure(Reason)
end.
```

## Tips for Success

### Timing

Both peers should start punching at nearly the same time:

```erlang
%% Coordinate via signaling server
SignalingServer ! {ready_to_punch, self(), MyAddr},
receive
    {start_punching, PeerAddr} ->
        %% Both peers receive this simultaneously
        estun:punch(SocketRef, PeerAddr, #{timeout => 10000})
end.
```

### Keepalive

Ensure NAT bindings are fresh before punching:

```erlang
%% Start keepalive BEFORE exchanging addresses
{ok, SocketRef} = estun:open_socket(),
{ok, Addr} = estun:bind_socket(SocketRef, default),
ok = estun:start_keepalive(SocketRef, 25),

%% NOW exchange addresses with peer
exchange_with_peer(Addr).
```

### Multiple Attempts

For difficult NATs, use more attempts with shorter intervals:

```erlang
estun:punch(SocketRef, PeerIP, PeerPort, #{
    timeout => 15000,    %% Longer overall timeout
    attempts => 50,      %% Many attempts
    interval => 30       %% Short interval
}).
```

### Symmetric NAT Handling

The module accepts connections from the same IP but different port,
handling some symmetric NAT cases:

```erlang
%% Peer's NAT may allocate different port than discovered
%% Module handles: same IP, different port = likely peer
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `timeout` | No response from peer | Check timing, try TURN |
| `{error, closed}` | Socket closed | Reopen socket |
| `{error, econnrefused}` | ICMP unreachable | Check peer address |

## Limitations

- Works best with endpoint-independent NATs
- May fail with symmetric NAT (both sides)
- Requires coordination mechanism (signaling server)
- UDP only (TCP hole punching not supported)
