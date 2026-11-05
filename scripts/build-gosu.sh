#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command go
require_command tar

archive="$DISTFILES_DIR/gosu-${GOSU_VERSION}.tar.gz"
verify_sha256 "$archive" "$GOSU_SOURCE_SHA256"

build_dir="/tmp/rmq-gosu-${GOSU_VERSION}"
rm -rf "$build_dir"
mkdir -p "$build_dir" /out
tar --extract --gzip --file "$archive" \
    --directory "$build_dir" --strip-components 1

cd "$build_dir"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -buildvcs=false \
    -ldflags '-d -w -buildid=' \
    -o /out/gosu .

/out/gosu --version
