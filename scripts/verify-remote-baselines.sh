#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command crane

check_reference() {
    local name="$1"
    local pinned="$2"
    local expected="$3"
    local tag_ref="${pinned%%@*}"
    local actual

    actual="$(crane digest "$tag_ref")"
    [[ "$actual" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || die "$name returned an invalid digest: $actual"
    [ "$actual" = "$expected" ] \
        || die "$name drift: pinned $expected, registry currently returns $actual"
    printf '[ok] %s %s\n' "$name" "$actual"
}

check_reference "openEuler base" "$OPENEULER_BASE" "$OPENEULER_BASE_DIGEST"
check_reference "Go builder base" "$GOLANG_BASE" \
    "${GOLANG_BASE##*@}"
check_reference "Python test image" "$TEST_PYTHON_IMAGE" \
    "${TEST_PYTHON_IMAGE##*@}"
