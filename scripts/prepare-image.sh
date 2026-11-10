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
ssl_prefix="${SSL_PREFIX:-/opt/openssl}"
ssl_kind="${SSL_KIND:-openssl}"
ssl_version="${SSL_VERSION:-${OPENSSL_VERSION}}"
gm_plugin_available="${GM_PLUGIN_AVAILABLE:-false}"

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
mkdir -p "$ssl_prefix/etc/ssl"
rm -rf "$ssl_prefix/etc/ssl/certs" "$ssl_prefix/etc/ssl/private"
ln -sfn /etc/ssl/certs "$ssl_prefix/etc/ssl/certs"
ln -sfn /etc/ssl/private "$ssl_prefix/etc/ssl/private"
if [ "$ssl_kind" = "openssl" ] &&
    [ -f "$ssl_prefix/etc/ssl/openssl.cnf" ] &&
    [ -f "$ssl_prefix/etc/ssl/fipsmodule.cnf" ]; then
    sed -i.ORIG \
        -e "/\.include.*fips/ s!.*!.include $ssl_prefix/etc/ssl/fipsmodule.cnf!" \
        -e '/# fips =/s/.*/fips = fips_sect/' \
        "$ssl_prefix/etc/ssl/openssl.cnf"
    sed -i.ORIG -e '/^activate/s/^/#/' \
        "$ssl_prefix/etc/ssl/fipsmodule.cnf"
fi

ldconfig
openssl version

rm -rf \
    "$ssl_prefix/include" \
    "$ssl_prefix/lib/pkgconfig" \
    "$ssl_prefix/share/doc" \
    "$ssl_prefix/share/man"
find "$ssl_prefix/lib" -maxdepth 1 -type f -name '*.a' -delete
rm -f \
    "$ssl_prefix/etc/ssl/openssl.cnf.ORIG" \
    "$ssl_prefix/etc/ssl/fipsmodule.cnf.ORIG"

cp /opt/rmq/stage/10-defaults.conf /etc/rabbitmq/conf.d/10-defaults.conf
chown rabbitmq:rabbitmq /etc/rabbitmq/conf.d/10-defaults.conf
chmod 0644 /etc/rabbitmq/conf.d/10-defaults.conf

plugins=(rabbitmq_management rabbitmq_prometheus rabbitmq_amqp1_0)
if [ "$gm_plugin_available" = "true" ]; then
    test -d "$rabbitmq_home/plugins/rabbitmq_gm-${RABBITMQ_VERSION}" \
        || die "rabbitmq_gm plugin directory is missing"
    plugins+=(rabbitmq_gm)
fi
gosu rabbitmq rabbitmq-plugins enable --offline "${plugins[@]}"

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
    | awk -v prefix="$ssl_prefix" '/libcrypto\.so/ { if (!index($0, prefix)) exit 1 }'

cat > /usr/local/share/rmq/build-info.json <<EOF
{
  "project": "RMQ",
  "version": "${RMQ_VERSION}",
  "upstream": {
    "rabbitmq": "${RABBITMQ_VERSION}",
    "erlangOtp": "${OTP_VERSION}",
    "ssl": {
      "kind": "${ssl_kind}",
      "version": "${ssl_version}"
    }
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
    "amqp10Enabled": true,
    "builtInHealthcheck": false,
    "gmStoragePluginAvailable": ${gm_plugin_available}
  },
  "claims": {
    "openEulerDistribution": true,
    "amqp10Enabled": true,
    "nationalCryptographyTls": false,
    "nationalCryptographyStorage": ${gm_plugin_available},
    "nationalCryptographyAmqp10Storage": ${gm_plugin_available},
    "fipsCompliance": false,
    "clusterTested": false
  }
}
EOF

rm -rf /opt/rmq
