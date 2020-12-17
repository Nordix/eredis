-module(eredis_tcp_SUITE).

%% Test framework
-export([ init_per_suite/1
        , end_per_suite/1
        , all/0
        , suite/0
        ]).

%% Test cases
-export([ t_connect/1
        , t_connect_ipv6/1
        , t_connect_hostname/1
        , t_connect_local/1
        , t_stop/1
        , t_get_set/1
        , t_set_get_term/1
        , t_delete/1
        , t_mset_mget/1
        , t_exec/1
        , t_exec_nil/1
        , t_pipeline/1
        , t_pipeline_mixed/1
        , t_q_noreply/1
        , t_q_async/1
        , t_undefined_database/1
        , t_select_logical_database/1
        , t_faulty_logical_database/1
        , t_authentication_error/1
        , t_connection_failure_during_start_no_reconnect/1
        , t_connection_failure_during_start_reconnect/1
        , t_unknown_client_call/1
        , t_unknown_client_cast/1
        , t_tcp_closed/1
        , t_connect_no_reconnect/1
        , t_tcp_closed_no_reconnect/1
        , t_reconnect/1
        , t_error_socket_closed_before_auth/1
        , t_error_socket_closed_while_waiting_for_auth_response/1
        , t_error_socket_closed_before_select_db/1
        , t_error_socket_closed_while_waiting_for_select_db_response/1
        , t_send_error/1
        , t_ignore_old_socket/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("eredis.hrl").

-import(eredis_test_utils, [get_tcp_ports/0, get_tcp_ports/1]).

-define(PORT, 6379).
-define(WRONG_PORT, 6378).

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

t_connect(Config) when is_list(Config) ->
    ?assertMatch({ok, _}, eredis:start_link()),
    ?assertMatch({ok, _}, eredis:start_link("127.0.0.1", ?PORT)),
    ?assertMatch({ok, _}, eredis:start_link("127.0.0.1", ?PORT, [{reconnect_sleep, no_reconnect}])),
    ?assertMatch({ok, _}, eredis:start_link("127.0.0.1", ?PORT, [{database, 0},
                                                                 {password, ""},
                                                                 {reconnect_sleep, 100},
                                                                 {connect_timeout, 5000},
                                                                 {socket_options, [{keepalive, true}]}
                                                                ])),
    ?assertMatch({ok, _}, eredis:start_link([])),
    ?assertMatch({ok, _}, eredis:start_link([{host, "127.0.0.1"}, {port, ?PORT}])).

t_connect_ipv6(Config) when is_list(Config) ->
    ?assertMatch({ok, _}, eredis:start_link("::1", ?PORT, [{reconnect_sleep, no_reconnect}])).

t_connect_hostname(Config) when is_list(Config) ->
    Res = eredis:start_link(net_adm:localhost(), ?PORT, [{reconnect_sleep, no_reconnect}]),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    ?assertMatch(ok, eredis:stop(C)).

t_connect_local(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    eredis:start_link({local, "/var/run/redis.sock"}, 0, [{reconnect_sleep, no_reconnect}]),
    IsDead = receive {'EXIT', _Pid, {connection_error, enoent}} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_stop(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    C = c(),
    ?assertMatch(ok, eredis:stop(C)),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    ?assertExit({noproc, _}, eredis:q(C, ["SET", foo, bar])).

t_get_set(Config) when is_list(Config) ->
    C = c(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),

    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

t_set_get_term(Config) when is_list(Config) ->
    C = c(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", term])),

    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", term, C])),
    ?assertEqual({ok, term_to_binary(C)}, eredis:q(C, ["GET", term])),
    ?assertMatch(ok, eredis:stop(C)).

t_delete(Config) when is_list(Config) ->
    C = c(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo])),

    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual({ok, <<"1">>}, eredis:q(C, ["DEL", foo])),
    ?assertEqual({ok, undefined}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

t_mset_mget(Config) when is_list(Config) ->
    C = c(),
    Keys = lists:seq(1, 1000),

    ?assertMatch({ok, _}, eredis:q(C, ["DEL" | Keys])),

    KeyValuePairs = [[K, K * 2] || K <- Keys],
    ExpectedResult = [list_to_binary(integer_to_list(K * 2)) || K <- Keys],

    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["MSET" | lists:flatten(KeyValuePairs)])),
    ?assertEqual({ok, ExpectedResult}, eredis:q(C, ["MGET" | Keys])),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL" | Keys])),
    ?assertMatch(ok, eredis:stop(C)).

t_exec(Config) when is_list(Config) ->
    C = c(),

    ?assertMatch({ok, _}, eredis:q(C, ["LPUSH", "k1", "b"])),
    ?assertMatch({ok, _}, eredis:q(C, ["LPUSH", "k1", "a"])),
    ?assertMatch({ok, _}, eredis:q(C, ["LPUSH", "k2", "c"])),

    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["MULTI"])),
    ?assertEqual({ok, <<"QUEUED">>}, eredis:q(C, ["LRANGE", "k1", "0", "-1"])),
    ?assertEqual({ok, <<"QUEUED">>}, eredis:q(C, ["LRANGE", "k2", "0", "-1"])),

    ExpectedResult = [[<<"a">>, <<"b">>], [<<"c">>]],

    ?assertEqual({ok, ExpectedResult}, eredis:q(C, ["EXEC"])),

    ?assertMatch({ok, _}, eredis:q(C, ["DEL", "k1", "k2"])),
    ?assertMatch(ok, eredis:stop(C)).

t_exec_nil(Config) when is_list(Config) ->
    C1 = c(),
    C2 = c(),

    ?assertEqual({ok, <<"OK">>}, eredis:q(C1, ["WATCH", "x"])),
    ?assertMatch({ok, _}, eredis:q(C2, ["INCR", "x"])),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C1, ["MULTI"])),
    ?assertEqual({ok, <<"QUEUED">>}, eredis:q(C1, ["GET", "x"])),
    ?assertEqual({ok, undefined}, eredis:q(C1, ["EXEC"])),
    ?assertMatch({ok, _}, eredis:q(C1, ["DEL", "x"])),
    ?assertMatch(ok, eredis:stop(C1)),
    ?assertMatch(ok, eredis:stop(C2)).

t_pipeline(Config) when is_list(Config) ->
    C = c(),

    P1 = [["SET", a, "1"],
          ["LPUSH", b, "3"],
          ["LPUSH", b, "2"]],

    ?assertEqual([{ok, <<"OK">>}, {ok, <<"1">>}, {ok, <<"2">>}],
                 eredis:qp(C, P1)),

    P2 = [["MULTI"],
          ["GET", a],
          ["LRANGE", b, "0", "-1"],
          ["EXEC"]],

    ?assertEqual([{ok, <<"OK">>},
                  {ok, <<"QUEUED">>},
                  {ok, <<"QUEUED">>},
                  {ok, [<<"1">>, [<<"2">>, <<"3">>]]}],
                 eredis:qp(C, P2)),

    P3 = [],

    ?assertEqual([],
                 eredis:qp(C, P3, 5000)),

    ?assertMatch({ok, _}, eredis:q(C, ["DEL", a, b])),
    ?assertMatch(ok, eredis:stop(C)).

t_pipeline_mixed(Config) when is_list(Config) ->
    C = c(),
    P1 = [["LPUSH", c, "1"] || _ <- lists:seq(1, 100)],
    P2 = [["LPUSH", d, "1"] || _ <- lists:seq(1, 100)],
    Expect = [{ok, list_to_binary(integer_to_list(I))} || I <- lists:seq(1, 100)],
    spawn(fun () ->
                  erlang:yield(),
                  ?assertEqual(Expect, eredis:qp(C, P1))
          end),
    spawn(fun () ->
                  ?assertEqual(Expect, eredis:qp(C, P2))
          end),
    timer:sleep(10),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", c, d])),
    ?assertMatch(ok, eredis:stop(C)).

t_q_noreply(Config) when is_list(Config) ->
    C = c(),
    ?assertEqual(ok, eredis:q_noreply(C, ["GET", foo])),
    ?assertEqual(ok, eredis:q_noreply(C, ["SET", foo, bar])),
    %% Even though q_noreply doesn't wait, it is sent before subsequent requests:
    ?assertEqual({ok, <<"bar">>}, eredis:q(C, ["GET", foo])),
    ?assertMatch(ok, eredis:stop(C)).

t_q_async(Config) when is_list(Config) ->
    C = c(),
    ?assertEqual({ok, <<"OK">>}, eredis:q(C, ["SET", foo, bar])),
    ?assertEqual(ok, eredis:q_async(C, ["GET", foo], self())),
    receive
        {response, Msg} ->
            ?assertEqual(Msg, {ok, <<"bar">>})
    end,
    ?assertEqual(ok, eredis:q_async(C, ["GET", foo])),
    receive
        {response, Msg2} ->
            ?assertEqual(Msg2, {ok, <<"bar">>}),
            ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo]))
    end,
    ?assertMatch(ok, eredis:stop(C)).

t_undefined_database(Config) when is_list(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?PORT, [{database, undefined},
                                                     {reconnect_sleep, no_reconnect}]),
    ?assertMatch(ok, eredis:stop(C)).

t_select_logical_database(Config) when is_list(Config) ->
    {ok, C} =  eredis:start_link("127.0.0.1", ?PORT, [{database, 2},
                                                      {reconnect_sleep, no_reconnect}]),
    ?assertMatch(ok, eredis:stop(C)).

t_faulty_logical_database(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", ?PORT, [{database, 99999999},
                                                 {reconnect_sleep, no_reconnect}]),
    %% Note: The error message content has changed from Redis 3 to Redis 4
    ?assertMatch({error, {select_error, {unexpected_response, <<"-ERR", _/binary>>}}}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_authentication_error(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", ?PORT, [{password, "password"},
                                                 {reconnect_sleep, no_reconnect}]),
    %% Note: The error message content has changed from Redis 5 to Redis 6
    ?assertMatch({error, {authentication_error, {unexpected_response, <<"-ERR", _/binary>>}}}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_connection_failure_during_start_no_reconnect(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", ?WRONG_PORT, [{reconnect_sleep, no_reconnect},
                                                       {connect_timeout, 1000}]),
    ?assertMatch({error, _}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 1000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead).

t_connection_failure_during_start_reconnect(Config) when is_list(Config) ->
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", ?WRONG_PORT, [{reconnect_sleep, 100}]),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    IsDead = receive {'EXIT', C, _} -> died
             after 400 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(still_alive, IsDead),
    ?assertMatch(ok, eredis:stop(C)).

t_unknown_client_call(Config) when is_list(Config) ->
    C = c(),
    Request = {test},
    ?assertEqual(unknown_request, gen_server:call(C, Request)),
    ?assertMatch(ok, eredis:stop(C)).

t_unknown_client_cast(Config) when is_list(Config) ->
    C = c(),
    Request = {test},
    ?assertEqual(ok, gen_server:cast(C, Request)),
    ?assertMatch(ok, eredis:stop(C)).

t_tcp_closed(Config) when is_list(Config) ->
    C = c(),
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    tcp_closed_rig(C),
    timer:sleep(1300), %% Wait for reconnection (1000ms)
    ?assertMatch({ok, _}, eredis:q(C, ["DEL", foo], 5000)),
    ?assertMatch(ok, eredis:stop(C)).

t_connect_no_reconnect(Config) when is_list(Config) ->
    C = c_no_reconnect(),
    ?assertMatch(ok, eredis:stop(C)).

t_tcp_closed_no_reconnect(Config) when is_list(Config) ->
    C = c_no_reconnect(),
    tcp_closed_rig(C).

t_reconnect(Config) when is_list(Config) ->
    %% Make sure a reconnect cleanup old sockets
    %% i.e we only have maximum 1 tcp port open
    ?assertEqual(0, length(get_tcp_ports())),
    {ok, C} = eredis:start_link("127.0.0.1", ?PORT, [{password, "wrong_password"},
                                                     {reconnect_sleep, 100},
                                                     {connect_timeout, 200}]),
    timer:sleep(1000), %% expect a couple of reconnect attempts
    ?assert(length(get_tcp_ports()) =< 1),
    ?assertMatch(ok, eredis:stop(C)),
    timer:sleep(200), %% Wait for reconnect process to terminate
    ?assertEqual(0, length(get_tcp_ports())).

t_error_socket_closed_before_auth(Config) when is_list(Config) ->
    %% Simulate that Redis closes the connection directly, before eredis sends
    %% the AUTH command.
    {ok, Pid, Port} = eredis_test_utils:start_server(
                        fun(ClientSocket) ->
                                ok = gen_tcp:close(ClientSocket)
                        end),
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", Port, [{password, "password"},
                                                {reconnect_sleep, no_reconnect}]),
    ?assertMatch({error, {authentication_error, _}}, Res), %% einval or closed depending of timing
    IsDead = receive {'EXIT', _, _} -> died
             after 2000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    eredis_test_utils:stop_server(Pid).

t_error_socket_closed_while_waiting_for_auth_response(Config) when is_list(Config) ->
    %% Simulate that Redis closes the connection after the AUTH
    %% command was sent.
    {ok, Pid, Port} = eredis_test_utils:start_server(
                        fun(ClientSocket) ->
                                {ok, <<"AUTH \"password\"\r\n">>} = gen_tcp:recv(ClientSocket, 0, 2000),
                                ok = gen_tcp:close(ClientSocket)
                        end),
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", Port, [{password, "password"},
                                                {reconnect_sleep, no_reconnect}]),
    ?assertMatch({error, {authentication_error, closed}}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 2000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    eredis_test_utils:stop_server(Pid).

t_error_socket_closed_before_select_db(Config) when is_list(Config) ->
    %% Simulate that Redis closes the connection directly, before eredis sends
    %% the SELECT command.
    {ok, Pid, Port} = eredis_test_utils:start_server(
                        fun(ClientSocket) ->
                                ok = gen_tcp:close(ClientSocket)
                        end),
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", Port, [{database, 2},
                                                {reconnect_sleep, no_reconnect}]),
    ?assertMatch({error, {select_error, _}}, Res), %% einval or closed depending of timing
    IsDead = receive {'EXIT', _, _} -> died
             after 2000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    eredis_test_utils:stop_server(Pid).

t_error_socket_closed_while_waiting_for_select_db_response(Config) when is_list(Config) ->
    %% Simulate that Redis closes the connection after the SELECT
    %% command was sent.
    {ok, Pid, Port} = eredis_test_utils:start_server(
                        fun(ClientSocket) ->
                                {ok, <<"SELECT 2\r\n">>} = gen_tcp:recv(ClientSocket, 0, 2000),
                                ok = gen_tcp:close(ClientSocket)
                        end),
    process_flag(trap_exit, true),
    Res = eredis:start_link("127.0.0.1", Port, [{database, 2},
                                                {reconnect_sleep, no_reconnect}]),
    ?assertMatch({error, {select_error, closed}}, Res),
    IsDead = receive {'EXIT', _, _} -> died
             after 2000 -> still_alive end,
    process_flag(trap_exit, false),
    ?assertEqual(died, IsDead),
    eredis_test_utils:stop_server(Pid).

t_send_error(Config) when is_list(Config) ->
    %% Verify handling of send errors by using the send_timout_close option.
    %% Connect an eredis client to a server and fill the clients sockets sendbuffer
    %% until the socket is full. Then let eredis handle a query which will
    %% trigger a send error (and reconnection attempts)
    %%
    %% The socket option send_timeout_close is used here (together with send_timeout),
    %% otherwise the socket close takes ~5s, and the tcp port is kept by Erlang.
    {ok, Pid, Port} = eredis_test_utils:start_server(
                        fun(ClientSocket) ->
                                inet:setopts(ClientSocket, [{recbuf, 4096}])
                        end),
    {ok, C} = eredis:start_link("127.0.0.1", Port, [{reconnect_sleep, 100},
                                                    {socket_options, [{send_timeout, 250},
                                                                      {send_timeout_close, true},
                                                                      {sndbuf, 4096}]}]),
    eredis_test_utils:await_connect(Pid),
    [Socket] = get_tcp_ports(C),                %% Steel the eredis client socket..
    {error, timeout} = send_data_loop(Socket),  %% ..and fill the socket buffer
    ?assertEqual({error, enotconn}, eredis:q(C, ["GET", foo])),
    timer:sleep(200),
    [Socket2] = get_tcp_ports(C),               %% Get new eredis client socket
    ?assertNotEqual(Socket, Socket2),           %% Reconnection attempts with new socket
    eredis_test_utils:stop_server(Pid).

send_data_loop(Socket) ->
    Data = << <<0>> || _ <- lists:seq(1, 1024) >>,
    case gen_tcp:send(Socket, Data) of
        ok -> send_data_loop(Socket);
        Error -> Error
    end.

t_ignore_old_socket(Config) when is_list(Config) ->
    %% Verify that the client ignores messages and errors for a
    %% previously used socket and keeps the current connection open.
    %% The events are simulated by sending similar messages the
    %% client process would receive as a socket owner process
    %% when these events occure.
    {ok, C} = eredis:start_link("127.0.0.1", ?PORT, []),
    [Socket] = get_tcp_ports(C),
    C ! {tcp, old_socket, data}, %% Incoming data event
    timer:sleep(200),
    [Socket] = get_tcp_ports(C),
    C ! {tcp_error, old_socket, reason}, %% Socket error event
    timer:sleep(200),
    [Socket] = get_tcp_ports(C),
    C ! {tcp_closed, old_socket}, %% Socket closed event
    timer:sleep(200),
    [Socket] = get_tcp_ports(C),
    C ! {send_error, old_socket, reason}, %% Internal send error event
    timer:sleep(200),
    [Socket] = get_tcp_ports(C).

%%
%% Helpers
%%

tcp_closed_rig(C) ->
    %% fire async requests to add to redis client queue and then trick
    %% the client into thinking the connection to redis has been
    %% closed. This behavior can be observed when Redis closes an idle
    %% connection just as a traffic burst starts.
    DoSend = fun(tcp_closed) ->
                     C ! {tcp_closed, fake_socket};
                (Cmd) ->
                     eredis:q(C, Cmd)
             end,
    %% attach an id to each message for later
    Msgs = [{1, ["GET", "foo"]},
            {2, ["GET", "bar"]},
            {3, tcp_closed}],
    Pids = [ remote_query(DoSend, M) || M <- Msgs ],
    Results = gather_remote_queries(Pids),
    ?assertEqual({error, tcp_closed}, proplists:get_value(1, Results)),
    ?assertEqual({error, tcp_closed}, proplists:get_value(2, Results)).

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

c() ->
    Res = eredis:start_link(),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    C.

c_no_reconnect() ->
    Res = eredis:start_link("127.0.0.1", ?PORT, [{reconnect_sleep, no_reconnect}]),
    ?assertMatch({ok, _}, Res),
    {ok, C} = Res,
    C.
