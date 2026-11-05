#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command curl
mkdir -p "$DISTFILES_DIR"

download() {
    local name="$1"
    local url="$2"
    local expected="$3"
    local target="$DISTFILES_DIR/$name"
    local attempt

    if [ -f "$target" ] && [ "$(sha256_file "$target")" = "$expected" ]; then
        printf '[ok] %s\n' "$name"
        return 0
    fi

    for attempt in $(seq 1 3); do
        printf '[fetch] %s (attempt %s/3)\n' "$name" "$attempt"
        rm -f "$target.part"
        if curl --fail --location \
            --connect-timeout 20 \
            --max-time 900 \
            --retry 12 \
            --retry-delay 5 \
            --retry-max-time 180 \
            --output "$target.part" "$url"; then
            verify_sha256 "$target.part" "$expected"
            mv "$target.part" "$target"
            printf '[ok] %s\n' "$name"
            return 0
        fi
        rm -f "$target.part"
        if [ "$attempt" -lt 3 ]; then
            printf '[retry] %s download failed; backing off 20 seconds\n' "$name" >&2
            sleep 20
        fi
    done

    die "failed to download $name after 3 attempts"
}

download "gosu-${GOSU_VERSION}.tar.gz" \
    "$GOSU_SOURCE_URL" "$GOSU_SOURCE_SHA256"
download "openssl-${OPENSSL_VERSION}.tar.gz" \
    "$OPENSSL_URL" "$OPENSSL_SHA256"
download "otp_src_${OTP_VERSION}.tar.gz" \
    "$OTP_URL" "$OTP_SHA256"
download "rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz" \
    "$RABBITMQ_TARBALL_URL" "$RABBITMQ_TARBALL_SHA256"
download "rabbitmqadmin-${RABBITMQADMIN_VERSION}" \
    "$RABBITMQADMIN_URL" "$RABBITMQADMIN_SHA256"

printf 'All source archives verified in %s\n' "$DISTFILES_DIR"
