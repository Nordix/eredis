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

     %% Test floats by float_to_binary(Float, [short]) or io_lib_format:fwrite_g(Float)
     ?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$5\r\n123.5\r\n">>,
                   list_to_binary(create_multibulk(['SET', foo, 123.5]))),
     ?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$17\r\n3.141592653589793\r\n">>,
                   list_to_binary(create_multibulk(['SET', foo, 3.141592653589793238462643383279]))),
     ?_assertEqual(<<"*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$14\r\n1.801439851e16\r\n">>,
                   list_to_binary(create_multibulk(['SET', foo, 18014398510000000.0])))
    ].
