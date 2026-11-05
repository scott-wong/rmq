#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$ROOT_DIR/scripts/baseline.env"
DISTFILES_DIR="${DISTFILES_DIR:-$ROOT_DIR/distfiles}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        die "sha256sum or shasum is required"
    fi
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    [ -f "$file" ] || die "file not found: $file"
    actual="$(sha256_file "$file")"
    [ "$actual" = "$expected" ] || die "SHA256 mismatch for $file: expected $expected, got $actual"
}

source_baseline() {
    [ -f "$BASELINE_FILE" ] || die "baseline not found: $BASELINE_FILE"
    # shellcheck disable=SC1090
    source "$BASELINE_FILE"
}
