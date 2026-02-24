# Installation

## Requirements

- **Erlang/OTP 27** or later
- **rebar3** build tool

## Adding to Your Project

### Using rebar3

Add `estun` to your `rebar.config` dependencies:

```erlang
{deps, [
    {estun, {git, "https://github.com/benoitc/estun.git", {tag, "v0.1.0"}}}
]}.
```

Then fetch dependencies:

```bash
rebar3 get-deps
```

### Using Hex

```erlang
{deps, [
    {estun, "0.1.0"}
]}.
```

## Building from Source

Clone the repository and build:

```bash
git clone https://github.com/benoitc/estun.git
cd estun
rebar3 compile
```

## Running Tests

### Unit Tests

```bash
rebar3 eunit
```

### Integration Tests

Integration tests require network access to public STUN servers:

```bash
rebar3 ct
```

### Dialyzer

```bash
rebar3 dialyzer
```

## Verifying Installation

Start an Erlang shell with estun loaded:

```bash
rebar3 shell
```

Then test basic functionality:

```erlang
1> application:ensure_all_started(estun).
{ok,[estun]}

2> estun:add_server(#{host => "stun.l.google.com", port => 19302}).
{ok, 1}

3> estun:discover().
{ok,{stun_addr,ipv4,54321,{203,0,113,42}}}
```

If you see your public IP address, estun is working correctly!

## Application Configuration

You can configure default STUN servers in your `sys.config`:

```erlang
[
    {estun, [
        {default_servers, [
            #{host => "stun.l.google.com", port => 19302},
            #{host => "stun1.l.google.com", port => 19302}
        ]},
        {default_timeout, 5000},
        {default_retries, 7}
    ]}
].
```
