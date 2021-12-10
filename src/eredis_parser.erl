%%
%% Parser of the Redis protocol, see http://redis.io/topics/protocol
%%
%% The idea behind this parser is that we accept any binary data
%% available on the socket. If there is not enough data to parse a
%% complete response, we ask the caller to call us later when there is
%% more data. If there is too much data, we only parse the first
%% response and let the caller call us again with the rest.
%%
%% This approach lets us write a "pure" parser that does not depend on
%% manipulating the socket, which erldis and redis-erl is
%% doing. Instead, we may ask the socket to send us data as fast as
%% possible and parse it continuously. The overhead of manipulating the
%% socket when parsing multibulk responses is killing the performance
%% of erldis.
%%
%% Future improvements:
%%  * When we return a bulk continuation, we also include the size of
%%    the bulk. The caller may use this to explicitly call
%%    gen_tcp:recv/2 with the desired size.

%% @private
-module(eredis_parser).
-include("eredis.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([init/0, parse/2]).

%%
%% API
%%

%% @doc: Initialize the parser
init() ->
    #pstate{}.


-spec parse(State::#pstate{}, Data::binary()) ->
                   {ok, return_value(), NewState::#pstate{}} |
                       {ok, return_value(), Rest::binary(), NewState::#pstate{}} |
                       {error, ErrString::binary(), NewState::#pstate{}} |
                       {error, ErrString::binary(), Rest::binary(), NewState::#pstate{}} |
                       {continue, NewState::#pstate{}}.

%% @doc: Parses the (possibly partial) response from Redis. Returns
%% either {ok, Value, NewState}, {ok, Value, Rest, NewState} or
%% {continue, NewState}. External entry point for parsing.
%%
%% In case {ok, Value, NewState} is returned, Value contains the value
%% returned by Redis. NewState will be an empty parser state.
%%
%% In case {ok, Value, Rest, NewState} is returned, Value contains the
%% most recent value returned by Redis, while Rest contains any extra
%% data that was given, but was not part of the same response. In this
%% case you should immeditely call parse again with Rest as the Data
%% argument and NewState as the State argument.
%%
%% In case {continue, NewState} is returned, more data is needed
%% before a complete value can be returned. As soon as you have more
%% data, call parse again with NewState as the State argument and any
%% new binary data as the Data argument.

%% Parser in initial state, the data we receive will be the beginning
%% of a response
parse(#pstate{states = []}, NewData) ->
    return(do_parse(start, NewData), []);
parse(#pstate{states = [State | States]}, NewData) ->
    return(do_parse(State, NewData), States).

%% Combines the result of do_parse/2 with the nested states of parse/2.
return({Tag, Value, <<>>}, []) when Tag =:= ok; Tag =:= error ->
    {Tag, Value, #pstate{}};
return({Tag, Value, RestData}, []) when Tag =:= ok; Tag =:= error ->
    {Tag, Value, RestData, #pstate{}};
return({Tag, Value, RestData}, [{multibulk_continue, NumLeft, Acc} | States])
  when Tag =:= ok; Tag =:= error ->
    NewStates = [{multibulk_continue, NumLeft - 1, [Value | Acc]} | States],
    parse(#pstate{states = NewStates}, RestData);
return({continue, Continue}, States) ->
    {continue, #pstate{states = [Continue | States]}};
return({nested, State, Data}, States) ->
    %% We're in a multibulk and need to parse a new element
    parse(#pstate{states = [start, State | States]}, Data);
return({error, _Reason} = ParseError, _States) ->
    ParseError.

%% Parses a value. State is not nested here.
-spec do_parse(continuation_data(), NewData :: binary()) ->
          {ok, Value :: any(), RestData :: binary()} |
          {error, Message :: binary(), RestData :: binary()} |
          {continue, continuation_data()} |
          {nested, continuation_data(), RestData :: binary()} |
          {error, unknown_response}.
do_parse(start, <<Type, Data/binary>>) ->
    %% Look at the first byte to get the type of reply
    case Type of
        %% Status (AKA simple string)
        $+ ->
            do_parse({status_continue, <<>>}, Data);

        %% Error
        $- ->
            do_parse({error_continue, <<>>}, Data);

        %% Integer reply (returned as binary)
        $: ->
            do_parse({status_continue, <<>>}, Data);

        %% Multibulk (array)
        $* ->
            do_parse({multibulk_size, <<>>}, Data);

        %% Bulk (string)
        $$ ->
            do_parse({bulk_size, <<>>}, Data);

        _ ->
            {error, unknown_response}
    end;
do_parse({StateTag, Acc}, Data) when StateTag =:= status_continue;
                                     StateTag =:= error_continue ->
    case split_by_newline(Acc, Data) of
        nomatch ->
            {continue, {StateTag, <<Acc/binary, Data/binary>>}};
        {Value, RestData} ->
            Tag = case StateTag of
                      status_continue -> ok;
                      error_continue -> error
                  end,
            {Tag, Value, RestData}
    end;
do_parse({StateTag, Acc}, Data) when StateTag =:= bulk_size;
                                     StateTag =:= multibulk_size ->
    %% Find the position of the first terminator, everything up until
    %% this point contains the size specifier. If we cannot find it,
    %% we received a partial response and need more data
    case split_by_newline(Acc, Data) of
        nomatch ->
            %% Incomplete size
            {continue, {StateTag, <<Acc/binary, Data/binary>>}};
        {Size, RestData} ->
            IntSize = binary_to_integer(Size),
            NextState = case StateTag of
                            bulk_size      -> {bulk_continue, IntSize, <<>>};
                            multibulk_size -> {multibulk_continue, IntSize, []}
                        end,
            do_parse(NextState, RestData)
    end;
do_parse({bulk_continue, -1, <<>>}, Data) ->
    %% Nil (AKA null) string
    {ok, undefined, Data};
do_parse({bulk_continue, -1, Acc}, <<"\n", RestData/binary>>) when byte_size(Acc) > 0 ->
    %% It's only half of the "\r\n" we're waiting for (unlikely case)
    BulkSize = byte_size(Acc) - 1,
    <<Bulk:BulkSize/binary, "\r">> = Acc,
    {ok, Bulk, RestData};
do_parse({bulk_continue, RemainingSize, Acc}, Data)
  when byte_size(Data) >= RemainingSize + length(?NL) ->
    %% We have enough data for the entire bulk
    <<RemainingBulk:RemainingSize/binary, ?NL, RestData/binary>> = Data,
    Bulk = <<Acc/binary, RemainingBulk/binary>>,
    {ok, Bulk, RestData};
do_parse({bulk_continue, RemainingSize, Acc}, Data) ->
    NewRemainingSize = RemainingSize - byte_size(Data),
    NewAcc = <<Acc/binary, Data/binary>>,
    {continue, {bulk_continue, NewRemainingSize, NewAcc}};
do_parse({multibulk_continue, -1, []}, Data) ->
    %% Nil (AKA null) array
    {ok, undefined, Data};
do_parse({multibulk_continue, 0, Acc}, Data) ->
    {ok, lists:reverse(Acc), Data};
do_parse({multibulk_continue, _RemainingItems, _Acc} = State, <<>>) ->
    {continue, State};
do_parse({multibulk_continue, _RemainingItems, _Acc} = State, Data) ->
    {nested, State, Data}.

%% Concat two binaries and then split by "\r\n", but without actually
%% concatenating, thus avoiding creating a large binary which becomes garbage.
%%
%% Pre-condition: Acc does not contain "\r\n".
split_by_newline(Acc, <<"\n", Rest/binary>>)
  when binary_part(Acc, byte_size(Acc), -1) =:= <<"\r">> ->
    %% Special case where the "\r\n" sequence is split between Acc and Data
    FirstLine = binary_part(Acc, 0, byte_size(Acc) - 1),
    {FirstLine, Rest};
split_by_newline(Acc, Data) ->
    %% There's no "\r\n" in Acc so we can search only in Data.
    case binary:match(Data, <<"\r\n">>) of
        nomatch ->
            nomatch;
        {NewlinePos, 2} ->
            <<LineEnd:NewlinePos/binary, "\r\n", Rest/binary>> = Data,
            FirstLine = <<Acc/binary, LineEnd/binary>>,
            {FirstLine, Rest}
    end.
