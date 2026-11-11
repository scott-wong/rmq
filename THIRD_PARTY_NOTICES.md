# Third-party notices

RMQ combines independently licensed components. The root `LICENSE` applies to
RMQ-owned scripts, documentation and configuration, not to upstream components.

| Component | Version | License | Source |
|---|---:|---|---|
| RabbitMQ server and bundled plugins | 4.4.0 | MPL-2.0; selected files Apache-2.0 | https://github.com/rabbitmq/rabbitmq-server/releases/tag/v4.4.0 |
| RabbitMQ management console static assets (RMQ fork) | 4.4.0, upstream commit `24d5157c` | MPL-2.0; bundled MIT/BSD/ISC notices | `packaging/management-ui/UPSTREAM.md` |
| Erlang/OTP | 29.1.2 | Apache-2.0 | https://github.com/erlang/otp/releases/tag/OTP-29.1.2 |
| OpenSSL | 3.5.9 | Apache-2.0 | https://github.com/openssl/openssl/releases/tag/openssl-3.5.9 |
| Tongsuo (default variant) | 8.5.0; OpenSSL 3.5.4 source baseline | Apache-2.0 | https://github.com/Tongsuo-Project/Tongsuo/releases/tag/8.5.0 |
| gosu | 1.20 | Apache-2.0 | https://github.com/tianon/gosu/tree/1.20 |
| rabbitmqadmin-ng | 2.35.0 | Apache-2.0 OR MIT | https://github.com/rabbitmq/rabbitmqadmin-ng/releases/tag/v2.35.0 |
| `rabbitmq_gm` plugin | 4.4.0 | Apache-2.0 | This repository |
| openEuler base packages | 24.03 LTS SP4 | Per-package RPM metadata | https://repo.openeuler.org/openEuler-24.03-LTS-SP4/ |
| docker-library/RabbitMQ scripts | 4.4 branch | MIT | https://github.com/docker-library/rabbitmq/blob/master/LICENSE |

The default Tongsuo image preserves the license files shipped inside the
RabbitMQ archive under `/opt/rabbitmq`, including the bundled
`rabbitmq_amqp1_0` and `amqp10_common` plugin files, and the complete
Erlang/OTP `LICENSES` set under `/opt/erlang/share/licenses`. It ships the
Tongsuo Apache-2.0 text at `/opt/tongsuo/share/licenses/tongsuo/LICENSE.txt`;
Syft's SBOM records the OpenSSL `3.5.4` source baseline as a property, not as a
separately linked OpenSSL `3.5.9` component. The MIT text for the upstream Docker scripts from
which RMQ's entrypoint behavior was adapted is reproduced at
`licenses/docker-library-rabbitmq-MIT.txt`.

The Apache License 2.0 text is reproduced in the repository root `LICENSE`. The
MPL 2.0 license shipped by RabbitMQ is included by the upstream generic
Unix archive and distributed with the resulting image.

The default Tongsuo image also ships the management-console fork's upstream
license set under `/usr/local/share/rmq/licenses/rabbitmq-management/`. The
fork's provenance, pristine tree digest and modification summary are recorded
in `packaging/management-ui/UPSTREAM.md`. New RMQ-authored files remain
Apache-2.0; modified upstream static files are distributed under MPL-2.0.

No upstream trademark, certification or support relationship is claimed. The
RMQ name identifies this independent container build.
