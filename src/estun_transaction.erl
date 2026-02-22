%% @doc STUN transaction management
%%
%% Implements RFC 5389 retransmission logic for reliable STUN transactions.
-module(estun_transaction).

-include("estun.hrl").

%% API
-export([new/2, new/3]).
-export([get_id/1, get_from/1, get_request/1]).
-export([next_timeout/1, increment_retries/1]).
-export([is_expired/1]).

%% Default RTO parameters (RFC 5389)
-define(DEFAULT_RTO, 500).      %% Initial RTO in ms
-define(MAX_RTO, 8000).         %% Maximum RTO
-define(MAX_RETRIES, 7).        %% Rc value

%%====================================================================
%% API
%%====================================================================

-spec new(binary(), term()) -> #transaction{}.
new(Request, From) ->
    new(Request, From, undefined).

-spec new(binary(), term(), binary() | undefined) -> #transaction{}.
new(Request, From, TxnId) ->
    Id = case TxnId of
        undefined -> estun_codec:make_transaction_id();
        _ -> TxnId
    end,
    #transaction{
        id = Id,
        from = From,
        request = Request,
        start_time = erlang:monotonic_time(millisecond),
        retries = 0
    }.

-spec get_id(#transaction{}) -> binary().
get_id(#transaction{id = Id}) ->
    Id.

-spec get_from(#transaction{}) -> term().
get_from(#transaction{from = From}) ->
    From.

-spec get_request(#transaction{}) -> binary().
get_request(#transaction{request = Request}) ->
    Request.

-spec next_timeout(#transaction{}) -> pos_integer().
next_timeout(#transaction{retries = Retries}) ->
    %% RFC 5389: RTO doubles each time, capped at MAX_RTO
    %% RTO = min(500 * 2^retries, 8000)
    min(?DEFAULT_RTO bsl Retries, ?MAX_RTO).

-spec increment_retries(#transaction{}) -> #transaction{}.
increment_retries(#transaction{retries = Retries} = Txn) ->
    Txn#transaction{retries = Retries + 1}.

-spec is_expired(#transaction{}) -> boolean().
is_expired(#transaction{retries = Retries}) ->
    Retries >= ?MAX_RETRIES.
