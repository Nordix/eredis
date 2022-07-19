

# Module eredis #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

<a name="types"></a>

## Data Types ##




<a name="type-client"></a>
### client() ###


<pre><code>
client() = pid() | atom() | {atom(), atom()} | {global, term()} | {via, atom(), term()}
</code>
</pre>




<a name="type-host"></a>
### host() ###


<pre><code>
host() = string() | {local, string()}
</code>
</pre>




<a name="type-option"></a>
### option() ###


<pre><code>
option() = {host, string() | {local, string()}} | {port, <a href="inet.md#type-port_number">inet:port_number()</a>} | {database, integer()} | {username, iodata() | <a href="#type-secret">secret()</a> | undefined} | {password, iodata() | <a href="#type-secret">secret()</a> | undefined} | {reconnect_sleep, <a href="#type-reconnect_sleep">reconnect_sleep()</a>} | {connect_timeout, integer()} | {socket_options, list()} | {tls, [<a href="ssl.md#type-tls_client_option">ssl:tls_client_option()</a>]} | {name, <a href="#type-registered_name">registered_name()</a>} | {sentinel, list()}
</code>
</pre>




<a name="type-options"></a>
### options() ###


<pre><code>
options() = [<a href="#type-option">option()</a>]
</code>
</pre>




<a name="type-pipeline"></a>
### pipeline() ###


<pre><code>
pipeline() = [iolist()]
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




<a name="type-return_value"></a>
### return_value() ###


<pre><code>
return_value() = undefined | binary() | [binary() | nonempty_list()]
</code>
</pre>




<a name="type-secret"></a>
### secret() ###


<pre><code>
secret() = fun(() -&gt; iodata())
</code>
</pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#q-2">q/2</a></td><td> Executes the given command in the specified connection.</td></tr><tr><td valign="top"><a href="#q-3">q/3</a></td><td>Like q/2 with a custom timeout.</td></tr><tr><td valign="top"><a href="#q_async-2">q_async/2</a></td><td>Executes the command, and sends a message to the calling process with the
response (with either error or success).</td></tr><tr><td valign="top"><a href="#q_async-3">q_async/3</a></td><td>Executes the command, and sends a message to <code>Pid</code> with the response
(with either or success).</td></tr><tr><td valign="top"><a href="#q_noreply-2">q_noreply/2</a></td><td>Executes the command but does not wait for a response and ignores any
errors.</td></tr><tr><td valign="top"><a href="#qp-2">qp/2</a></td><td> Executes the given pipeline (list of commands) in the
specified connection.</td></tr><tr><td valign="top"><a href="#qp-3">qp/3</a></td><td>Like qp/2 with a custom timeout.</td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>Connect with default options.</td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td>Connect with the given options.</td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td>Connect to the given host and port.</td></tr><tr><td valign="top"><a href="#start_link-3">start_link/3</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#start_link-4">start_link/4</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#start_link-5">start_link/5</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#start_link-6">start_link/6</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#start_link-7">start_link/7</a></td><td>(<em>Deprecated</em>.) </td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td>Closes the connection and stops the client.</td></tr>
</table>


<a name="functions"></a>

## Function Details ##

<a name="q-2"></a>

### q/2 ###

<pre><code>
q(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; {ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary() | no_connection}
</code>
</pre>


Executes the given command in the specified connection. The
command must be a valid Redis command and may contain arbitrary
data which will be converted to binaries. The returned values will
always be binaries.

<a name="q-3"></a>

### q/3 ###

<pre><code>
q(Client::<a href="#type-client">client()</a>, Command::[any()], Timeout::integer()) -&gt; {ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary() | no_connection}
</code>
</pre>


Like q/2 with a custom timeout.

<a name="q_async-2"></a>

### q_async/2 ###

<pre><code>
q_async(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; ok
</code>
</pre>


Executes the command, and sends a message to the calling process with the
response (with either error or success). Message is of the form `{response,
Reply}`, where `Reply` is the reply expected from `q/2`.

<a name="q_async-3"></a>

### q_async/3 ###

<pre><code>
q_async(Client::<a href="#type-client">client()</a>, Command::[any()], Pid::pid() | atom()) -&gt; ok
</code>
</pre>


Executes the command, and sends a message to `Pid` with the response
(with either or success).

__See also:__ [q_async/2](#q_async-2).

<a name="q_noreply-2"></a>

### q_noreply/2 ###

<pre><code>
q_noreply(Client::<a href="#type-client">client()</a>, Command::[any()]) -&gt; ok
</code>
</pre>


Executes the command but does not wait for a response and ignores any
errors.

__See also:__ [q/2](#q-2).

<a name="qp-2"></a>

### qp/2 ###

<pre><code>
qp(Client::<a href="#type-client">client()</a>, Pipeline::<a href="#type-pipeline">pipeline()</a>) -&gt; [{ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary()}] | {error, no_connection}
</code>
</pre>


Executes the given pipeline (list of commands) in the
specified connection. The commands must be valid Redis commands and
may contain arbitrary data which will be converted to binaries. The
values returned by each command in the pipeline are returned in a list.

<a name="qp-3"></a>

### qp/3 ###

<pre><code>
qp(Client::<a href="#type-client">client()</a>, Pipeline::<a href="#type-pipeline">pipeline()</a>, Timeout::integer()) -&gt; [{ok, <a href="#type-return_value">return_value()</a>} | {error, Reason::binary()}] | {error, no_connection}
</code>
</pre>


Like qp/2 with a custom timeout.

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code>
</pre>


Equivalent to [`start_link([])`](#start_link-1).

Connect with default options.

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Options::<a href="#type-options">options()</a>) -&gt; {ok, pid()} | {error, Reason::term()}
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
  appearing in logs and stacktraces), a string or iodata or the
  atom <code>undefined</code> for no username; default <code>undefined</code>
</dd>



<dt><code>{password, Password}</code></dt>



<dd>A 0-ary function that returns the password
  (the preferred way to provide password as it prevents the actual secret from
  appearing in logs and stacktraces), a string or iodata or the
  atom <code>undefined</code> for no username; default <code>undefined</code>
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



<dt><code>{sentinel, SentinelOptions}</code></dt>



<dd> Enables client for sentinel mode; options are required
  to connect to sentinel cluster; default: undefined 
</dd>



<dd> Sentinel Options: <code>{master_group, master_group_name}</code> - Atom, default: mymaster;<code>{endpoints, [{Host, Port}]}</code> - List of {Host, Port} tuples, default: [{"127.0.0.1", 26379}];<code>{username, Username}</code>;<code>{password, Password}</code>;<code>{connect_timeout, Timeout}</code>;<code>{socket_options, SockOpts}</code><code>{tls, TlsOpts}</code>
</dd>



Connect with the given options.

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code>
</pre>


Equivalent to [`start_link([{host, Host}, {port, Port}])`](#start_link-1).

Connect to the given host and port.

<a name="start_link-3"></a>

### start_link/3 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, OptionsOrDatabase) -&gt; {ok, Pid::pid()} | {error, Reason::term()}
</code>
</pre>

<ul class="definitions"><li><code>OptionsOrDatabase = <a href="#type-options">options()</a> | integer()</code></li></ul>

__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

<a name="start_link-4"></a>

### start_link/4 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, Database::integer(), Password::string()) -&gt; {ok, pid()} | {error, term()}
</code>
</pre>


__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

__See also:__ [start_link/1](#start_link-1).

<a name="start_link-5"></a>

### start_link/5 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, Database::integer(), Password::string(), ReconnectSleep::<a href="#type-reconnect_sleep">reconnect_sleep()</a>) -&gt; {ok, pid()} | {error, term()}
</code>
</pre>


__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

__See also:__ [start_link/1](#start_link-1).

<a name="start_link-6"></a>

### start_link/6 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, Database::integer(), Password::string(), ReconnectSleep::<a href="#type-reconnect_sleep">reconnect_sleep()</a>, ConnectTimeout::timeout()) -&gt; {ok, pid()} | {error, term()}
</code>
</pre>


__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

__See also:__ [start_link/1](#start_link-1).

<a name="start_link-7"></a>

### start_link/7 ###

<pre><code>
start_link(Host::<a href="#type-host">host()</a>, Port::<a href="inet.md#type-port_number">inet:port_number()</a>, Database::integer(), Password::string(), ReconnectSleep::<a href="#type-reconnect_sleep">reconnect_sleep()</a>, ConnectTimeout::timeout(), SocketOptions::list()) -&gt; {ok, pid()} | {error, term()}
</code>
</pre>


__This function is deprecated:__ Use [`start_link/1`](#start_link-1) instead.

__See also:__ [start_link/1](#start_link-1).

<a name="stop-1"></a>

### stop/1 ###

<pre><code>
stop(Client::<a href="#type-client">client()</a>) -&gt; ok
</code>
</pre>


Closes the connection and stops the client.

