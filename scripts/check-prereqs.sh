#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_command "${DOCKER:-docker}"
require_command curl

"${DOCKER:-docker}" buildx version >/dev/null

if [ ! -d "$DISTFILES_DIR" ]; then
    die "distfiles missing; run make fetch first"
fi
