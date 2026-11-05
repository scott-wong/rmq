#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:?output directory is required}"
mkdir -p "$output_dir"

openssl genpkey \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:3072 \
    -out "$output_dir/ca.key" >/dev/null 2>&1
openssl req -x509 -new -sha256 -days 2 \
    -key "$output_dir/ca.key" \
    -subj "/CN=RMQ smoke CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$output_dir/ca.crt"

openssl genpkey \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:3072 \
    -out "$output_dir/server.key" >/dev/null 2>&1
openssl req -new -sha256 \
    -key "$output_dir/server.key" \
    -subj "/CN=rmq-test" \
    -out "$output_dir/server.csr"

cat > "$output_dir/server.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:rmq-test
EOF

openssl x509 -req -sha256 -days 2 \
    -in "$output_dir/server.csr" \
    -CA "$output_dir/ca.crt" \
    -CAkey "$output_dir/ca.key" \
    -CAcreateserial \
    -extfile "$output_dir/server.ext" \
    -out "$output_dir/server.crt"

chmod 0644 "$output_dir"/*.crt "$output_dir"/ca.key "$output_dir"/server.key
