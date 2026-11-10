# Tongsuo 成为默认构建，并覆盖 AMQP 1.0 body

## Status

Accepted for `4.4.0-rmq.2`.

## Context

`4.4.0-rmq.1` 已作为 OpenSSL 标准镜像发布，其 tag 和 digest 不可移动。后续产品
方向转为以 Tongsuo 为默认，并要求 `rabbitmq_gm` 不只处理 AMQP 0-9-1，还要覆盖
AMQP 1.0 等消息类型。

RabbitMQ `4.4.0` 的 AMQP 1.0 支持依赖启用
`rabbitmq_amqp1_0` 插件。AMQP 1.0 的 body 可以是 `data`、`amqp-value` 或
`amqp-sequence`；内部 `mc_amqp` 状态与 AMQP 0-9-1 的 `#content{}` 完全不同。

## Decision

- `make build`、`make smoke` 和 CI 默认构建 Tongsuo 镜像；标准 OpenSSL
  Dockerfile 保留在仓库中，只用于复现历史 `v4.4.0-rmq.1`，默认 CI 不再构建。
- 新版本线为 `4.4.0-rmq.2`，默认完整 tag 为
  `4.4.0-rmq.2-tongsuo-openeuler`。
- 镜像必须启用 `rabbitmq_amqp1_0`，使 AMQP 0-9-1 与 AMQP 1.0 使用同一
  AMQP listener 提供协议协商。
- `rabbitmq_gm` 对 AMQP 1.0 incoming body 做 SM4-GCM 加密：
  - 从 `mc_amqp` 的 `msg_body_encoded` 或持久化 `v1` 状态定位 bare message
    body；
  - 支持 `data`、`amqp-value` 和 `amqp-sequence`；
  - 保存原始 body descriptor code 和加密元数据到 broker-owned annotations；
  - message headers、properties、application properties、message annotations、
    footer、routing key 和 queue index 不加密。
- encryption/decryption 只依赖 broker-owned `mc` annotations，不读取客户端
  headers。加密 body 使用 AEAD 认证，认证成功后才用
  `binary_to_term(Plain, [safe])` 还原原始 body section。
- 对无法识别的 AMQP 1.0 body 布局采取 fail-closed：在入队前拒绝消息，不静默
  降级为明文存储。
- 仍然不实现也不宣称 TLCP、TLS+国密、FIPS、集群国密或 management TLCP。

## Consequences

- 默认启动必须提供 GM 密钥；没有密钥时容器启动失败。
- AMQP 1.0 消息在队列中的 body 表示会变为单条 `data` section，消费时恢复；
  headers 和其他 section 保持不加密。
- `rabbitmq_gm` 依赖 RabbitMQ 4.4 的 `mc_amqp`、`amqp10_common` 和
  `rabbit_msg_interceptor` 内部结构，升级 RabbitMQ 必须重新编译并跑
  AMQP 0-9-1/1.0 回归。
- 先前发布的 `v4.4.0-rmq.1` 标准镜像不迁移、不覆盖；需要标准 OpenSSL 镜像的
  用户必须固定该历史 tag/digest，或自行使用 `make build-standard`。

## Verification

- 本地真实 RabbitMQ 4.4 节点验证 AMQP 1.0 `data`、`amqp-value`、
  `amqp-sequence` 发布、持久化扫描、重启后透明消费。
- `test/smoke/amqp10_smoke.escript` 使用镜像内 RabbitMQ 自带的
  `amqp10_client`，通过 SASL PLAIN 和标准 TLS 连接，不引入额外 AMQP 1.0
  Python 运行时。
- `make verify` 检查 AMQP 1.0 插件启用、body section 支持、safe term decode 和
  Tongsuo 默认构建目标。
