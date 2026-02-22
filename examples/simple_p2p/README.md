# Simple P2P Example

A minimal example demonstrating peer-to-peer communication using STUN discovery.

## Quick Test

The easiest way to test is using `local_test.erl`:

```bash
cd examples/simple_p2p
erl -pa ../../_build/default/lib/estun/ebin
```

```erlang
1> c(local_test).
2> local_test:run().
```

### Expected Output

```
=== Simple P2P Test ===

Creating sockets and discovering addresses...

  Alice:
    Public: {195,24,245,185}:32170
    Local:  127.0.0.1:61193

  Bob:
    Public: {195,24,245,185}:38738
    Local:  127.0.0.1:54686

  Same network: true
  Using LOCAL addresses for communication

--- Messaging Test ---

  Alice -> Bob: "Hello Bob!"
  Bob received: Hello Bob!

  Bob -> Alice: "Hi Alice!"
  Alice received: Hi Alice!

=== Test Complete ===
```

## How It Works

1. Two sockets are created and bound via STUN
2. Public addresses are discovered from Google's STUN server
3. Same-network detection (same public IP = same NAT)
4. Automatic fallback to local addresses for same-network peers
5. Bidirectional UDP messaging

## Multi-Terminal Example

For a more realistic multi-process test:

### Terminal 1: Start the signaling server

```erlang
cd examples/simple_p2p
erl -pa ../../_build/default/lib/estun/ebin

1> c(simple_signaling).
2> c(simple_peer).
3> Sig = simple_signaling:start().
```

### Terminal 2: Start Alice

```erlang
cd examples/simple_p2p
erl -pa ../../_build/default/lib/estun/ebin

1> c(simple_peer).
2> simple_peer:start(alice, '<paste Sig pid from Terminal 1>').
```

### Terminal 3: Start Bob

```erlang
cd examples/simple_p2p
erl -pa ../../_build/default/lib/estun/ebin

1> c(simple_peer).
2> simple_peer:start(bob, '<paste Sig pid from Terminal 1>').
```

### Sending Messages

```erlang
%% From Alice's terminal
simple_peer:send(alice, <<"Hello Bob!">>).

%% From Bob's terminal
simple_peer:send(bob, <<"Hi Alice!">>).
```

## Files

| File | Description |
|------|-------------|
| `local_test.erl` | Single-shell test with STUN discovery |
| `simple_peer.erl` | Full peer implementation with messaging |
| `simple_signaling.erl` | Address exchange server |

## See Also

For cross-subnet testing, see the [docker_p2p](../docker_p2p/) example.
