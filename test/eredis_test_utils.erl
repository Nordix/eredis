-module(eredis_test_utils).

%% API.
-export([ get_tcp_ports/0
        , get_tcp_ports/1
        , start_server/1
        , stop_server/1
        , await_connect/1
        , await_connect/2
        ]).

%% Internal
-export([ start_server/2 ]).

%% Get available TCP ports (includes TLS)
-spec get_tcp_ports() -> [erlang:port()].
get_tcp_ports() ->
    [Port || Port <- erlang:ports(),
             {name, "tcp_inet"} =:= erlang:port_info(Port, name)].

%% Get available TCP ports (includes TLS) handled by pid
-spec get_tcp_ports(Pid :: pid()) -> [erlang:port()].
get_tcp_ports(Pid) ->
    [Port || Port <- get_tcp_ports(),
             {connected, Pid} =:= erlang:port_info(Port, connected)].

%% Start a server port and run Fun when a client connect.
-spec start_server(Fun :: fun((ClientSocket::inet:socket()) -> ok)) ->
          {ok, inet:port_number()}.
start_server(Fun) ->
    Pid = spawn_link(?MODULE, start_server, [self(), Fun]),
    Port = receive_from(Pid, 5000),
    {ok, Pid, Port}.

%% Stop server and close client socket as well if needed.
-spec stop_server(Pid :: pid()) -> ok.
stop_server(Pid) ->
    Pid ! shutdown.

%% Wait for a client to connect to server
-spec await_connect(Pid :: pid()) -> ok.
await_connect(Pid) ->
    await_connect(Pid, 5000).

-spec await_connect(Pid :: pid(), Timeout :: integer()) -> ok.
await_connect(Pid, Timeout) ->
    receive {Pid, connect} ->
            ok
    after Timeout ->
            error(timeout)
    end.

%% Internal

start_server(Parent, Fun) ->
    {ok, ListenSocket} = gen_tcp:listen(0, [binary, {active, false}]),
    {ok, {_, Port}} = inet:sockname(ListenSocket),
    Parent ! {self(), Port},
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket, 5000),
    Parent ! {self(), connect},
    Fun(ClientSocket),
    loop_server(ListenSocket, ClientSocket).

loop_server(ListenSocket, ClientSocket) ->
    receive
        shutdown ->
            gen_tcp:close(ClientSocket),
            gen_tcp:close(ListenSocket),
            ok;
        _ ->
            loop_server(ListenSocket, ClientSocket)
    end.

receive_from(Pid, Timeout) ->
    receive
        {Pid, Msg} ->
            Msg
    after
        Timeout ->
            error(timeout)
    end.
