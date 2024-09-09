-module(eredis_sentinel_SUITE).

%% Test framework
-export([ init_per_suite/1
        , end_per_suite/1
        , all/0
        , suite/0
        ]).

%% Test cases
-export([
         t_connect_with_default_opts/1
        , t_connect_with_wrong_master_port/1
        , t_connect_with_mix_sentinel_endpoints/1
        , t_connect_with_explicit_options/1
        , t_stop/1
        , t_connection_failure_during_start_no_reconnect/1
        , t_connection_failure_during_start_reconnect/1
        , t_reconnect_success_on_sentinel_process_exit/1
        , t_reconnect_success_on_sentinel_connection_break/1
        , t_reconnect_success_on_sentinel_connection_break_mix_endpoints/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("eredis.hrl").

-define(WRONG_PORT, 6378).
-define(SENTINEL_PORT, 26379).
-define(WRONG_SENTINEL_ENDPOINTS, [{"127.0.0.1", 26381}, {"127.0.0.1", 26382}]).
-define(SENTINEL_UNREACHABLE, sentinel_unreachable).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

all() -> [F || {F, _A} <- module_info(exports),
               case atom_to_list(F) of
                   "t_" ++ _ -> true;
                   _         -> false
               end].

suite() -> [{timetrap, {minutes, 1}}].

%% Tests

t_connect_with_default_opts(Config) when is_list(Config) ->
    connect_eredis_sentinel([{sentinel, []}]).

t_connect_with_wrong_master_port(Config) when is_list(Config) ->
    connect_eredis_sentinel([{port, ?WRONG_PORT}, {sentinel, []}]).

t_connect_with_mix_sentinel_endpoints(Config) when is_list(Config) ->
    SentinelAddr = ?WRONG_SENTINEL_ENDPOINTS ++ [{"127.0.0.1", ?SENTINEL_PORT}],
    connect_eredis_sentinel([{sentinel, [{endpoints, SentinelAddr}]}]).

t_connect_with_explicit_options(Config) when is_list(Config) ->
    connect_eredis_sentinel([{sentinel, [{master_group, mymaster},
                                         {endpoints, [{"127.0.0.1", ?SENTINEL_PORT}]},
                                         {connect_timeout, 5000},
                                         {socket_options, [{keepalive, true}]},
                                         {password, ""}
                                        ]}]).

t_stop(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    C = c_sentinel(),
    ok = eredis:stop(C),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    ?assertExit({noproc, _}, eredis:q(C, ["SET", foo, bar])),
    timer:sleep(100),
    ?assertMatch(undefined, whereis(mymaster)).

t_connection_failure_during_start_no_reconnect(Config) when is_list(Config) ->
    SentinelOpts = [{endpoints, ?WRONG_SENTINEL_ENDPOINTS}],
    process_flag(trap_exit, true),
    Res = eredis:start_link([{reconnect_sleep, no_reconnect},
                             {sentinel, SentinelOpts}]),
    ?assertMatch({error, ?SENTINEL_UNREACHABLE}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_connection_failure_during_start_reconnect(Config) when is_list(Config) ->
    SentinelOpts = [{endpoints, ?WRONG_SENTINEL_ENDPOINTS}],
    process_flag(trap_exit, true),
    Res = eredis:start_link([{reconnect_sleep, 100},
                             {sentinel, SentinelOpts}
                            ]),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    IsDead = receive {'EXIT', C, _} -> died
             after 400 -> still_alive end,
    ?assertEqual(still_alive, IsDead),
    ok = eredis:stop(C),
    IsDead2 = receive {'EXIT', _Pid, _Reason} -> died
              after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead2).

t_reconnect_success_on_sentinel_process_exit(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    C = c_sentinel(),
    timer:sleep(100),
    ?assert(is_process_alive(whereis(mymaster))),
    erlang:exit(whereis(mymaster), abnormal),
    timer:sleep(100),
    ?assertMatch(undefined, whereis(mymaster)),
    {ok, C1} = eredis:start_link(),
    eredis:q(C1, ["CLIENT", "KILL", "TYPE", "NORMAL"]),
    timer:sleep(100),
    ?assert(is_process_alive(whereis(mymaster))),
    ok = eredis:stop(C),
    IsDead = receive {'EXIT', _Pid, _Reason} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_reconnect_success_on_sentinel_connection_break(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    C = c_sentinel(),
    timer:sleep(100),
    {links, LinkedPids1} = process_info(whereis(mymaster), links),
    ?assertMatch(2, length(LinkedPids1)),
    {ok, SC} = eredis:start_link("127.0.0.1", ?SENTINEL_PORT),
    eredis:q(SC, ["CLIENT", "KILL", "TYPE", "NORMAL"]),
    timer:sleep(100),
    {links, LinkedPids2} = process_info(whereis(mymaster), links),
    ?assertEqual(1, length(LinkedPids2)),
    {ok, C1} = eredis:start_link(),
    eredis:q(C1, ["CLIENT", "KILL", "TYPE", "NORMAL"]),
    timer:sleep(100),
    {links, LinkedPids3} = process_info(whereis(mymaster), links),
    ?assertMatch(2, length(LinkedPids3)),
    ok = eredis:stop(C),
    IsDead = receive {'EXIT', _Pid, _Reason} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_reconnect_success_on_sentinel_connection_break_mix_endpoints(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    SentinelOpts = [{endpoints, ?WRONG_SENTINEL_ENDPOINTS ++ [{"127.0.0.1", ?SENTINEL_PORT}]}],
    {ok, C} = eredis:start_link([{sentinel, SentinelOpts}]),
    ?assertMatch({ok, [<<"master">> | _]}, eredis:q(C, ["ROLE"])),
    timer:sleep(100),
    {links, LinkedPids1} = process_info(whereis(mymaster), links),
    ?assertMatch(2, length(LinkedPids1)),
    {ok, SC} = eredis:start_link("127.0.0.1", ?SENTINEL_PORT),
    eredis:q(SC, ["CLIENT", "KILL", "TYPE", "NORMAL"]),
    timer:sleep(100),
    {links, LinkedPids2} = process_info(whereis(mymaster), links),
    ?assertEqual(1, length(LinkedPids2)),
    erlang:exit(whereis(mymaster), abnormal),
    timer:sleep(100),
    ?assertMatch(undefined, whereis(mymaster)),
    {ok, C1} = eredis:start_link(),
    eredis:q(C1, ["CLIENT", "KILL", "TYPE", "NORMAL"]),
    timer:sleep(100),
    ?assertMatch({ok, [<<"master">> | _]}, eredis:q(C, ["ROLE"])),
    timer:sleep(100),
    {links, LinkedPids3} = process_info(whereis(mymaster), links),
    ?assertMatch(2, length(LinkedPids3)),
    ?assertMatch(ok, eredis:stop(C)),
    IsDead = receive {'EXIT', _Pid, _Reason} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

%%
%% Helpers
%%

c_sentinel() ->
    Res = eredis:start_link([{sentinel, []}]),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    C.

connect_eredis_sentinel(Options) ->
    process_flag(trap_exit, true),
    Res = eredis:start_link(Options),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    ?assertMatch({ok, [<<"master">> | _]}, eredis:q(C, ["ROLE"])),
    ok = eredis:stop(C),
    IsDead = receive {'EXIT', _Pid, _Reason} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).
