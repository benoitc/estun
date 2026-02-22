%% @doc STUN authentication module
%%
%% Implements short-term and long-term authentication (RFC 5389).
-module(estun_auth).

-include("estun.hrl").
-include("estun_attrs.hrl").

%% API
-export([add_message_integrity/3]).
-export([add_fingerprint/1]).
-export([verify_response/3]).
-export([build_auth_attrs/1]).

%%====================================================================
%% API
%%====================================================================

%% @doc Add MESSAGE-INTEGRITY attribute to a message
-spec add_message_integrity(binary(), #stun_server{}, binary()) -> binary().
add_message_integrity(MsgBin, #stun_server{auth = short_term, password = Password}, _TxnId) ->
    HMAC = estun_crypto:compute_message_integrity(MsgBin, Password),
    append_attr(MsgBin, {message_integrity, HMAC});

add_message_integrity(MsgBin, #stun_server{auth = long_term, username = User,
                                            password = Pass, realm = Realm}, _TxnId) ->
    Key = estun_crypto:compute_key(User, Realm, Pass),
    HMAC = estun_crypto:compute_message_integrity(MsgBin, Key),
    append_attr(MsgBin, {message_integrity, HMAC});

add_message_integrity(MsgBin, _, _) ->
    MsgBin.

%% @doc Add FINGERPRINT attribute to a message
-spec add_fingerprint(binary()) -> binary().
add_fingerprint(MsgBin) ->
    Fingerprint = estun_crypto:compute_fingerprint(MsgBin),
    append_attr(MsgBin, {fingerprint, Fingerprint}).

%% @doc Verify MESSAGE-INTEGRITY and FINGERPRINT in response
-spec verify_response(binary(), #stun_server{}, [stun_attr()]) ->
    ok | {error, term()}.
verify_response(MsgBin, Server, Attrs) ->
    %% Verify FINGERPRINT first (if present)
    case lists:keyfind(fingerprint, 1, Attrs) of
        {fingerprint, _} ->
            case estun_crypto:verify_fingerprint(MsgBin) of
                true -> verify_message_integrity(MsgBin, Server, Attrs);
                false -> {error, invalid_fingerprint}
            end;
        false ->
            verify_message_integrity(MsgBin, Server, Attrs)
    end.

%% @doc Build authentication attributes for request
-spec build_auth_attrs(#stun_server{}) -> [stun_attr()].
build_auth_attrs(#stun_server{auth = none}) ->
    [];
build_auth_attrs(#stun_server{auth = short_term, username = User}) ->
    [{username, User}];
build_auth_attrs(#stun_server{auth = long_term, username = User,
                              realm = Realm, nonce = Nonce}) ->
    Attrs = [{username, User}],
    Attrs1 = case Realm of
        undefined -> Attrs;
        _ -> [{realm, Realm} | Attrs]
    end,
    case Nonce of
        undefined -> Attrs1;
        _ -> [{nonce, Nonce} | Attrs1]
    end.

%%====================================================================
%% Internal
%%====================================================================

verify_message_integrity(_MsgBin, #stun_server{auth = none}, _Attrs) ->
    ok;
verify_message_integrity(MsgBin, Server, Attrs) ->
    case lists:keyfind(message_integrity, 1, Attrs) of
        {message_integrity, ReceivedHMAC} ->
            Key = get_auth_key(Server),
            case estun_crypto:verify_message_integrity(MsgBin, ReceivedHMAC, Key) of
                true -> ok;
                false -> {error, invalid_message_integrity}
            end;
        false ->
            %% No MESSAGE-INTEGRITY - may be OK for error responses
            ok
    end.

get_auth_key(#stun_server{auth = short_term, password = Pass}) ->
    Pass;
get_auth_key(#stun_server{auth = long_term, username = User,
                          password = Pass, realm = Realm}) ->
    estun_crypto:compute_key(User, Realm, Pass).

append_attr(<<Type:16, Length:16, Rest/binary>>, Attr) ->
    AttrBin = estun_attrs:encode(Attr),
    NewLength = Length + byte_size(AttrBin),
    <<Type:16, NewLength:16, Rest/binary, AttrBin/binary>>.
