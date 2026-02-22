# estun_client Module

STUN client state machine (gen_statem).

## Overview

`estun_client` is a `gen_statem` implementation that manages the STUN client lifecycle:

```
┌──────┐     bind     ┌─────────┐    success    ┌───────┐
│ idle │ ──────────► │ binding │ ────────────► │ bound │
└──────┘             └─────────┘               └───────┘
    ▲                     │                        │
    │                     │ timeout/error          │ transfer
    │                     ▼                        ▼
    └─────────────────────┴────────────────────────┘
```

## Functions

### start_link/1, start_link/2

Start a client process.

```erlang
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
-spec start_link(map(), map()) -> {ok, pid()} | {error, term()}.
```

**Socket Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `family` | `inet \| inet6` | `inet` | Address family |
| `local_addr` | `inet:ip_address()` | `any` | Local bind address |
| `local_port` | `inet:port_number()` | `0` | Local port (0 = system assigned) |
| `reuse_port` | `boolean()` | `true` | Enable SO_REUSEPORT |

### stop/1

Stop a client process.

```erlang
-spec stop(pid()) -> ok.
```

### bind/2, bind/3

Perform STUN binding to discover public address.

```erlang
-spec bind(pid(), #stun_server{}) -> {ok, #stun_addr{}} | {error, term()}.
-spec bind(pid(), #stun_server{}, timeout()) -> {ok, #stun_addr{}} | {error, term()}.
```

### get_mapped_address/1

Get current mapped address.

```erlang
-spec get_mapped_address(pid()) -> {ok, #stun_addr{}} | {error, not_bound}.
```

### get_binding_info/1

Get detailed binding information.

```erlang
-spec get_binding_info(pid()) -> {ok, map()} | {error, not_bound}.
```

### get_socket/1

Get the underlying socket.

```erlang
-spec get_socket(pid()) -> {ok, socket:socket()} | {error, term()}.
```

### set_event_handler/2

Set event handler for notifications.

```erlang
-spec set_event_handler(pid(), event_handler()) -> ok.
```

### start_keepalive/2

Start periodic binding refresh.

```erlang
-spec start_keepalive(pid(), pos_integer()) -> ok.
```

**Parameters:**

- `pid()` - Client process
- `pos_integer()` - Interval in milliseconds

### stop_keepalive/1

Stop periodic binding refresh.

```erlang
-spec stop_keepalive(pid()) -> ok.
```

### transfer/1

Transfer socket ownership to caller.

```erlang
-spec transfer(pid()) -> {ok, socket:socket(), #stun_addr{}} | {error, term()}.
```

## States

### idle

Initial state. Socket may or may not be open.

**Handles:**

- `bind` - Start binding process
- `get_socket` - Return socket (opens if needed)

### binding

Waiting for STUN response.

**Handles:**

- Socket data - Process response
- State timeout - Retransmit or fail

**Retransmission:**

- Initial RTO: 500ms
- Doubles each retry up to 8000ms
- Maximum 7 retries (RFC 5389)

### bound

Have valid binding.

**Handles:**

- `get_mapped_address` - Return address
- `get_binding_info` - Return full info
- `start_keepalive` - Begin refresh
- `transfer` - Hand off socket
- Keepalive responses - Update state

## Event Types

```erlang
-type event() ::
    {binding_created, #stun_addr{}} |
    {binding_refreshed, #stun_addr{}} |
    {binding_expiring, pos_integer()} |
    {binding_expired} |
    {binding_changed, #stun_addr{}, #stun_addr{}} |
    {error, term()}.
```

## Example Usage

```erlang
%% Start client
{ok, Pid} = estun_client:start_link(#{family => inet}),

%% Set event handler
ok = estun_client:set_event_handler(Pid, self()),

%% Create server config
Server = #stun_server{
    host = "stun.l.google.com",
    port = 19302
},

%% Bind
{ok, Addr} = estun_client:bind(Pid, Server),
io:format("Mapped: ~p:~p~n", [Addr#stun_addr.address, Addr#stun_addr.port]),

%% Start keepalive
ok = estun_client:start_keepalive(Pid, 25000),

%% ... use connection ...

%% Transfer for direct use
{ok, Socket, Addr} = estun_client:transfer(Pid).
```

## Supervision

Clients are typically started via `estun_client_sup`:

```erlang
{ok, Pid} = estun_client_sup:start_client(SocketOpts).
{ok, Pid} = estun_client_sup:start_client(SocketOpts, ClientOpts).

%% List all clients
Pids = estun_client_sup:which_clients().

%% Stop a client
ok = estun_client_sup:stop_client(Pid).
```
