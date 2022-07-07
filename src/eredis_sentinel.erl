%% @private
-module(eredis_sentinel).
-behaviour(gen_server).
-include("eredis.hrl").

%% API
-export([start_link/2, stop/1, get_master/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(errors, {
                 sentinel_unreachable = 0 :: integer(),
                 master_unknown = 0       :: integer(),
                 master_unreachable = 0   :: integer(),
                 total = 0                :: integer()
                }).

%% Hide secret strings in funs to prevent them from appearing in logs
-type obfuscated_string() :: fun(() -> string()).

-record(eredis_sentinel_state, {
                                master_group    :: atom(),
                                endpoints       :: [{string() | {local, string()} , integer()}],
                                username        :: obfuscated_string() | undefined,
                                password        :: obfuscated_string() | undefined,
                                connect_timeout :: integer() | undefined,
                                socket_options  :: list(),
                                tls_options     :: list(),
                                conn_pid        :: undefined | pid(),
                                errors          :: #errors{}
                               }).

-define(CONNECT_TIMEOUT, 5000).
%́% Sentinel errors
-define(SENTINEL_UNREACHABLE, sentinel_unreachable).
-define(MASTER_UNKNOWN, master_unknown).
-define(MASTER_UNREACHABLE, master_unreachable).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(atom(), list()) ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Options) ->
    gen_server:start_link({local, Name}, ?MODULE, Options, []).

stop(Pid) ->
    gen_server:call(Pid, stop).

get_master(Pid) ->
    gen_server:call(Pid, get_master).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc Initializes the server
-spec(init(Args :: term()) ->
             {ok, State :: #eredis_sentinel_state{}} | {ok, State :: #eredis_sentinel_state{}, timeout() | hibernate} |
             {stop, Reason :: term()} | ignore).
init(Options) ->
    process_flag(trap_exit, true),
    MasterGroup         = proplists:get_value(master_group, Options, mymaster),
    Endpoints           = proplists:get_value(endpoints, Options, [{"127.0.0.1", 26379}]),
    Username            = proplists:get_value(username, Options, undefined),
    Password            = proplists:get_value(password, Options, undefined),
    ConnectTimeout      = proplists:get_value(connect_timeout, Options, ?CONNECT_TIMEOUT),
    SocketOptions       = proplists:get_value(socket_options, Options, []),
    TlsOptions          = proplists:get_value(tls, Options, []),
    {ok, #eredis_sentinel_state{master_group = MasterGroup,
                                endpoints = Endpoints,
                                username = obfuscate(Username),
                                password = obfuscate(Password),
                                connect_timeout = ConnectTimeout,
                                socket_options = SocketOptions,
                                tls_options = TlsOptions,
                                conn_pid = undefined,
                                errors    = #errors{}}}.

%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #eredis_sentinel_state{}) ->
             {reply, Reply :: term(), NewState :: #eredis_sentinel_state{}} |
             {reply, Reply :: term(), NewState :: #eredis_sentinel_state{}, timeout() | hibernate} |
             {noreply, NewState :: #eredis_sentinel_state{}} |
             {noreply, NewState :: #eredis_sentinel_state{}, timeout() | hibernate} |
             {stop, Reason :: term(), Reply :: term(), NewState :: #eredis_sentinel_state{}} |
             {stop, Reason :: term(), NewState :: #eredis_sentinel_state{}}).
handle_call(get_master, _From, State) ->
    case query_master(State#eredis_sentinel_state{errors = #errors{}}) of
        {ok, {Host, Port}, S1} ->
            {reply, {ok, Host, Port}, S1};
        {error, Error, S1} ->
            {reply, {error, Error}, S1}
    end;

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #eredis_sentinel_state{}) ->
             {noreply, NewState :: #eredis_sentinel_state{}} |
             {noreply, NewState :: #eredis_sentinel_state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #eredis_sentinel_state{}}).
handle_cast(_Request, State = #eredis_sentinel_state{}) ->
    {noreply, State}.

%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #eredis_sentinel_state{}) ->
             {noreply, NewState :: #eredis_sentinel_state{}} |
             {noreply, NewState :: #eredis_sentinel_state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #eredis_sentinel_state{}}).
%% Current sentinel connection broken
handle_info({'EXIT', Pid, _Reason}, #eredis_sentinel_state{conn_pid = Pid} = S) ->
    {noreply, S#eredis_sentinel_state{conn_pid = undefined}};

handle_info({'EXIT', _Pid, _Reason}, S) ->
    {stop, normal, S};

handle_info(_Info, State) ->
    {noreply, State}.

%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #eredis_sentinel_state{}) -> term()).
terminate(_Reason, _State = #eredis_sentinel_state{conn_pid = undefined}) ->
    ok;
terminate(_Reason, _State = #eredis_sentinel_state{conn_pid = Pid}) ->
    eredis:stop(Pid),
    ok.

%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #eredis_sentinel_state{},
                  Extra :: term()) ->
             {ok, NewState :: #eredis_sentinel_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #eredis_sentinel_state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
rotate([X|Xs]) -> Xs ++ [X].

%% Finding new master host for named cluster:
%% * First try to query already connected sentinel if we have one.
%% * If this failed try to connect and query all sentinels starting from the last connected one.
%% * If connected sentinel returns port:ip - return {ok, {Host, Port}} and remember connection pid.
%% * In case no sentinels return valid answer - response with error:
%%   * If all sentinels failed connect to - return {error, sentinel_unreachable}
%%   * If all connected sentinels return null - return {error, sentinel_master_unknown}
%%   * If some of connected sentinels return -IDONTKNOW - return {error, sentinel_master_unreachable}

-spec query_master(#eredis_sentinel_state{}) ->
          {ok, {string(), integer()}, #eredis_sentinel_state{}} | {error, any(), #eredis_sentinel_state{}}.

%% All sentinels return errors
query_master(#eredis_sentinel_state{errors = Errors, endpoints = Sentinels} = S)
  when Errors#errors.total >= length(Sentinels) ->
    #errors{sentinel_unreachable=SU, master_unknown=MUK, master_unreachable=MUR} = Errors,
    if
        SU == length(Sentinels) ->
            {error, ?SENTINEL_UNREACHABLE, S};
        MUK > 0, MUR == 0 ->
            {error, ?MASTER_UNKNOWN, S};
        true ->
            {error, ?MASTER_UNREACHABLE, S}
    end;

%% No connected sentinel
query_master(#eredis_sentinel_state{conn_pid=undefined,
                                    endpoints = [{H, P} | _],
                                    username = Username,
                                    password = Password,
                                    connect_timeout = ConnectTimeout,
                                    socket_options = SocketOptions,
                                    tls_options = TlsOptions} = S
            ) ->
    case eredis:start_link([{host, H},
                            {port, P},
                            {username, deobfuscate(Username)},
                            {password, deobfuscate(Password)},
                            {connect_timeout, ConnectTimeout},
                            {socket_options, SocketOptions},
                            {tls, TlsOptions},
                            {reconnect_sleep, no_reconnect}]) of
        {ok, ConnPid} ->
            query_master(S#eredis_sentinel_state{conn_pid=ConnPid});
        {error, E} ->
            error_logger:error_msg("Error connecting to sentinel at ~p:~p : ~p~n", [H, P, E]),
            Errors = update_errors(?SENTINEL_UNREACHABLE, S#eredis_sentinel_state.errors),
            Sentinels = rotate(S#eredis_sentinel_state.endpoints),
            query_master(S#eredis_sentinel_state{endpoints = Sentinels, errors = Errors})
    end;
%% Sentinel connected
query_master(#eredis_sentinel_state{conn_pid=ConnPid,
                                    master_group = MasterGroup,
                                    endpoints=[{H, P}|_]} = S) when is_pid(ConnPid)->
    case query_master(ConnPid, MasterGroup) of
        {ok, HostPort} ->
            {ok, HostPort, S};
        {error, Error} ->
            error_logger:error_msg("Master request for ~p to sentinel ~p:~p failed with ~p~n", [MasterGroup, H, P, Error]),
            eredis:stop(ConnPid),
            Errors = update_errors(Error, S#eredis_sentinel_state.errors),
            Sentinels = rotate(S#eredis_sentinel_state.endpoints),
            query_master(S#eredis_sentinel_state{conn_pid = undefined, errors = Errors, endpoints = Sentinels})
    end.

update_errors(E, #errors{sentinel_unreachable=SU, master_unknown=MUK, master_unreachable=MUR, total = T} = Errors) ->
    Errors1 =
        case E of
            ?SENTINEL_UNREACHABLE ->
                Errors#errors{sentinel_unreachable = SU + 1};
            ?MASTER_UNKNOWN ->
                Errors#errors{master_unknown = MUK + 1};
            ?MASTER_UNREACHABLE ->
                Errors#errors{master_unreachable = MUR + 1}
        end,
    Errors1#errors{total = T + 1}.

query_master(Pid, MasterGroup) ->
    Req = ["SENTINEL", "get-master-addr-by-name", atom_to_list(MasterGroup)],
    try get_master_response(eredis:q(Pid, Req)) of
        Result ->
            Result
    catch Type:Error ->
            error_logger:error_msg("Sentinel error getting master ~p : ~p:~p", [MasterGroup, Type, Error]),
            {error, Error}
    end.

get_master_response({ok, [HostBin, PortBin]}) ->
    Host = binary_to_list(HostBin),
    Port = list_to_integer(binary_to_list(PortBin)),
    {ok, {Host, Port}};
get_master_response({ok, undefined}) ->
    {error, ?MASTER_UNKNOWN};
get_master_response({error, <<"IDONTKNOW", _Rest/binary >>}) ->
    {error, ?MASTER_UNREACHABLE}.

-spec obfuscate(string() | undefined) -> obfuscated_string() | undefined.
obfuscate(undefined) ->
    undefined;
obfuscate(String) ->
    fun () -> String end.

-spec deobfuscate(obfuscated_string() | undefined) -> string() | undefined.
deobfuscate(undefined) ->
    undefined;
deobfuscate(Fun) when is_function(Fun, 0) ->
    Fun().
