# Configuration

## Application Environment

Configure estun in your `sys.config` or application environment:

```erlang
[
    {estun, [
        %% Pre-configured STUN servers loaded at startup
        {default_servers, [
            #{host => "stun.l.google.com", port => 19302},
            #{host => "stun1.l.google.com", port => 19302}
        ]},

        %% Default timeout for STUN requests (milliseconds)
        {default_timeout, 5000},

        %% Maximum retransmission attempts (RFC 5389 recommends 7)
        {default_retries, 7}
    ]}
].
```

## Server Configuration

When adding a server, you can specify various options:

```erlang
estun:add_server(#{
    %% Required: hostname or IP address
    host => "stun.example.com",

    %% Port (default: 3478)
    port => 3478,

    %% Transport protocol (default: udp)
    transport => udp,  %% udp | tcp | tls

    %% Address family (default: inet)
    family => inet,    %% inet | inet6

    %% Authentication (default: none)
    auth => none,      %% none | short_term | long_term

    %% Credentials (for authenticated servers)
    username => <<"user">>,
    password => <<"pass">>,
    realm => <<"example.com">>
}).
```

## Socket Options

When opening a socket for hole punching:

```erlang
estun:open_socket(#{
    %% Address family
    family => inet,         %% inet | inet6

    %% Local address to bind (default: any)
    local_addr => {0,0,0,0},

    %% Local port (default: 0 = system assigned)
    local_port => 0,

    %% Enable port reuse for hole punching (default: true)
    reuse_port => true
}).
```

## Timeout Configuration

### Per-Request Timeout

```erlang
%% Bind with custom timeout
{ok, Addr} = estun:bind_socket(SocketRef, ServerId, 10000).  %% 10 seconds
```

### Hole Punching Options

```erlang
estun:punch(SocketRef, PeerIP, PeerPort, #{
    timeout => 5000,    %% Total timeout in ms
    attempts => 10,     %% Number of punch attempts
    interval => 50      %% Interval between attempts in ms
}).
```

## Public STUN Servers

Here are some reliable public STUN servers:

| Provider | Host | Port |
|----------|------|------|
| Google | stun.l.google.com | 19302 |
| Google | stun1.l.google.com | 19302 |
| Google | stun2.l.google.com | 19302 |
| Twilio | global.stun.twilio.com | 3478 |
| Cloudflare | stun.cloudflare.com | 3478 |

!!! warning "Production Use"
    For production applications, consider running your own STUN server
    or using a paid service for reliability and SLA guarantees.

## IPv6 Configuration

To use IPv6:

```erlang
%% Add IPv6 server
estun:add_server(#{
    host => "stun.example.com",
    port => 3478,
    family => inet6
}).

%% Open IPv6 socket
{ok, SocketRef} = estun:open_socket(#{family => inet6}).
```

## Logging

estun uses the standard Erlang `logger` for logging. Configure log levels:

```erlang
logger:set_module_level(estun_client, debug).
logger:set_module_level(estun_codec, warning).
```
