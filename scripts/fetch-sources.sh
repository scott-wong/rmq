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

    if [ -f "$target" ] && [ "$(sha256_file "$target")" = "$expected" ]; then
        printf '[ok] %s\n' "$name"
        return 0
    fi

    printf '[fetch] %s\n' "$name"
    curl --fail --location --retry 5 --retry-all-errors \
        --output "$target.part" "$url"
    verify_sha256 "$target.part" "$expected"
    mv "$target.part" "$target"
    printf '[ok] %s\n' "$name"
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
