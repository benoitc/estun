# Docker P2P Example

Simulates two peers on different subnets using Docker.

## Quick Start

```bash
./run.sh
```

Or manually:

```bash
rebar3 compile
docker-compose build
docker-compose up
```

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                          Host Machine                            │
│                                                                  │
│   ┌──────────────────────┐       ┌──────────────────────┐       │
│   │   Subnet A           │       │   Subnet B           │       │
│   │   172.20.0.0/16      │       │   172.21.0.0/16      │       │
│   │                      │       │                      │       │
│   │  ┌─────────────┐     │       │     ┌─────────────┐  │       │
│   │  │   Alice     │     │       │     │    Bob      │  │       │
│   │  │ 172.20.0.100│     │       │     │172.21.0.100 │  │       │
│   │  └─────────────┘     │       │     └─────────────┘  │       │
│   │                      │       │                      │       │
│   │  ┌─────────────┐     │       │     ┌─────────────┐  │       │
│   │  │ Signaling   │─────┼───────┼─────│ Signaling   │  │       │
│   │  │ 172.20.0.10 │     │       │     │ 172.21.0.10 │  │       │
│   │  └─────────────┘     │       │     └─────────────┘  │       │
│   │    (same container, dual-homed)                     │       │
│   └──────────────────────┘       └──────────────────────┘       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Signaling server** runs on both networks (dual-homed)
2. **Alice** (172.20.0.100) registers with signaling via 172.20.0.10
3. **Bob** (172.21.0.100) registers with signaling via 172.21.0.10
4. Signaling exchanges addresses between peers
5. Peers attempt to communicate directly

## Running

```bash
# From project root
cd examples/docker_p2p

# Build estun first
cd ../..
rebar3 compile
cd examples/docker_p2p

# Build and run
docker-compose build
docker-compose up

# Watch the output - you'll see:
# - Signaling server starting
# - Alice and Bob registering
# - Address exchange
# - P2P communication attempts

# Clean up
docker-compose down
```

## Expected Output

```
signaling-1  | [Signaling] Starting on port 9999...
signaling-1  | [Signaling] Listening...

alice-1      | [alice] Starting...
alice-1      | [alice] Discovering public address...
alice-1      | [alice] Public: {195,24,245,185}:38394
alice-1      | [alice] Local: {172,20,0,100}:37904
alice-1      | [alice] Connecting to signaling server 172.20.0.10...
alice-1      | [alice] Connected to signaling
alice-1      | [alice] Waiting for peer...

bob-1        | [bob] Starting...
bob-1        | [bob] Discovering public address...
bob-1        | [bob] Public: {195,24,245,185}:39583
bob-1        | [bob] Local: {172,21,0,100}:51447
bob-1        | [bob] Connecting to signaling server 172.21.0.10...
bob-1        | [bob] Connected to signaling
bob-1        | [bob] Waiting for peer...

signaling-1  | [Signaling] alice registered
signaling-1  | [Signaling] bob registered
signaling-1  | [Signaling] Connecting alice <-> bob
signaling-1  | [Signaling] Peers notified

alice-1      | [alice] Peer bob info received:
alice-1      |   Public: {195,24,245,185}:39583
alice-1      |   Local:  {172,21,0,100}:51447
alice-1      | [alice] Connecting to bob at {172,21,0,100}:51447...
alice-1      | [alice] RECEIVED: MSG_bob_1 from {172,20,0,1}:51447
alice-1      | [alice] RECEIVED: REPLY_bob from {172,21,0,100}:51447
alice-1      | [alice] === TEST COMPLETE ===

bob-1        | [bob] Peer alice info received:
bob-1        |   Public: {195,24,245,185}:38394
bob-1        |   Local:  {172,20,0,100}:37904
bob-1        | [bob] Connecting to alice at {172,20,0,100}:37904...
bob-1        | [bob] RECEIVED: MSG_alice_1 from {172,21,0,1}:37904
bob-1        | [bob] RECEIVED: REPLY_alice from {172,20,0,100}:37904
bob-1        | [bob] === TEST COMPLETE ===
```

## What This Demonstrates

1. **STUN Discovery**: Both peers discover their public IP via Google's STUN server
2. **Signaling**: TCP-based address exchange between isolated networks
3. **Cross-Subnet UDP**: Direct P2P communication between 172.20.x.x and 172.21.x.x
4. **Bidirectional Messaging**: Both peers send and receive messages

## Files

| File | Description |
|------|-------------|
| `docker_peer.erl` | Peer implementation with STUN discovery |
| `docker_signaling.erl` | TCP signaling server for address exchange |
| `docker-compose.yml` | Network topology and container setup |
| `Dockerfile` | Container build configuration |
| `run.sh` | Build and run script |

## Notes

- Docker networks simulate isolated subnets
- The signaling server bridges both networks (dual-homed)
- Both peers discover the same public IP (NAT) but different ports
- Communication uses container IPs since Docker routes between subnets
