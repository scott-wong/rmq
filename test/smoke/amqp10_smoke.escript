#!/usr/bin/env escript
%%! -noshell
-mode(compile).
-include_lib("amqp10_common/include/amqp10_framing.hrl").
-include_lib("amqp10_common/include/amqp10_types.hrl").

main(["publish", Queue, Prefix]) ->
    run(fun() -> publish(Queue, Prefix) end);
main(["consume", Queue, Prefix]) ->
    run(fun() -> consume(Queue, Prefix) end);
main(_) ->
    io:format(standard_error, "usage: amqp10_smoke.escript publish|consume QUEUE PREFIX~n", []),
    halt(2).

run(Fun) ->
    add_plugin_paths(),
    {ok, _} = application:ensure_all_started(amqp10_client),
    try
        Fun(),
        halt(0)
    catch
        Class:Reason:Stack ->
            io:format(standard_error,
                      "AMQP 1.0 smoke failure: ~p:~p~n~p~n",
                      [Class, Reason, Stack]),
            halt(1)
    end.

add_plugin_paths() ->
    PluginDir = os:getenv("RMQ_PLUGIN_DIR", "/opt/rabbitmq/plugins"),
    Paths = filelib:wildcard(filename:join(PluginDir, "*/ebin")),
    ok = code:add_pathsz(Paths).

publish(Queue, Prefix) ->
    Connection = connect(),
    {ok, Session} = amqp10_client:begin_session_sync(Connection),
    Address = queue_address(Queue),
    {ok, Sender} =
        amqp10_client:attach_sender_link_sync(
          Session, <<"rmq-smoke-amqp10-sender">>, Address,
          settled, unsettled_state),
    await_link(Sender, credited, 30000),
    Bodies = [
        {"data", data_body(Prefix)},
        {"value", value_body(Prefix)},
        {"sequence", sequence_body(Prefix)}
    ],
    lists:foreach(
      fun({Type, Body}) ->
          Tag = <<"rmq-smoke-", (list_to_binary(Type))/binary>>,
          ok = amqp10_client:send_msg(
                 Sender, amqp10_msg:new(Tag, Body, true)),
          io:format("published AMQP 1.0 ~s body~n", [Type])
      end, Bodies),
    timer:sleep(500),
    ok = amqp10_client:detach_link(Sender),
    ok = amqp10_client:end_session(Session),
    ok = amqp10_client:close_connection(Connection).

consume(Queue, Prefix) ->
    Connection = connect(),
    {ok, Session} = amqp10_client:begin_session_sync(Connection),
    Address = queue_address(Queue),
    {ok, Receiver} =
        amqp10_client:attach_receiver_link(
          Session, <<"rmq-smoke-amqp10-receiver">>, Address,
          settled, unsettled_state),
    await_link(Receiver, attached, 30000),
    lists:foreach(
      fun({Type, ExpectedBody}) ->
          {ok, Msg} = amqp10_client:get_msg(Receiver, 30000),
          Body = amqp10_msg:body(Msg),
          case {Type, Body} of
              {"data", [Plain]} when Plain =:= ExpectedBody ->
                  io:format("consumed AMQP 1.0 data body~n");
              {"value", #'v1_0.amqp_value'{
                          content = {utf8, Plain}}} when Plain =:= ExpectedBody ->
                  io:format("consumed AMQP 1.0 value body~n");
              {"sequence", [#'v1_0.amqp_sequence'{
                               content = [{utf8, Plain}]}]}
                when Plain =:= ExpectedBody ->
                  io:format("consumed AMQP 1.0 sequence body~n");
              _ ->
                  error({unexpected_body, Type, Body})
          end
      end,
      [{"data", body(Prefix, "data")},
       {"value", body(Prefix, "value")},
       {"sequence", body(Prefix, "sequence")}]),
    ok = amqp10_client:detach_link(Receiver),
    ok = amqp10_client:end_session(Session),
    ok = amqp10_client:close_connection(Connection).

data_body(Prefix) ->
    #'v1_0.data'{content = body(Prefix, "data")}.

value_body(Prefix) ->
    #'v1_0.amqp_value'{content = {utf8, body(Prefix, "value")}}.

sequence_body(Prefix) ->
    #'v1_0.amqp_sequence'{
      content = [{utf8, body(Prefix, "sequence")}]}.

body(Prefix, Type) ->
    list_to_binary(Prefix ++ "-" ++ Type).

queue_address(Queue) ->
    Quoted = list_to_binary(uri_string:quote(Queue)),
    <<"/queues/", Quoted/binary>>.

connect() ->
    Host = os:getenv("AMQP_HOST", "rmq-test"),
    Port = list_to_integer(os:getenv("AMQP_PORT", "5671")),
    User = list_to_binary(os:getenv("AMQP_USER")),
    Password = list_to_binary(os:getenv("AMQP_PASSWORD")),
    CAFile = os:getenv("AMQP_CAFILE"),
    Config0 = #{
        address => Host,
        port => Port,
        sasl => {plain, User, Password},
        container_id => <<"rmq-amqp10-smoke">>,
        notify => self()
    },
    Config = case os:getenv("AMQP_TLS", "1") of
        "0" ->
            Config0;
        _ ->
            Config0#{
                tls_opts => {secure_port, [
                    {cacertfile, CAFile},
                    {verify, verify_peer},
                    {server_name_indication, Host}
                ]}
            }
    end,
    {ok, Connection} = amqp10_client:open_connection(Config),
    receive
        {amqp10_event, {connection, Connection, opened}} ->
            Connection;
        {amqp10_event, {connection, Connection, {closed, Why}}} ->
            error({connection_closed, Why})
    after 30000 ->
        error(connection_timeout)
    end.

await_link(Link, Event, Timeout) ->
    receive
        {amqp10_event, {link, Link, Event}} ->
            ok;
        {amqp10_event, {link, Link, {detached, Why}}} ->
            error({link_detached, Why})
    after Timeout ->
        error({link_event_timeout, Event})
    end.
