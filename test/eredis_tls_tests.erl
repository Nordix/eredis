-module(eredis_tls_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TLS_PORT, 6380).

tls_connect_test() ->
    C = c_tls(),
    process_flag(trap_exit, true),
    ?assertMatch(ok, eredis:stop(C)),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    ?assertExit({noproc, _}, eredis:q(C, ["SET", foo, bar])).

tls_get_set_test() ->
    C = c_tls(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

tls_closed_test() ->
    C = c_tls(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    tls_closed_rig(C),
    timer:sleep(1300), %% Wait for reconnection (1000ms)
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    ?assertMatch(ok, eredis:stop(C)).

tls_connect_database_test() ->
    ExtraOptions = [{database, 2}],
    C = c_tls(ExtraOptions),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

tls_1_2_cert_expired_test() ->
    ExtraOptions = [],
    CertDir = "tls_expired_client_certs",
    C = c_tls(ExtraOptions, CertDir, [{versions, ['tlsv1.2']}]),
    ?assertMatch({error, no_connection}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

-ifdef(OTP_RELEASE).
-if(?OTP_RELEASE >= 22).
%% In TLS 1.3 the client send the 'certificate' message after the server's 'finished'
%% so the connect will be ok, but later a ssl_error will arrive
tls_1_3_cert_expired_test() ->
    ExtraOptions = [],
    CertDir = "tls_expired_client_certs",
    %%io:format(user, "## ~p~n", [ssl:cipher_suites(all, 'tlsv1.3')]),
    C = c_tls(ExtraOptions, CertDir, [{versions, ['tlsv1.3']}]),
    ?assertMatch({error, {tls_alert, {certificate_expired, _}}}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).
-endif.
-endif.

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
    Dir = filename:join([code:priv_dir(eredis), "configs", CertDir]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])},
                      {verify,                 verify_peer},
                      {server_name_indication, "Server"}] ++ ExtraTlSOptions}],
    Res = eredis:start_link("127.0.0.1", ?TLS_PORT, Options ++ ExtraOptions),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    C.

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
