

# Module eredis_sub #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

<a name="types"></a>

## Data Types ##




### <a name="type-channel">channel()</a> ###


<pre><code>
channel() = binary()
</code></pre>




### <a name="type-option">option()</a> ###


<pre><code>
option() = {host, string() | {local, string()}} | {port, <a href="inet.md#type-port_number">inet:port_number()</a>} | {database, integer() | string()} | {password, string()} | {reconnect_sleep, <a href="#type-reconnect_sleep">reconnect_sleep()</a>} | {connect_timeout, integer()} | {socket_options, list()} | {tls, [<a href="ssl.md#type-tls_client_option">ssl:tls_client_option()</a>]}
</code></pre>




### <a name="type-options">options()</a> ###


<pre><code>
options() = [<a href="#type-option">option()</a>]
</code></pre>




### <a name="type-reconnect_sleep">reconnect_sleep()</a> ###


<pre><code>
reconnect_sleep() = no_reconnect | integer()
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#ack_message-1">ack_message/1</a></td><td> acknowledge the receipt of a pubsub message.</td></tr><tr><td valign="top"><a href="#channels-1">channels/1</a></td><td> Returns the channels the given client is currently
subscribing to.</td></tr><tr><td valign="top"><a href="#controlling_process-1">controlling_process/1</a></td><td> Make the calling process the controlling process.</td></tr><tr><td valign="top"><a href="#controlling_process-2">controlling_process/2</a></td><td> Make the given process (pid) the controlling process.</td></tr><tr><td valign="top"><a href="#controlling_process-3">controlling_process/3</a></td><td> Make the given process (pid) the controlling process subscriber
with the given Timeout.</td></tr><tr><td valign="top"><a href="#psubscribe-2">psubscribe/2</a></td><td> Pattern subscribe to the given channels.</td></tr><tr><td valign="top"><a href="#punsubscribe-2">punsubscribe/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td> Callback for starting from poolboy.</td></tr><tr><td valign="top"><a href="#start_link-3">start_link/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-6">start_link/6</a></td><td></td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td></td></tr><tr><td valign="top"><a href="#subscribe-2">subscribe/2</a></td><td> Subscribe to the given channels.</td></tr><tr><td valign="top"><a href="#unsubscribe-2">unsubscribe/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="ack_message-1"></a>

### ack_message/1 ###

<pre><code>
ack_message(Client::pid()) -&gt; ok
</code></pre>
<br />

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
</code></pre>
<br />

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
</code></pre>
<br />

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
</code></pre>
<br />

Pattern subscribe to the given channels. Returns immediately. The
result will be delivered to the controlling process as any other
message. Delivers {subscribed, Channel::binary(), pid()}

<a name="punsubscribe-2"></a>

### punsubscribe/2 ###

<pre><code>
punsubscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code></pre>
<br />

<a name="start_link-0"></a>

### start_link/0 ###

`start_link() -> any()`

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Args::<a href="#type-options">options()</a>) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code></pre>
<br />

Callback for starting from poolboy

<a name="start_link-3"></a>

### start_link/3 ###

`start_link(Host, Port, Password) -> any()`

<a name="start_link-6"></a>

### start_link/6 ###

`start_link(Host, Port, Password, ReconnectSleep, MaxQueueSize, QueueBehaviour) -> any()`

<a name="stop-1"></a>

### stop/1 ###

`stop(Pid) -> any()`

<a name="subscribe-2"></a>

### subscribe/2 ###

<pre><code>
subscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code></pre>
<br />

Subscribe to the given channels. Returns immediately. The
result will be delivered to the controlling process as any other
message. Delivers {subscribed, Channel::binary(), pid()}

<a name="unsubscribe-2"></a>

### unsubscribe/2 ###

<pre><code>
unsubscribe(Client::pid(), Channels::[<a href="#type-channel">channel()</a>]) -&gt; ok
</code></pre>
<br />

