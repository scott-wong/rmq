#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command openssl
require_command useradd
require_command groupadd
require_command gosu
require_command erl

rabbitmq_home="/opt/rabbitmq"
rabbitmq_data_dir="/var/lib/rabbitmq"
openssl_prefix="/opt/openssl"

groupadd --gid 999 --system rabbitmq
useradd --uid 999 --system \
    --gid rabbitmq \
    --home-dir "$rabbitmq_data_dir" \
    --shell /usr/sbin/nologin \
    rabbitmq

mkdir -p \
    "$rabbitmq_data_dir" \
    /etc/rabbitmq/conf.d \
    /tmp/rabbitmq-ssl \
    /var/log/rabbitmq \
    /usr/local/share/rmq/licenses

chown -R rabbitmq:rabbitmq "$rabbitmq_home"
chown -fR rabbitmq:rabbitmq \
    "$rabbitmq_data_dir" \
    /etc/rabbitmq \
    /etc/rabbitmq/conf.d \
    /tmp/rabbitmq-ssl \
    /var/log/rabbitmq
chmod 1777 \
    "$rabbitmq_data_dir" \
    /etc/rabbitmq \
    /etc/rabbitmq/conf.d \
    /tmp/rabbitmq-ssl \
    /var/log/rabbitmq

ln -sf "$rabbitmq_data_dir/.erlang.cookie" /root/.erlang.cookie
ln -sf "$rabbitmq_home/plugins" /plugins

mkdir -p /etc/ssl/private
rm -rf "$openssl_prefix/etc/ssl/certs" "$openssl_prefix/etc/ssl/private"
ln -sfn /etc/ssl/certs "$openssl_prefix/etc/ssl/certs"
ln -sfn /etc/ssl/private "$openssl_prefix/etc/ssl/private"
sed -i.ORIG \
    -e "/\.include.*fips/ s!.*!.include $openssl_prefix/etc/ssl/fipsmodule.cnf!" \
    -e '/# fips =/s/.*/fips = fips_sect/' \
    "$openssl_prefix/etc/ssl/openssl.cnf"
sed -i.ORIG -e '/^activate/s/^/#/' \
    "$openssl_prefix/etc/ssl/fipsmodule.cnf"

ldconfig
openssl version

rm -rf \
    /opt/openssl/include \
    /opt/openssl/lib/pkgconfig \
    /opt/openssl/share/doc \
    /opt/openssl/share/man
find /opt/openssl/lib -maxdepth 1 -type f -name '*.a' -delete
rm -f \
    /opt/openssl/etc/ssl/openssl.cnf.ORIG \
    /opt/openssl/etc/ssl/fipsmodule.cnf.ORIG

cp /opt/rmq/stage/10-defaults.conf /etc/rabbitmq/conf.d/10-defaults.conf
chown rabbitmq:rabbitmq /etc/rabbitmq/conf.d/10-defaults.conf
chmod 0644 /etc/rabbitmq/conf.d/10-defaults.conf

gosu rabbitmq rabbitmq-plugins enable --offline \
    rabbitmq_management rabbitmq_prometheus

[ ! -e "$rabbitmq_data_dir/.erlang.cookie" ] || rm -f "$rabbitmq_data_dir/.erlang.cookie"
gosu rabbitmq rabbitmqctl help >/dev/null
gosu rabbitmq rabbitmqctl list_ciphers >/dev/null
gosu rabbitmq rabbitmq-plugins list >/dev/null
gosu rabbitmq rabbitmqadmin --help >/dev/null

erl -noshell -eval \
    'ok = crypto:start(), ok = io:format("~p~n", [crypto:supports()]), init:stop().' \
    >/dev/null

crypto_objects="$(find /opt/erlang -type f -name crypto.so)"
test -n "$crypto_objects"
find /opt/erlang -type f -name crypto.so -exec ldd '{}' \; \
    | awk -v prefix="$openssl_prefix" '/libcrypto\.so/ { if (!index($0, prefix)) exit 1 }'

cat > /usr/local/share/rmq/build-info.json <<EOF
{
  "project": "RMQ",
  "version": "${RMQ_VERSION}",
  "upstream": {
    "rabbitmq": "${RABBITMQ_VERSION}",
    "erlangOtp": "${OTP_VERSION}",
    "openssl": "${OPENSSL_VERSION}"
  },
  "tools": {
    "gosu": "${GOSU_VERSION}",
    "rabbitmqadmin": "${RABBITMQADMIN_VERSION}"
  },
  "base": {
    "image": "quay.io/openeuler/openeuler:${OPENEULER_RELEASE}",
    "digest": "${OPENEULER_BASE_DIGEST}"
  },
  "securityDefaults": {
    "guestLoopbackOnly": true,
    "managementEnabled": true,
    "prometheusEnabled": true,
    "builtInHealthcheck": false
  },
  "claims": {
    "openEulerDistribution": true,
    "nationalCryptography": false,
    "fipsCompliance": false,
    "clusterTested": false
  }
}
EOF

rm -rf /opt/rmq
