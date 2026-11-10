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

# Erlang/OTP 29 includes these legacy OpenSSL headers unconditionally even
# though Tongsuo 8.5 no longer ships them. The compatibility headers only
# declare the corresponding algorithms unavailable; they add no implementation.
compat_include="$prefix/include/openssl"
mkdir -p "$compat_include"
if [ ! -f "$compat_include/md4.h" ]; then
    printf '%s\n' \
        '#ifndef OPENSSL_NO_MD4' \
        '# define OPENSSL_NO_MD4' \
        '#endif' > "$compat_include/md4.h"
fi
if [ ! -f "$compat_include/ripemd.h" ]; then
    printf '%s\n' \
        '#ifndef OPENSSL_NO_RMD160' \
        '# define OPENSSL_NO_RMD160' \
        '#endif' \
        '#ifndef OPENSSL_NO_RIPEMD160' \
        '# define OPENSSL_NO_RIPEMD160' \
        '#endif' \
        '#ifndef OPENSSL_NO_RIPEMD' \
        '# define OPENSSL_NO_RIPEMD' \
        '#endif' > "$compat_include/ripemd.h"
fi
if [ ! -f "$compat_include/blowfish.h" ]; then
    printf '%s\n' \
        '#ifndef OPENSSL_NO_BF' \
        '# define OPENSSL_NO_BF' \
        '#endif' > "$compat_include/blowfish.h"
fi
if [ ! -f "$compat_include/rc2.h" ]; then
    printf '%s\n' \
        '#ifndef OPENSSL_NO_RC2' \
        '# define OPENSSL_NO_RC2' \
        '#endif' > "$compat_include/rc2.h"
fi

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
