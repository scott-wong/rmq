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
-define(ANN_AMQP10_BODY_CODE, rmq_gm_amqp10_body_code).
-define(AMQP10_DATA, 16#75).

intercept(Msg, _Ctx, Stage, Config) ->
    case message_protocol(Msg) of
        mc_amqpl ->
            transform_amqpl(Stage, Msg, Config);
        mc_amqp ->
            transform_amqp10(Stage, Msg, Config);
        _ ->
            Msg
    end.

message_protocol(Msg) when is_tuple(Msg), tuple_size(Msg) >= 3 ->
    case element(1, Msg) of
        mc -> element(2, Msg);
        _ -> undefined
    end;
message_protocol(_) ->
    undefined.

transform_amqpl(incoming, Msg, Config) ->
    case mc:get_annotation(?ANN_MARKER, Msg) of
        undefined -> encrypt_amqpl(Msg, Config);
        _ -> Msg
    end;
transform_amqpl(outgoing, Msg, Config) ->
    case decryption_annotations(Msg) of
        {ok, KeyId, Nonce, Tag} ->
            decrypt_amqpl(Msg, Config, KeyId, Nonce, Tag);
        error ->
            Msg
    end;
transform_amqpl(_, Msg, _Config) ->
    Msg.

transform_amqp10(incoming, Msg, Config) ->
    case mc:get_annotation(?ANN_MARKER, Msg) of
        undefined ->
            case encrypt_amqp10(Msg, Config) of
                {ok, Encrypted} ->
                    Encrypted;
                {error, Reason} ->
                    logger:error(
                      "rabbitmq_gm: refusing to store AMQP 1.0 body "
                      "without encryption: ~p", [Reason]),
                    error({rabbitmq_gm, Reason})
            end;
        _ -> Msg
    end;
transform_amqp10(outgoing, Msg, Config) ->
    case decryption_annotations(Msg) of
        {ok, KeyId, Nonce, Tag} ->
            decrypt_amqp10(Msg, Config, KeyId, Nonce, Tag);
        error ->
            Msg
    end;
transform_amqp10(_, Msg, _Config) ->
    Msg.

message_content(Msg) ->
    element(3, Msg).

set_message_content(Msg, Content) ->
    setelement(3, Msg, Content).

encrypt_amqpl(Msg, Config) ->
    Content = message_content(Msg),
    case encrypt_content(Content, Config) of
        {ok, EncryptedContent, Nonce, Tag} ->
            KeyId = maps:get(key_id, Config),
            Msg1 = set_message_content(Msg, EncryptedContent),
            set_encryption_annotations(Msg1, KeyId, Nonce, Tag);
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

decrypt_amqpl(Msg, Config, KeyId, Nonce, Tag) ->
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

encrypt_amqp10(Msg, Config) ->
    case amqp10_body_data(Msg) of
        {ok, Bare, BodyPos, BodyCode, _BodyIndex, _CodeIndex} ->
            Tail = binary_part(Bare, BodyPos, byte_size(Bare) - BodyPos),
            case decode_amqp10_sections(Tail) of
                {ok, BodySections, FooterSections}
                  when BodySections =/= [] ->
                    Plain = term_to_binary(BodySections),
                    {Cipher, Nonce, Tag} =
                        rabbitmq_gm_crypto:encrypt(Plain, Config),
                    KeyId = maps:get(key_id, Config),
                    Prefix = binary_part(Bare, 0, BodyPos),
                    EncodedBody = amqp10_framing:encode_bin(
                                     {'v1_0.data', Cipher}),
                    EncodedFooter = [amqp10_framing:encode_bin(Section)
                                     || Section <- FooterSections],
                    NewBare = iolist_to_binary(
                                [Prefix, EncodedBody | EncodedFooter]),
                    Msg1 = set_amqp10_body(Msg, NewBare, ?AMQP10_DATA),
                    Msg2 = set_encryption_annotations(
                             Msg1, KeyId, Nonce, Tag),
                    {ok, mc:set_annotation(
                           ?ANN_AMQP10_BODY_CODE, BodyCode, Msg2)};
                _ ->
                    {error, unsupported_section_layout}
            end;
        error ->
            {error, unsupported_message_representation}
    end.

decrypt_amqp10(Msg, Config, KeyId, Nonce, Tag) ->
    case amqp10_body_data(Msg) of
        {ok, Bare, BodyPos, _BodyCode, _BodyIndex, _CodeIndex} ->
            Tail = binary_part(Bare, BodyPos, byte_size(Bare) - BodyPos),
            case decode_amqp10_sections(Tail) of
                {ok, [DataSection], FooterSections} ->
                    Cipher = element(2, DataSection),
                    case rabbitmq_gm_crypto:decrypt(
                           Cipher, Nonce, Tag, KeyId, Config) of
                        {ok, Plain} ->
                            restore_amqp10_body(
                              Msg, Plain, Bare, BodyPos, FooterSections);
                        error ->
                            logger:error(
                              "rabbitmq_gm: unable to decrypt AMQP 1.0 message"),
                            Msg
                    end;
                _ ->
                    logger:error(
                      "rabbitmq_gm: unexpected AMQP 1.0 encrypted body"),
                    Msg
            end;
        error ->
            Msg
    end.

restore_amqp10_body(Msg, Plain, Bare, BodyPos, FooterSections) ->
    try binary_to_term(Plain, [safe]) of
        BodySections when is_list(BodySections) ->
            Prefix = binary_part(Bare, 0, BodyPos),
            EncodedBody = [amqp10_framing:encode_bin(Section)
                           || Section <- BodySections],
            EncodedFooter = [amqp10_framing:encode_bin(Section)
                             || Section <- FooterSections],
            NewBare = iolist_to_binary(
                        [Prefix | EncodedBody] ++ EncodedFooter),
            BodyCode = case mc:get_annotation(
                              ?ANN_AMQP10_BODY_CODE, Msg) of
                           Code when is_integer(Code) -> Code;
                           _ -> ?AMQP10_DATA
                       end,
            Msg1 = set_amqp10_body(Msg, NewBare, BodyCode),
            clear_annotations(Msg1);
        _ ->
            Msg
    catch
        _:_ ->
            logger:error("rabbitmq_gm: malformed AMQP 1.0 encrypted body"),
            Msg
    end.

amqp10_body_data(Msg) ->
    case element(3, Msg) of
        {msg_body_encoded, _, _, _, _, Bare, _, BodyPos, BodyCode}
          when tuple_size(element(3, Msg)) =:= 9 ->
            {ok, Bare, BodyPos, BodyCode, 6, 9};
        {v1, _, Bare, _, _, BodyPos, BodyCode}
          when tuple_size(element(3, Msg)) =:= 7 ->
            {ok, Bare, BodyPos, BodyCode, 3, 7};
        _ ->
            error
    end.

set_amqp10_body(Msg, Bare, BodyCode) ->
    Data0 = element(3, Msg),
    case element(1, Data0) of
        msg_body_encoded ->
            Data1 = setelement(6, Data0, Bare),
            setelement(3, Msg, setelement(9, Data1, BodyCode));
        v1 ->
            Data1 = setelement(3, Data0, Bare),
            setelement(3, Msg, setelement(7, Data1, BodyCode))
    end.

decode_amqp10_sections(Tail) ->
    try amqp10_framing:decode_bin(Tail) of
        Sections ->
            Body = [Section || Section <- Sections,
                               is_body_section(Section)],
            Footer = [Section || Section <- Sections,
                                 is_footer_section(Section)],
            case length(Body) + length(Footer) =:= length(Sections) of
                true -> {ok, Body, Footer};
                false -> error
            end
    catch
        _:_ -> error
    end.

is_body_section(Section) when is_tuple(Section), tuple_size(Section) > 0 ->
    case element(1, Section) of
        'v1_0.data' -> true;
        'v1_0.amqp_sequence' -> true;
        'v1_0.amqp_value' -> true;
        _ -> false
    end;
is_body_section(_) ->
    false.

is_footer_section(Section) when is_tuple(Section), tuple_size(Section) > 0 ->
    element(1, Section) =:= 'v1_0.footer';
is_footer_section(_) ->
    false.

set_encryption_annotations(Msg, KeyId, Nonce, Tag) ->
    Msg1 = mc:set_annotation(?ANN_MARKER, true, Msg),
    Msg2 = mc:set_annotation(?ANN_ALG, <<"SM4-GCM-SM3">>, Msg1),
    Msg3 = mc:set_annotation(?ANN_KEY_ID, KeyId, Msg2),
    Msg4 = mc:set_annotation(?ANN_NONCE, Nonce, Msg3),
    mc:set_annotation(?ANN_TAG, Tag, Msg4).

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
    {_, Msg6} = mc:take_annotation(?ANN_AMQP10_BODY_CODE, Msg5),
    Msg6.
