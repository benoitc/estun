%% @doc STUN client supervisor (simple_one_for_one)
-module(estun_client_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_client/1, start_client/2]).
-export([stop_client/1]).
-export([which_clients/0]).

%% Supervisor callbacks
-export([init/1]).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_client(map()) -> {ok, pid()} | {error, term()}.
start_client(SocketOpts) ->
    start_client(SocketOpts, #{}).

-spec start_client(map(), map()) -> {ok, pid()} | {error, term()}.
start_client(SocketOpts, ClientOpts) ->
    supervisor:start_child(?MODULE, [SocketOpts, ClientOpts]).

-spec stop_client(pid()) -> ok | {error, term()}.
stop_client(Pid) ->
    supervisor:terminate_child(?MODULE, Pid).

-spec which_clients() -> [pid()].
which_clients() ->
    [Pid || {_, Pid, _, _} <- supervisor:which_children(?MODULE),
            is_pid(Pid)].

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 60
    },

    ChildSpec = #{
        id => estun_client,
        start => {estun_client, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [estun_client]
    },

    {ok, {SupFlags, [ChildSpec]}}.
