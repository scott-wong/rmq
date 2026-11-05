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

"$DOCKER" run --detach \
    --name "$CONTAINER" \
    --hostname rmq-test \
    --network "$NETWORK" \
    --network-alias rmq-test \
    -e RABBITMQ_DEFAULT_USER="$USER_NAME" \
    -e RABBITMQ_DEFAULT_PASS="$USER_PASSWORD" \
    -v "$TMPDIR_LOCAL/certs:/etc/rabbitmq/certs:ro" \
    -v "$ROOT_DIR/test/smoke/rabbitmq-tls.conf:/etc/rabbitmq/conf.d/99-tls.conf:ro" \
    "$IMAGE" >/dev/null

wait_for_rabbitmq

# shellcheck disable=SC2016
"$DOCKER" exec "$CONTAINER" bash -c '
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
    test -f /opt/openssl/share/licenses/openssl/LICENSE.txt
    test -f /opt/erlang/share/licenses/erlang-otp/LICENSE.txt
    test ! -d /opt/openssl/include
    ! command -v gcc >/dev/null 2>&1
    ! command -v make >/dev/null 2>&1
    openssl_version="$(/opt/openssl/bin/openssl version)"
    [[ "$openssl_version" == "OpenSSL 3.5.9 "* ]]
    /opt/erlang/bin/erl -noshell -eval "ok = crypto:start(), init:stop()."
    enabled_plugins="$(rabbitmq-plugins list -e)"
    [[ "$enabled_plugins" == *rabbitmq_management* ]]
    [[ "$enabled_plugins" == *rabbitmq_prometheus* ]]
    rabbitmq_version="$(rabbitmqctl version)"
    [[ "$rabbitmq_version" == *"4.4.0"* ]]
    rabbitmqadmin --help >/dev/null
'

test "$("$DOCKER" exec "$CONTAINER" ps -o user= -p 1 | xargs)" = "rabbitmq"

# shellcheck disable=SC2016
"$DOCKER" exec "$CONTAINER" bash -c '
    find /opt/erlang -type f -name crypto.so -exec ldd {} \; \
        | awk "/libcrypto.so/ { if (!index(\$0, \"/opt/openssl/lib\")) exit 1 }"
'

test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.User}}')" = ""
test "$("$DOCKER" inspect "$CONTAINER" --format '{{json .Config.Healthcheck}}')" = "null"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.Entrypoint}}')" = "[docker-entrypoint.sh]"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{.Config.Cmd}}')" = "[rabbitmq-server]"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.security.guest-loopback-only"}}')" = "true"
test "$("$DOCKER" inspect "$CONTAINER" --format '{{index .Config.Labels "io.rmq.variant"}}')" = "openeuler"

"$DOCKER" exec "$CONTAINER" grep -q 'openEuler 24.03 (LTS-SP4)' /etc/os-release

run_client publish
"$DOCKER" restart "$CONTAINER" >/dev/null
wait_for_rabbitmq
run_client consume \
    -e AMQP_PORT=5671 \
    -e AMQP_TLS=1
run_client http-checks

printf 'RMQ smoke test passed for %s\n' "$IMAGE"
