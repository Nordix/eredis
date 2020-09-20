-module(eredis_test_utils).

-export([ get_tcp_ports/0 ]).

% Get number of available TCP ports (includes TLS)
get_tcp_ports() ->
    [Port || Port <- erlang:ports(),
             {name, "tcp_inet"} =:= erlang:port_info(Port, name)].
