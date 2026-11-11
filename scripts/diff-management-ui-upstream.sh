#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

upstream_root="${1:?usage: diff-management-ui-upstream.sh RABBITMQ_SERVER_CHECKOUT}"
upstream_www="$upstream_root/deps/rabbitmq_management/priv/www"
fork_www="$ROOT_DIR/packaging/management-ui/www"

test -d "$upstream_www" || die "upstream management UI not found: $upstream_www"
test -d "$fork_www" || die "RMQ management UI not found: $fork_www"
require_command diff

printf 'Upstream: %s\n' "$upstream_www"
printf 'Fork:     %s\n\n' "$fork_www"

diff --brief --recursive "$upstream_www" "$fork_www" || true
