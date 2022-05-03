-module(eredis_tls_SUITE).

%% Test framework
-export([ init_per_suite/1
        , end_per_suite/1
        , all/0
        , suite/0
        ]).
%% Test cases
-export([ t_tls_connect/1
        , t_tls_connect_eredis_sub/1
        , t_tls_get_set/1
        , t_tls_closed/1
        , t_tls_connect_database/1
        , t_tls_1_2_cert_expired/1
        , t_soon_expiring_cert/1
        , t_reconnect/1
        ]).

-ifdef(OTP_RELEASE).
-if(?OTP_RELEASE >= 22).
-export([ t_tls_1_3_cert_expired/1 ]).
-endif.
-endif.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-import(eredis_test_utils, [get_tcp_ports/0]).

-define(TLS_PORT, 6380).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

all() -> [F || {F, 1} <- module_info(exports),
               case atom_to_list(F) of
                   "t_" ++ _ -> true;
                   _         -> false
               end].

suite() -> [{timetrap, {minutes, 3}}].

%% Tests

t_tls_connect(Config) when is_list(Config) ->
    C = c_tls(),
    process_flag(trap_exit, true),
    ?assertMatch(ok, eredis:stop(C)),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    ?assertExit({noproc, _}, eredis:q(C, ["SET", foo, bar])).

t_tls_connect_eredis_sub(Config) when is_list(Config) ->
    Res = eredis_sub:start_link([{host, "127.0.0.1"},
                                 {port, ?TLS_PORT},
                                 {tls, tls_options("tls")}]),
    ?assertMatch({ok, _}, Res),
    {ok, Pid} = Res,
    process_flag(trap_exit, true),
    ?assertMatch(ok, eredis_sub:stop(Pid)),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive
             end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_tls_get_set(Config) when is_list(Config) ->
    C = c_tls(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

t_tls_closed(Config) when is_list(Config) ->
    C = c_tls(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    tls_closed_rig(C),
    timer:sleep(1300), %% Wait for reconnection (1000ms)
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    ?assertMatch(ok, eredis:stop(C)).

t_tls_connect_database(Config) when is_list(Config) ->
    ExtraOptions = [{database, 2}],
    C = c_tls(ExtraOptions),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

t_tls_1_2_cert_expired(Config) when is_list(Config) ->
    ExtraOptions = [],
    CertDir = "tls_expired_client_certs",
    C = c_tls(ExtraOptions, CertDir, [{versions, ['tlsv1.2']}]),
    ?assertMatch({error, no_connection}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

-ifdef(OTP_RELEASE).
-if(?OTP_RELEASE >= 22).
%% In TLS 1.3 the client send the 'certificate' message after the server's 'finished'
%% so the connect will be ok, but later a ssl_error will arrive
t_tls_1_3_cert_expired(Config) when is_list(Config) ->
    ExtraOptions = [],
    CertDir = "tls_expired_client_certs",
    C = c_tls(ExtraOptions, CertDir, [{versions, ['tlsv1.3']}]),
    %% Depending on timing the query will result in a tls_alert error,
    %% but if the error indication was handled before sending the query
    %% the connection has already been taken down, hence a no_connection
    case eredis:q(C, ["GET", foo]) of
        {error, {tls_alert, {certificate_expired, _}}} -> ok;
        {error, no_connection} -> ok
    end,
    ?assertMatch(ok, eredis:stop(C)).
-endif.
-endif.

t_soon_expiring_cert(Config) when is_list(Config) ->
    Dir = filename:join([code:priv_dir(eredis), "configs", "tls_soon_expired_client_certs"]),
    Options = [{reconnect_sleep, 2000},
               {tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])},
                      {verify,     verify_peer},
                      {server_name_indication, "Server"}]}],

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

    %% Connecting with an expired certificate works fine during the
    %% connect and handshake, but triggers a ssl_error message that
    %% makes the client perform a reconnect.
    ct:pal("Connect with an expired certificate..."),
    Res2 = eredis:start_link("127.0.0.1", ?TLS_PORT, Options),
    ?assertMatch({ok, _}, Res2),
    {ok, C2} = Res2,

    timer:sleep(200),

    ?assertEqual({error, no_connection}, eredis:q(C2, ["SET", foo, bar4])),
    ?assertMatch(ok, eredis:stop(C2)).

%% Make sure a reconnect cleanup old sockets
%% i.e we have maximum 1 tcp/tls port open
t_reconnect(Config) when is_list(Config) ->
    ?assertEqual(0, length(get_tcp_ports())),
    ExtraOptions = [{password, "wrong_password"},
                    {reconnect_sleep, 100},
                    {connect_timeout, 200}],
    C = c_tls(ExtraOptions),
    timer:sleep(1000), %% expect a couple of reconnect attempts
    ?assert(length(get_tcp_ports()) =< 1),
    ?assertMatch(ok, eredis:stop(C)),
    timer:sleep(200), %% Wait for reconnect process to terminate
    ?assertEqual(0, length(get_tcp_ports())).

%%
%% Helpers
%%
c_tls() ->
    c_tls([]).

c_tls(ExtraOptions) ->
    c_tls(ExtraOptions, "tls").

c_tls(ExtraOptions, CertDir) ->
    c_tls(ExtraOptions, CertDir, []).

c_tls(ExtraOptions, CertDir, ExtraTlSOptions) ->
    Options = [{tls, tls_options(CertDir) ++ ExtraTlSOptions}],
    Res = eredis:start_link("127.0.0.1", ?TLS_PORT, Options ++ ExtraOptions),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    C.

tls_options(CertDir) ->
    Dir = filename:join([code:priv_dir(eredis), "configs", CertDir]),
    [{cacertfile, filename:join([Dir, "ca.crt"])},
     {certfile,   filename:join([Dir, "client.crt"])},
     {keyfile,    filename:join([Dir, "client.key"])},
     {verify,                 verify_peer},
     {server_name_indication, "Server"}].

tls_closed_rig(C) ->
    %% fire async requests to add to redis client queue and then trick
    %% the client into thinking the connection to redis has been
    %% closed. This behavior can be observed when Redis closes an idle
    %% connection just as a traffic burst starts.
    DoSend = fun(ssl_closed) ->
                     C ! {ssl_closed, fake_socket};
                (Cmd) ->
                     eredis:q(C, Cmd)
             end,
    %% attach an id to each message for later
    Msgs = [{1, ["GET", "foo"]},
            {2, ["GET", "bar"]},
            {3, ssl_closed}],
    Pids = [ remote_query(DoSend, M) || M <- Msgs ],
    Results = gather_remote_queries(Pids),
    ?assertEqual({error, ssl_closed}, proplists:get_value(1, Results)),
    ?assertEqual({error, ssl_closed}, proplists:get_value(2, Results)).

remote_query(Fun, {Id, Cmd}) ->
    Parent = self(),
    spawn(fun() ->
                  Result = Fun(Cmd),
                  Parent ! {self(), Id, Result}
          end).

gather_remote_queries(Pids) ->
    gather_remote_queries(Pids, []).

gather_remote_queries([], Acc) ->
    Acc;
gather_remote_queries([Pid | Rest], Acc) ->
    receive
        {Pid, Id, Result} ->
            gather_remote_queries(Rest, [{Id, Result} | Acc])
    after
        10000 ->
            error({gather_remote_queries, timeout})
    end.
