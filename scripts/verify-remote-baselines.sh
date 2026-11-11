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
    local actual=""
    local attempt

    for attempt in 1 2 3; do
        if actual="$(crane digest "$tag_ref")"; then
            break
        fi
        [ "$attempt" -lt 3 ] || die "$name digest lookup failed after 3 attempts"
        printf '[retry] %s digest lookup failed; retrying in 5 seconds\n' "$name" >&2
        sleep 5
    done
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
check_reference "Playwright test image" "$PLAYWRIGHT_IMAGE" \
    "${PLAYWRIGHT_IMAGE##*@}"
