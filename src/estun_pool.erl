%% @doc STUN server pool management
%%
%% Manages a pool of STUN servers with health checking and selection.
-module(estun_pool).
-behaviour(gen_server).

-include("estun.hrl").

%% API
-export([start_link/0]).
-export([add_server/1, add_server/2]).
-export([remove_server/1]).
-export([get_server/1]).
-export([get_default_server/0]).
-export([list_servers/0]).
-export([set_default/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    servers = #{} :: #{term() => #stun_server{}},
    default_id :: term() | undefined,
    next_id = 1 :: pos_integer()
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec add_server(map()) -> {ok, term()} | {error, term()}.
add_server(Config) ->
    gen_server:call(?MODULE, {add_server, Config, undefined}).

-spec add_server(map(), term()) -> {ok, term()} | {error, term()}.
add_server(Config, Id) ->
    gen_server:call(?MODULE, {add_server, Config, Id}).

-spec remove_server(term()) -> ok | {error, not_found}.
remove_server(Id) ->
    gen_server:call(?MODULE, {remove_server, Id}).

-spec get_server(term()) -> {ok, #stun_server{}} | {error, not_found}.
get_server(Id) ->
    gen_server:call(?MODULE, {get_server, Id}).

-spec get_default_server() -> {ok, #stun_server{}} | {error, no_servers}.
get_default_server() ->
    gen_server:call(?MODULE, get_default_server).

-spec list_servers() -> [{term(), #stun_server{}}].
list_servers() ->
    gen_server:call(?MODULE, list_servers).

-spec set_default(term()) -> ok | {error, not_found}.
set_default(Id) ->
    gen_server:call(?MODULE, {set_default, Id}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    %% Load default servers from application config
    Defaults = application:get_env(estun, default_servers, []),
    State = lists:foldl(fun(Config, S) ->
        {ok, _, NewState} = do_add_server(Config, undefined, S),
        NewState
    end, #state{}, Defaults),
    {ok, State}.

handle_call({add_server, Config, Id}, _From, State) ->
    case do_add_server(Config, Id, State) of
        {ok, ServerId, NewState} ->
            {reply, {ok, ServerId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({remove_server, Id}, _From, #state{servers = Servers} = State) ->
    case maps:is_key(Id, Servers) of
        true ->
            NewServers = maps:remove(Id, Servers),
            NewDefault = case State#state.default_id of
                Id ->
                    case maps:keys(NewServers) of
                        [First | _] -> First;
                        [] -> undefined
                    end;
                Other ->
                    Other
            end,
            {reply, ok, State#state{servers = NewServers, default_id = NewDefault}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call({get_server, Id}, _From, #state{servers = Servers} = State) ->
    case maps:find(Id, Servers) of
        {ok, Server} ->
            {reply, {ok, Server}, State};
        error ->
            {reply, {error, not_found}, State}
    end;

handle_call(get_default_server, _From, #state{default_id = undefined} = State) ->
    {reply, {error, no_servers}, State};

handle_call(get_default_server, _From, #state{servers = Servers, default_id = Id} = State) ->
    case maps:find(Id, Servers) of
        {ok, Server} ->
            {reply, {ok, Server}, State};
        error ->
            {reply, {error, no_servers}, State}
    end;

handle_call(list_servers, _From, #state{servers = Servers} = State) ->
    {reply, maps:to_list(Servers), State};

handle_call({set_default, Id}, _From, #state{servers = Servers} = State) ->
    case maps:is_key(Id, Servers) of
        true ->
            {reply, ok, State#state{default_id = Id}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal
%%====================================================================

do_add_server(Config, Id, #state{servers = Servers, next_id = NextId} = State) ->
    case validate_config(Config) of
        {ok, Server0} ->
            ServerId = case Id of
                undefined -> NextId;
                _ -> Id
            end,
            Server = Server0#stun_server{id = ServerId},
            NewServers = maps:put(ServerId, Server, Servers),
            NewDefault = case State#state.default_id of
                undefined -> ServerId;
                D -> D
            end,
            NewNextId = case Id of
                undefined -> NextId + 1;
                _ -> NextId
            end,
            {ok, ServerId, State#state{
                servers = NewServers,
                default_id = NewDefault,
                next_id = NewNextId
            }};
        {error, Reason} ->
            {error, Reason}
    end.

validate_config(Config) when is_map(Config) ->
    case maps:find(host, Config) of
        {ok, Host} ->
            Server = #stun_server{
                host = Host,
                port = maps:get(port, Config, 3478),
                transport = maps:get(transport, Config, udp),
                family = maps:get(family, Config, inet),
                auth = maps:get(auth, Config, none),
                username = maps:get(username, Config, undefined),
                password = maps:get(password, Config, undefined),
                realm = maps:get(realm, Config, undefined),
                nonce = maps:get(nonce, Config, undefined)
            },
            {ok, Server};
        error ->
            {error, missing_host}
    end;
validate_config(_) ->
    {error, invalid_config}.
