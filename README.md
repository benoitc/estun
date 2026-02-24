# estun

[![CI](https://github.com/benoitc/estun/actions/workflows/ci.yml/badge.svg)](https://github.com/benoitc/estun/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/estun.svg)](https://hex.pm/packages/estun)

Modern Erlang STUN client library for OTP 27+.

Pure Erlang implementation using the `socket` module. Supports RFC 5389 (STUN), RFC 5769 (test vectors), and RFC 5780 (NAT behavior discovery).

## Features

- STUN binding requests and responses
- NAT type detection (mapping and filtering behavior)
- UDP hole punching with keepalive
- Socket transfer for P2P traffic
- Short-term and long-term authentication
- IPv4 and IPv6 support

## Requirements

- Erlang/OTP 27 or later

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {estun, "0.1.0"}
]}.
```

Or from git:

```erlang
{deps, [
    {estun, {git, "https://github.com/benoitc/estun.git", {tag, "v0.1.0"}}}
]}.
```

## Quick Start

```erlang
%% Add a STUN server
{ok, ServerId} = estun:add_server(#{host => "stun.l.google.com", port => 19302}).

%% Discover public address
{ok, MappedAddr} = estun:discover().
```

## Hole Punching

```erlang
%% Open a socket and bind it
{ok, SocketRef} = estun:open_socket().
{ok, MappedAddr} = estun:bind_socket(SocketRef, ServerId).

%% Start keepalive to maintain NAT binding
ok = estun:start_keepalive(SocketRef, 25).

%% Punch through to peer
{ok, connected} = estun:punch(SocketRef, PeerIP, PeerPort).

%% Transfer socket for direct P2P communication
{ok, Socket, MappedAddr} = estun:transfer_socket(SocketRef).
```

## NAT Discovery

```erlang
%% Discover NAT behavior (requires RFC 5780 compliant server)
{ok, Behavior} = estun:discover_nat(ServerId).

%% Returns #nat_behavior{} with:
%%   mapping_behavior  - endpoint_independent | address_dependent | address_port_dependent
%%   filtering_behavior - endpoint_independent | address_dependent | address_port_dependent
%%   nat_present       - true | false
%%   hairpin_supported - true | false | unknown
```

## Event Handling

```erlang
%% Set event handler for binding lifecycle
estun:set_event_handler(SocketRef, self()).

%% Receive events
receive
    {estun_event, SocketRef, {binding_created, Addr}} -> ok;
    {estun_event, SocketRef, {binding_refreshed, Addr}} -> ok;
    {estun_event, SocketRef, {binding_changed, OldAddr, NewAddr}} -> ok;
    {estun_event, SocketRef, {binding_expiring, RemainingMs}} -> ok;
    {estun_event, SocketRef, {binding_expired}} -> ok
end.
```

## Server Configuration

```erlang
estun:add_server(#{
    host => "stun.example.com",
    port => 3478,                    %% default
    transport => udp,                %% udp | tcp | tls
    family => inet,                  %% inet | inet6
    auth => none,                    %% none | short_term | long_term
    username => <<"user">>,
    password => <<"pass">>,
    realm => <<"example.com">>
}).
```

## Examples

### Simple P2P

```erlang
%% Discover public address
{ok, SocketRef} = estun:open_socket().
{ok, MyAddr} = estun:bind_socket(SocketRef, default).
io:format("Public: ~p:~p~n", [MyAddr#stun_addr.address, MyAddr#stun_addr.port]).

%% Exchange MyAddr with peer, then connect
{ok, connected} = estun:punch(SocketRef, PeerIP, PeerPort).

%% Transfer socket for direct communication
{ok, Socket, _} = estun:transfer_socket(SocketRef).
socket:sendto(Socket, <<"Hello!">>, #{family => inet, addr => PeerIP, port => PeerPort}).
```

See [examples/simple_p2p/](https://github.com/benoitc/estun/tree/main/examples/simple_p2p) for a runnable example.

### Docker P2P (Cross-Subnet)

```bash
cd examples/docker_p2p && ./run.sh
```

Creates two isolated Docker networks and demonstrates P2P communication between them.
See [examples/docker_p2p/](https://github.com/benoitc/estun/tree/main/examples/docker_p2p) for details.

## Documentation

Full documentation is available at [benoitc.github.io/estun](https://benoitc.github.io/estun/).

## License

MIT License - see [LICENSE](https://github.com/benoitc/estun/blob/main/LICENSE) for details.
