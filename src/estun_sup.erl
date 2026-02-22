%% @doc Top-level supervisor for ESTUN
-module(estun_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },

    Pool = #{
        id => estun_pool,
        start => {estun_pool, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [estun_pool]
    },

    ClientSup = #{
        id => estun_client_sup,
        start => {estun_client_sup, start_link, []},
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [estun_client_sup]
    },

    {ok, {SupFlags, [Pool, ClientSup]}}.
