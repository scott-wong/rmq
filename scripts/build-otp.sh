#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command gcc
require_command make
require_command tar

archive="$DISTFILES_DIR/otp_src_${OTP_VERSION}.tar.gz"
verify_sha256 "$archive" "$OTP_SHA256"

prefix="/opt/erlang"
openssl_prefix="${SSL_PREFIX:-/opt/openssl}"
source_dir="/tmp/rmq-otp-${OTP_VERSION}"

rm -rf "$source_dir" "$prefix"
mkdir -p "$source_dir" "$prefix"
tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cd "$source_dir"
export ERL_TOP="$source_dir"
export PATH="$openssl_prefix/bin:$PATH"
export CFLAGS="-O2 -g -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security"
export LDFLAGS="-Wl,-rpath,$openssl_prefix/lib -Wl,-z,relro -Wl,-z,now"

host_arch="$(gcc -dumpmachine)"
build_arch="$host_arch"

./configure \
    --prefix="$prefix" \
    --host="$host_arch" \
    --build="$build_arch" \
    --disable-hipe \
    --disable-sctp \
    --disable-silent-rules \
    --enable-builtin-zlib \
    --enable-clock-gettime \
    --enable-hybrid-heap \
    --enable-jit \
    --enable-kernel-poll \
    --enable-smp-support \
    --enable-threads \
    --with-microstate-accounting=extra \
    --with-ssl="$openssl_prefix" \
    --without-common_test \
    --without-debugger \
    --without-dialyzer \
    --without-diameter \
    --without-edoc \
    --without-erl_docgen \
    --without-et \
    --without-eunit \
    --without-ftp \
    --without-hipe \
    --without-jinterface \
    --without-megaco \
    --without-observer \
    --without-odbc \
    --without-reltool \
    --without-snmp \
    --without-ssh \
    --without-tftp \
    --without-wx

make -j"$(nproc)" GEN_OPT_FLGS="-O2 -fno-strict-aliasing"
make install

find "$prefix/lib/erlang" -type d -name examples -exec rm -rf '{}' +
find "$prefix/lib/erlang" -type d -name src -exec rm -rf '{}' +
find "$prefix/lib/erlang" -type d -name include -exec rm -rf '{}' +

export PATH="$prefix/bin:$PATH"

crypto_objects="$(find "$prefix" -type f -name crypto.so)"
test -n "$crypto_objects"
find "$prefix" -type f -name crypto.so -exec ldd '{}' \; \
    | awk -v prefix="$openssl_prefix" '/libcrypto\.so/ { if (!index($0, prefix)) exit 1 }'
erl -noshell -eval \
    'ok = crypto:start(), ok = io:format("~p~n", [crypto:supports()]), init:stop().' \
    >/dev/null

mkdir -p "$prefix/share/licenses/erlang-otp"
cp "$source_dir/LICENSE.txt" "$prefix/share/licenses/erlang-otp/LICENSE.txt"
mkdir -p "$prefix/share/licenses/erlang-otp/LICENSES"
cp -a "$source_dir/LICENSES/." "$prefix/share/licenses/erlang-otp/LICENSES/"
