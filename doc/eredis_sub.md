

# Module eredis_sub #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

<a name="types"></a>

## Data Types ##




<a name="type-channel"></a>
### channel() ###


<pre><code>
channel() = binary()
</code>
</pre>




<a name="type-option"></a>
### option() ###


<pre><code>
option() = {host, string() | {local, string()}} | {port, <a href="inet.md#type-port_number">inet:port_number()</a>} | {database, integer()} | {username, iodata() | <a href="#type-secret">secret()</a> | undefined} | {password, iodata() | <a href="#type-secret">secret()</a> | undefined} | {reconnect_sleep, <a href="#type-reconnect_sleep">reconnect_sleep()</a>} | {connect_timeout, integer()} | {socket_options, list()} | {tls, [<a href="ssl.md#type-tls_client_option">ssl:tls_client_option()</a>]} | {name, <a href="#type-registered_name">registered_name()</a>} | {sentinel, list()}
</code>
</pre>




<a name="type-reconnect_sleep"></a>
### reconnect_sleep() ###


<pre><code>
reconnect_sleep() = no_reconnect | integer()
</code>
</pre>




<a name="type-registered_name"></a>
### registered_name() ###


<pre><code>
registered_name() = {local, atom()} | {global, term()} | {via, atom(), term()}
</code>
</pre>




<a name="type-secret"></a>
### secret() ###


<pre><code>
secret() = fun(() -&gt; iodata())
</code>
</pre>




<a name="type-sub_option"></a>
### sub_option() ###


<pre><code>
sub_option() = {max_queue_size, integer() | infinity} | {queue_behaviour, drop | exit} | <a href="#type-option">option()</a>
</code>
</pre>




<a name="type-sub_options"></a>
### sub_options() ###


<pre><code>
sub_options() = [<a href="#type-sub_option">sub_option()</a>]
</code>
</pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#ack_message-1">ack_message/1</a></td><td> acknowledge the receipt of a pubsub message.</td></tr><tr><td valign="top"><a href="#channels-1">channels/1</a></td><td> Returns the channels the given client is currently
subscribing to.</td></tr><tr><td valign="top"><a href="#controlling_process-1">controlling_process/1</a></td><td> Make the calling process the controlling process.</td></tr><tr><td valign="top"><a href="#controlling_process-2">controlling_process/2</a></td><td> Make the given process (pid) the controlling process.</td></tr><tr><td valign="top"><a href="#controlling_process-3">controlling_process/3</a></td><td> Make the given process (pid) the controlling process subscriber
with the given Timeout.</td></tr><tr><td valign="top"><a href="#psubscribe-2">psubscribe/2</a></td><td> Pattern subscribe to the given channels.</td></tr><tr><td valign="top"><a href="#punsubscribe-2">punsubscribe/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td>Start with options in proplist format.</td></tr><tr><td valign="top"><a href="#start_link-3">start_link/3</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#start_link-6">start_link/6</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td></td></tr><tr><td valign="top"><a href="#subscribe-2">subscribe/2</a></td><td> Subscribe to the given channels.</td></tr><tr><td valign="top"><a href="#unsubscribe-2">unsubscribe/2</a></td><td></td></tr>
</table>


<a name="functions"></a>

## Function Details ##

<a name="ack_message-1"></a>

### ack_message/1 ###

<pre><code>
ack_message(Client::pid()) -&gt; ok
</code>
</pre>


acknowledge the receipt of a pubsub message. each pubsub
message must be acknowledged before the next one is received

<a name="channels-1"></a>

### channels/1 ###

`channels(Client) -> any()`

Returns the channels the given client is currently
subscribing to. Note: this list is based on the channels at startup
and any channel added during runtime. It might not immediately
reflect the channels Redis thinks the client is subscribed to.

<a name="controlling_process-1"></a>

### controlling_process/1 ###

<pre><code>
controlling_process(Client::pid()) -&gt; ok
</code>
</pre>


Make the calling process the controlling process. The
controlling process received pubsub-related messages, of which
there are three kinds. In each message, the pid refers to the
eredis client process.

{message, Channel::binary(), Message::binary(), pid()}
This is sent for each pubsub message received by the client.

{pmessage, Pattern::binary(), Channel::binary(), Message::binary(), pid()}
This is sent for each pattern pubsub message received by the client.

{dropped, NumMessages::integer(), pid()}
If the queue reaches the max size as specified in start_link
and the behaviour is to drop messages, this message is sent when
the queue is flushed.

{subscribed, Channel::binary(), pid()}
When using eredis_sub:subscribe(pid()), this message will be
sent for each channel Redis aknowledges the subscription. The
opposite, 'unsubscribed' is sent when Redis aknowledges removal
of a subscription.

{eredis_disconnected, pid()}
This is sent when the eredis client is disconnected from redis.

{eredis_connected, pid()}
This is sent when the eredis client reconnects to redis after
an existing connection was disconnected.

Any message of the form {message, _, _, _} must be acknowledged
before any subsequent message of the same form is sent. This
prevents the controlling process from being overrun with redis
pubsub messages. See ack_message/1.

<a name="controlling_process-2"></a>

### controlling_process/2 ###

<pre><code>
controlling_process(Client::pid(), Pid::pid()) -&gt; ok
</code>
</pre>


Make the given process (pid) the controlling process.

<a name="controlling_process-3"></a>

### controlling_process/3 ###

`controlling_process(Client, Pid, Timeout) -> any()`

Make the given process (pid) the controlling process subscriber
with the given Timeout.

<a name="psubscribe-2"></a>

### psubscribe/2 ###

<pre><code>
psubscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code>
</pre>


Pattern subscribe to the given channels. Returns immediately. The
result will be delivered to the controlling process as any other
message. Delivers {subscribed, Channel::binary(), pid()}

<a name="punsubscribe-2"></a>

### punsubscribe/2 ###

<pre><code>
punsubscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code>
</pre>


<a name="start_link-0"></a>

### start_link/0 ###

`start_link() -> any()`

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Options::<a href="#type-sub_options">sub_options()</a>) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code>
</pre>


`Options`: 

<dt><code>{host, Host}</code></dt>



<dd>DNS name or IP address as string; or unix domain
  socket as <code>{local, Path}</code> (available in OTP 19+); default <code>"127.0.0.1"</code>
</dd>



<dt><code>{port, Port}</code></dt>



<dd>Integer, default is 6379
</dd>



<dt><code>{database, Database}</code></dt>



<dd>Integer; 0 for the default database
</dd>



<dt><code>{username, Username}</code></dt>



<dd>A 0-ary function that returns the username
  (the preferred way to provide username as it prevents the actual secret from
  appearing in logs and stacktraces), a string or iodata or the atom<code>undefined</code> for no username; default <code>undefined</code>
</dd>



<dt><code>{password, Password}</code></dt>



<dd>A 0-ary function that returns the password
  (the preferred way to provide password as it prevents the actual secret from
  appearing in logs and stacktraces), a string or iodata or the atom<code>undefined</code> for no username; default <code>undefined</code>
</dd>



<dt><code>{reconnect_sleep, ReconnectSleep}</code></dt>



<dd>Integer of milliseconds to
  sleep between reconnect attempts; default: 100
</dd>



<dt><code>{connect_timeout, Timeout}</code></dt>



<dd>Timeout value in milliseconds to use
  when connecting to Redis; default: 5000
</dd>



<dt><code>{socket_options, SockOpts}</code></dt>



<dd>List of<a href="https://erlang.org/doc/man/gen_tcp.md">gen_tcp options</a> used
  when connecting the socket; default is <code>?SOCKET_OPTS</code>
</dd>



<dt><code>{tls, TlsOpts}</code></dt>



<dd>Enabling TLS and a list of<a href="https://erlang.org/doc/man/ssl.md">ssl options</a>; used when
  establishing a TLS connection; default is off
</dd>



<dt><code>{name, Name}</code></dt>



<dd>Tuple to register the client with a name
  such as <code>{local, atom()}</code>; for all options see <code>ServerName</code> at<a href="https://erlang.org/doc/man/gen_server.md#start_link-4">gen_server:start_link/4</a>;
  default: no name
</dd>



<dt><code>{max_queue_size, N}</code></dt>



<dd>Queue size for incoming pubsub messages
</dd>



<dt><code>{queue_behaviour, drop | exit}</code></dt>



<dd>What to do if the controlling
  process doesn't ack pubsub messages fast enough
</dd>

.

Start with options in proplist format.

<a name="start_link-3"></a>

### start_link/3 ###

`start_link(Host, Port, Password) -> any()`

__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

<a name="start_link-6"></a>

### start_link/6 ###

`start_link(Host, Port, Password, ReconnectSleep, MaxQueueSize, QueueBehaviour) -> any()`

__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

<a name="stop-1"></a>

### stop/1 ###

`stop(Pid) -> any()`

<a name="subscribe-2"></a>

### subscribe/2 ###

<pre><code>
subscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code>
</pre>


Subscribe to the given channels. Returns immediately. The
result will be delivered to the controlling process as any other
message. Delivers {subscribed, Channel::binary(), pid()}

<a name="unsubscribe-2"></a>

### unsubscribe/2 ###

<pre><code>
unsubscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code>
</pre>


