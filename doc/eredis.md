

# Module eredis #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

<a name="types"></a>

## Data Types ##




### <a name="type-client">client()</a> ###


<pre><code>
client() = pid()
</code></pre>




### <a name="type-host">host()</a> ###


<pre><code>
host() = list() | {local, list()}
</code></pre>




### <a name="type-option">option()</a> ###


<pre><code>
option() = {database, string()} | {password, string()} | {reconnect_sleep, <a href="#type-reconnect_sleep">reconnect_sleep()</a>} | {connect_timeout, integer()} | {socket_options, list()}
</code></pre>




### <a name="type-options">options()</a> ###


<pre><code>
options() = [<a href="#type-option">option()</a>]
</code></pre>




### <a name="type-pipeline">pipeline()</a> ###


<pre><code>
pipeline() = [iolist()]
</code></pre>




### <a name="type-reconnect_sleep">reconnect_sleep()</a> ###


<pre><code>
reconnect_sleep() = no_reconnect | integer()
</code></pre>




### <a name="type-return_value">return_value()</a> ###


<pre><code>
return_value() = undefined | binary() | [binary() | nonempty_list()]
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#q-2">q/2</a></td><td> Executes the given command in the specified connection.</td></tr><tr><td valign="top"><a href="#q-3">q/3</a></td><td></td></tr><tr><td valign="top"><a href="#q_async-2">q_async/2</a></td><td>Executes the command, and sends a message to this process with the response (with either error or success).</td></tr><tr><td valign="top"><a href="#q_async-3">q_async/3</a></td><td>Executes the command, and sends a message to <code>Pid</code> with the response (with either or success).</td></tr><tr><td valign="top"><a href="#q_noreply-2">q_noreply/2</a></td><td>Executes the command but does not wait for a response and ignores any errors.</td></tr><tr><td valign="top"><a href="#qp-2">qp/2</a></td><td> Executes the given pipeline (list of commands) in the
specified connection.</td></tr><tr><td valign="top"><a href="#qp-3">qp/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-3">start_link/3</a></td><td></td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="q-2"></a>

### q/2 ###

<pre><code>
q(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; {ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary() | no_connection}
</code></pre>
<br />

Executes the given command in the specified connection. The
command must be a valid Redis command and may contain arbitrary
data which will be converted to binaries. The returned values will
always be binaries.

<a name="q-3"></a>

### q/3 ###

<pre><code>
q(Client::<a href="#type-client">client()</a>, Command::[any()], Timeout::integer()) -&gt; {ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary() | no_connection}
</code></pre>
<br />

<a name="q_async-2"></a>

### q_async/2 ###

<pre><code>
q_async(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; ok
</code></pre>
<br />

Executes the command, and sends a message to this process with the response (with either error or success). Message is of the form `{response, Reply}`, where `Reply` is the reply expected from `q/2`.

<a name="q_async-3"></a>

### q_async/3 ###

<pre><code>
q_async(Client::<a href="#type-client">client()</a>, Command::[any()], Pid::pid() | atom()) -&gt; ok
</code></pre>
<br />

Executes the command, and sends a message to `Pid` with the response (with either or success).

__See also:__ [q_async/2](#q_async-2).

<a name="q_noreply-2"></a>

### q_noreply/2 ###

<pre><code>
q_noreply(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; ok
</code></pre>
<br />

Executes the command but does not wait for a response and ignores any errors.

__See also:__ [q/2](#q-2).

<a name="qp-2"></a>

### qp/2 ###

<pre><code>
qp(Client::<a href="#type-client">client()</a>, Pipeline::<a href="#type-pipeline">pipeline()</a>) -&gt; [{ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary()}] | {error, no_connection}
</code></pre>
<br />

Executes the given pipeline (list of commands) in the
specified connection. The commands must be valid Redis commands and
may contain arbitrary data which will be converted to binaries. The
values returned by each command in the pipeline are returned in a list.

<a name="qp-3"></a>

### qp/3 ###

<pre><code>
qp(Client::<a href="#type-client">client()</a>, Pipeline::<a href="#type-pipeline">pipeline()</a>, Timeout::integer()) -&gt; [{ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary()}] | {error, no_connection}
</code></pre>
<br />

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code></pre>
<br />

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Options::[<a href="#type-option">option()</a> | {host, <a href="#type-host">host()</a>} | {port, <a href="inet.md#type-port_number">inet:port_number()</a>}]) -&gt; {ok, pid()} | {error, Reason::term()}
</code></pre>
<br />

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code></pre>
<br />

<a name="start_link-3"></a>

### start_link/3 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, Options::<a href="#type-options">options()</a>) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code></pre>
<br />

<a name="stop-1"></a>

### stop/1 ###

<pre><code>
stop(Client::<a href="#type-client">client()</a>) -&gt; ok
</code></pre>
<br />

