# 首版只交付 openEuler amd64 management 镜像

RMQ 首版不复制 `agw` 的双发行版矩阵，也不发布非 management 或 arm64 变体。

## Reasons

- 当前需求是 openEuler 上的 RabbitMQ 4.4 management 容器。
- 单个变体让 OTP/OpenSSL 编译、冒烟和发布证明保持可复核。
- RabbitMQ 集群需要额外的 hostname、cookie、网络和升级验证，不能从单节点
  通过直接外推。

## Consequences

- 不提供全局 `latest`；Tongsuo 默认线提供 `latest-tongsuo-openeuler`，
  历史标准镜像固定使用完整版本 tag。
- 需要新变体时必须先新增独立构建矩阵和验收，不得复用未经验证的镜像标签。
