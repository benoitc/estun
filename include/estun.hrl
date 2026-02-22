%% estun.hrl - Core types and records for STUN client
%% RFC 5389 - Session Traversal Utilities for NAT (STUN)

-ifndef(ESTUN_HRL).
-define(ESTUN_HRL, true).

%% STUN Magic Cookie (RFC 5389)
-define(STUN_MAGIC, 16#2112A442).

%% STUN Message Header Size
-define(STUN_HEADER_SIZE, 20).

%% Default ports
-define(STUN_DEFAULT_PORT, 3478).
-define(STUNS_DEFAULT_PORT, 5349).

%% Message classes (2 bits)
-define(STUN_CLASS_REQUEST, 2#00).
-define(STUN_CLASS_INDICATION, 2#01).
-define(STUN_CLASS_SUCCESS, 2#10).
-define(STUN_CLASS_ERROR, 2#11).

%% Message methods (RFC 5389)
-define(STUN_METHOD_BINDING, 16#001).

%% STUN Message
-record(stun_msg, {
    class           :: request | indication | success | error,
    method          :: binding | atom() | non_neg_integer(),
    transaction_id  :: binary(),  %% 12 bytes (RFC 5389) or 16 bytes (RFC 3489)
    attributes = [] :: [stun_attr()]
}).

-type stun_attr() :: {atom(), term()}.

%% Transport Address
-record(stun_addr, {
    family  :: ipv4 | ipv6,
    port    :: inet:port_number(),
    address :: inet:ip_address()
}).

%% Server Configuration
-record(stun_server, {
    id              :: term(),
    host            :: inet:hostname() | inet:ip_address() | binary(),
    port = 3478     :: inet:port_number(),
    transport = udp :: udp | tcp | tls,
    family = inet   :: inet | inet6,
    %% RFC 5780 - alternate server info
    alternate_host  :: inet:ip_address() | undefined,
    alternate_port  :: inet:port_number() | undefined,
    %% Authentication
    auth = none     :: none | short_term | long_term | oauth,
    username        :: binary() | undefined,
    password        :: binary() | undefined,
    realm           :: binary() | undefined,
    nonce           :: binary() | undefined
}).

%% NAT Behavior (RFC 5780)
-record(nat_behavior, {
    mapped_address      :: #stun_addr{} | undefined,
    mapping_behavior    :: endpoint_independent | address_dependent |
                           address_port_dependent | unknown,
    filtering_behavior  :: endpoint_independent | address_dependent |
                           address_port_dependent | unknown,
    nat_present         :: boolean() | unknown,
    hairpin_supported   :: boolean() | unknown,
    binding_lifetime    :: pos_integer() | unknown
}).

%% Transaction state
-record(transaction, {
    id          :: binary(),
    from        :: {pid(), term()} | undefined,
    request     :: binary(),
    start_time  :: integer(),
    retries = 0 :: non_neg_integer()
}).

%% Type exports
-type stun_msg() :: #stun_msg{}.
-type stun_addr() :: #stun_addr{}.
-type stun_server() :: #stun_server{}.
-type nat_behavior() :: #nat_behavior{}.

-export_type([stun_msg/0, stun_addr/0, stun_server/0, nat_behavior/0]).

-endif. %% ESTUN_HRL
