# estun - Erlang STUN Client

**estun** is a modern Erlang/OTP 28+ STUN client library for NAT traversal and UDP hole punching.

## Features

- **RFC 5389** - Modern STUN protocol support
- **RFC 5780** - NAT behavior discovery
- **RFC 5769** - Test vectors verified
- **RFC 3489** - Classic STUN compatibility
- **OTP 28+** - Uses modern `socket` module
- **UDP Hole Punching** - P2P connection establishment
- **gen_statem** - Robust state machine implementation

## Quick Example

```erlang
%% Start the application
application:ensure_all_started(estun).

%% Add a STUN server
{ok, _} = estun:add_server(#{
    host => "stun.l.google.com",
    port => 19302
}).

%% Discover your public IP address
{ok, #stun_addr{address = IP, port = Port}} = estun:discover().
io:format("Public address: ~p:~p~n", [IP, Port]).
```

## Use Cases

### NAT Traversal
Discover your public IP address and port as seen from the internet, essential for:

- VoIP applications
- Video conferencing
- Online gaming
- IoT device connectivity

### P2P Connections
Establish direct peer-to-peer connections through NAT using hole punching:

```erlang
%% Open a socket and discover public address
{ok, SocketRef} = estun:open_socket().
{ok, MyAddr} = estun:bind_socket(SocketRef, default).

%% Exchange MyAddr with peer via signaling server
%% Then punch through to peer
{ok, connected} = estun:punch(SocketRef, PeerIP, PeerPort).
```

### NAT Type Detection
Determine NAT behavior for connectivity planning:

```erlang
{ok, Behavior} = estun:discover_nat(ServerId).
case Behavior#nat_behavior.mapping_behavior of
    endpoint_independent ->
        io:format("Easy NAT - hole punching will work~n");
    address_port_dependent ->
        io:format("Symmetric NAT - may need TURN relay~n")
end.
```

## Examples

### Simple P2P

```erlang
%% Open socket and discover public address
{ok, SocketRef} = estun:open_socket().
{ok, MyAddr} = estun:bind_socket(SocketRef, default).

%% Connect to peer (after exchanging addresses)
{ok, connected} = estun:punch(SocketRef, PeerIP, PeerPort).

%% Use socket directly
{ok, Socket, _} = estun:transfer_socket(SocketRef).
socket:sendto(Socket, <<"Hello!">>, #{family => inet, addr => PeerIP, port => PeerPort}).
```

Full example: [examples/simple_p2p/](https://github.com/benoitc/estun/tree/main/examples/simple_p2p)

### Docker P2P (Cross-Subnet)

Test P2P across isolated networks:

```bash
cd examples/docker_p2p && ./run.sh
```

Full example: [examples/docker_p2p/](https://github.com/benoitc/estun/tree/main/examples/docker_p2p)

## Requirements

- **Erlang/OTP 28** or later
- No external dependencies (pure Erlang)
- Docker (for docker_p2p example)

## License

MIT License

## Links

- [GitHub Repository](https://github.com/benoitc/estun)
- [API Documentation](api/estun.md)
- [Getting Started](getting-started/installation.md)
- [Hole Punching Guide](guide/hole-punching.md)
- [Examples](https://github.com/benoitc/estun/tree/main/examples)
