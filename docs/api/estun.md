# estun Module

The main public API module for estun.

## Types

```erlang
-type server_id() :: term().
-type socket_ref() :: pid().

-type server_config() :: #{
    host := inet:hostname() | inet:ip_address() | binary(),
    port => inet:port_number(),       %% default: 3478
    transport => udp | tcp | tls,     %% default: udp
    family => inet | inet6,           %% default: inet
    auth => none | short_term | long_term,
    username => binary(),
    password => binary(),
    realm => binary()
}.

-type socket_opts() :: #{
    family => inet | inet6,
    local_addr => inet:ip_address(),
    local_port => inet:port_number(),
    reuse_port => boolean()
}.

-type punch_opts() :: #{
    timeout => pos_integer(),
    attempts => pos_integer(),
    interval => pos_integer()
}.
```

## Server Management

### add_server/1, add_server/2

Add a STUN server to the pool.

```erlang
-spec add_server(server_config()) -> {ok, server_id()} | {error, term()}.
-spec add_server(server_config(), server_id()) -> {ok, server_id()} | {error, term()}.
```

**Examples:**

```erlang
%% Auto-generated ID
{ok, Id} = estun:add_server(#{host => "stun.example.com"}).

%% Custom ID
{ok, my_server} = estun:add_server(#{
    host => "stun.example.com",
    port => 3478
}, my_server).
```

### remove_server/1

Remove a server from the pool.

```erlang
-spec remove_server(server_id()) -> ok | {error, not_found}.
```

### list_servers/0

List all configured servers.

```erlang
-spec list_servers() -> [{server_id(), #stun_server{}}].
```

### get_server/1

Get server configuration by ID.

```erlang
-spec get_server(server_id()) -> {ok, #stun_server{}} | {error, not_found}.
```

## Discovery

### discover/0, discover/1

Discover public address using STUN.

```erlang
-spec discover() -> {ok, #stun_addr{}} | {error, term()}.
-spec discover(server_id()) -> {ok, #stun_addr{}} | {error, term()}.
```

**Examples:**

```erlang
%% Using default server
{ok, Addr} = estun:discover().

%% Using specific server
{ok, Addr} = estun:discover(my_server).
```

### bind/1, bind/2

Alias for discover/1.

```erlang
-spec bind(server_id()) -> {ok, #stun_addr{}} | {error, term()}.
-spec bind(server_id(), map()) -> {ok, #stun_addr{}} | {error, term()}.
```

### discover_nat/1, discover_nat/2

Discover NAT behavior using RFC 5780 tests.

```erlang
-spec discover_nat(server_id()) -> {ok, #nat_behavior{}} | {error, term()}.
-spec discover_nat(server_id(), map()) -> {ok, #nat_behavior{}} | {error, term()}.
```

**Example:**

```erlang
{ok, Behavior} = estun:discover_nat(my_server).
io:format("Mapping: ~p~n", [Behavior#nat_behavior.mapping_behavior]).
io:format("Filtering: ~p~n", [Behavior#nat_behavior.filtering_behavior]).
```

## Socket Management

### open_socket/0, open_socket/1

Open a socket for STUN operations and hole punching.

```erlang
-spec open_socket() -> {ok, socket_ref()} | {error, term()}.
-spec open_socket(socket_opts()) -> {ok, socket_ref()} | {error, term()}.
```

**Examples:**

```erlang
%% Default options
{ok, SocketRef} = estun:open_socket().

%% With options
{ok, SocketRef} = estun:open_socket(#{
    family => inet,
    local_port => 5000,
    reuse_port => true
}).
```

### bind_socket/2, bind_socket/3

Bind socket and discover public address.

```erlang
-spec bind_socket(socket_ref(), server_id() | default) ->
    {ok, #stun_addr{}} | {error, term()}.
-spec bind_socket(socket_ref(), server_id() | default, timeout()) ->
    {ok, #stun_addr{}} | {error, term()}.
```

**Examples:**

```erlang
%% Using default server
{ok, Addr} = estun:bind_socket(SocketRef, default).

%% With timeout
{ok, Addr} = estun:bind_socket(SocketRef, my_server, 10000).
```

### get_mapped_address/1

Get current mapped address for a socket.

```erlang
-spec get_mapped_address(socket_ref()) -> {ok, #stun_addr{}} | {error, not_bound}.
```

### get_binding_info/1

Get detailed binding information.

```erlang
-spec get_binding_info(socket_ref()) -> {ok, map()} | {error, not_bound}.
```

**Returns:**

```erlang
#{
    mapped_address => #stun_addr{},
    created_at => integer(),      %% monotonic_time(millisecond)
    last_refresh => integer(),
    lifetime => pos_integer() | unknown,
    remaining => pos_integer() | unknown,
    server => #stun_server{}
}
```

### transfer_socket/1

Transfer socket ownership for direct use.

```erlang
-spec transfer_socket(socket_ref()) ->
    {ok, socket:socket(), #stun_addr{}} | {error, term()}.
```

**Example:**

```erlang
{ok, RawSocket, MyAddr} = estun:transfer_socket(SocketRef).
%% Now use RawSocket directly
socket:sendto(RawSocket, Data, Dest).
```

### close_socket/1

Close a managed socket.

```erlang
-spec close_socket(socket_ref()) -> ok.
```

## Keepalive

### start_keepalive/2

Start periodic binding refresh.

```erlang
-spec start_keepalive(socket_ref(), pos_integer()) -> ok.
```

**Parameters:**

- `socket_ref()` - Socket reference
- `pos_integer()` - Interval in seconds

**Example:**

```erlang
%% Refresh every 25 seconds
ok = estun:start_keepalive(SocketRef, 25).
```

### stop_keepalive/1

Stop periodic binding refresh.

```erlang
-spec stop_keepalive(socket_ref()) -> ok.
```

## Event Handling

### set_event_handler/2

Set event handler for binding lifecycle notifications.

```erlang
-spec set_event_handler(socket_ref(), event_handler()) -> ok.

-type event_handler() :: pid() | fun((event()) -> any()) | {module(), atom()}.
-type event() ::
    {binding_created, #stun_addr{}} |
    {binding_refreshed, #stun_addr{}} |
    {binding_expiring, pos_integer()} |
    {binding_expired} |
    {binding_changed, #stun_addr{}, #stun_addr{}} |
    {error, term()}.
```

**Examples:**

```erlang
%% Process handler
estun:set_event_handler(SocketRef, self()).

%% Function handler
estun:set_event_handler(SocketRef, fun(E) -> io:format("~p~n", [E]) end).

%% Module callback
estun:set_event_handler(SocketRef, {my_module, handle_event}).
```

## Hole Punching

### punch/3, punch/4

Attempt UDP hole punch to peer.

```erlang
-spec punch(socket_ref(), inet:ip_address(), inet:port_number()) ->
    {ok, connected} | {error, term()}.
-spec punch(socket_ref(), inet:ip_address(), inet:port_number(), punch_opts()) ->
    {ok, connected} | {error, term()}.
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeout` | `pos_integer()` | 5000 | Total timeout (ms) |
| `attempts` | `pos_integer()` | 10 | Number of punch attempts |
| `interval` | `pos_integer()` | 50 | Interval between attempts (ms) |

**Example:**

```erlang
case estun:punch(SocketRef, {198, 51, 100, 1}, 54321, #{
    timeout => 10000,
    attempts => 20
}) of
    {ok, connected} ->
        io:format("Connected!~n");
    {error, timeout} ->
        io:format("Punch failed~n")
end.
```
