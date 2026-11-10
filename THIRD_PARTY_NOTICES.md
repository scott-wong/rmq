# Third-party notices

RMQ combines independently licensed components. The root `LICENSE` applies to
RMQ-owned scripts, documentation and configuration, not to upstream components.

| Component | Version | License | Source |
|---|---:|---|---|
| RabbitMQ server and bundled plugins | 4.4.0 | MPL-2.0; selected files Apache-2.0 | https://github.com/rabbitmq/rabbitmq-server/releases/tag/v4.4.0 |
| Erlang/OTP | 29.1.2 | Apache-2.0 | https://github.com/erlang/otp/releases/tag/OTP-29.1.2 |
| OpenSSL | 3.5.9 | Apache-2.0 | https://github.com/openssl/openssl/releases/tag/openssl-3.5.9 |
| Tongsuo (experimental variant) | 8.5.0; OpenSSL 3.5.4 source baseline | Apache-2.0 | https://github.com/Tongsuo-Project/Tongsuo/releases/tag/8.5.0 |
| gosu | 1.20 | Apache-2.0 | https://github.com/tianon/gosu/tree/1.20 |
| rabbitmqadmin-ng | 2.35.0 | Apache-2.0 OR MIT | https://github.com/rabbitmq/rabbitmqadmin-ng/releases/tag/v2.35.0 |
| `rabbitmq_gm` plugin | 4.4.0 | Apache-2.0 | This repository |
| openEuler base packages | 24.03 LTS SP4 | Per-package RPM metadata | https://repo.openeuler.org/openEuler-24.03-LTS-SP4/ |
| docker-library/RabbitMQ scripts | 4.4 branch | MIT | https://github.com/docker-library/rabbitmq/blob/master/LICENSE |

The standard image preserves the license files shipped inside the RabbitMQ
archive under `/opt/rabbitmq`, along with OpenSSL's license under
`/opt/openssl/share/licenses` and the complete Erlang/OTP `LICENSES` set under
`/opt/erlang/share/licenses`. The Tongsuo experimental variant instead ships the
Tongsuo Apache-2.0 text at `/opt/tongsuo/share/licenses/tongsuo/LICENSE.txt`;
Syft's SBOM records the OpenSSL `3.5.4` source baseline as a property, not as a
separately linked OpenSSL `3.5.9` component. The MIT text for the upstream Docker scripts from
which RMQ's entrypoint behavior was adapted is reproduced at
`licenses/docker-library-rabbitmq-MIT.txt`.

The Apache License 2.0 text is reproduced in the repository root `LICENSE`. The
MPL 2.0 license shipped by RabbitMQ is included by the upstream generic
Unix archive and distributed with the resulting image.

No upstream trademark, certification or support relationship is claimed. The
RMQ name identifies this independent container build.
