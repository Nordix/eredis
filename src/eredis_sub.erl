%%
%% Erlang PubSub Redis client
%%
-module(eredis_sub).
-include("eredis.hrl").

%% Default timeout for calls to the client gen_server
%% Specified in http://www.erlang.org/doc/man/gen_server.html#call-3
-define(TIMEOUT, 5000).

-export([start_link/0, start_link/1, start_link/3, start_link/6, stop/1,
         controlling_process/1, controlling_process/2, controlling_process/3,
         ack_message/1, subscribe/2, unsubscribe/2, channels/1]).

-export([psubscribe/2, punsubscribe/2]).

-export_type([sub_options/0, sub_option/0]).

-type sub_option() ::
        {max_queue_size, integer() | infinity} |
        {queue_behaviour, drop | exit} |
        option().
-type sub_options() :: [sub_option()].

%%
%% PUBLIC API
%%

start_link() ->
    start_link([]).

%% @deprecated Use {@link start_link/1} instead.
start_link(Host, Port, Password) ->
    start_link(Host, Port, Password, 100, infinity, drop).

%% @deprecated Use {@link start_link/1} instead.
start_link(Host, Port, Password, ReconnectSleep,
           MaxQueueSize, QueueBehaviour)
  when is_list(Host) andalso
       is_integer(Port) andalso
       is_list(Password) andalso
       (is_integer(ReconnectSleep) orelse ReconnectSleep =:= no_reconnect) andalso
       (is_integer(MaxQueueSize) orelse MaxQueueSize =:= infinity) andalso
       (QueueBehaviour =:= drop orelse QueueBehaviour =:= exit) ->
    start_link([{host, Host},
                {port, Port},
                {password, Password},
                {reconnect_sleep, ReconnectSleep},
                {max_queue_size, MaxQueueSize},
                {queue_behaviour, QueueBehaviour}]).

%% @doc Start with options in proplist format.
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
%% <dt>`{max_queue_size, N}'</dt><dd>Queue size for incoming pubsub messages</dd>
%% <dt>`{queue_behaviour, drop | exit}'</dt><dd>What to do if the controlling
%% process doesn't ack pubsub messages fast enough</dd>.
%% </dl>
-spec start_link(sub_options()) -> {ok, Pid::pid()} | {error, Reason::term()}.
start_link(Options) ->
    eredis_sub_client:start_link(Options).

stop(Pid) ->
    eredis_sub_client:stop(Pid).

-spec controlling_process(Client::pid()) -> ok.
%% @doc: Make the calling process the controlling process. The
%% controlling process received pubsub-related messages, of which
%% there are three kinds. In each message, the pid refers to the
%% eredis client process.
%%
%%   {message, Channel::binary(), Message::binary(), pid()}
%%     This is sent for each pubsub message received by the client.
%%
%%   {pmessage, Pattern::binary(), Channel::binary(), Message::binary(), pid()}
%%     This is sent for each pattern pubsub message received by the client.
%%
%%   {dropped, NumMessages::integer(), pid()}
%%     If the queue reaches the max size as specified in start_link
%%     and the behaviour is to drop messages, this message is sent when
%%     the queue is flushed.
%%
%%   {subscribed, Channel::binary(), pid()}
%%     When using eredis_sub:subscribe(pid()), this message will be
%%     sent for each channel Redis aknowledges the subscription. The
%%     opposite, 'unsubscribed' is sent when Redis aknowledges removal
%%     of a subscription.
%%
%%   {eredis_disconnected, pid()}
%%     This is sent when the eredis client is disconnected from redis.
%%
%%   {eredis_connected, pid()}
%%     This is sent when the eredis client reconnects to redis after
%%     an existing connection was disconnected.
%%
%% Any message of the form {message, _, _, _} must be acknowledged
%% before any subsequent message of the same form is sent. This
%% prevents the controlling process from being overrun with redis
%% pubsub messages. See ack_message/1.
controlling_process(Client) ->
    controlling_process(Client, self()).

-spec controlling_process(Client::pid(), Pid::pid()) -> ok.
%% @doc: Make the given process (pid) the controlling process.
controlling_process(Client, Pid) ->
    controlling_process(Client, Pid, ?TIMEOUT).

%% @doc: Make the given process (pid) the controlling process subscriber
%% with the given Timeout.
controlling_process(Client, Pid, Timeout) ->
    gen_server:call(Client, {controlling_process, Pid}, Timeout).

-spec ack_message(Client::pid()) -> ok.
%% @doc: acknowledge the receipt of a pubsub message. each pubsub
%% message must be acknowledged before the next one is received
ack_message(Client) ->
    gen_server:cast(Client, {ack_message, self()}).

%% @doc: Subscribe to the given channels. Returns immediately. The
%% result will be delivered to the controlling process as any other
%% message. Delivers {subscribed, Channel::binary(), pid()}
-spec subscribe(pid(), [channel()]) -> ok.
subscribe(Client, Channels) ->
    gen_server:cast(Client, {subscribe, self(), Channels}).

%% @doc: Pattern subscribe to the given channels. Returns immediately. The
%% result will be delivered to the controlling process as any other
%% message. Delivers {subscribed, Channel::binary(), pid()}
-spec psubscribe(pid(), [channel()]) -> ok.
psubscribe(Client, Channels) ->
    gen_server:cast(Client, {psubscribe, self(), Channels}).

-spec unsubscribe(pid(), [channel()]) -> ok.
unsubscribe(Client, Channels) ->
    gen_server:cast(Client, {unsubscribe, self(), Channels}).

-spec punsubscribe(pid(), [channel()]) -> ok.
punsubscribe(Client, Channels) ->
    gen_server:cast(Client, {punsubscribe, self(), Channels}).

%% @doc: Returns the channels the given client is currently
%% subscribing to. Note: this list is based on the channels at startup
%% and any channel added during runtime. It might not immediately
%% reflect the channels Redis thinks the client is subscribed to.
channels(Client) ->
    gen_server:call(Client, get_channels).

%%
%% Examples
%%

%% receiver(Sub) ->
%%     receive
%%         Msg ->
%%             io:format("received ~p~n", [Msg]),
%%             ack_message(Sub),
%%             ?MODULE:receiver(Sub)
%%     end.

%% sub_example() ->
%%     {ok, Sub} = start_link(),
%%     Receiver = spawn_link(fun () ->
%%                                   controlling_process(Sub),
%%                                   subscribe(Sub, [<<"foo">>]),
%%                                   receiver(Sub)
%%                           end),
%%     {Sub, Receiver}.

%% psub_example() ->
%%     {ok, Sub} = start_link(),
%%     Receiver = spawn_link(fun () ->
%%                                   controlling_process(Sub),
%%                                   psubscribe(Sub, [<<"foo*">>]),
%%                                   receiver(Sub)
%%                           end),
%%     {Sub, Receiver}.

%% pub_example() ->
%%     {ok, P} = eredis:start_link(),
%%     eredis:q(P, ["PUBLISH", "foo", "bar"]),
%%     eredis_client:stop(P).

%% ppub_example() ->
%%     {ok, P} = eredis:start_link(),
%%     eredis:q(P, ["PUBLISH", "foo123", "bar"]),
%%     eredis_client:stop(P).
