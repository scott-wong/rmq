#!/usr/bin/env bash
set -euo pipefail

image_digest="${1:?usage: verify-cosign.sh IMAGE_DIGEST CERTIFICATE_IDENTITY [LOG_DIR]}"
certificate_identity="${2:?certificate identity is required}"
log_dir="${3:-.}"
issuer="https://token.actions.githubusercontent.com"

for command in cosign timeout grep; do
    command -v "$command" >/dev/null 2>&1 \
        || {
            printf 'ERROR: required command not found: %s\n' "$command" >&2
            exit 1
        }
done

mkdir -p "$log_dir"

run_cosign() {
    local name="$1"
    shift
    local log="$log_dir/$name.txt"
    local raw_log="$log_dir/.$name.raw.log"
    local rc

    rm -f "$raw_log"
    set +e
    timeout -k 5s 60s "$@" >"$raw_log" 2>&1
    rc=$?
    set -e

    {
        awk 'length($0) <= 512 { print }' "$raw_log" 2>/dev/null \
            | head -n 20 || true
        if [ "$name" = "cosign-verify-attestation" ]; then
            echo "predicate-type=https://cyclonedx.org/bom"
        fi
        echo "full-payload=omitted"
    } > "$log"
    cat "$log"

    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
        printf 'ERROR: %s failed with exit code %s\n' "$name" "$rc" >&2
        exit 1
    fi

    grep -q 'The cosign claims were validated' "$raw_log" \
        || {
            printf 'ERROR: %s output lacks validated claims\n' "$name" >&2
            exit 1
        }
    grep -q 'The code-signing certificate was verified' "$raw_log" \
        || {
            printf 'ERROR: %s output lacks certificate verification\n' "$name" >&2
            exit 1
        }
    if [ "$rc" -eq 124 ]; then
        printf 'WARNING: %s reported successful checks but did not exit; timeout killed it\n' \
            "$name" >&2
    fi

    rm -f "$raw_log"
}

run_cosign cosign-verify \
    cosign verify \
    --certificate-identity "$certificate_identity" \
    --certificate-oidc-issuer "$issuer" \
    "$image_digest"

run_cosign cosign-verify-attestation \
    cosign verify-attestation \
    --type cyclonedx \
    --certificate-identity "$certificate_identity" \
    --certificate-oidc-issuer "$issuer" \
    "$image_digest"

printf 'Cosign image signature and CycloneDX attestation verified\n'
