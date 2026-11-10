-module(rabbitmq_gm_app).

-behaviour(application).

-export([start/2, stop/1]).

-define(CONFIG_KEY, {?MODULE, config}).
-define(WORKER_KEY, {?MODULE, worker}).

start(_Type, _Args) ->
    case rabbitmq_gm_crypto:load_config() of
        {ok, Config} ->
            {module, rabbitmq_gm_msg_interceptor} =
                code:ensure_loaded(rabbitmq_gm_msg_interceptor),
            Interceptor = {rabbitmq_gm_msg_interceptor, Config},
            ok = rabbit_msg_interceptor:add([Interceptor]),
            persistent_term:put(?CONFIG_KEY, Config),
            Worker = spawn_link(fun worker_loop/0),
            persistent_term:put(?WORKER_KEY, Worker),
            {ok, Worker};
        {error, Reason} ->
            {error, {rabbitmq_gm, Reason}}
    end.

stop(_State) ->
    Config = persistent_term:get(?CONFIG_KEY, #{}),
    rabbit_msg_interceptor:remove([{rabbitmq_gm_msg_interceptor, Config}]),
    case persistent_term:get(?WORKER_KEY, undefined) of
        Worker when is_pid(Worker) -> exit(Worker, shutdown);
        _ -> ok
    end,
    persistent_term:erase(?CONFIG_KEY),
    persistent_term:erase(?WORKER_KEY),
    ok.

worker_loop() ->
    receive
        stop -> ok
    end.
