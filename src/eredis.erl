%%
%% Erlang Redis client
%%
%% Usage:
%%   {ok, Client} = eredis:start_link().
%%   {ok, <<"OK">>} = eredis:q(Client, ["SET", "foo", "bar"]).
%%   {ok, <<"bar">>} = eredis:q(Client, ["GET", "foo"]).

-module(eredis).
-include("eredis.hrl").

%% Default timeout for calls to the client gen_server
-define(TIMEOUT, 5000).

-export([start_link/0, start_link/1, start_link/2, start_link/3, start_link/4,
         start_link/5, start_link/6, start_link/7]).
-export([stop/1]).
-export([q/2, q/3, qp/2, qp/3, q_noreply/2, q_async/2, q_async/3]).
-export_type([options/0]).

%% Exported for eredis_client, eredis_sub_client and testing
-export([create_multibulk/1]).

%% Type of gen_server process id
-type client() :: pid() |
                  atom() |
                  {atom(), atom()} |
                  {global, term()} |
                  {via, atom(), term()}.

-type host() :: string() | {local, string()}.

%%
%% PUBLIC API
%%

%% @doc Connect with default options.
%%
%% @equiv start_link([])
-spec start_link() -> {ok, Pid::pid()} | {error, Reason::term()}.
start_link() ->
    start_link([]).

%% @doc Connect with the given options.
%%
%% @param Options <dl>
%% <dt>`{host, Host}'</dt><dd>DNS name or IP address as string; or unix domain
%% socket as `{local, Path}' (available in OTP 19+); default `"127.0.0.1"'</dd>
%% <dt>`{port, Port}'</dt><dd>Integer, default is 6379</dd>
%% <dt>`{database, Database}'</dt><dd>Integer; 0 for the default database</dd>
%% <dt>`{username, Username}'</dt><dd>A 0-ary function that returns the username
%% (the preferred way to provide username as it prevent the actual secret from
%% appearing in logs and stacktraces), a string or iodata or the atom
%% `undefined' for no username; default `undefined'</dd>
%% <dt>`{password, Password}'</dt><dd>A 0-ary function that returns the password
%% (the preferred way to provide password as it prevent the actual secret from
%% appearing in logs and stacktraces), a string or iodata or the atom
%% `undefined' for no username; default `undefined'</dd>
%% <dt>`{reconnect_sleep, ReconnectSleep}'</dt><dd>Integer of milliseconds to
%% sleep between reconnect attempts; default: 100</dd>
%% <dt>`{connect_timeout, Timeout}'</dt><dd>Timeout value in milliseconds to use
%% when connecting to Redis; default: 5000</dd>
%% <dt>`{socket_options, SockOpts}'</dt><dd>List of
%% <a href="https://erlang.org/doc/man/gen_tcp.html">gen_tcp options</a> used
%% when connecting the socket; default is `?SOCKET_OPTS'</dd>
%% <dt>`{tls, TlsOpts}'</dt><dd>Enabling TLS and a list of
%% <a href="https://erlang.org/doc/man/ssl.html">ssl options</a>; used when
%% establishing a TLS connection; default is off</dd>
%% <dt>`{name, Name}'</dt><dd>Tuple to register the client with a name
%% such as `{local, atom()}'; for all options see `ServerName' at
%% <a href="https://erlang.org/doc/man/gen_server.html#start_link-4">gen_server:start_link/4</a>;
%% default: no name</dd>
%% <dt>`{sentinel, SentinelOptions}'</dt><dd> Enables client for sentinel mode; options are required
%% to connect to sentinel cluster; default: undefined </dd>
%% <dd> Sentinel Options: `{master_group, master_group_name}' - Atom, default: mymaster;
%% `{endpoints, [{Host, Port}]}' - List of {Host, Port} tuples, default: [{"127.0.0.1", 26379}];
%% `{username, Username}';`{password, Password}';`{connect_timeout, Timeout}';`{socket_options, SockOpts}'
%% `{tls, TlsOpts}'</dd></dl>
-spec start_link(options()) -> {ok, pid()} | {error, Reason::term()}.
start_link(Options) ->
    eredis_client:start_link(Options).

%% @doc Connect to the given host and port.
%%
%% @equiv start_link([{host, Host}, {port, Port}])
-spec start_link(Host::host(), Port::inet:port_number()) ->
          {ok, Pid::pid()} | {error, Reason::term()}.
start_link(Host, Port) ->
    start_link([{host, Host}, {port,  Port}]).

%% @deprecated Use {@link start_link/1} instead.
-spec start_link(Host::host(), Port::inet:port_number(), OptionsOrDatabase) ->
          {ok, Pid::pid()} | {error, Reason::term()}
              when OptionsOrDatabase :: options() | integer().
start_link(Host, Port, Options) when Options =:= []; is_tuple(hd(Options)) ->
    start_link([{host, Host}, {port, Port} | Options]);
start_link(Host, Port, Database) ->
    start_link([{host, Host}, {port, Port}, {database, Database}]).

%% @deprecated Use {@link start_link/1} instead.
%% @see start_link/1
-spec start_link(host(), inet:port_number(), integer(), string()) ->
          {ok, pid()} | {error, term()}.
start_link(Host, Port, Database, Password) ->
    start_link([{host, Host}, {port, Port}, {database, Database},
                {password, Password}]).

%% @deprecated Use {@link start_link/1} instead.
%% @see start_link/1
-spec start_link(host(), inet:port_number(), integer(), string(),
                 reconnect_sleep()) ->
          {ok, pid()} | {error, term()}.
start_link(Host, Port, Database, Password, ReconnectSleep) ->
    start_link([{host, Host}, {port, Port}, {database, Database},
                {password, Password}, {reconnect_sleep, ReconnectSleep}]).

%% @deprecated Use {@link start_link/1} instead.
%% @see start_link/1
-spec start_link(host(), inet:port_number(), integer(), string(),
                 reconnect_sleep(), timeout()) ->
          {ok, pid()} | {error, term()}.
start_link(Host, Port, Database, Password, ReconnectSleep, ConnectTimeout) ->
    start_link([{host, Host}, {port, Port}, {database, Database},
                {password, Password}, {reconnect_sleep, ReconnectSleep},
                {connect_timeout, ConnectTimeout}]).

%% @deprecated Use {@link start_link/1} instead.
%% @see start_link/1
-spec start_link(host(), inet:port_number(), integer(), string(),
                 reconnect_sleep(), timeout(), list()) ->
          {ok, pid()} | {error, term()}.
start_link(Host, Port, Database, Password, ReconnectSleep, ConnectTimeout,
           SocketOptions) ->
    start_link([{host, Host}, {port, Port}, {database, Database},
                {password, Password}, {reconnect_sleep, ReconnectSleep},
                {connect_timeout, ConnectTimeout},
                {socket_options, SocketOptions}]).

%% @doc Closes the connection and stops the client.
-spec stop(Client::client()) -> ok.
stop(Client) ->
    eredis_client:stop(Client).

-spec q(Client::client(), Command::[any()]) ->
               {ok, return_value()} | {error, Reason::binary() | no_connection}.
%% @doc: Executes the given command in the specified connection. The
%% command must be a valid Redis command and may contain arbitrary
%% data which will be converted to binaries. The returned values will
%% always be binaries.
q(Client, Command) ->
    call(Client, Command, ?TIMEOUT).

-spec q(Client::client(), Command::[any()], Timeout::integer()) ->
               {ok, return_value()} | {error, Reason::binary() | no_connection}.
%% @doc Like q/2 with a custom timeout.
q(Client, Command, Timeout) ->
    call(Client, Command, Timeout).


-spec qp(Client::client(), Pipeline::pipeline()) ->
                [{ok, return_value()} | {error, Reason::binary()}] |
                {error, no_connection}.
%% @doc: Executes the given pipeline (list of commands) in the
%% specified connection. The commands must be valid Redis commands and
%% may contain arbitrary data which will be converted to binaries. The
%% values returned by each command in the pipeline are returned in a list.
qp(Client, Pipeline) ->
    pipeline(Client, Pipeline, ?TIMEOUT).

-spec qp(Client::client(), Pipeline::pipeline(), Timeout::integer()) ->
                [{ok, return_value()} | {error, Reason::binary()}] |
                {error, no_connection}.
%% @doc Like qp/2 with a custom timeout.
qp(Client, Pipeline, Timeout) ->
    pipeline(Client, Pipeline, Timeout).

-spec q_noreply(Client::client(), Command::[any()]) -> ok.
%% @doc Executes the command but does not wait for a response and ignores any
%% errors.
%% @see q/2
q_noreply(Client, Command) ->
    cast(Client, Command).

-spec q_async(Client::client(), Command::[any()]) -> ok.
% @doc Executes the command, and sends a message to the calling process with the
% response (with either error or success). Message is of the form `{response,
% Reply}', where `Reply' is the reply expected from `q/2'.
q_async(Client, Command) ->
    q_async(Client, Command, self()).

-spec q_async(Client::client(), Command::[any()], Pid::pid()|atom()) -> ok.
%% @doc Executes the command, and sends a message to `Pid' with the response
%% (with either or success).
%% @see q_async/2
q_async(Client, Command, Pid) when is_pid(Pid) ->
    Request = {request, create_multibulk(Command), Pid},
    gen_server:cast(Client, Request).

%%
%% INTERNAL HELPERS
%%

call(Client, Command, Timeout) ->
    Request = {request, create_multibulk(Command)},
    gen_server:call(Client, Request, Timeout).

pipeline(_Client, [], _Timeout) ->
    [];
pipeline(Client, Pipeline, Timeout) ->
    Request = {pipeline, [create_multibulk(Command) || Command <- Pipeline]},
    gen_server:call(Client, Request, Timeout).

cast(Client, Command) ->
    Request = {request, create_multibulk(Command)},
    gen_server:cast(Client, Request).

-spec create_multibulk(Args::[any()]) -> Command::iolist().
%% @doc: Creates a multibulk command with all the correct size headers
%% @private
create_multibulk(Args) ->
    ArgCount = [<<$*>>, integer_to_list(length(Args)), <<?NL>>],
    ArgsBin = lists:map(fun to_bulk/1, lists:map(fun to_binary/1, Args)),

    [ArgCount, ArgsBin].

to_bulk(B) when is_binary(B) ->
    [<<$$>>, integer_to_list(iolist_size(B)), <<?NL>>, B, <<?NL>>].

%% @doc: Convert given value to binary. Fallbacks to
%% term_to_binary/1. For floats, throws {cannot_store_floats, Float}
%% as we do not want floats to be stored in Redis. Your future self
%% will thank you for this.
to_binary(X) when is_list(X)    -> list_to_binary(X);
to_binary(X) when is_atom(X)    -> atom_to_binary(X, utf8);
to_binary(X) when is_binary(X)  -> X;
to_binary(X) when is_integer(X) -> integer_to_binary(X);
to_binary(X) when is_float(X)   -> throw({cannot_store_floats, X});
to_binary(X)                    -> term_to_binary(X).
