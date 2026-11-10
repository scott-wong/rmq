-module(rabbitmq_gm_msg_interceptor).

-behaviour(rabbit_msg_interceptor).

-include("rabbit.hrl").
-include("rabbit_framing.hrl").

-export([intercept/4]).

-define(ANN_MARKER, rmq_gm_marker).
-define(ANN_ALG, rmq_gm_alg).
-define(ANN_KEY_ID, rmq_gm_key_id).
-define(ANN_NONCE, rmq_gm_nonce).
-define(ANN_TAG, rmq_gm_tag).

intercept(Msg, Ctx, Stage, Config) ->
    case maps:get(protocol, Ctx, undefined) =:= amqp091 andalso is_amqpl_message(Msg) of
        true -> transform(Stage, Msg, Config);
        false -> Msg
    end.

transform(incoming, Msg, Config) ->
    case mc:get_annotation(?ANN_MARKER, Msg) of
        undefined -> encrypt_message(Msg, Config);
        _ -> Msg
    end;
transform(outgoing, Msg, Config) ->
    case decryption_annotations(Msg) of
        {ok, KeyId, Nonce, Tag} ->
            decrypt_message(Msg, Config, KeyId, Nonce, Tag);
        error ->
            Msg
    end;
transform(_, Msg, _Config) ->
    Msg.

is_amqpl_message(Msg) when is_tuple(Msg), tuple_size(Msg) =:= 4 ->
    element(1, Msg) =:= mc andalso element(2, Msg) =:= mc_amqpl;
is_amqpl_message(_) ->
    false.

message_content(Msg) ->
    element(3, Msg).

set_message_content(Msg, Content) ->
    setelement(3, Msg, Content).

encrypt_message(Msg, Config) ->
    Content = message_content(Msg),
    case encrypt_content(Content, Config) of
        {ok, EncryptedContent, Nonce, Tag} ->
            KeyId = maps:get(key_id, Config),
            Msg1 = set_message_content(Msg, EncryptedContent),
            Msg2 = mc:set_annotation(?ANN_MARKER, true, Msg1),
            Msg3 = mc:set_annotation(?ANN_ALG, <<"SM4-GCM-SM3">>, Msg2),
            Msg4 = mc:set_annotation(?ANN_KEY_ID, KeyId, Msg3),
            Msg5 = mc:set_annotation(?ANN_NONCE, Nonce, Msg4),
            mc:set_annotation(?ANN_TAG, Tag, Msg5);
        error ->
            Msg
    end.

encrypt_content(#content{payload_fragments_rev = PFR} = Content,
                Config) ->
    Plain = iolist_to_binary(lists:reverse(PFR)),
    {Cipher, Nonce, Tag} = rabbitmq_gm_crypto:encrypt(Plain, Config),
    {ok, Content#content{payload_fragments_rev = [Cipher]}, Nonce, Tag};
encrypt_content(_Content, _Config) ->
    error.

decrypt_message(Msg, Config, KeyId, Nonce, Tag) ->
    Content = message_content(Msg),
    case decrypt_content(Content, Config, KeyId, Nonce, Tag) of
        {ok, PlainContent} ->
            Msg1 = set_message_content(Msg, PlainContent),
            clear_annotations(Msg1);
        error ->
            logger:error("rabbitmq_gm: unable to decrypt a persisted message"),
            Msg
    end.

decrypt_content(#content{payload_fragments_rev = PFR} = Content,
                Config, KeyId, Nonce, Tag) ->
    Cipher = iolist_to_binary(lists:reverse(PFR)),
    case rabbitmq_gm_crypto:decrypt(Cipher, Nonce, Tag, KeyId, Config) of
        {ok, Plain} ->
            {ok, Content#content{payload_fragments_rev = [Plain]}};
        error ->
            error
    end;
decrypt_content(_Content, _Config, _KeyId, _Nonce, _Tag) ->
    error.

decryption_annotations(Msg) ->
    case {mc:get_annotation(?ANN_MARKER, Msg),
          mc:get_annotation(?ANN_KEY_ID, Msg),
          mc:get_annotation(?ANN_NONCE, Msg),
          mc:get_annotation(?ANN_TAG, Msg)} of
        {true, KeyId, Nonce, Tag} when is_binary(KeyId),
                                is_binary(Nonce),
                                is_binary(Tag) ->
            {ok, KeyId, Nonce, Tag};
        _ ->
            error
    end.

clear_annotations(Msg) ->
    {_, Msg1} = mc:take_annotation(?ANN_MARKER, Msg),
    {_, Msg2} = mc:take_annotation(?ANN_ALG, Msg1),
    {_, Msg3} = mc:take_annotation(?ANN_KEY_ID, Msg2),
    {_, Msg4} = mc:take_annotation(?ANN_NONCE, Msg3),
    {_, Msg5} = mc:take_annotation(?ANN_TAG, Msg4),
    Msg5.
