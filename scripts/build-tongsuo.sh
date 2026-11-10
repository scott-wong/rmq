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

archive="$DISTFILES_DIR/tongsuo-${TONGSHUO_VERSION}.tar.gz"
verify_sha256 "$archive" "$TONGSHUO_SHA256"

prefix="/opt/tongsuo"
source_dir="/tmp/rmq-tongsuo-${TONGSHUO_VERSION}"

rm -rf "$source_dir" "$prefix"
mkdir -p "$source_dir" "$prefix"
tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cd "$source_dir"

./config \
    shared \
    enable-ntls \
    --prefix="$prefix" \
    --openssldir="$prefix/etc/ssl" \
    --libdir="$prefix/lib" \
    -Wl,-rpath,"$prefix/lib"

make -j"$(nproc)"
make install_sw install_ssldirs

mkdir -p "$prefix/share/licenses/tongsuo"
cp "$source_dir/LICENSE.txt" "$prefix/share/licenses/tongsuo/LICENSE.txt"

ldconfig
"$prefix/bin/openssl" version | grep -q '^Tongsuo: Tongsuo 8.5.0 ' \
    || {
        printf 'ERROR: unexpected Tongsuo version output\n' >&2
        exit 1
    }
test -s "$prefix/lib/libssl.so.3"
test -s "$prefix/lib/libcrypto.so.3"
"$prefix/bin/openssl" ciphers -v ECDHE-SM2-SM4-GCM-SM3 \
    | grep -q 'NTLSv1.1'
