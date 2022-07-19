-record(state, {
                host :: string() | undefined,
                port :: integer() | undefined,
                database :: binary() | undefined,
                auth_cmd :: secret() | undefined,
                reconnect_sleep :: integer() | undefined | no_reconnect,
                connect_timeout :: integer() | undefined,
                socket_options :: list(),
                tls_options :: list(),

                transport :: gen_tcp | ssl,
                socket :: gen_tcp:socket() | ssl:sslsocket() | undefined,
                reconnect_timer :: reference() | undefined,
                parser_state :: #pstate{} | undefined,

                %% Channels we should subscribe to
                channels = [] :: [channel()],
                pchannels = [] :: [channel()], % psubscribe

                %% The process we send pubsub and connection state messages to.
                controlling_process :: undefined | {reference(), pid()},

                %% This is the queue of messages to send to the controlling process.
                msg_queue :: eredis_queue(),

                %% When the queue reaches this size, either drop all
                %% messages or exit.
                max_queue_size :: integer() | inifinity,
                queue_behaviour :: drop | exit,

                %% The msg_state keeps track of whether we are waiting for the
                %% controlling process to acknowledge the last message.
                msg_state = need_ack :: ready | need_ack
               }).
