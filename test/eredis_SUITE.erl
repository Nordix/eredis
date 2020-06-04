-module(eredis_SUITE).

%% Test framework
-export([ init_per_suite/1
        , end_per_suite/1
        , all/0
        , suite/0
        ]).

%% Test cases
-export([ t_expiring_certs/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-define(TLS_PORT, 6380).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

all() -> [F || {F, _A} <- module_info(exports),
               case atom_to_list(F) of
                   "t_" ++ _ -> true;
                   _         -> false
               end].

suite() -> [{timetrap, {minutes, 10}}].

%% Tests

t_expiring_certs(Config) when is_list(Config) ->
    Dir = filename:join([code:priv_dir(eredis), "configs", "tls_soon_expired_client_certs"]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])},
                      {verify,     verify_peer},
                      {server_name_indication, "Server"}]}],

    %%observer:start(),

    ct:pal("Connect a client with a certificate that expires in 1 minute"),
    Res = eredis:start_link("127.0.0.1", ?TLS_PORT, Options),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar1])),
    ?assertEqual({ok, <<"bar1">>}, eredis:q(C, ["GET", foo])),

    ct:pal(user, "Sleep 1 minute [1 of 2]"),
    timer:sleep(1 * 60 * 1000),

    %% Client works even when certificate has expired
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar2])),
    ?assertEqual({ok, <<"bar2">>}, eredis:q(C, ["GET", foo])),

    ct:pal(user, "Sleep 1 minute [2 of 2]"),
    timer:sleep(1 * 60 * 1000),

    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar3])),
    ?assertEqual({ok, <<"bar3">>}, eredis:q(C, ["GET", foo])),
    ct:pal(user, "Stopping client"),
    ?assertMatch(ok, eredis:stop(C)),

    %% Reconnect, will give ok during connect+handshake
    %% but trigger a ssl_error that makes the client try reconnect
    ct:pal("Reconnect, now with expired certificate..."),
    Res2 = eredis:start_link("127.0.0.1", ?TLS_PORT, Options),
    ?assertMatch({ok, _}, Res2),
    {ok, C2} = Res2,

    ?assertEqual({error, no_connection}, eredis:q(C2, ["SET", foo, bar4])),
    ?assertMatch(ok, eredis:stop(C2)),
    ok.
