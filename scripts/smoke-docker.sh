#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

IMAGE="${1:?usage: smoke-docker.sh IMAGE}"
DOCKER="${DOCKER:-docker}"
CONTAINER="rmq-smoke-$RANDOM-$$"
NETWORK="rmq-smoke-network-$RANDOM-$$"
TMPDIR_LOCAL="$(mktemp -d "${TMPDIR:-/tmp}/rmq-smoke.XXXXXX")"
USER_NAME="rmq_smoke"
USER_PASSWORD="rmq-smoke-$RANDOM-$RANDOM"
SSL_PREFIX="${SSL_PREFIX:-/opt/openssl}"
SSL_KIND="${SSL_KIND:-openssl}"
SSL_VERSION_PATTERN="${SSL_VERSION_PATTERN:-OpenSSL 3.5.9}"
SSL_LICENSE_NAME="${SSL_LICENSE_NAME:-openssl}"
GM_STORAGE="${GM_STORAGE:-0}"
EXPECTED_VARIANT="${EXPECTED_VARIANT:-openeuler}"

cleanup() {
    "$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true
    "$DOCKER" network rm "$NETWORK" >/dev/null 2>&1 || true
    rm -rf "$TMPDIR_LOCAL"
}

on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        printf 'RMQ smoke test failed (exit %s); collecting diagnostics\n' \
            "$exit_code" >&2
        "$DOCKER" ps -a >&2 || true
        "$DOCKER" logs --tail 200 "$CONTAINER" >&2 || true
        "$DOCKER" exec "$CONTAINER" \
            rabbitmq-diagnostics -q listeners >&2 || true
    fi
    cleanup
}
trap on_exit EXIT

require_command "$DOCKER"
require_command openssl

run_client() {
    local mode="$1"
    shift
    "$DOCKER" run --rm \
        --network "$NETWORK" \
        -e AMQP_HOST=rmq-test \
        -e AMQP_USER="$USER_NAME" \
        -e AMQP_PASSWORD="$USER_PASSWORD" \
        -e RMQ_HOST=rmq-test \
        -e RMQ_USER="$USER_NAME" \
        -e RMQ_PASSWORD="$USER_PASSWORD" \
        -e RMQ_CAFILE=/certs/ca.crt \
        -e AMQP_CAFILE=/certs/ca.crt \
        -v "$ROOT_DIR/test/smoke:/test:ro" \
        -v "$TMPDIR_LOCAL/certs:/certs:ro" \
        "$@" \
        "$TEST_PYTHON_IMAGE" \
        bash -c "python -m pip install --no-cache-dir --require-hashes -q -r /test/requirements.txt && python /test/client.py $mode"
}

wait_for_rabbitmq() {
    for _ in $(seq 1 90); do
        listeners="$(
            "$DOCKER" exec "$CONTAINER" \
                rabbitmq-diagnostics -q listeners 2>/dev/null || true
        )"
        if [[ "$listeners" == *"port: 15671,"* ]] &&
            [[ "$listeners" == *"port: 15672,"* ]] &&
            [[ "$listeners" == *"port: 15692,"* ]]; then
            return 0
        fi
        sleep 2
    done
    "$DOCKER" logs --tail 120 "$CONTAINER" >&2 || true
    die "RabbitMQ did not become healthy"
}

bash "$ROOT_DIR/test/smoke/generate-certs.sh" "$TMPDIR_LOCAL/certs"

"$DOCKER" network create "$NETWORK" >/dev/null

server_args=(
    --detach
    --name "$CONTAINER"
    --hostname rmq-test
    --network "$NETWORK"
    --network-alias rmq-test
    -e RABBITMQ_DEFAULT_USER="$USER_NAME"
    -e RABBITMQ_DEFAULT_PASS="$USER_PASSWORD"
    -v "$TMPDIR_LOCAL/certs:/etc/rabbitmq/certs:ro"
    -v "$ROOT_DIR/test/smoke/rabbitmq-tls.conf:/etc/rabbitmq/conf.d/99-tls.conf:ro"
)
server_command=(rabbitmq-server)

if [ "$GM_STORAGE" = "1" ]; then
    printf '%064d\n' 0 > "$TMPDIR_LOCAL/gm.key"
    server_args+=(
        --entrypoint /bin/bash
        -v "$TMPDIR_LOCAL/gm.key:/etc/rabbitmq/gm.key:ro"
    )
    server_command=(
        -c 'set -e; rabbitmq-plugins enable --offline rabbitmq_gm >/dev/null; exec docker-entrypoint.sh rabbitmq-server'
    )
fi

"$DOCKER" run "${server_args[@]}" "$IMAGE" "${server_command[@]}" >/dev/null

wait_for_rabbitmq

# shellcheck disable=SC2016
"$DOCKER" exec \
    -e SSL_PREFIX="$SSL_PREFIX" \
    -e SSL_KIND="$SSL_KIND" \
    -e SSL_VERSION_PATTERN="$SSL_VERSION_PATTERN" \
    -e SSL_LICENSE_NAME="$SSL_LICENSE_NAME" \
    -e GM_STORAGE="$GM_STORAGE" \
    "$CONTAINER" bash -c '
    set -euxo pipefail
    test "$(readlink /plugins)" = "/opt/rabbitmq/plugins"
    test -f /etc/rabbitmq/conf.d/10-defaults.conf
    grep -q "^loopback_users.guest = true$" /etc/rabbitmq/conf.d/10-defaults.conf
    test ! -e /etc/rabbitmq/conf.d/20-management_agent.disable_metrics_collector.conf
    test -f /usr/local/bin/rabbitmqadmin
    test -x /usr/local/bin/rabbitmqadmin
    test -f /usr/local/share/rmq/build-info.json
    test -f /usr/local/share/rmq/LICENSE
    test -f /usr/local/share/rmq/THIRD_PARTY_NOTICES.md
    test -f /opt/rabbitmq/LICENSE-MPL-2.0
    test -f "$SSL_PREFIX/share/licenses/$SSL_LICENSE_NAME/LICENSE.txt"
    test -f /opt/erlang/share/licenses/erlang-otp/LICENSE.txt
    test ! -d "$SSL_PREFIX/include"
    ! command -v gcc >/dev/null 2>&1
    ! command -v make >/dev/null 2>&1
    ssl_version="$("$SSL_PREFIX/bin/openssl" version)"
    [[ "$ssl_version" == "$SSL_VERSION_PATTERN"* ]]
    /opt/erlang/bin/erl -noshell -eval "ok = crypto:start(), init:stop()."
    enabled_plugins="$(rabbitmq-plugins list -e)"
    [[ "$enabled_plugins" == *rabbitmq_management* ]]
    [[ "$enabled_plugins" == *rabbitmq_prometheus* ]]
    if [ "$GM_STORAGE" = "1" ]; then
        [[ "$enabled_plugins" == *rabbitmq_gm* ]]
        crypto_caps="$("/opt/erlang/bin/erl" -noshell -eval \
            "ok = crypto:start(), io:format(\"~p~n\", [crypto:supports()]), init:stop().")"
        [[ "$crypto_caps" == *sm3* ]]
        [[ "$crypto_caps" == *sm4_gcm* ]]
        sm2_key="$("$SSL_PREFIX/bin/openssl" ecparam -genkey -name SM2 2>/dev/null)"
        [[ "$sm2_key" == *"PRIVATE KEY"* ]]
        sm3_digest="$(printf rmq-sm3 | "$SSL_PREFIX/bin/openssl" dgst -sm3 -hex)"
        [[ "$sm3_digest" =~ [0-9a-f]{64} ]]
        "$SSL_PREFIX/bin/openssl" ciphers -v ECDHE-SM2-SM4-GCM-SM3 \
            | grep -q NTLSv1.1
        gm_crypto="$("/opt/erlang/bin/erl" -noshell -eval \
            "ok = crypto:start(), \
             Key = <<0:128>>, \
             Nonce = <<0:96>>, \
             Plain = <<103,109,45,99,104,101,99,107>>, \
             {Cipher, Tag} = crypto:crypto_one_time_aead(\
               sm4_gcm, Key, Nonce, Plain, <<>>, 16, true), \
             Plain = crypto:crypto_one_time_aead(\
               sm4_gcm, Key, Nonce, Cipher, <<>>, Tag, false), \
             true = is_binary(crypto:mac(hmac, sm3, Key, Nonce)), \
             io:format(\"sm4-gcm-sm3-ok~n\"), \
             init:stop().")"
        [[ "$gm_crypto" == *sm4-gcm-sm3-ok* ]]
    fi
    rabbitmq_version="$(rabbitmqctl version)"
    [[ "$rabbitmq_version" == *"4.4.0"* ]]
    if ! rabbitmqadmin --help >/dev/null 2>/tmp/rmq-admin-help; then
        cat /tmp/rmq-admin-help >&2
        exit 1
    fi
    rm -f /tmp/rmq-admin-help
'

test "$("$DOCKER" exec "$CONTAINER" ps -o user= -p 1 | xargs)" = "rabbitmq"

# shellcheck disable=SC2016
"$DOCKER" exec -e SSL_PREFIX="$SSL_PREFIX" "$CONTAINER" bash -c '
    find /opt/erlang -type f -name crypto.so -exec ldd {} \; \
        | awk -v prefix="$SSL_PREFIX" "/libcrypto.so/ { if (!index(\$0, prefix \"/lib\")) exit 1 }"
'

test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.User}}')" = ""
test "$("$DOCKER" inspect "$CONTAINER" --format '{{json .Config.Healthcheck}}')" = "null"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.Entrypoint}}')" = "[docker-entrypoint.sh]"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.Cmd}}')" = "[rabbitmq-server]"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.security.guest-loopback-only"}}')" = "true"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.variant"}}')" = "$EXPECTED_VARIANT"
if [ "$GM_STORAGE" = "1" ]; then
    test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.gm.storage-plugin-enabled"}}')" = "true"
    test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.gm.tls"}}')" = "false"
fi

"$DOCKER" exec "$CONTAINER" grep -q 'openEuler 24.03 (LTS-SP4)' /etc/os-release

if [ "$GM_STORAGE" = "1" ]; then
    GM_BODY="rmq-gm-storage-marker-$RANDOM"
    run_client publish -e AMQP_BODY="$GM_BODY"
    sleep 2
    if "$DOCKER" exec "$CONTAINER" \
        grep -R -a -l "$GM_BODY" /var/lib/rabbitmq/mnesia >/dev/null; then
        die "GM plaintext marker found in the message store"
    fi
else
    run_client publish
fi
"$DOCKER" restart "$CONTAINER" >/dev/null
wait_for_rabbitmq
if [ "$GM_STORAGE" = "1" ]; then
    run_client consume \
        -e AMQP_BODY="$GM_BODY" \
        -e AMQP_PORT=5671 \
        -e AMQP_TLS=1
else
    run_client consume \
        -e AMQP_PORT=5671 \
        -e AMQP_TLS=1
fi
run_client http-checks

printf 'RMQ smoke test passed for %s\n' "$IMAGE"
