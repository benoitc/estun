# estun_socket Module

Socket module wrapper for OTP 28+.

## Overview

`estun_socket` provides a unified interface over the modern OTP `socket` module,
handling platform differences and providing convenient UDP operations.

## Types

```erlang
-type socket() :: socket:socket().
-type socket_opts() :: #{
    family => inet | inet6,
    type => dgram | stream,
    protocol => udp | tcp,
    local_addr => inet:ip_address() | any,
    local_port => inet:port_number(),
    reuse_addr => boolean(),
    reuse_port => boolean()
}.
```

## Functions

### open/1

Open a socket with options.

```erlang
-spec open(socket_opts()) -> {ok, socket()} | {error, term()}.
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `family` | `inet \| inet6` | `inet` | Address family |
| `type` | `dgram \| stream` | `dgram` | Socket type |
| `protocol` | `udp \| tcp` | `udp` | Protocol |
| `local_addr` | `ip_address() \| any` | `any` | Local bind address |
| `local_port` | `port_number()` | `0` | Local port |
| `reuse_addr` | `boolean()` | `true` | SO_REUSEADDR |
| `reuse_port` | `boolean()` | `true` | SO_REUSEPORT |

**Example:**

```erlang
{ok, Socket} = estun_socket:open(#{
    family => inet,
    local_port => 5000,
    reuse_port => true
}).
```

### close/1

Close a socket.

```erlang
-spec close(socket()) -> ok.
```

### send/3

Send data to a destination.

```erlang
-spec send(socket(), {inet:ip_address(), inet:port_number()}, iodata()) ->
    ok | {error, term()}.
```

**Example:**

```erlang
ok = estun_socket:send(Socket, {{192,168,1,1}, 3478}, <<"data">>).
```

### recv/2, recv/3

Receive data with timeout.

```erlang
-spec recv(socket(), timeout()) ->
    {ok, {inet:ip_address(), inet:port_number()}, binary()} | {error, term()}.
-spec recv(socket(), non_neg_integer(), timeout()) ->
    {ok, {inet:ip_address(), inet:port_number()}, binary()} | {error, term()}.
```

**Parameters:**

- `socket()` - Socket handle
- `non_neg_integer()` - Max bytes (0 = any)
- `timeout()` - Timeout in milliseconds

**Example:**

```erlang
case estun_socket:recv(Socket, 5000) of
    {ok, {FromIP, FromPort}, Data} ->
        io:format("Received ~p bytes from ~p:~p~n", [
            byte_size(Data), FromIP, FromPort
        ]);
    {error, timeout} ->
        io:format("Receive timed out~n")
end.
```

### controlling_process/2

Transfer socket ownership.

```erlang
-spec controlling_process(socket(), pid()) -> ok | {error, term()}.
```

### sockname/1

Get local address and port.

```erlang
-spec sockname(socket()) -> {ok, {inet:ip_address(), inet:port_number()}} | {error, term()}.
```

### peername/1

Get peer address and port (for connected sockets).

```erlang
-spec peername(socket()) -> {ok, {inet:ip_address(), inet:port_number()}} | {error, term()}.
```

### setopt/3

Set a socket option.

```erlang
-spec setopt(socket(), atom(), term()) -> ok | {error, term()}.
```

### getopt/2

Get a socket option.

```erlang
-spec getopt(socket(), atom()) -> {ok, term()} | {error, term()}.
```

## Platform Notes

### SO_REUSEPORT

Required for hole punching to work correctly. Allows multiple sockets
to bind to the same port.

```erlang
%% Enabled by default
{ok, Socket} = estun_socket:open(#{reuse_port => true}).
```

!!! note "Platform Support"
    SO_REUSEPORT is supported on Linux 3.9+, macOS, and FreeBSD.
    On Windows, SO_REUSEADDR provides similar functionality.

### OTP 28 Socket Module

estun uses the modern `socket` module instead of `gen_udp`:

- Better performance
- More control over socket options
- Native async/select support
- Required for proper hole punching

## Example: Custom Socket

```erlang
%% Open socket manually
{ok, Socket} = estun_socket:open(#{
    family => inet,
    local_port => 12345
}),

%% Get local address
{ok, {LocalIP, LocalPort}} = estun_socket:sockname(Socket),
io:format("Bound to ~p:~p~n", [LocalIP, LocalPort]),

%% Send data
Dest = {{93, 184, 216, 34}, 80},
ok = estun_socket:send(Socket, Dest, <<"Hello">>),

%% Receive response
case estun_socket:recv(Socket, 5000) of
    {ok, {IP, Port}, Data} ->
        io:format("Response from ~p:~p: ~p~n", [IP, Port, Data]);
    {error, Reason} ->
        io:format("Error: ~p~n", [Reason])
end,

%% Cleanup
estun_socket:close(Socket).
```
