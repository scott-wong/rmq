# Tongsuo 变体先做消息体存储加密，不宣称 TLCP

## Status

Accepted for the experimental Tongsuo variant. The standard
`v4.4.0-rmq.1` release remains OpenSSL-based and unchanged.

## Context

标准 RMQ 镜像使用 OpenSSL `3.5.9`，其 AMQP、management 和节点 TLS 由
Erlang/OTP `ssl` 驱动。把 OpenSSL 替换成 Tongsuo，只能证明动态链接和
`crypto` 层可以使用 SM2/SM3/SM4 等算法；它不能让 OTP `ssl` 自动获得 TLCP、
SM2 双证书或国密握手状态机。

对 Erlang/OTP `29.1.2` 源码的检查没有发现 TLCP/NTLS 握手分支。因此，第一阶段
将问题拆成两个可独立验证的层次：

1. **Tongsuo 链接与算法能力**：镜像内 `openssl` 为 Tongsuo `8.5.0`，OTP
   `crypto` 动态链接 `/opt/tongsuo/lib/libcrypto.so.3`，并验证 SM3、SM4-GCM、
   SM2 和 NTLS cipher 构建能力。
2. **消息持久化保护**：使用 vendor plugin `rabbitmq_gm`，对 AMQP 0-9-1
   消息 body 做 SM4-GCM 加密。这是本阶段唯一的“国密”产品行为。

## Decision

- 新增独立 Dockerfile 和镜像目标 `rmq-tongsuo-final`，不修改已发布的标准
  镜像、tag 或 digest。
- Tongsuo 基线固定为 `8.5.0`，源码归档 SHA256 固定；其 OpenSSL 源码基线
  记录为 `3.5.4`，不把它写成 `3.5.9`。
- 插件使用 `rabbit_msg_interceptor` 对 incoming AMQP 0-9-1 body 加密，对
  outgoing body 解密。加密元数据使用 `mc:set_annotation/3` 和
  `mc:take_annotation/2` 保存，不能信任客户端 headers。
- 只覆盖消息 body。消息属性、headers、routing key、queue index、Mnesia 元数据
  和整个数据目录均不在加密范围内。
- Tongsuo 变体仍运行标准 TLS/AMQPS/HTTPS 回归，以证明 Tongsuo 动态链接没有
  破坏原有 TLS；这不构成 TLCP 或“TLS+国密”支持声明。
- 浏览器可读的 `x-rmq-gm-*` headers 不作为信任来源，也不用于解密；插件不把
  nonce、tag 或 key id 暴露给客户端。

## Consequences

- Tongsuo 变体启动时必须提供 `/etc/rabbitmq/gm.key`（或
  `RMQ_GM_KEY_FILE`）。插件启用但没有有效密钥时，启动失败比静默明文写入更安全。
- 当前只支持一个主密钥，key id 主要作为 AAD 和未来轮换的占位符；多密钥轮换、
  外部 KMS、密钥审计和密钥销毁尚未实现。
- `rabbitmq_gm` 依赖 RabbitMQ `4.4.x` 的内部 API；RabbitMQ 升级必须重新编译
  插件并跑持久化、消费、重投和重启回归。它不是上游支持的稳定扩展点。
- Tongsuo `8.5.0` 与其 OpenSSL `3.5.4` 源码基线的 CVE 状态**未审计**，不能
  把 Tongsuo 的商用密码产品认证继承为 RMQ 或 RabbitMQ 的产品认证。
- 不宣称 FIPS、全盘加密、集群、Kubernetes、完整国密合规或 TLCP 互操作。
- 标准镜像继续保持不可变；未来 Tongsuo 正式发布必须使用新的 `rmq.N` 版本，
  不得移动已发布的 `v4.4.0-rmq.1`。

## Verification

- `scripts/build-tongsuo.sh` 校验 Tongsuo 版本、共享库和
  `ECDHE-SM2-SM4-GCM-SM3` 的 `NTLSv1.1` 输出。
- `scripts/smoke-docker.sh` 在 `GM_STORAGE=1` 时验证 SM4-GCM/SM3 往返、
  插件启用、持久消息重启后消费，以及 Mnesia 文件不含明文 marker。
- `make verify` 检查标准变体、Tongsuo Dockerfile、插件 annotation 使用和
  “不宣称 TLS+GM”的标签。
- 正式发布前仍需补充独立安全评审、密钥管理设计、Tongsuo CVE 审计和真实
  TLCP 互操作测试；这些不是本 ADR 的已完成项。
