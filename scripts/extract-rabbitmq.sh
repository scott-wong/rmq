#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command tar
require_command xz

archive="$DISTFILES_DIR/rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz"
verify_sha256 "$archive" "$RABBITMQ_TARBALL_SHA256"

rabbitmq_home="/opt/rabbitmq"
rm -rf "$rabbitmq_home"
mkdir -p "$rabbitmq_home"
tar --extract --xz --file "$archive" \
    --directory "$rabbitmq_home" --strip-components 1

grep -qE '^SYS_PREFIX=\$\{RABBITMQ_HOME\}$' "$rabbitmq_home/sbin/rabbitmq-defaults"
sed -i 's/^SYS_PREFIX=.*$/SYS_PREFIX=/' "$rabbitmq_home/sbin/rabbitmq-defaults"
grep -qE '^SYS_PREFIX=$' "$rabbitmq_home/sbin/rabbitmq-defaults"
