%% estun_attrs.hrl - STUN Attribute Constants
%% RFC 5389, RFC 5780, RFC 3489

-ifndef(ESTUN_ATTRS_HRL).
-define(ESTUN_ATTRS_HRL, true).

%% Comprehension Required (0x0000-0x7FFF)
-define(ATTR_MAPPED_ADDRESS,        16#0001).  %% RFC 5389 / RFC 3489
-define(ATTR_RESPONSE_ADDRESS,      16#0002).  %% RFC 3489 (deprecated)
-define(ATTR_CHANGE_REQUEST,        16#0003).  %% RFC 5780 / RFC 3489
-define(ATTR_SOURCE_ADDRESS,        16#0004).  %% RFC 3489 (deprecated)
-define(ATTR_CHANGED_ADDRESS,       16#0005).  %% RFC 3489 (deprecated)
-define(ATTR_USERNAME,              16#0006).  %% RFC 5389
-define(ATTR_PASSWORD,              16#0007).  %% RFC 3489 (deprecated)
-define(ATTR_MESSAGE_INTEGRITY,     16#0008).  %% RFC 5389
-define(ATTR_ERROR_CODE,            16#0009).  %% RFC 5389
-define(ATTR_UNKNOWN_ATTRIBUTES,    16#000A).  %% RFC 5389
-define(ATTR_REFLECTED_FROM,        16#000B).  %% RFC 3489 (deprecated)
-define(ATTR_REALM,                 16#0014).  %% RFC 5389
-define(ATTR_NONCE,                 16#0015).  %% RFC 5389
-define(ATTR_XOR_MAPPED_ADDRESS,    16#0020).  %% RFC 5389

%% RFC 5780 - NAT Behavior Discovery
-define(ATTR_PADDING,               16#0026).
-define(ATTR_RESPONSE_PORT,         16#0027).
-define(ATTR_RESPONSE_ORIGIN,       16#802b).
-define(ATTR_OTHER_ADDRESS,         16#802c).

%% Comprehension Optional (0x8000-0xFFFF)
-define(ATTR_SOFTWARE,              16#8022).  %% RFC 5389
-define(ATTR_ALTERNATE_SERVER,      16#8023).  %% RFC 5389
-define(ATTR_FINGERPRINT,           16#8028).  %% RFC 5389

%% CHANGE-REQUEST flags (RFC 5780)
-define(CHANGE_IP,   16#04).
-define(CHANGE_PORT, 16#02).

%% Address family
-define(ADDR_FAMILY_IPV4, 16#01).
-define(ADDR_FAMILY_IPV6, 16#02).

%% Error codes (RFC 5389)
-define(ERR_TRY_ALTERNATE,          300).
-define(ERR_BAD_REQUEST,            400).
-define(ERR_UNAUTHORIZED,           401).
-define(ERR_UNKNOWN_ATTRIBUTE,      420).
-define(ERR_STALE_NONCE,            438).
-define(ERR_SERVER_ERROR,           500).

%% Helper macros
-define(IS_COMPREHENSION_REQUIRED(Type), (Type band 16#8000) =:= 0).
-define(IS_COMPREHENSION_OPTIONAL(Type), (Type band 16#8000) =/= 0).

-endif. %% ESTUN_ATTRS_HRL
