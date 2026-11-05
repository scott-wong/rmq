#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command gcc
require_command make
require_command perl
require_command tar

archive="$DISTFILES_DIR/openssl-${OPENSSL_VERSION}.tar.gz"
verify_sha256 "$archive" "$OPENSSL_SHA256"

prefix="/opt/openssl"
source_dir="/tmp/rmq-openssl-${OPENSSL_VERSION}"

rm -rf "$source_dir" "$prefix"
mkdir -p "$source_dir" "$prefix"
tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cd "$source_dir"

# Keep upstream's FIPS provider build, but do not claim FIPS validation.
./Configure \
    linux-x86_64 \
    enable-fips \
    --prefix="$prefix" \
    --openssldir="$prefix/etc/ssl" \
    --libdir="$prefix/lib" \
    -Wl,-rpath,"$prefix/lib"

make -j"$(nproc)"
make install_sw install_ssldirs install_fips

ldconfig
"$prefix/bin/openssl" version
test -s "$prefix/lib/libssl.so.3"
test -s "$prefix/lib/libcrypto.so.3"
mkdir -p "$prefix/share/licenses/openssl"
cp "$source_dir/LICENSE.txt" "$prefix/share/licenses/openssl/LICENSE.txt"
