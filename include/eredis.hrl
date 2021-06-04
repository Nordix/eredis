%% Public types

-type reconnect_sleep() :: no_reconnect | integer().
-type registered_name() :: {local, atom()} | {global, term()} | {via, atom(), term()}.

-type option() :: {host, string() | {local, string()}} |
                  {port, inet:port_number()} |
                  {database, integer() | string()} |
                  {password, string()} |
                  {reconnect_sleep, reconnect_sleep()} |
                  {connect_timeout, integer()} |
                  {socket_options, list()} |
                  {tls, [ssl:tls_client_option()]} |
                  {name, registered_name()}.

-type options() :: [option()].
-type server_args() :: options().               % for backwards compatibility

-type return_value() :: undefined | binary() | [binary() | nonempty_list()].

-type pipeline() :: [iolist()].

-type channel() :: binary().

%% Continuation data is whatever data returned by any of the parse
%% functions. This is used to continue where we left off the next time
%% the user calls parse/2.
-type continuation_data() :: any().
-type parser_state() :: status_continue | bulk_continue | multibulk_continue | error_continue.

%% Internal types
-ifdef(OTP_RELEASE). % OTP >= 21
-type eredis_queue() :: queue:queue().
-else.
-ifdef(namespaced_types). % Macro defined in rebar.conf if OTP >= 17
-type eredis_queue() :: queue:queue().
-else.
-type eredis_queue() :: queue().
-endif.
-endif.

%% Internal parser state. Is returned from parse/2 and must be
%% included on the next calls to parse/2.
-record(pstate, {
          state = undefined :: parser_state() | undefined,
          continuation_data :: continuation_data() | undefined
}).

-define(NL, "\r\n").

-define(SOCKET_MODE, binary).
-define(SOCKET_OPTS, [{active, once}, {packet, raw}, {reuseaddr, false},
                      {keepalive, false}, {send_timeout, ?SEND_TIMEOUT}]).

-define(RECV_TIMEOUT, 5000).
-define(SEND_TIMEOUT, 5000).
