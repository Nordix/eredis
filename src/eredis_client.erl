%%
%% eredis_client
%%
%% The client is implemented as a gen_server which keeps one socket
%% open to a single Redis instance. Users call us using the API in
%% eredis.erl.
%%
%% The client works like this:
%%  * When starting up, we connect to Redis with the given connection
%%     information, or fail.
%%  * Users calls us using gen_server:call, we send the request to Redis,
%%    add the calling process at the end of the queue and reply with
%%    noreply. We are then free to handle new requests and may reply to
%%    the user later.
%%  * We receive data on the socket, we parse the response and reply to
%%    the client at the front of the queue. If the parser does not have
%%    enough data to parse the complete response, we will wait for more
%%    data to arrive.
%%  * For pipeline commands, we include the number of responses we are
%%    waiting for in each element of the queue. Responses are queued until
%%    we have all the responses we need and then reply with all of them.
%%
%% @private
-module(eredis_client).
-behaviour(gen_server).
-include("eredis.hrl").

-define(CONNECT_TIMEOUT, 5000).
-define(RECONNECT_SLEEP, 100).

%% API
-export([start_link/1, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Used by eredis_sub_client.erl
-export([read_database/1, get_auth_command/2, connect/7, reconnect_loop/9]).

-record(state, {
                host            :: string() | {local, string()} | undefined,
                port            :: integer() | undefined,
                auth_cmd        :: iodata() | undefined,
                database        :: binary() | undefined,
                reconnect_sleep :: reconnect_sleep() | undefined,
                connect_timeout :: integer() | undefined,
                socket_options  :: list(),
                tls_options     :: list(),

                transport       :: gen_tcp | ssl,
                socket          :: gen_tcp:socket() | ssl:sslsocket() | undefined,
                parser_state    :: #pstate{} | undefined,
                queue           :: eredis_queue() | undefined
               }).

%%
%% API
%%

-spec start_link(Options::options()) ->
          {ok, Pid::pid()} | {error, Reason::term()}.
start_link(Options) ->
    case proplists:lookup(name, Options) of
        {name, Name} ->
            gen_server:start_link(Name, ?MODULE, Options, []);
        none ->
            gen_server:start_link(?MODULE, Options, [])
    end.


stop(Pid) ->
    gen_server:call(Pid, stop).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Options) ->
    Host           = proplists:get_value(host, Options, "localhost"),
    Port           = proplists:get_value(port, Options, 6379),
    Database       = proplists:get_value(database, Options, 0),
    Username       = proplists:get_value(username, Options, undefined),
    Password       = proplists:get_value(password, Options, undefined),
    ReconnectSleep = proplists:get_value(reconnect_sleep, Options, ?RECONNECT_SLEEP),
    ConnectTimeout = proplists:get_value(connect_timeout, Options, ?CONNECT_TIMEOUT),
    SocketOptions  = proplists:get_value(socket_options, Options, []),
    TlsOptions     = proplists:get_value(tls, Options, []),
    Transport      = transport_module(TlsOptions),

    State = #state{host = Host,
                   port = Port,
                   database = read_database(Database),
                   auth_cmd = get_auth_command(Username, Password),
                   reconnect_sleep = ReconnectSleep,
                   connect_timeout = ConnectTimeout,
                   socket_options = SocketOptions,
                   tls_options = TlsOptions,
                   transport = Transport,

                   socket = undefined,
                   parser_state = eredis_parser:init(),
                   queue = queue:new()},

    case ReconnectSleep of
        no_reconnect ->
            case connect(State) of
                {ok, _NewState} = Res -> Res;
                {error, Reason} -> {stop, Reason}
            end;
        T when is_integer(T) ->
            self() ! initiate_connection,
            {ok, State}
    end.

handle_call({request, Req}, From, State) ->
    do_request(Req, From, State);

handle_call({pipeline, Pipeline}, From, State) ->
    do_pipeline(Pipeline, From, State);

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.


handle_cast({request, Req}, State) ->
    case do_request(Req, undefined, State) of
        {reply, _Reply, State1} ->
            {noreply, State1};
        {noreply, State1} ->
            {noreply, State1}
    end;

handle_cast({request, Req, Pid}, State) ->
    case do_request(Req, Pid, State) of
        {reply, Reply, State1} ->
            safe_send(Pid, {response, Reply}),
            {noreply, State1};
        {noreply, State1} ->
            {noreply, State1}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.


%% Receive TCP/TLS data from socket. Match `Socket' to enforce sanity.
handle_info({Type, Socket, Data},
            #state{socket = Socket, transport = Transport} = State1)
  when Type =:= tcp orelse Type =:= ssl ->
    State = handle_response(Data, State1),
    case setopts(Socket, Transport, [{active, once}]) of
        ok ->
            {noreply, State};
        {error, Reason} ->
            Transport:close(Socket),
            maybe_reconnect(Reason, State)
    end;

%% Socket errors. If the network or peer is down, the error is not
%% always followed by a tcp_closed.
%%
%% TLS 1.3: Called after a connect when the client certificate has expired
handle_info({Error, Socket, Reason},
            #state{socket = Socket, transport = Transport} = State)
  when Error =:= tcp_error; Error =:= ssl_error ->
    Transport:close(Socket),
    maybe_reconnect(Reason, State);

%% Socket got closed, for example by Redis terminating idle
%% clients. If desired, spawn of a new process which will try to reconnect and
%% notify us when Redis is ready. In the meantime, we can respond with
%% an error message to all our clients.
%%
%% fake_socket is used for testing.
handle_info({Closed, Socket}, #state{socket = OurSocket} = State)
  when Closed =:= tcp_closed orelse Closed =:= ssl_closed,
       Socket =:= OurSocket orelse Socket =:= fake_socket ->
    maybe_reconnect(Closed, State);

%% Ignore messages and errors for an old socket.
handle_info({Type, Socket, _}, #state{socket = OurSocket} = State)
  when OurSocket =/= Socket,
       Type =:= tcp       orelse Type =:= ssl       orelse
       Type =:= tcp_error orelse Type =:= ssl_error ->
    %% Ignore tcp messages and errors when the socket in message
    %% doesn't match our state.
    {noreply, State};

%% Ignore close for an old socket.
handle_info({Type, Socket}, #state{socket = OurSocket} = State)
  when OurSocket =/= Socket,
       Type =:= tcp_closed orelse Type =:= ssl_closed ->
    {noreply, State};

%% Errors returned by gen_tcp:send/2 and ssl:send/2 are handled
%% asynchronously by message passing to self.
handle_info({send_error, Socket, Reason},
            #state{transport = Transport, socket = Socket} = State) ->
    Transport:close(Socket),
    maybe_reconnect(Reason, State);

handle_info({send_error, _Socket, _Reason}, State) ->
    %% Socket doesn't match the state. Ignore.
    {noreply, State};

%% Redis is ready to accept requests, the given Socket is a socket
%% already connected and authenticated.
handle_info({connection_ready, Socket}, #state{socket = undefined} = State) ->
    {noreply, State#state{socket = Socket}};

%% eredis can be used in Poolboy, but it requires to support a simple API
%% that Poolboy uses to manage the connections.
handle_info(stop, State) ->
    {stop, shutdown, State};

handle_info(initiate_connection,
            #state{socket = undefined,
                   reconnect_sleep = ReconnectSleep} = State) ->
    case connect(State) of
        {ok, NewState} ->
            {noreply, NewState};
        {error, _Reason} when ReconnectSleep =:= no_reconnect ->
            {stop, normal, State};
        {error, Reason} ->
            erlang:send_after(ReconnectSleep, self(), {reconnect, Reason}),
            {noreply, State}
    end;

handle_info({reconnect, Reason}, #state{socket = undefined} = State) ->
    %% Scheduled reconnect
    maybe_reconnect(Reason, State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket = undefined}) ->
    ok;
terminate(_Reason, #state{socket = Socket, transport = Transport}) ->
    Transport:close(Socket).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

-spec do_request(Req::iolist(), From::pid() | undefined, #state{}) ->
          {noreply, #state{}} | {reply, Reply::any(), #state{}}.
%% @doc: Sends the given request to redis. If we do not have a
%% connection, returns error.
do_request(_Req, _From, #state{socket = undefined} = State) ->
    {reply, {error, no_connection}, State};

do_request(Req, From, #state{socket=Socket, transport=Transport}=State) ->
    case Transport:send(Socket, Req) of
        ok ->
            NewQueue = queue:in({1, From}, State#state.queue),
            {noreply, State#state{queue = NewQueue}};
        {error, Reason} ->
            self() ! {send_error, Socket, Reason},
            {reply, {error, Reason}, State}
    end.

-spec do_pipeline(Pipeline::pipeline(), From::pid(), #state{}) ->
          {noreply, #state{}} | {reply, Reply::any(), #state{}}.
%% @doc: Sends the entire pipeline to redis. If we do not have a
%% connection, returns error.
do_pipeline(_Pipeline, _From, #state{socket = undefined} = State) ->
    {reply, {error, no_connection}, State};

do_pipeline(Pipeline, From, #state{socket=Socket, transport=Transport}=State) ->
    case Transport:send(Socket, Pipeline) of
        ok ->
            NewQueue = queue:in({length(Pipeline), From, []}, State#state.queue),
            {noreply, State#state{queue = NewQueue}};
        {error, Reason} ->
            self() ! {send_error, Socket, Reason},
            {reply, {error, Reason}, State}
    end.

-spec handle_response(Data::binary(), State::#state{}) -> NewState::#state{}.
%% @doc: Handle the response coming from Redis. This includes parsing
%% and replying to the correct client, handling partial responses,
%% handling too much data and handling continuations.
handle_response(Data, #state{parser_state = ParserState,
                             queue = Queue} = State) ->

    case eredis_parser:parse(ParserState, Data) of
        %% Got complete response, return value to client
        {ReturnCode, Value, NewParserState} ->
            NewQueue = reply({ReturnCode, Value}, Queue),
            State#state{parser_state = NewParserState,
                        queue = NewQueue};

        %% Got complete response, with extra data, reply to client and
        %% recurse over the extra data
        {ReturnCode, Value, Rest, NewParserState} ->
            NewQueue = reply({ReturnCode, Value}, Queue),
            handle_response(Rest, State#state{parser_state = NewParserState,
                                              queue = NewQueue});

        %% Parser needs more data, the parser state now contains the
        %% continuation data and we will try calling parse again when
        %% we have more data
        {continue, NewParserState} ->
            State#state{parser_state = NewParserState}
    end.

%% @doc: Sends a value to the first client in queue. Returns the new
%% queue without this client. If we are still waiting for parts of a
%% pipelined request, push the reply to the the head of the queue and
%% wait for another reply from redis.
reply(Value, Queue) ->
    case queue:out(Queue) of
        {{value, {1, From}}, NewQueue} ->
            safe_reply(From, Value),
            NewQueue;
        {{value, {1, From, Replies}}, NewQueue} ->
            safe_reply(From, lists:reverse([Value | Replies])),
            NewQueue;
        {{value, {N, From, Replies}}, NewQueue} when N > 1 ->
            queue:in_r({N - 1, From, [Value | Replies]}, NewQueue);
        {empty, Queue} ->
            %% Oops
            error_logger:info_msg("eredis: Nothing in queue, but got value from parser~n"),
            exit(empty_queue)
    end.

%% @doc Send `Value' to each client in queue. Only useful for sending
%% an error message. Any in-progress reply data is ignored.
-spec reply_all(any(), eredis_queue()) -> ok.
reply_all(Value, Queue) ->
    case queue:peek(Queue) of
        empty ->
            ok;
        {value, Item} ->
            safe_reply(recipient(Item), Value),
            reply_all(Value, queue:drop(Queue))
    end.

recipient({_, From}) ->
    From;
recipient({_, From, _}) ->
    From.

safe_reply(undefined, _Value) ->
    ok;
safe_reply(Pid, Value) when is_pid(Pid) ->
    safe_send(Pid, {response, Value});
safe_reply(From, Value) ->
    gen_server:reply(From, Value).

safe_send(Pid, Value) ->
    try erlang:send(Pid, Value)
    catch
        Err:Reason ->
            error_logger:info_msg("eredis: Failed to send message to ~p with reason ~p~n", [Pid, {Err, Reason}])
    end.

%% @doc: Helper for connecting to Redis, authenticating and selecting
%% the correct database synchronously.
%% Returns: {ok, State} or {error, Reason}.
connect(#state{host = Host,
               port = Port,
               socket_options = SocketOptions,
               tls_options = TlsOptions,
               connect_timeout = ConnectTimeout,
               auth_cmd = AuthCmd,
               database = Db} = State) ->
    case connect(Host, Port, SocketOptions, TlsOptions,
                 ConnectTimeout, AuthCmd, Db) of
        {ok, Socket} ->
            {ok, State#state{socket = Socket}};
        Error ->
            Error
    end.

%% Connect helper also used by eredis_sub_client.
-spec connect(Host           :: string() | {local, string()} | undefined,
              Port           :: integer() | undefined,
              SocketOptions  :: list(),
              TlsOptions     :: list(),
              ConnectTimeout :: integer() | undefined,
              AuthCmd        :: iodata() | undefined,
              Db             :: binary() | undefined) ->
          {ok, Socket :: gen_tcp:socket() | ssl:sslsocket()} |
          {error, Reason :: term()}.
connect(Host, Port, SocketOptions, TlsOptions, ConnectTimeout, AuthCmd, Db) ->
    {ok, {AFamily, Addrs}} = get_addrs(Host),
    Port1 = case AFamily of
                local -> 0;
                _ -> Port
            end,

    SocketOptions1 = lists:ukeymerge(1, lists:keysort(1, SocketOptions),
                                     lists:keysort(1, ?SOCKET_OPTS)),
    SocketOptions2 = [AFamily | [?SOCKET_MODE | SocketOptions1]],

    connect_next_addr(Addrs, Port1, SocketOptions2, TlsOptions, ConnectTimeout,
                      AuthCmd, Db).

connect_next_addr([Addr|Addrs], Port, SocketOptions, TlsOptions, ConnectTimeout,
                  AuthCmd, Db) ->
    case gen_tcp:connect(Addr, Port, SocketOptions, ConnectTimeout) of
        {ok, Socket} ->
            case maybe_upgrade_to_tls(Socket, TlsOptions, ConnectTimeout) of
                {ok, NewSocket} ->
                    Transport = transport_module(TlsOptions),
                    case authenticate(NewSocket, Transport, AuthCmd) of
                        ok ->
                            case select_database(NewSocket, Transport, Db) of
                                ok ->
                                    {ok, NewSocket};
                                {error, Reason} ->
                                    Transport:close(NewSocket),
                                    {error, {select_error, Reason}}
                            end;
                        {error, Reason} ->
                            Transport:close(NewSocket),
                            {error, {authentication_error, Reason}}
                    end;
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    {error, {failed_to_upgrade_to_tls, Reason}} %% Used in TLS v1.2
            end;
        {error, Reason} when Addrs =:= [] ->
            {error, {connection_error, Reason}};
        {error, _Reason} ->
            %% Try next address
            connect_next_addr(Addrs, Port, SocketOptions, TlsOptions,
                              ConnectTimeout, AuthCmd, Db)
    end.

maybe_upgrade_to_tls(Socket, [], _Timeout) ->
    {ok, Socket};
maybe_upgrade_to_tls(Socket, TlsOptions, Timeout) ->
    %% Active needs to be 'false' before an upgrade to ssl is possible
    case inet:setopts(Socket, [{active, false}]) of
        ok ->
            case ssl:connect(Socket, TlsOptions, Timeout) of
                {ok, NewSocket} ->
                    %% Enter `{active, once}' mode. NOTE: tls/ssl doesn't
                    %% support `{active, N}'
                    case ssl:setopts(NewSocket, [{active, once}]) of
                        ok ->
                            {ok, NewSocket};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

get_addrs({local, Path}) ->
    {ok, {local, [{local, Path}]}};
get_addrs(Hostname) ->
    case inet:parse_address(Hostname) of
        {ok, {_, _, _, _} = Addr} ->             {ok, {inet, [Addr]}};
        {ok, {_, _, _, _, _, _, _, _} = Addr} -> {ok, {inet6, [Addr]}};
        {error, einval} ->
            case inet:getaddrs(Hostname, inet6) of
                {error, _} ->
                    case inet:getaddrs(Hostname, inet) of
                        {ok, Addrs} ->
                            {ok, {inet, deduplicate(Addrs)}};
                        {error, _} = Res ->
                            Res
                    end;
                {ok, Addrs} ->
                    {ok, {inet6, deduplicate(Addrs)}}
            end
    end.

%% Removes duplicates without sorting.
deduplicate([X|Xs]) ->
    [X | deduplicate([Y || Y <- Xs,
                           Y =/= X])];
deduplicate([]) ->
    [].

select_database(_Socket, _TransportType, undefined) ->
    ok;
select_database(_Socket, _TransportType, <<"0">>) ->
    ok;
select_database(Socket, TransportType, Database) ->
    do_sync_command(Socket, TransportType, ["SELECT", " ", Database, "\r\n"]).

authenticate(_Socket, _TransportType, undefined) ->
    ok;
authenticate(Socket, TransportType, AuthCmd) ->
    do_sync_command(Socket, TransportType, AuthCmd).

%% @doc: Executes the given command synchronously, expects Redis to
%% return "+OK\r\n", otherwise it will fail.
do_sync_command(Socket, Transport, Command) ->
    case setopts(Socket, Transport, [{active, false}]) of
        ok ->
            do_sync_command2(Socket, Transport, Command);
        {error, Reason} ->
            {error, Reason}
    end.

do_sync_command2(Socket, Transport, Command) ->
    case Transport:send(Socket, Command) of
        ok ->
            case Transport:recv(Socket, 0, ?RECV_TIMEOUT) of
                {ok, <<"+OK\r\n">>} ->
                    setopts(Socket, Transport, [{active, once}]);
                {ok, Data} ->
                    {error, {unexpected_response, Data}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

transport_module([]) -> gen_tcp;
transport_module(_) -> ssl.

setopts(Socket, _Transport=gen_tcp, Opts) -> inet:setopts(Socket, Opts);
setopts(Socket, _Transport=ssl, Opts)     ->  ssl:setopts(Socket, Opts).

maybe_reconnect(Reason, #state{reconnect_sleep = no_reconnect, queue = Queue} = State) ->
    reply_all({error, Reason}, Queue),
    %% If we aren't going to reconnect, then there is nothing else for
    %% this process to do.
    {stop, normal, State#state{socket = undefined}};
maybe_reconnect(Reason,
                #state{queue = Queue,
                       host = Host,
                       port = Port,
                       socket_options = SocketOptions,
                       tls_options = TlsOptions,
                       connect_timeout = ConnectTimeout,
                       reconnect_sleep = ReconnectSleep,
                       auth_cmd = AuthCmd,
                       database = Db} = State) ->
    error_logger:error_msg("eredis: Re-establishing connection to ~p:~p due to ~p",
                           [Host, Port, Reason]),
    Self = self(),
    spawn_link(fun() ->
                       process_flag(trap_exit, true),
                       reconnect_loop(Self, ReconnectSleep, Host, Port,
                                      SocketOptions, TlsOptions, ConnectTimeout,
                                      AuthCmd, Db)
               end),

    %% tell all of our clients what has happened.
    reply_all({error, Reason}, Queue),

    %% Throw away the socket and the queue, as we will never get a
    %% response to the requests sent on the old socket. The absence of
    %% a socket is used to signal we are "down"
    {noreply, State#state{socket = undefined, queue = queue:new()}}.

%% @doc: Loop until a connection can be established, this includes
%% successfully issuing the auth and select calls. When we have a
%% connection, send the socket to Client in a message on the form
%% `{connection_ready, Socket}'.
reconnect_loop(Client, ReconnectSleep, Host, Port, SocketOptions,
               TlsOptions, ConnectTimeout, AuthCmd, Db) ->
    Client ! reconnect_attempt,
    case connect(Host, Port, SocketOptions, TlsOptions, ConnectTimeout,
                 AuthCmd, Db) of
        {ok, Socket} ->
            Client ! {connection_ready, Socket},
            Transport = transport_module(TlsOptions),
            Transport:controlling_process(Socket, Client),
            Msgs = get_all_messages([]),
            [Client ! M || M <- Msgs];
        {error, Reason} ->
            Client ! {reconnect_failed, Reason},
            receive
                {'EXIT', Client, ExitReason} -> exit(ExitReason)
            after
                ReconnectSleep ->
                    reconnect_loop(Client, ReconnectSleep, Host, Port,
                                   SocketOptions, TlsOptions, ConnectTimeout,
                                   AuthCmd, Db)
            end
    end.

read_database(undefined) ->
    undefined;
read_database(Database) when is_integer(Database) ->
    list_to_binary(integer_to_list(Database)).

-spec get_auth_command(Username :: iodata() | undefined,
                       Password :: iodata() | undefined) ->
          iodata() | undefined.
get_auth_command(undefined, undefined) ->
    undefined;
get_auth_command(undefined, "") -> % legacy
    undefined;
get_auth_command(undefined, Password) ->
    eredis:create_multibulk([<<"AUTH">>, Password]);
get_auth_command(Username, Password) ->
    eredis:create_multibulk([<<"AUTH">>, Username, Password]).

get_all_messages(Acc) ->
    receive
        M ->
            get_all_messages([M | Acc])
    after 0 ->
            lists:reverse(Acc)
    end.
