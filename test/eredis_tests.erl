-module(eredis_tests).

-include_lib("eunit/include/eunit.hrl").
-include("eredis.hrl").

-import(eredis, [create_multibulk/1]).

multibulk_test_() ->
    [?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n">>,
                   list_to_binary(create_multibulk(["SET", "foo", "bar"]))),
     ?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n">>,
                   list_to_binary(create_multibulk(['SET', foo, bar]))),

     ?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\n123\r\n">>,
                   list_to_binary(create_multibulk(['SET', foo, 123]))),

     ?_assertThrow({cannot_store_floats, 123.5},
                   list_to_binary(create_multibulk(['SET', foo, 123.5])))
    ].
