#!/usr/bin/env bash
set -euo pipefail

# Preserve the upstream RabbitMQ image behavior: root is used only to repair
# the named data volume and then the process is re-executed as rabbitmq.
if [[ "${1:-}" == rabbitmq* ]] && [ "$(id -u)" = '0' ]; then
    key_file="${RMQ_GM_KEY_FILE:-/etc/rabbitmq/gm.key}"
    if [ "${GM_PLUGIN_AVAILABLE:-false}" = "true" ] && [ ! -f "$key_file" ]; then
        printf 'error: GM storage encryption is enabled but %s is missing\n' \
            "$key_file" >&2
        exit 1
    fi
    if [ -f "$key_file" ]; then
        mkdir -p /run/rmq
        chown rabbitmq:rabbitmq /run/rmq
        chmod 0700 /run/rmq
        cp "$key_file" /run/rmq/gm.key
        chown rabbitmq:rabbitmq /run/rmq/gm.key
        chmod 0600 /run/rmq/gm.key
        export RMQ_GM_KEY_FILE=/run/rmq/gm.key
    fi
    if [ "$1" = 'rabbitmq-server' ]; then
        find /var/lib/rabbitmq \! -user rabbitmq -exec chown rabbitmq '{}' +
    fi

    exec gosu rabbitmq /usr/local/bin/docker-entrypoint.sh "$@"
fi

deprecated_env_vars=(
    RABBITMQ_DEFAULT_PASS_FILE
    RABBITMQ_DEFAULT_USER_FILE
    RABBITMQ_MANAGEMENT_SSL_CACERTFILE
    RABBITMQ_MANAGEMENT_SSL_CERTFILE
    RABBITMQ_MANAGEMENT_SSL_DEPTH
    RABBITMQ_MANAGEMENT_SSL_FAIL_IF_NO_PEER_CERT
    RABBITMQ_MANAGEMENT_SSL_KEYFILE
    RABBITMQ_MANAGEMENT_SSL_VERIFY
    RABBITMQ_SSL_CACERTFILE
    RABBITMQ_SSL_CERTFILE
    RABBITMQ_SSL_DEPTH
    RABBITMQ_SSL_FAIL_IF_NO_PEER_CERT
    RABBITMQ_SSL_KEYFILE
    RABBITMQ_SSL_VERIFY
    RABBITMQ_VM_MEMORY_HIGH_WATERMARK
)

found_deprecated_env=
for name in "${deprecated_env_vars[@]}"; do
    if [ -n "${!name:-}" ]; then
        printf 'error: %s is set but deprecated\n' "$name" >&2
        found_deprecated_env=1
    fi
done

if [ -n "$found_deprecated_env" ]; then
    printf 'error: deprecated environment variables detected\n\n' >&2
    printf 'Use a RabbitMQ configuration file instead: https://www.rabbitmq.com/docs/configure\n' >&2
    exit 1
fi

if [ -z "${RABBITMQ_USE_LONGNAME:-}" ] && [ "$(hostname)" != "$(hostname -s)" ]; then
    : "${RABBITMQ_USE_LONGNAME:=true}"
fi

exec "$@"
