-module(rabbitmq_gm_crypto).

-export([load_config/0, encrypt/2, decrypt/4, decrypt/5]).

-define(TAG_LENGTH, 16).
-define(IV_LENGTH, 12).
-define(KEY_LENGTH, 16).

load_config() ->
    KeyFile = os:getenv("RMQ_GM_KEY_FILE"),
    Path = case KeyFile of
               false -> "/etc/rabbitmq/gm.key";
               Value -> Value
           end,
    KeyId = case os:getenv("RMQ_GM_KEY_ID") of
                false -> <<"v1">>;
                Id -> list_to_binary(Id)
            end,
    case file:read_file(Path) of
        {ok, Raw} ->
            case parse_key(Raw) of
                {ok, MasterKey} ->
                    case supported() of
                        ok ->
                            {ok, #{master_key => MasterKey, key_id => KeyId}};
                        {error, _} = Error ->
                            Error
                    end;
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error, {key_file, Path, Reason}}
    end.

supported() ->
    Hashs = crypto:supports(hashs),
    Ciphers = crypto:supports(ciphers),
    case lists:member(sm3, Hashs) andalso lists:member(sm4_gcm, Ciphers) of
        true ->
            ok;
        false ->
            {error, {unsupported_crypto, #{sm3 => lists:member(sm3, Hashs),
                                           sm4_gcm => lists:member(sm4_gcm, Ciphers)}}}
    end.

parse_key(Raw0) ->
    Raw = strip_line_ending(Raw0),
    case byte_size(Raw) of
        64 ->
            case decode_hex(Raw) of
                {ok, Key} when byte_size(Key) =:= 32 -> {ok, Key};
                _ -> {error, invalid_hex_key}
            end;
        32 ->
            {ok, Raw};
        _ ->
            {error, {invalid_key_length, byte_size(Raw)}}
    end.

strip_line_ending(Bin) ->
    case byte_size(Bin) of
        0 ->
            Bin;
        N ->
            case binary:at(Bin, N - 1) of
                $\n ->
                    Trimmed = binary:part(Bin, 0, N - 1),
                    case byte_size(Trimmed) of
                        0 -> Trimmed;
                        M ->
                            case binary:at(Trimmed, M - 1) of
                                $\r -> binary:part(Trimmed, 0, M - 1);
                                _ -> Trimmed
                            end
                    end;
                $\r ->
                    binary:part(Bin, 0, N - 1);
                _ ->
                    Bin
            end
    end.

decode_hex(Bin) ->
    decode_hex(Bin, <<>>).

decode_hex(<<>>, Acc) ->
    {ok, Acc};
decode_hex(<<A, B, Rest/binary>>, Acc) ->
    case {hex_digit(A), hex_digit(B)} of
        {A1, B1} when is_integer(A1), is_integer(B1) ->
            decode_hex(Rest, <<Acc/binary, (A1 bsl 4 bor B1)>>);
        _ ->
            error
    end.

hex_digit(C) when C >= $0, C =< $9 -> C - $0;
hex_digit(C) when C >= $a, C =< $f -> C - $a + 10;
hex_digit(C) when C >= $A, C =< $F -> C - $A + 10;
hex_digit(_) -> error.

encrypt(Plain, #{master_key := MasterKey, key_id := KeyId}) ->
    Nonce = crypto:strong_rand_bytes(?IV_LENGTH),
    Key = derive_key(MasterKey, Nonce),
    Aad = aad(KeyId, Nonce),
    {Cipher, Tag} = crypto:crypto_one_time_aead(
                      sm4_gcm, Key, Nonce, Plain, Aad, ?TAG_LENGTH, true),
    {Cipher, Nonce, Tag}.

decrypt(Cipher, Nonce, Tag, Config) ->
    decrypt(Cipher, Nonce, Tag, maps:get(key_id, Config), Config).

decrypt(Cipher, Nonce, Tag, KeyId, #{master_key := MasterKey,
                                     key_id := KeyId}) ->
    Key = derive_key(MasterKey, Nonce),
    Aad = aad(KeyId, Nonce),
    case crypto:crypto_one_time_aead(
           sm4_gcm, Key, Nonce, Cipher, Aad, Tag, false) of
        error -> error;
        Plain when is_binary(Plain) -> {ok, Plain}
    end;
decrypt(_Cipher, _Nonce, _Tag, _KeyId, _Config) ->
    error.

derive_key(MasterKey, Nonce) ->
    <<Key:?KEY_LENGTH/binary, _/binary>> =
        crypto:mac(hmac, sm3, MasterKey, Nonce),
    Key.

aad(KeyId, Nonce) ->
    <<"rmq-gm-v1:", KeyId/binary, ":", Nonce/binary>>.
