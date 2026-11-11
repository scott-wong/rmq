#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

IMAGE="${1:?usage: smoke-docker.sh IMAGE}"
DOCKER="${DOCKER:-docker}"
RMQ_VERSION="${RMQ_VERSION:-$(tr -d ' \n' < "$ROOT_DIR/VERSION")}"
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
UI_TEST="${UI_TEST:-0}"
UI_ARTIFACTS_DIR="${UI_ARTIFACTS_DIR:-$ROOT_DIR/artifacts/ui}"

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

run_amqp10() {
    local mode="$1"
    local prefix="$2"
    "$DOCKER" exec \
        -e AMQP_HOST=rmq-test \
        -e AMQP_PORT=5671 \
        -e AMQP_USER="$USER_NAME" \
        -e AMQP_PASSWORD="$USER_PASSWORD" \
        -e AMQP_CAFILE=/etc/rabbitmq/certs/ca.crt \
        -e ERL_LIBS=/opt/rabbitmq/plugins \
        "$CONTAINER" \
        escript /test/amqp10_smoke.escript "$mode" "$AMQP10_QUEUE" "$prefix"
}

run_management_ui() {
    test "$UI_TEST" = "1" || return 0
    mkdir -p "$UI_ARTIFACTS_DIR"
    "$DOCKER" run --rm \
        --network "$NETWORK" \
        -e RMQ_HOST=rmq-test \
        -e RMQ_PORT=15671 \
        -e RMQ_USER="$USER_NAME" \
        -e RMQ_PASSWORD="$USER_PASSWORD" \
        -e RMQ_VERSION="$RMQ_VERSION" \
        -e UI_ARTIFACTS_DIR=/artifacts \
        -v "$ROOT_DIR/test/ui:/test:ro" \
        -v "$UI_ARTIFACTS_DIR:/artifacts" \
        "$PLAYWRIGHT_IMAGE" \
        python /test/test_management_ui.py
}

inspect_image_format() {
    "$DOCKER" image inspect "$IMAGE" --format "$1" 2>/dev/null ||
        printf 'INSPECT_ERROR'
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
    -v "$ROOT_DIR/test/smoke:/test:ro"
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
    set -euo pipefail
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
    [[ "$enabled_plugins" == *rabbitmq_amqp1_0* ]]
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
    exit 0
'

printf 'smoke: static checks passed\n'
test "$("$DOCKER" exec "$CONTAINER" ps -o user= -p 1 | xargs)" = "rabbitmq"
printf 'smoke: process user check passed\n'

# shellcheck disable=SC2016
"$DOCKER" exec -e SSL_PREFIX="$SSL_PREFIX" "$CONTAINER" bash -c '
    find /opt/erlang -type f -name crypto.so -exec ldd {} \; \
        | awk -v prefix="$SSL_PREFIX" "/libcrypto.so/ { if (!index(\$0, prefix \"/lib\")) exit 1 }"
'
printf 'smoke: Tongsuo linkage check passed\n'

printf 'smoke metadata: user=%s entrypoint=%s cmd=%s health=%s guest=%s variant=%s gm-enabled=%s gm-tls=%s\n' \
    "$(inspect_image_format '{{.Config.User}}')" \
    "$(inspect_image_format '{{.Config.Entrypoint}}')" \
    "$(inspect_image_format '{{.Config.Cmd}}')" \
    "$(inspect_image_format '{{json .Config.Healthcheck}}')" \
    "$(inspect_image_format '{{index .Config.Labels "io.rmq.security.guest-loopback-only"}}')" \
    "$(inspect_image_format '{{index .Config.Labels "io.rmq.variant"}}')" \
    "$(inspect_image_format '{{index .Config.Labels "io.rmq.gm.storage-plugin-enabled"}}')" \
    "$(inspect_image_format '{{index .Config.Labels "io.rmq.gm.tls"}}')"

test "$(inspect_image_format '{{.Config.User}}')" = ""
test "$(inspect_image_format '{{json .Config.Healthcheck}}')" = "null"
test "$(inspect_image_format '{{.Config.Entrypoint}}')" = "[docker-entrypoint.sh]"
test "$(inspect_image_format '{{.Config.Cmd}}')" = "[rabbitmq-server]"
test "$(inspect_image_format '{{index .Config.Labels "io.rmq.security.guest-loopback-only"}}')" = "true"
test "$(inspect_image_format '{{index .Config.Labels "io.rmq.variant"}}')" = "$EXPECTED_VARIANT"
test "$(inspect_image_format '{{index .Config.Labels "io.rmq.amqp10.enabled"}}')" = "true"
if [ "$GM_STORAGE" = "1" ]; then
    test "$(inspect_image_format '{{index .Config.Labels "io.rmq.gm.storage-plugin-enabled"}}')" = "true"
    test "$(inspect_image_format '{{index .Config.Labels "io.rmq.gm.amqp10-body-encryption"}}')" = "true"
    test "$(inspect_image_format '{{index .Config.Labels "io.rmq.gm.tls"}}')" = "false"
fi
printf 'smoke: image metadata checks passed\n'

"$DOCKER" exec "$CONTAINER" grep -q 'openEuler 24.03 (LTS-SP4)' /etc/os-release
printf 'smoke: OS check passed\n'

if [ "$GM_STORAGE" = "1" ]; then
    GM_BODY="rmq-gm-storage-marker-$RANDOM"
    AMQP10_QUEUE="rmq.gm.amqp10"
    AMQP10_PREFIX="rmq-gm-amqp10-$RANDOM"
    run_client publish -e AMQP_BODY="$GM_BODY"
    printf 'smoke: GM publish passed\n'
    run_client declare -e AMQP_QUEUE="$AMQP10_QUEUE"
    run_amqp10 publish "$AMQP10_PREFIX"
    printf 'smoke: AMQP 1.0 GM publish passed\n'
    sleep 2
    set +e
    "$DOCKER" exec "$CONTAINER" \
        grep -R -a -l \
        -e "$GM_BODY" \
        -e "$AMQP10_PREFIX-data" \
        -e "$AMQP10_PREFIX-value" \
        -e "$AMQP10_PREFIX-sequence" \
        /var/lib/rabbitmq/mnesia >/dev/null
    grep_rc=$?
    set -e
    if [ "$grep_rc" -eq 0 ]; then
        die "GM plaintext marker found in the message store"
    elif [ "$grep_rc" -ne 1 ]; then
        die "GM plaintext scan failed with exit $grep_rc"
    fi
    printf 'smoke: AMQP 0-9-1 and AMQP 1.0 plaintext absent from store\n'
else
    run_client publish
    printf 'smoke: standard publish passed\n'
fi
"$DOCKER" restart "$CONTAINER" >/dev/null
wait_for_rabbitmq
printf 'smoke: restart passed\n'
if [ "$GM_STORAGE" = "1" ]; then
    run_client consume \
        -e AMQP_BODY="$GM_BODY" \
        -e AMQP_PORT=5671 \
        -e AMQP_TLS=1
    printf 'smoke: AMQP 0-9-1 TLS consume passed\n'
    run_amqp10 consume "$AMQP10_PREFIX"
    printf 'smoke: AMQP 1.0 TLS consume passed\n'
else
    run_client consume \
        -e AMQP_PORT=5671 \
        -e AMQP_TLS=1
    printf 'smoke: standard TLS consume passed\n'
fi
run_client http-checks
printf 'smoke: management and metrics checks passed\n'
run_management_ui
if [ "$UI_TEST" = "1" ]; then
    printf 'smoke: management UI browser checks passed\n'
fi

printf 'RMQ smoke test passed for %s\n' "$IMAGE"
