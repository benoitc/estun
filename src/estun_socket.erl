%% @doc Socket module wrapper for OTP 28+
%%
%% Provides a unified interface over the modern socket module for UDP/TCP.
-module(estun_socket).

-include("estun.hrl").

%% API
-export([open/1, close/1]).
-export([send/3, recv/2, recv/3]).
-export([controlling_process/2]).
-export([sockname/1, peername/1]).
-export([setopt/3, getopt/2]).

%% Socket types
-type socket() :: socket:socket().
-type socket_opts() :: #{
    family => inet | inet6,
    type => dgram | stream,
    protocol => udp | tcp,
    local_addr => inet:ip_address() | any,
    local_port => inet:port_number(),
    reuse_addr => boolean(),
    reuse_port => boolean(),
    active => boolean() | once | integer()
}.

-export_type([socket/0, socket_opts/0]).

%%====================================================================
%% API
%%====================================================================

-spec open(socket_opts()) -> {ok, socket()} | {error, term()}.
open(Opts) ->
    Family = maps:get(family, Opts, inet),
    Type = maps:get(type, Opts, dgram),
    Protocol = maps:get(protocol, Opts, udp),

    Domain = case Family of
        inet -> inet;
        inet6 -> inet6
    end,

    case socket:open(Domain, Type, Protocol) of
        {ok, Socket} ->
            case configure_socket(Socket, Opts) of
                ok ->
                    case bind_socket(Socket, Opts) of
                        ok -> {ok, Socket};
                        Error ->
                            socket:close(Socket),
                            Error
                    end;
                Error ->
                    socket:close(Socket),
                    Error
            end;
        Error ->
            Error
    end.

-spec close(socket()) -> ok.
close(Socket) ->
    socket:close(Socket).

-spec send(socket(), {inet:ip_address(), inet:port_number()}, iodata()) ->
    ok | {error, term()}.
send(Socket, {Addr, Port}, Data) ->
    Family = get_family(Addr),
    Dest = #{family => Family, addr => Addr, port => Port},
    case socket:sendto(Socket, Data, Dest) of
        ok -> ok;
        {ok, _RestData} -> ok;
        Error -> Error
    end.

-spec recv(socket(), timeout()) ->
    {ok, {inet:ip_address(), inet:port_number()}, binary()} | {error, term()}.
recv(Socket, Timeout) ->
    recv(Socket, 0, Timeout).

-spec recv(socket(), non_neg_integer(), timeout()) ->
    {ok, {inet:ip_address(), inet:port_number()}, binary()} | {error, term()}.
recv(Socket, Length, Timeout) ->
    case socket:recvfrom(Socket, Length, [], Timeout) of
        {ok, {#{addr := Addr, port := Port}, Data}} ->
            {ok, {Addr, Port}, Data};
        {error, timeout} ->
            {error, timeout};
        Error ->
            Error
    end.

-spec controlling_process(socket(), pid()) -> ok | {error, term()}.
controlling_process(Socket, Pid) ->
    socket:setopt(Socket, {otp, controlling_process}, Pid).

-spec sockname(socket()) -> {ok, {inet:ip_address(), inet:port_number()}} | {error, term()}.
sockname(Socket) ->
    case socket:sockname(Socket) of
        {ok, #{addr := Addr, port := Port}} ->
            {ok, {Addr, Port}};
        Error ->
            Error
    end.

-spec peername(socket()) -> {ok, {inet:ip_address(), inet:port_number()}} | {error, term()}.
peername(Socket) ->
    case socket:peername(Socket) of
        {ok, #{addr := Addr, port := Port}} ->
            {ok, {Addr, Port}};
        Error ->
            Error
    end.

-spec setopt(socket(), atom(), term()) -> ok | {error, term()}.
setopt(Socket, OptName, Value) ->
    socket:setopt(Socket, {socket, OptName}, Value).

-spec getopt(socket(), atom()) -> {ok, term()} | {error, term()}.
getopt(Socket, OptName) ->
    socket:getopt(Socket, {socket, OptName}).

%%====================================================================
%% Internal
%%====================================================================

configure_socket(Socket, Opts) ->
    try
        ReuseAddr = maps:get(reuse_addr, Opts, true),
        ok = socket:setopt(Socket, {socket, reuseaddr}, ReuseAddr),
        ReusePort = maps:get(reuse_port, Opts, true),
        case ReusePort of
            true ->
                _ = socket:setopt(Socket, {socket, reuseport}, true);
            false ->
                ok
        end,
        ok
    catch
        _:Reason ->
            {error, {configure_failed, Reason}}
    end.

bind_socket(Socket, Opts) ->
    Family = maps:get(family, Opts, inet),
    LocalAddr = maps:get(local_addr, Opts, any),
    LocalPort = maps:get(local_port, Opts, 0),

    SockAddr = case LocalAddr of
        any ->
            #{family => Family, port => LocalPort, addr => any};
        Addr ->
            #{family => Family, port => LocalPort, addr => Addr}
    end,

    socket:bind(Socket, SockAddr).

get_family({_, _, _, _}) -> inet;
get_family({_, _, _, _, _, _, _, _}) -> inet6.
