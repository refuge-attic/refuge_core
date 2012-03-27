%% @author Edward Wang <yujiangw@gmail.com>
%% @doc Supervises all processes of UPnP subsystem.
%% @end

-module(refuge_upnp_sup).
-behaviour(supervisor).


-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([start_link/0,
         add_upnp_entity/2]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    SupName = {local, ?SERVER},
    supervisor:start_link(SupName, ?MODULE, []).


init([]) ->
    UPNP_NET = {refuge_upnp_net, {refuge_upnp_net, start_link, []},
                permanent, 2000, worker, [refuge_upnp_net]},
    HTTPd_Dispatch = [ {'_', [{'_', refuge_upnp_handler, []}]} ],
    HTTPd = cowboy:child_spec(upnp_cowboy,
                              10, cowboy_tcp_transport, [{port, 0}],
                              cowboy_http_protocol, [{dispatch, HTTPd_Dispatch}]),
    Children = [UPNP_NET, HTTPd],
    RestartStrategy = {one_for_one, 1, 60},
    {ok, {RestartStrategy, Children}}.


add_upnp_entity(Category, Proplist) ->
    %% Each UPnP device or service can be uniquely identified by its
    %% category + type + uuid.
    ChildID = {refuge_upnp_entity, Category,
               proplists:get_value(type, Proplist),
               proplists:get_value(uuid, Proplist)},
    ChildSpec = {ChildID,
                 {refuge_upnp_entity, start_link, [Category, Proplist]},
                 permanent, 2000, worker, dynamic},
    case supervisor:start_child(?SERVER, ChildSpec) of
        {ok, _} -> ok;
        {error, {already_started, _}} ->
            refuge_upnp_entity:update(Category, Proplist)
    end.


-ifdef(EUNIT).

setup_upnp_sup_tree() ->
    {event, Event} = {event, refuge_event:start_link()},
    {table, Table} = {table, refuge_table:start_link()},
    {upnp,  UPNP}  = {upnp,  refuge_upnp_sup:start_link()},
    {Event, Table, UPNP}.

teardown_upnp_sup_tree({Event, Table, UPNP}) ->
    Shutdown = fun
        ({ok, Pid}) -> refuge_utils:shutdown(Pid);
        ({error, Reason}) -> Reason
    end,
    EventStatus = Shutdown(Event),
    TableStatus = Shutdown(Table),
    UPNPStatus  = Shutdown(UPNP),
    ?assertEqual(ok, EventStatus),
    ?assertEqual(ok, TableStatus),
    ?assertEqual(ok, UPNPStatus).

upnp_sup_test_() ->
    {foreach,
        fun setup_upnp_sup_tree/0,
        fun teardown_upnp_sup_tree/1, [
        ?_test(upnp_sup_tree_start_case())]}.


upnp_sup_tree_start_case() ->
    refuge_upnp_entity:create(device, [{type, <<"InternetGatewayDevice">>},
                                         {uuid, <<"whatever">>}]),
    refuge_upnp_entity:create(service, [{type, <<"WANIPConnection">>},
                                          {uuid, <<"whatever">>}]),
    refuge_upnp_entity:update(service, [{type, <<"WANIPConnection">>},
                                          {uuid, <<"whatever">>},
                                          {loc, {192,168,1,1}}]),
    ?assert(true).


-endif.

