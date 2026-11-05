# RMQ

RMQ 是一个独立维护的 openEuler RabbitMQ 4.4 management 容器发行版。
项目基于 [RabbitMQ](https://www.rabbitmq.com/)，但**不是 RabbitMQ 官方镜像**，
也不受 RabbitMQ 团队或 openEuler 社区的官方支持。

首版只交付一个镜像：

```text
ghcr.io/scott-wong/rmq:4.4.0-rmq.1-openeuler
```

- `linux/amd64`
- openEuler `24.03 LTS SP4`
- RabbitMQ `4.4.0` management + Prometheus plugins
- Erlang/OTP `29.1.2`
- OpenSSL `3.5.9`
- 单节点验收，不宣称已验证集群或 Kubernetes Operator

## 快速开始

```sh
docker run --detach \
  --hostname rmq-single \
  --name rmq-single \
  --env RABBITMQ_DEFAULT_USER=rmq-admin \
  --env RABBITMQ_DEFAULT_PASS='replace-with-a-long-random-password' \
  --publish 5672:5672 \
  --publish 15672:15672 \
  --publish 15692:15692 \
  --volume rmq-data:/var/lib/rabbitmq \
  ghcr.io/scott-wong/rmq:4.4.0-rmq.1-openeuler
```

管理界面为 `http://127.0.0.1:15672/`，Prometheus 指标为
`http://127.0.0.1:15692/metrics`。

`RABBITMQ_DEFAULT_*` 环境变量适合开发、CI 和首次启动示例；上游文档明确不建议
把它作为生产用户管理方案。生产部署应通过受控的 `rabbitmq.conf`、definitions
或外部密钥管理流程创建用户，避免密码出现在容器环境变量中。

更完整的安全部署起点见
[`examples/docker-compose/rmq-single`](examples/docker-compose/rmq-single/README.md)。

## 与官方镜像的有意差异

上游 Docker 镜像的
[`10-defaults.conf`](https://github.com/docker-library/rabbitmq/blob/master/4.4/ubuntu/10-defaults.conf)
设置 `loopback_users.guest = false`，让默认 `guest/guest` 可从远端登录。RMQ 改为：

```text
loopback_users.guest = true
```

远程使用前必须通过 `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` 或挂载
`rabbitmq.conf` 创建显式账户。该变量由 RabbitMQ 自身读取，不由 RMQ
入口脚本模拟。

RMQ 不内置 `HEALTHCHECK`，与官方镜像一致。Compose 示例提供外部健康检查。

## 运行接口

保留 RabbitMQ 官方容器的核心契约：

- `rabbitmq` 用户/组 UID/GID 均为 `999`
- 数据卷 `/var/lib/rabbitmq`
- `/etc/rabbitmq`、`/etc/rabbitmq/conf.d`、`/plugins`
- 官方入口脚本的 root → rabbitmq 降权和弃用环境变量检查
- `CMD ["rabbitmq-server"]`
- 端口 `4369`、`5671`、`5672`、`15671`、`15672`、`15691`、`15692`、`25672`

入口脚本只负责官方镜像已有的降权和环境变量防护，不自动创建用户或修改 TLS 配置。

RabbitMQ 4.4 在只配置 `management.ssl.*` 时会进入 HTTPS-only 模式，不再启动
15672 明文监听器。若需要同时保留 HTTP 与 HTTPS，须显式设置
`management.tcp.port = 15672`；冒烟测试的 TLS 覆盖配置即采用该方式。

## 版本与标签

`VERSION` 是唯一版本事实源，格式为 `<上游版本>-rmq.<修订号>`。一个正式版本发布：

```text
ghcr.io/scott-wong/rmq:4.4.0-rmq.1-openeuler   # 不可移动的完整版本
ghcr.io/scott-wong/rmq:4.4.0-openeuler         # 上游线别名
ghcr.io/scott-wong/rmq:latest-openeuler        # 浮动别名
```

同一上游版本需要安全重建时 bump `rmq.N`；不覆盖完整版本标签，不提供全局
`4.4.0` 或 `latest`。

## 构建

需要 Linux amd64、Docker Buildx、网络和约 4 GB 临时空间。

```sh
make verify
make fetch
make build IMAGE=rmq:4.4.0-rmq.1-openeuler
make smoke IMAGE=rmq:4.4.0-rmq.1-openeuler
```

所有源码归档版本与 SHA256 集中在
[`scripts/baseline.env`](scripts/baseline.env)。最终镜像不包含编译器、头文件、
源码包或测试依赖。

openEuler 基础镜像按 index digest 固定，但 RPM 的具体 patch level 由签名仓库在
构建时解析，并先应用 `dnf upgrade --security`；因此不同日期重建同一 git commit
不保证字节级相同。每个发布镜像仍按不可变 digest 固定，实际 RPM 集合进入 SBOM。详见
[`docs/adr/0005-signed-floating-rpms.md`](docs/adr/0005-signed-floating-rpms.md)。

## 验收范围

冒烟测试覆盖：

- openEuler 24.03 SP4、amd64、UID/GID 和数据目录权限
- AMQP 发布/消费，以及重启后的持久消息恢复
- 标准 AMQPS 与 management HTTPS
- management HTTP/HTTPS API、UI 与 Prometheus 指标
- guest 远端访问被拒绝
- Erlang crypto 与 `/opt/openssl` 动态链接关系
- management、Prometheus 插件和 `rabbitmqadmin`

未覆盖：多节点集群、Kubernetes、滚动升级、国密/TLCP、FIPS 合规。

## 供应链验证

Release 附件包含 CycloneDX SBOM、Trivy 报告和
`release-manifest.json`。最终镜像 digest 使用 GitHub OIDC keyless
Cosign 签名，并附加 SBOM attestation。

```sh
cosign verify \
  --certificate-identity \
    'https://github.com/scott-wong/rmq/.github/workflows/publish.yml@refs/tags/v4.4.0-rmq.1' \
  --certificate-oidc-issuer \
    'https://token.actions.githubusercontent.com' \
  ghcr.io/scott-wong/rmq:4.4.0-rmq.1-openeuler
```

Trivy 阻断 `HIGH`/`CRITICAL` 中已有修复版本的漏洞与 secret 命中；未修复漏洞仍会
进入报告。当前 Trivy `0.76.1` 把本镜像的 OS family 识别为 `none`，不会扫描
openEuler RPM 的 CVE；阻断范围实际是 Go、Python 等可识别的语言包和 secret。
工作流另附非阻断的 `dnf updateinfo --security` 证据，但它不能替代 openEuler
漏洞数据库。因此 RMQ 不宣称“零漏洞”或“已完成 openEuler 全量安全审计”。

## 国密

首版不实现也不宣称 TLCP/国密套件。RabbitMQ 的 TLS 主要在 Erlang/OTP
`ssl` 层完成，单纯把 OpenSSL 换成 Tongsuo 不能证明原生 TLCP 可用。后续必须分别
验证 AMQP、management HTTPS 和节点互连后，才能新增国密变体。详见
[`docs/adr/0003-defer-national-cryptography.md`](docs/adr/0003-defer-national-cryptography.md)。

## 许可证

RMQ 自有代码使用 Apache License 2.0。镜像内 RabbitMQ 核心为 MPL 2.0，
部分文件为 Apache 2.0；第三方组件和改编来源见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
