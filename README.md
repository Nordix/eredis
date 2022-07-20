# eredis

Non-blocking Redis client with focus on performance and robustness.

[![Build Status](https://github.com/Nordix/eredis/workflows/CI/badge.svg)](https://github.com/Nordix/eredis)
[![Hex pm](https://img.shields.io/hexpm/v/eredis.svg?style=flat)](https://hex.pm/packages/eredis)
[![Hex.pm](https://img.shields.io/hexpm/dt/eredis.svg)](https://hex.pm/packages/eredis)

This fork is the official continuation of `wooga/eredis`.
It includes several improvements, such as
TLS support, Sentinel support and TCP error handling corrections.
See [CHANGELOG.md](CHANGELOG.md) for details.

Note: This client connects to a standalone Redis node, optionally using Sentinel.
For *Redis Cluster*, you need
[eredis_cluster](https://github.com/Nordix/eredis_cluster) or
[ecredis](https://github.com/HalloAppInc/ecredis).

Supported Redis features:

 * Any command, through `eredis:q/2,3`
 * Transactions
 * Pipelining
 * Authentication & multiple DBs
 * Pubsub
 * TLS
 * Sentinel support

Generated API documentation: [doc/eredis.md](doc/eredis.md)

Published documentation can also be found on [hexdocs](https://hexdocs.pm/eredis/).

## Setup

If you have Redis running on localhost with default settings, like:

    docker run --rm --net=host redis:latest

you may copy and paste the following into a shell to try out Eredis:

    git clone https://github.com/Nordix/eredis.git
    cd eredis
    rebar3 shell
    {ok, C} = eredis:start_link().
    {ok, <<"OK">>} = eredis:q(C, ["SET", "foo", "bar"]).
    {ok, <<"bar">>} = eredis:q(C, ["GET", "foo"]).

To connect to a Redis instance listening on a Unix domain socket:

```erlang
{ok, C1} = eredis:start_link({local, "/var/run/redis.sock"}, 0).
```

To connect to a Redis instance using TLS:

```erlang
Options = [{tls, [{cacertfile, "ca.crt"},
                  {certfile,   "client.crt"},
                  {keyfile,    "client.key"}]}],
{ok, C2} = eredis:start_link("127.0.0.1", ?TLS_PORT, Options),
```

To connect to a Redis sentinel cluster:

```erlang
SentinelOptions = [{master_group, mymaster},
                   {endpoints, [{"127.0.0.1", 26379}]}],
{ok, C1} = eredis:start_link([{sentinel, SentinelOptions}]).
```

## Example

MSET and MGET:

```erlang
KeyValuePairs = ["key1", "value1", "key2", "value2", "key3", "value3"].
{ok, <<"OK">>} = eredis:q(C, ["MSET" | KeyValuePairs]).
{ok, Values} = eredis:q(C, ["MGET" | ["key1", "key2", "key3"]]).
```

HASH

```erlang
HashObj = ["id", "objectId", "message", "message", "receiver", "receiver", "status", "read"].
{ok, <<"OK">>} = eredis:q(C, ["HMSET", "key" | HashObj]).
{ok, Values} = eredis:q(C, ["HGETALL", "key"]).
```

LIST

```erlang
eredis:q(C, ["LPUSH", "keylist", "value"]).
eredis:q(C, ["RPUSH", "keylist", "value"]).
eredis:q(C, ["LRANGE", "keylist", 0, -1]).
```

Transactions:

```erlang
{ok, <<"OK">>} = eredis:q(C, ["MULTI"]).
{ok, <<"QUEUED">>} = eredis:q(C, ["SET", "foo", "bar"]).
{ok, <<"QUEUED">>} = eredis:q(C, ["SET", "bar", "baz"]).
{ok, [<<"OK">>, <<"OK">>]} = eredis:q(C, ["EXEC"]).
```

Pipelining:

```erlang
P1 = [["SET", a, "1"],
      ["LPUSH", b, "3"],
      ["LPUSH", b, "2"]].
[{ok, <<"OK">>}, {ok, <<"1">>}, {ok, <<"2">>}] = eredis:qp(C, P1).
```

Pubsub:

```erlang
1> eredis_sub:sub_example().
received {subscribed,<<"foo">>,<0.34.0>}
{<0.34.0>,<0.37.0>}
2> eredis_sub:pub_example().
received {message,<<"foo">>,<<"bar">>,<0.34.0>}
ok
3>
```

Pattern Subscribe:

```erlang
1> eredis_sub:psub_example().
received {subscribed,<<"foo*">>,<0.33.0>}
{<0.33.0>,<0.36.0>}
2> eredis_sub:ppub_example().
received {pmessage,<<"foo*">>,<<"foo123">>,<<"bar">>,<0.33.0>}
ok
3>
```

## Commands

### Query: [qp/2,3](doc/eredis.md#q-2)

Eredis has one main function to interact with redis, which is
`eredis:q(Client::pid(), Command::iolist())`. The response will either
be `{ok, Value::binary() | [binary()]}` or `{error,
Message::binary()}`.  The value is always the exact value returned by
Redis, without any type conversion. If Redis returns a list of values,
this list is returned in the exact same order without any type
conversion.

### Pipelined query: [qp/2,3](doc/eredis.md#qp-2)

To send multiple requests to redis in a batch, aka. pipelining
requests, you may use `eredis:qp(Client::pid(),
[Command::iolist()])`. This function returns `{ok, [Value::binary()]}`
where the values are the redis responses in the same order as the
commands you provided.

### Connect a client: [start_link/1](doc/eredis.md#start_link-1)

To start the client, use `start_link/1` or one of its variants. `start_link/1`
takes the following options (proplist):

* `host`: DNS name or IP address as string; or unix domain socket as `{local,
  Path}` (available in OTP 19+)
* `port`: integer, default is 6379
* `database`: integer or 0 for default database, default: 0
* `username`: string, default: no username
* `password`: string, default: no password
* `reconnect_sleep`: integer of milliseconds to sleep between reconnect attempts, default: 100
* `connect_timeout`: timeout value in milliseconds to use in the connect, default: 5000
* `socket_options`: proplist of [gen_tcp](https://erlang.org/doc/man/gen_tcp.html)
  options used when connecting the socket, default is `?SOCKET_OPTS`.
  It's possible to specify `{active, N}` or `{active, true}`.
  Active `once` and `false` are not supported. The default is N = 10.
* `tls`: enable TLS by providing a list of
  [options](https://erlang.org/doc/man/ssl.html) used when establishing the TLS
  connection, default is off.
  It's possible to specify `{active, N}` or `{active, true}` in TLS options.
  Active `once` and `false` are not supported. The default is N = 10.
  Note that `{active, N}` with TLS requires OTP 21.3 or later.

## Implicit pipelining

Commands are pipelined automatically so multiple processes can share the same
Eredis connection instance. Although `q/2,3` and `qp/2,3` are blocking until the
response is returned, Eredis is not blocked.

```
  Process A          Process B          Eredis        TCP/TLS socket
     |                  |                  |          (Redis server)
     | q(Pid, Command1) |                  |                 |
     |------------------------------------>|---------------->|
     |                  | q(Pid, Command2) |                 |
     |                  |----------------->|---------------->|
     |                  |                  |                 |
    ...                ...                ...               ...
     |                  |                  |                 |
     |                  |                  |      Response 1 |
     |<------------------------------------|<----------------|
     |                  |                  |      Response 2 |
     |                  |<-----------------|<----------------|
```

## Reconnecting on Redis down / network failure / timeout / etc

When Eredis for some reason looses the connection to Redis, Eredis
will keep trying to reconnect until a connection is successfully
established, which includes the `AUTH` and `SELECT` calls. The sleep
time between attempts to reconnect can be set in the
`eredis:start_link/1` call.

As long as the connection is down, Eredis will respond to any request
immediately with `{error, no_connection}` without actually trying to
connect. This serves as a kind of circuit breaker and prevents a
stampede of clients just waiting for a failed connection attempt or
`gen_server:call` timeout.

Note: If Eredis is starting up and cannot connect, it will fail
immediately with `{connection_error, Reason}`.

## Pubsub

Thanks to Dave Peticolas (jdavisp3), eredis supports
pubsub. [`eredis_sub`](doc/eredis_sub.md) offers a separate client that will forward
channel messages from Redis to an Erlang process in a "active-once"
pattern similar to gen_tcp sockets. After every message received, the
controlling process must acknowledge receipt using
`eredis_sub:ack_message/1`.

If the controlling process does not process messages fast enough,
eredis will queue the messages up to a certain queue size controlled
by configuration. When the max size is reached, eredis will either
drop messages or crash, also based on configuration.

Subscriptions are managed using `eredis_sub:subscribe/2` and
`eredis_sub:unsubscribe/2`. When Redis acknowledges the change in
subscription, a message is sent to the controlling process for each
channel. Then, eredis sends a message on the form `{subscribed, Channel,
ClientPid}` to the controlling process, which must be acked using
`eredis_sub:ack_message/1`.

eredis also supports Pattern Subscribe using `eredis_sub:psubscribe/2`
and `eredis_sub:punsubscribe/2`. As with normal subscriptions, a message
is sent to the controlling process for each channel and eredis sends a
message on the form `{subscribed, Channel, ClientPid}` to the
controlling process, which must be acked using `eredis_sub:ack_message/1`.

The controlling process is also notified in case of reconnection attempts or
failures. See `test/eredis_pubsub_SUITE.erl` for examples.

Starting with version 1.5, eredis automatically resubscribes after reconnect.
Then, the controlling process will receive `{subscribed, Channel, ClientPid}`
messages again for every channel and pattern subscribed to. These must also be
acked.

Here is a list of all the messages that are sent to the controlling process.
Some messages don't need to be acked, but it does not harm doing so.

* `{eredis_connected, Pid}` when the socket to Redis is established
  and authenticated. Doesn't need to be acked.

* `{eredis_disconnected, Pid}` when the connection to Redis has been lost.
  Doesn't need to be acked.

* `{eredis_reconnect_attempt, Pid}` at every reconnect attempt, when the
  connection to Redis has been lost. Doesn't need to be acked.

* `{eredis_reconnect_failed, Pid, {error, {connection_error, Reason}}}` after
  every failed reconnect attempt. Doesn't need to be acked.

* `{message, Channel, Message, Pid}` for every incoming message on subscribed
  channels. Needs to be acked using `eredis_sub:ack_message/1`.

* `{pmessage, Pattern, Channel, Message, Pid}` for every incoming message on
  channels subscribed to by pattern, using using `eredis_sub:psubscribe/2`.
  Needs to be acked using `eredis_sub:ack_message/1`.

* `{subscribed, Channel, Pid}` when a subscription has been confirmed by Redis.
  Channel is either a channel (subscribe) or a pattern (psubscribe). Needs to be
  acked using `eredis_sub:ack_message/1`.

* `{unsubscribed, Channel, Pid}` when a subscription has been removed from
  Redis. Channel is either a channel (unsubscribe) or a pattern (punsubscribe).
  Needs to be acked using `eredis_sub:ack_message/1`.

## AUTH and SELECT

Eredis also implements the AUTH and SELECT calls for you. When the
client is started with something else than default values for password
and database, it will issue the `AUTH` and `SELECT` commands
appropriately, even when reconnecting after a timeout.

## Benchmarking

Using [lasp-bench](https://github.com/lasp-lang/lasp-bench/) you may
benchmark Eredis on your own hardware using the provided config and
driver. See `priv/basho_bench_driver_eredis.config` and
`src/basho_bench_driver_eredis.erl`.

Testcase summary from our daily runs:

* [eredis](https://bjosv.github.io/eredis-benchmark/results/latest/eredis/summary.png)
* [eredis_pipeline](https://bjosv.github.io/eredis-benchmark/results/latest/eredis_pipeline/summary.png)

The [eredis-benchmark](https://github.com/bjosv/eredis-benchmark) repo runs
a daily job that produces above graphs. It also contains the script
`run-tests.sh` that might help you with the needed steps when setting up the
benchmark testing on your own.

## Queueing

Eredis uses the same queueing mechanism as Erldis. `eredis:q/2` uses
`gen_server:call/2` to do a blocking call to the client
gen_server. The client will immediately send the request to Redis, add
the caller to the queue and reply with `noreply`. This frees the
gen_server up to accept new requests and parse responses as they come
on the socket.

When data is received on the socket, we call `eredis_parser:parse/2`
until it returns a value, we then use `gen_server:reply/2` to reply to
the first process waiting in the queue.

This queueing mechanism works because Redis guarantees that the
response will be in the same order as the requests.

## Response parsing

The socket is set to `{active, N}` with N = 10 by default. This is configurable
by including `{active, N}` in socket options or TLS options (if TLS is used). N
must be an integer or `true`. Active `once` and `false` are not supported.

The response parser is capable of parsing partial data and continuing when more
data arrives on the socket.

## Tests and code checking

EUnit tests currently requires a locally running instance of Redis.

```console
rebar3 eunit
```

Xref, dialyzer and elvis should result in no errors.

```console
rebar3 xref
rebar3 dialyzer
elvis rock
```

## Future improvements

When the parser is accumulating data, a new binary is generated for
every call to `parse/2`. This might create binaries that will be
reference counted. This could be improved by replacing it with an
iolist.

When parsing bulk replies, the parser knows the size of the bulk. If the
bulk is big and would come in many chunks, this could improved by
having the client explicitly use `gen_tcp:recv/2` to fetch the entire
bulk at once.

## Credits

This is a fork of the original Eredis. Eredis was created by Knut Nesheim, with
inspiration from the earlier Erldis.

Although this project is almost a complete rewrite, many patterns are
the same as you find in Erldis, most notably the queueing of requests.

`create_multibulk/1` and `to_binary/1` were taken verbatim from Erldis.
