#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

version="$(tr -d ' \n' < "$ROOT_DIR/VERSION")"

[[ "$version" =~ ^${RABBITMQ_VERSION}\-rmq\.[0-9]+$ ]] \
    || die "VERSION must be ${RABBITMQ_VERSION}-rmq.<N>, got: $version"

for variable in OPENSSL_SHA256 OTP_SHA256 GOSU_SOURCE_SHA256 \
    RABBITMQ_TARBALL_SHA256 RABBITMQADMIN_SHA256 TONGSHUO_SHA256 \
    COSIGN_SHA256 SYFT_SHA256 TRIVY_SHA256 CRANE_SHA256; do
    value="${!variable}"
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] \
        || die "$variable must be a lowercase SHA256"
done

[[ "$TONGSHUO_VERSION" == "8.5.0" ]] \
    || die "TONGSHUO_VERSION must be the reviewed 8.5.0 baseline"
[[ "$TONGSHUO_OPENSSL_VERSION" == "3.5.4" ]] \
    || die "TONGSHUO_OPENSSL_VERSION must match the reviewed Tongsuo source baseline"
[[ "$TONGSHUO_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
    || die "TONGSHUO_COMMIT must be a lowercase git commit"

[[ "$OPENEULER_BASE" == *"@$OPENEULER_BASE_DIGEST" ]] \
    || die "OPENEULER_BASE tag and digest disagree"
[[ "$OPENEULER_BASE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "invalid openEuler digest"
[[ "$GOLANG_BASE" == *"@sha256:"* ]] \
    || die "GOLANG_BASE must be digest-pinned"
[[ "$TEST_PYTHON_IMAGE" == *"@sha256:"* ]] \
    || die "TEST_PYTHON_IMAGE must be digest-pinned"

while IFS= read -r -d '' script; do
    bash -n "$script"
    if [ ! -x "$script" ]; then
        case "$script" in
            */docker-entrypoint.sh) ;;
            *) die "shell script is not executable: ${script#"$ROOT_DIR"/}" ;;
        esac
    fi
    printf '[ok] bash %s\n' "${script#"$ROOT_DIR"/}"
done < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/test" "$ROOT_DIR/packaging" \
    -type f -name '*.sh' -print0)

python3 - "$ROOT_DIR" <<'PY'
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.py"):
    if "distfiles" in path.parts:
        continue
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    print(f"[ok] python {path.relative_to(root)}")
PY

if command -v ruby >/dev/null 2>&1; then
    while IFS= read -r -d '' file; do
        ruby -ryaml -e 'YAML.load_file(ARGV.fetch(0))' "$file"
        printf '[ok] yaml %s\n' "${file#"$ROOT_DIR"/}"
    done < <(find "$ROOT_DIR" \
        -path "$ROOT_DIR/distfiles" -prune -o \
        -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
else
    printf '[skip] Ruby YAML parser unavailable\n'
fi

dockerfile="$ROOT_DIR/packaging/docker/Dockerfile"
[ -f "$dockerfile" ] || die "Dockerfile missing"
! grep -qE '^FROM[[:space:]]+(rabbitmq|ubuntu)' "$dockerfile" \
    || die "Dockerfile must not derive from RabbitMQ or Ubuntu images"
grep -q 'AS rmq-final' "$dockerfile" \
    || die "Dockerfile is missing the rmq-final target"
grep -q 'CMD \["rabbitmq-server"\]' "$dockerfile" \
    || die "Dockerfile must preserve the rabbitmq-server CMD"
! grep -q '^HEALTHCHECK' "$dockerfile" \
    || die "RMQ must not define a built-in HEALTHCHECK"
grep -q 'io.rmq.security.guest-loopback-only="true"' "$dockerfile" \
    || die "missing secure-default OCI label"

tongsuo_dockerfile="$ROOT_DIR/packaging/docker/Dockerfile.tongsuo"
[ -f "$tongsuo_dockerfile" ] || die "Tongsuo Dockerfile missing"
! grep -qE '^FROM[[:space:]]+(rabbitmq|ubuntu)' "$tongsuo_dockerfile" \
    || die "Tongsuo Dockerfile must not derive from RabbitMQ or Ubuntu images"
grep -q 'AS rmq-tongsuo-final' "$tongsuo_dockerfile" \
    || die "Tongsuo Dockerfile is missing the rmq-tongsuo-final target"
grep -q 'CMD \["rabbitmq-server"\]' "$tongsuo_dockerfile" \
    || die "Tongsuo Dockerfile must preserve the rabbitmq-server CMD"
! grep -q '^HEALTHCHECK' "$tongsuo_dockerfile" \
    || die "RMQ must not define a built-in HEALTHCHECK"
grep -q 'SSL_PREFIX=/opt/tongsuo' "$tongsuo_dockerfile" \
    || die "Tongsuo Dockerfile must link the runtime to /opt/tongsuo"
grep -q 'io.rmq.gm.tls="false"' "$tongsuo_dockerfile" \
    || die "Tongsuo variant must explicitly mark TLS+GM as not implemented"
grep -q 'COPY --from=gm-plugin-builder' "$tongsuo_dockerfile" \
    || die "Tongsuo Dockerfile must install the GM plugin"

plugin_dir="$ROOT_DIR/packaging/plugin/rabbitmq_gm"
[ -f "$plugin_dir/src/rabbitmq_gm.app" ] || die "GM plugin app file missing"
[ -f "$plugin_dir/src/rabbitmq_gm_msg_interceptor.erl" ] \
    || die "GM plugin interceptor missing"
grep -q 'mc:set_annotation' "$plugin_dir/src/rabbitmq_gm_msg_interceptor.erl" \
    || die "GM plugin must use broker annotations for encrypted metadata"
grep -q 'mc:take_annotation' "$plugin_dir/src/rabbitmq_gm_msg_interceptor.erl" \
    || die "GM plugin must clear broker annotations before delivery"
! grep -q 'headers_for_decryption' "$plugin_dir/src/rabbitmq_gm_msg_interceptor.erl" \
    || die "GM plugin must not trust client-controlled headers"

defaults="$ROOT_DIR/packaging/rabbitmq/10-defaults.conf"
grep -q '^loopback_users.guest = true$' "$defaults" \
    || die "guest loopback restriction missing"
grep -q '^log.console = true$' "$defaults" \
    || die "console logging default missing"

[ ! -e "$ROOT_DIR/examples/docker-compose/rmq-single/.env" ] \
    || die "example contains a live .env file"
[ -f "$ROOT_DIR/examples/docker-compose/rmq-single/.env.example" ] \
    || die "example .env.example is missing"

if grep -RInE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*["'\''])' \
    "$ROOT_DIR/README.md" \
    "$ROOT_DIR/examples" \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/packaging" \
    "$ROOT_DIR/test" \
    "$ROOT_DIR/docs" 2>/dev/null; then
    die "possible secret material found in tracked project files"
fi

printf 'Static checks passed for RMQ %s\n' "$version"
