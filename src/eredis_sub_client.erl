%%
%% eredis_pubsub_client
%%
%% This client implements a subscriber to a Redis pubsub channel. It
%% is implemented in the same way as eredis_client, except channel
%% messages are streamed to the controlling process. Messages are
%% queued and delivered when the client acknowledges receipt.
%%
%% There is one consuming process per eredis_sub_client.
%% @private
-module(eredis_sub_client).
-behaviour(gen_server).
-include("eredis.hrl").
-include("eredis_sub.hrl").
-define(CONNECT_TIMEOUT, 5000).
-define(RECONNECT_SLEEP, 100).

%% API
-export([start_link/1, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%
%% API
%%

-spec start_link(eredis_sub:sub_options()) ->
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
    %% Options
    Host           = proplists:get_value(host, Options, "127.0.0.1"),
    Port           = proplists:get_value(port, Options, 6379),
    Database       = proplists:get_value(database, Options, 0),
    Username       = proplists:get_value(username, Options, undefined),
    Password       = proplists:get_value(password, Options, undefined),
    ReconnectSleep = proplists:get_value(reconnect_sleep, Options, ?RECONNECT_SLEEP),
    ConnectTimeout = proplists:get_value(connect_timeout, Options, ?CONNECT_TIMEOUT),
    SocketOptions  = proplists:get_value(socket_options, Options, []),
    TlsOptions     = proplists:get_value(tls, Options, []),
    Transport      = case TlsOptions of
                         [] -> gen_tcp;
                         _ -> ssl
                     end,

    %% eredis_pub specific options
    MaxQueueSize   = proplists:get_value(max_queue_size, Options, infinity),
    QueueBehaviour = proplists:get_value(queue_behaviour, Options, drop),

    State = #state{host            = Host,
                   port            = Port,
                   database        = eredis_client:read_database(Database),
                   auth_cmd        = eredis_client:get_auth_command(Username,
                                                                    Password),
                   reconnect_sleep = ReconnectSleep,
                   connect_timeout = ConnectTimeout,
                   socket_options  = SocketOptions,
                   tls_options     = TlsOptions,
                   transport       = Transport,
                   channels        = [],
                   pchannels       = [],
                   parser_state    = eredis_parser:init(),
                   msg_queue       = queue:new(),
                   max_queue_size  = MaxQueueSize,
                   queue_behaviour = QueueBehaviour},

    %% Same sync/async connect behaviour as eredis_client.
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

%% Set the controlling process. All messages on all channels are directed here.
handle_call({controlling_process, Pid}, _From, State) ->
    case State#state.controlling_process of
        undefined ->
            ok;
        {OldRef, _OldPid} ->
            erlang:demonitor(OldRef)
    end,
    Ref = erlang:monitor(process, Pid),
    {reply, ok, State#state{controlling_process={Ref, Pid}, msg_state = ready}};

handle_call(get_channels, _From, State) ->
    {reply, {ok, State#state.channels ++ State#state.pchannels}, State};


handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.


%% Controlling process acks, but we have no connection. When the
%% connection comes back up, we should be ready to forward a message
%% again.
handle_cast({ack_message, Pid},
            #state{controlling_process={_, Pid}, socket = undefined} = State) ->
    {noreply, State#state{msg_state = ready}};

%% Controlling process acknowledges receipt of previous message. Send
%% the next if there is any messages queued or ask for more on the
%% socket.
handle_cast({ack_message, Pid},
            #state{controlling_process={_, Pid}} = State) ->
    NewState = case queue:out(State#state.msg_queue) of
                   {empty, _Queue} ->
                       State#state{msg_state = ready};
                   {{value, Msg}, Queue} ->
                       send_to_controller(Msg, State),
                       State#state{msg_queue = Queue, msg_state = need_ack}
               end,
    {noreply, NewState};

handle_cast({subscribe, Pid, Channels},
            #state{transport = Transport,
                   socket = Socket,
                   controlling_process = {_, Pid}} = State) ->
    ok = send_subscribe_command(Transport, Socket, "SUBSCRIBE", Channels),
    NewChannels = add_channels(Channels, State#state.channels),
    {noreply, State#state{channels = NewChannels}};


handle_cast({psubscribe, Pid, Channels},
            #state{transport = Transport,
                   socket = Socket,
                   controlling_process = {_, Pid}} = State) ->
    ok = send_subscribe_command(Transport, Socket, "PSUBSCRIBE", Channels),
    NewChannels = add_channels(Channels, State#state.pchannels),
    {noreply, State#state{pchannels = NewChannels}};



handle_cast({unsubscribe, Pid, Channels},
            #state{transport = Transport,
                   controlling_process = {_, Pid}} = State) ->
    Command = eredis:create_multibulk(["UNSUBSCRIBE" | Channels]),
    ok = Transport:send(State#state.socket, Command),
    NewChannels = remove_channels(Channels, State#state.channels),
    {noreply, State#state{channels = NewChannels}};



handle_cast({punsubscribe, Pid, Channels},
            #state{transport = Transport,
                   controlling_process = {_, Pid}} = State) ->
    Command = eredis:create_multibulk(["PUNSUBSCRIBE" | Channels]),
    ok = Transport:send(State#state.socket, Command),
    NewChannels = remove_channels(Channels, State#state.pchannels),
    {noreply, State#state{pchannels = NewChannels}};



handle_cast({ack_message, _}, State) ->
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.


%% Receive TCP/TLS data from socket. Match `Socket' to enforce sanity.
handle_info({Type, Socket, Bs},
            #state{socket = Socket, transport = Transport} = State)
  when Type =:= tcp; Type =:= ssl->
    ok = setopts(Socket, Transport, [{active, once}]),
    NewState = handle_response(Bs, State),
    case queue:len(NewState#state.msg_queue) > NewState#state.max_queue_size of
        true ->
            case State#state.queue_behaviour of
                drop ->
                    Msg = {dropped, queue:len(NewState#state.msg_queue)},
                    send_to_controller(Msg, NewState),
                    {noreply, NewState#state{msg_queue = queue:new()}};
                exit ->
                    {stop, max_queue_size, State}
            end;
        false ->
            {noreply, NewState}
    end;

handle_info({Error, Socket, _Reason},
            #state{socket = Socket, transport = Transport} = State)
  when Error =:= tcp_error; Error =:= ssl_error ->
    Transport:close(Socket),
    maybe_reconnect(Error, State);

%% Socket got closed, for example by Redis terminating idle
%% clients. If desired, spawn of a new process which will try to reconnect and
%% notify us when Redis is ready. In the meantime, we can respond with
%% an error message to all our clients.
handle_info({Closed, Socket}, #state{socket = OurSocket} = State)
  when Closed =:= tcp_closed orelse Closed =:= ssl_closed,
       Socket =:= OurSocket orelse Socket =:= fake_socket ->
    maybe_reconnect(Closed, State);

handle_info(initiate_connection, #state{socket = undefined} = State) ->
    case connect(State) of
        {ok, NewState} ->
            {noreply, NewState};
        {error, Reason} ->
            maybe_reconnect(Reason, State)
    end;

%% Controller might want to be notified about every reconnect attempt
handle_info(reconnect_attempt, State) ->
    send_to_controller({eredis_reconnect_attempt, self()}, State),
    {noreply, State};

%% Controller might want to be notified about every reconnect failure and reason
handle_info({reconnect_failed, Reason}, State) ->
    send_to_controller({eredis_reconnect_failed, self(),
                        {error, {connection_error, Reason}}}, State),
    {noreply, State};

%% Redis is ready to accept requests, the given Socket is a socket
%% already connected and authenticated.
handle_info({connection_ready, Socket},
            #state{socket = undefined, transport = Transport} = State) ->
    send_to_controller({eredis_connected, self()}, State),
    %% Re-subscribe to channels. Channels are stored in reverse order in state.
    ok = send_subscribe_command(Transport, Socket, "SUBSCRIBE",
                                lists:reverse(State#state.channels)),
    ok = send_subscribe_command(Transport, Socket, "PSUBSCRIBE",
                                lists:reverse(State#state.pchannels)),
    ok = setopts(Socket, Transport, [{active, once}]),
    {noreply, State#state{socket = Socket}};


%% Our controlling process is down.
handle_info({'DOWN', Ref, process, Pid, _Reason},
            #state{controlling_process={Ref, Pid}} = State) ->
    {stop, shutdown, State#state{controlling_process=undefined,
                                 msg_state=ready,
                                 msg_queue=queue:new()}};

%% eredis can be used in Poolboy, but it requires to support a simple API
%% that Poolboy uses to manage the connections.
handle_info(stop, State) ->
    {stop, shutdown, State};

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

%% @doc When no channels are given, we unsubscribe from all channels. This
%% matches the semantics of (P)UNSUBSCRIBE without channels.
-spec remove_channels([binary()], [binary()]) -> [binary()].
remove_channels([], _OldChannels) ->
    [];
remove_channels(Channels, OldChannels) ->
    lists:foldl(fun lists:delete/2, OldChannels, Channels).

-spec add_channels([binary()], [binary()]) -> [binary()].
add_channels(Channels, OldChannels) ->
    lists:foldl(fun(C, Cs) ->
        case lists:member(C, Cs) of
            true ->
                Cs;
            false ->
                [C|Cs]
        end
    end, OldChannels, Channels).

%% @doc Sends a subscribe or psubscribe command to Redis.
-spec send_subscribe_command(Transport :: gen_tcp | ssl,
                             Socket :: gen_tcp:socket() | ssl:socket(),
                             Command :: iodata(),
                             Channels :: list()) -> ok.
send_subscribe_command(_Transport, _Socket, _Command, []) ->
    ok;
send_subscribe_command(Transport, Socket, Command, Channels) ->
    Cmd = eredis:create_multibulk([Command | Channels]),
    Transport:send(Socket, Cmd).

-spec handle_response(Data::binary(), State::#state{}) -> NewState::#state{}.
%% @doc: Handle the response coming from Redis. This should only be
%% channel messages that we should forward to the controlling process
%% or queue if the previous message has not been acked. If there are
%% more than a single response in the data we got, queue the responses
%% and serve them up when the controlling process is ready
handle_response(Data, #state{parser_state = ParserState} = State) ->
    case eredis_parser:parse(ParserState, Data) of
        {ReturnCode, Value, NewParserState} ->
            reply({ReturnCode, Value},
                  State#state{parser_state=NewParserState});

        {ReturnCode, Value, Rest, NewParserState} ->
            NewState = reply({ReturnCode, Value},
                             State#state{parser_state=NewParserState}),
            handle_response(Rest, NewState);

        {continue, NewParserState} ->
            State#state{parser_state = NewParserState}
    end.

%% @doc: Sends a reply to the controlling process if the process has
%% acknowledged the previous process, otherwise the message is queued
%% for later delivery.
reply({ok, [<<"message">>, Channel, Message]}, State) ->
    queue_or_send({message, Channel, Message, self()}, State);

reply({ok, [<<"pmessage">>, Pattern, Channel, Message]}, State) ->
    queue_or_send({pmessage, Pattern, Channel, Message, self()}, State);



reply({ok, [<<"subscribe">>, Channel, _]}, State) ->
    queue_or_send({subscribed, Channel, self()}, State);

reply({ok, [<<"psubscribe">>, Channel, _]}, State) ->
    queue_or_send({subscribed, Channel, self()}, State);


reply({ok, [<<"unsubscribe">>, Channel, _]}, State) ->
    queue_or_send({unsubscribed, Channel, self()}, State);


reply({ok, [<<"punsubscribe">>, Channel, _]}, State) ->
    queue_or_send({unsubscribed, Channel, self()}, State);
reply({ReturnCode, Value}, State) ->
    throw({unexpected_response_from_redis, ReturnCode, Value, State}).


queue_or_send(Msg, State) ->
    case State#state.msg_state of
        need_ack ->
            MsgQueue = queue:in(Msg, State#state.msg_queue),
            State#state{msg_queue = MsgQueue};
        ready ->
            send_to_controller(Msg, State),
            State#state{msg_state = need_ack}
    end.


%% @doc: Helper for connecting to Redis. These commands are
%% synchronous and if Redis returns something we don't expect, we
%% crash. Returns {ok, State} or {error, Reason}.
connect(#state{host = Host, port = Port, socket_options = SocketOptions,
               connect_timeout = ConnectTimeout, tls_options = TlsOptions,
               auth_cmd = AuthCmd, database = Db} = State) ->
    case eredis_client:connect(Host, Port, SocketOptions, TlsOptions,
                               ConnectTimeout, AuthCmd, Db) of
        {ok, Socket} ->
            {ok, State#state{socket = Socket}};
        Error ->
            Error
    end.

%% Helper for handle_info/2. Returns {noreply, _} or {stop, _, _}.
maybe_reconnect(_Reason, #state{reconnect_sleep = no_reconnect} = State) ->
    %% If we aren't going to reconnect, then there is nothing else for this process to do.
    {stop, normal, State#state{socket = undefined}};
maybe_reconnect(_Reason,
                #state{host = Host,
                       port = Port,
                       socket_options = SocketOptions,
                       tls_options = TlsOptions,
                       connect_timeout = ConnectTimeout,
                       reconnect_sleep = ReconnectSleep,
                       auth_cmd = AuthCmd,
                       database = Db} = State) ->
    Self = self(),
    send_to_controller({eredis_disconnected, Self}, State),
    spawn_link(fun() ->
                       process_flag(trap_exit, true),
                       eredis_client:reconnect_loop(Self, ReconnectSleep,
                                                    Host, Port, SocketOptions,
                                                    TlsOptions, ConnectTimeout,
                                                    AuthCmd, Db)
               end),

    %% Throw away the socket. The absence of a socket is used to
    %% signal we are "down"; discard possibly patrially parsed data
    {noreply, State#state{socket = undefined, parser_state = eredis_parser:init()}}.

setopts(Socket, _Transport=gen_tcp, Opts) -> inet:setopts(Socket, Opts);
setopts(Socket, _Transport=ssl, Opts)     ->  ssl:setopts(Socket, Opts).

send_to_controller(_Msg, #state{controlling_process=undefined}) ->
    ok;
send_to_controller(Msg, #state{controlling_process={_Ref, Pid}}) ->
    Pid ! Msg.
