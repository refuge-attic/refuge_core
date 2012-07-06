%% @doc advertise node using dnssd

-module(refuge_dnssd_advertise).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    SName = service_name(),
    {ok, SPort} = couch_httpd_util:get_port(https),
    {ok, RegRef} = dnssd:register(SName, "_refuge._tcp", SPort),

    {ok, HttpRef} = case couch_config:get("refuge", "advertise_dnssd_http",
                                          "true") of
        "true" ->
            {ok, Port} = couch_httpd_util:get_port(http),
            HttpName = << "Refuge (", SName/binary, ")" >>,
            dnssd:register(HttpName, "_http._tcp", Port, [{path, "/_utils"}]);
        _ ->
            {ok, nil}
    end,

    {ok, [RegRef, HttpRef]}.

handle_call(_Request, _From, Refs) ->
    {noreply, Refs}.

handle_cast(_Msg, Refs) ->
    {noreply, Refs}.

handle_info({dnssd, _Ref, {register, Change, Result}}, Refs) ->
    lager:info(?MODULE_STRING " register ~s: ~p~n", [Change, Result]),
    {noreply,  Refs};

handle_info(_Info, Refs) ->
    {noreply, Refs}.

terminate(_Reason, Refs) ->
    lists:foreach(fun
            (nil) -> ok;
            (Ref) -> dnssd:stop(Ref)
        end, Refs),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

service_name() ->
    refuge_util:new_id().
