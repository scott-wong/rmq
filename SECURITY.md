# Security policy

RMQ reports security issues against the container distribution in this
repository. Upstream RabbitMQ, Erlang/OTP, OpenSSL and openEuler package
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
- The container entrypoint starts as root only to repair the data volume and
  immediately re-executes as the `rabbitmq` UID. The broker process itself is
  non-root. RMQ intentionally preserves this official-image behavior, so a
  Dockerfile misconfiguration scanner reports the expected `DS-0002` waiver.
- The image does not define `HEALTHCHECK`.
- Cluster operation, Kubernetes deployment and national cryptography are not
  validated in the first release.
- FIPS mode is not claimed even though the OpenSSL build includes a FIPS
  provider.

Security reports that require modifying upstream RabbitMQ behavior should
state whether the same behavior exists in the official image.
