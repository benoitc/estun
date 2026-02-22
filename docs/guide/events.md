# Event Handling

estun provides an event system to monitor binding lifecycle and state changes.

## Event Types

| Event | Description |
|-------|-------------|
| `{binding_created, Addr}` | New binding established |
| `{binding_refreshed, Addr}` | Binding successfully refreshed |
| `{binding_expiring, RemainingMs}` | Binding about to expire |
| `{binding_expired}` | Binding has expired |
| `{binding_changed, OldAddr, NewAddr}` | Mapped address changed |
| `{error, Reason}` | Error occurred |

## Setting Event Handlers

### Option 1: Process Messages

Receive events as messages to a process:

```erlang
%% Set handler to receive messages
{ok, SocketRef} = estun:open_socket(),
ok = estun:set_event_handler(SocketRef, self()),
{ok, _Addr} = estun:bind_socket(SocketRef, default),

%% Handle events
receive
    {estun_event, SocketRef, {binding_created, Addr}} ->
        io:format("Binding created: ~p~n", [Addr]);
    {estun_event, SocketRef, {binding_refreshed, Addr}} ->
        io:format("Binding refreshed: ~p~n", [Addr]);
    {estun_event, SocketRef, {binding_expiring, Remaining}} ->
        io:format("Binding expiring in ~p ms~n", [Remaining]);
    {estun_event, SocketRef, {binding_expired}} ->
        io:format("Binding expired!~n");
    {estun_event, SocketRef, {binding_changed, Old, New}} ->
        io:format("Address changed: ~p -> ~p~n", [Old, New]);
    {estun_event, SocketRef, {error, Reason}} ->
        io:format("Error: ~p~n", [Reason])
end.
```

### Option 2: Callback Function

Use a function to handle events:

```erlang
Handler = fun(Event) ->
    io:format("STUN Event: ~p~n", [Event])
end,

ok = estun:set_event_handler(SocketRef, Handler).
```

### Option 3: Module Callback

Use a module:function callback:

```erlang
ok = estun:set_event_handler(SocketRef, {my_handler, on_event}).

%% In my_handler.erl
-module(my_handler).
-export([on_event/1]).

on_event({binding_created, Addr}) ->
    logger:info("Binding created: ~p", [Addr]);
on_event({binding_refreshed, Addr}) ->
    logger:debug("Binding refreshed: ~p", [Addr]);
on_event({binding_expiring, Remaining}) ->
    logger:warning("Binding expiring in ~p ms", [Remaining]);
on_event({binding_expired}) ->
    logger:error("Binding expired!");
on_event({binding_changed, Old, New}) ->
    logger:warning("Address changed: ~p -> ~p", [Old, New]);
on_event({error, Reason}) ->
    logger:error("STUN error: ~p", [Reason]).
```

## Practical Examples

### Monitoring Connection Health

```erlang
-module(connection_monitor).
-export([start/1]).

-include_lib("estun/include/estun.hrl").

start(SocketRef) ->
    %% Set ourselves as handler
    ok = estun:set_event_handler(SocketRef, self()),

    %% Start monitoring loop
    monitor_loop(SocketRef, #{
        healthy => true,
        last_refresh => erlang:monotonic_time(millisecond),
        address => undefined
    }).

monitor_loop(SocketRef, State) ->
    receive
        {estun_event, SocketRef, Event} ->
            NewState = handle_event(Event, State),
            monitor_loop(SocketRef, NewState);
        {get_status, From} ->
            From ! {status, State},
            monitor_loop(SocketRef, State);
        stop ->
            ok
    end.

handle_event({binding_created, Addr}, State) ->
    io:format("[MONITOR] Connection established~n"),
    State#{
        healthy := true,
        address := Addr,
        last_refresh := erlang:monotonic_time(millisecond)
    };

handle_event({binding_refreshed, _Addr}, State) ->
    State#{
        healthy := true,
        last_refresh := erlang:monotonic_time(millisecond)
    };

handle_event({binding_expiring, Remaining}, State) ->
    io:format("[MONITOR] Warning: binding expiring in ~p ms~n", [Remaining]),
    State;

handle_event({binding_expired}, State) ->
    io:format("[MONITOR] ALERT: binding expired!~n"),
    State#{healthy := false};

handle_event({binding_changed, Old, New}, State) ->
    io:format("[MONITOR] Address changed!~n"),
    io:format("  Old: ~p:~p~n", [Old#stun_addr.address, Old#stun_addr.port]),
    io:format("  New: ~p:~p~n", [New#stun_addr.address, New#stun_addr.port]),
    %% Notify application of address change
    State#{address := New};

handle_event({error, Reason}, State) ->
    io:format("[MONITOR] Error: ~p~n", [Reason]),
    State#{healthy := false}.
```

### Auto-Reconnect on Expiry

```erlang
-module(auto_reconnect).
-export([start/0]).

-include_lib("estun/include/estun.hrl").

start() ->
    %% Initial setup
    {ok, SocketRef} = estun:open_socket(),
    ok = estun:set_event_handler(SocketRef, self()),
    {ok, Addr} = estun:bind_socket(SocketRef, default),
    ok = estun:start_keepalive(SocketRef, 25),

    io:format("Connected: ~p:~p~n", [
        Addr#stun_addr.address, Addr#stun_addr.port
    ]),

    event_loop(SocketRef).

event_loop(SocketRef) ->
    receive
        {estun_event, SocketRef, {binding_expired}} ->
            io:format("Binding expired, reconnecting...~n"),
            %% Close old socket
            estun:close_socket(SocketRef),
            %% Reconnect
            start();

        {estun_event, SocketRef, {binding_changed, _Old, New}} ->
            io:format("Address changed to ~p:~p~n", [
                New#stun_addr.address, New#stun_addr.port
            ]),
            %% Notify application of new address
            event_loop(SocketRef);

        {estun_event, SocketRef, {error, Reason}} ->
            io:format("Error: ~p, attempting recovery...~n", [Reason]),
            %% Attempt recovery
            case estun:bind_socket(SocketRef, default) of
                {ok, _} ->
                    io:format("Recovered~n"),
                    event_loop(SocketRef);
                {error, _} ->
                    io:format("Recovery failed, restarting...~n"),
                    estun:close_socket(SocketRef),
                    start()
            end;

        {estun_event, SocketRef, _Event} ->
            %% Ignore other events
            event_loop(SocketRef)
    end.
```

### Logging All Events

```erlang
-module(event_logger).
-export([attach/1]).

attach(SocketRef) ->
    Handler = fun(Event) ->
        Timestamp = calendar:system_time_to_rfc3339(
            erlang:system_time(second)
        ),
        logger:info("[~s] STUN: ~p", [Timestamp, Event])
    end,
    estun:set_event_handler(SocketRef, Handler).
```

## Best Practices

1. **Always set a handler** when using keepalive to detect address changes
2. **React to `binding_changed`** - your public address may change
3. **Handle `binding_expiring`** - opportunity to extend or notify
4. **Log `error` events** - helps diagnose network issues
5. **Use module callbacks** for complex event handling logic
