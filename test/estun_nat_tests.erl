%% @doc NAT discovery tests
-module(estun_nat_tests).

-include_lib("eunit/include/eunit.hrl").
-include("estun.hrl").

%%====================================================================
%% NAT Behavior Record Tests
%%====================================================================

nat_behavior_record_test() ->
    Behavior = #nat_behavior{
        mapped_address = #stun_addr{
            family = ipv4,
            port = 12345,
            address = {203, 0, 113, 1}
        },
        mapping_behavior = endpoint_independent,
        filtering_behavior = address_port_dependent,
        nat_present = true,
        hairpin_supported = unknown,
        binding_lifetime = unknown
    },
    ?assertEqual(endpoint_independent, Behavior#nat_behavior.mapping_behavior),
    ?assertEqual(address_port_dependent, Behavior#nat_behavior.filtering_behavior),
    ?assertEqual(true, Behavior#nat_behavior.nat_present).

%%====================================================================
%% NAT Type Classification Tests
%%====================================================================

nat_types_test() ->
    %% Full Cone (Endpoint Independent Mapping + Endpoint Independent Filtering)
    FullCone = #nat_behavior{
        mapping_behavior = endpoint_independent,
        filtering_behavior = endpoint_independent
    },
    ?assertEqual(endpoint_independent, FullCone#nat_behavior.mapping_behavior),
    ?assertEqual(endpoint_independent, FullCone#nat_behavior.filtering_behavior),

    %% Restricted Cone (Endpoint Independent Mapping + Address Dependent Filtering)
    RestrictedCone = #nat_behavior{
        mapping_behavior = endpoint_independent,
        filtering_behavior = address_dependent
    },
    ?assertEqual(endpoint_independent, RestrictedCone#nat_behavior.mapping_behavior),
    ?assertEqual(address_dependent, RestrictedCone#nat_behavior.filtering_behavior),

    %% Port Restricted Cone (Endpoint Independent Mapping + Address+Port Dependent Filtering)
    PortRestrictedCone = #nat_behavior{
        mapping_behavior = endpoint_independent,
        filtering_behavior = address_port_dependent
    },
    ?assertEqual(endpoint_independent, PortRestrictedCone#nat_behavior.mapping_behavior),
    ?assertEqual(address_port_dependent, PortRestrictedCone#nat_behavior.filtering_behavior),

    %% Symmetric NAT (Address+Port Dependent Mapping)
    Symmetric = #nat_behavior{
        mapping_behavior = address_port_dependent,
        filtering_behavior = address_port_dependent
    },
    ?assertEqual(address_port_dependent, Symmetric#nat_behavior.mapping_behavior).
