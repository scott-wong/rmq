# Security policy

RMQ reports security issues against the container distribution in this
repository. Upstream RabbitMQ, Erlang/OTP, OpenSSL/Tongsuo and openEuler package
vulnerabilities remain the responsibility of their respective projects.

Do not open a public issue for an undisclosed vulnerability. Contact the
repository owner privately through the security contact configured on GitHub.
Include the affected RMQ version, image digest, reproduction steps and whether
the issue applies to the official RabbitMQ image.

## Deployment boundary

- `guest` is restricted to loopback by default.
- No default password is included in the image or Compose example.
- `RABBITMQ_DEFAULT_*` is a development/CI convenience. Production deployments
  should provision users through controlled configuration/definitions and a
  secret manager.
- The container entrypoint starts as root only to repair the data volume and,
  in the Tongsuo variant, stage the read-only GM key under `/run/rmq` with
  ownership `rabbitmq`. It immediately re-executes as the `rabbitmq` UID. The
  broker process itself is non-root. RMQ intentionally preserves this
  official-image behavior, so a Dockerfile misconfiguration scanner reports the
  expected `DS-0002` waiver.
- The image does not define `HEALTHCHECK`.
- Cluster operation, Kubernetes deployment and national cryptography transport
  are not validated.
- FIPS mode is not claimed even though the OpenSSL build includes a FIPS
  provider.

Security reports that require modifying upstream RabbitMQ behavior should
state whether the same behavior exists in the official image.

## Tongsuo default variant

- The default Tongsuo `8.5.0` variant uses a `3.5.4` OpenSSL source baseline.
  RMQ has not audited CVE parity with the historical standard variant's OpenSSL
  `3.5.9`; do not treat the two builds as equivalent from a
  vulnerability-response standpoint.
- `rabbitmq_gm` implements SM4-GCM encryption of AMQP 0-9-1 bodies and AMQP 1.0
  `data`, `amqp-value`, and `amqp-sequence` bodies. Queue indexes, Mnesia,
  headers, properties, application properties, annotations, footers, routing
  keys, the data directory, and the key file are not covered. This is not
  full-disk encryption.
- AMQP 1.0 support requires `rabbitmq_amqp1_0`. The plugin rejects an
  unrecognized AMQP 1.0 body layout before enqueueing it rather than silently
  storing plaintext.
- The plugin trusts broker-owned `mc` annotations, not client-supplied AMQP
  headers. Do not add a header-based bypass or a “decrypt on failure” fallback
  without a new threat-model review.
- A valid 32-byte key (or 64-hex-character key) is required. The current design
  supports one master key. Key rotation, external KMS, key destruction, and
  operator audit trails are not implemented.
- `rabbitmq_gm` is a vendor plugin targeting RabbitMQ `4.4.x` internals
  (`mc`, `rabbit_msg_interceptor`). Upstream upgrades require rebuilding and
  regression testing; it is not an upstream-supported extension contract.
- The default variant does not implement or claim TLCP, SM2 dual-certificate
  transport, management TLCP, node-to-node national cryptography, cluster
  behavior, Kubernetes operation, FIPS, or Chinese commercial cryptography
  product certification. Standard TLS/AMQPS/HTTPS smoke coverage is not TLCP
  evidence.
- The Tongsuo build enables `enable-ntls` and verifies the library cipher list;
  that is a library capability check, not a completed application handshake.
