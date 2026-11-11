# RMQ 术语表

本表统一 RMQ 文档、测试和发布记录中的术语。术语只描述本仓库验证过的行为，
不把库能力、协议能力和产品认证混为一谈。

| 术语 | 定义 |
|---|---|
| **RMQ** | 本仓库独立维护的 RabbitMQ 容器发行版，不是官方 RabbitMQ 镜像。 |
| **标准变体** | 使用 OpenSSL `3.5.9` 的历史单节点镜像，仅用于复现已发布的 `v4.4.0-rmq.1`；不再是默认构建。 |
| **Tongsuo 变体** | 使用 Tongsuo `8.5.0`（OpenSSL `3.5.4` 源码基线）的默认镜像；标签以 `-tongsuo-openeuler` 结尾。 |
| **Tongsuo（铜锁）** | OpenSSL 的国密兼容分支。本仓库使用 `enable-ntls` 构建；库中存在 NTLS/TLCP 能力不等于 RabbitMQ 的 TLS listener 已支持 TLCP。 |
| **TLCP** | Transport Layer Cryptography Protocol，国密传输层协议。第一阶段 Tongsuo 变体**不实现也不宣称** AMQP、management 或节点互连的 TLCP。 |
| **NTLS** | Tongsuo 对 TLCP 能力的构建名称。`openssl ciphers ...` 出现 `NTLSv1.1` 只证明库层能力，不证明业务进程完成握手。 |
| **SM2 / SM3 / SM4** | 国密算法。SM2 为非对称签名/密钥交换，SM3 为摘要，SM4 为分组密码。 |
| **SM4-GCM** | 使用 SM4 的 GCM 认证加密模式。Tongsuo 变体用它保护 AMQP 0-9-1 和 AMQP 1.0 消息 body。 |
| **国密消息体存储加密** | 本仓库插件对 AMQP 0-9-1 body 和 AMQP 1.0 的 `data`、`amqp-value`、`amqp-sequence` body 做 SM4-GCM 加密，密文和认证标签随消息持久化；不覆盖 queue index、Mnesia、消息属性、headers 或全盘。 |
| **AMQP 1.0** | 通过 `rabbitmq_amqp1_0` 插件在 AMQP listener 上协商的协议；插件支持 `data`、`amqp-value`、`amqp-sequence` body 的加密存储。 |
| **`rabbitmq_gm`** | RMQ 自有 vendor plugin。固定适配 RabbitMQ `4.4.x`，依赖内部 `mc`/`rabbit_msg_interceptor` API，不是上游官方插件。 |
| **annotation** | RabbitMQ `mc` 消息内部的键值元数据。插件把加密标记、key id、nonce 和 tag 放在 annotation 中，客户端不能通过 AMQP headers 伪造。 |
| **主密钥** | 从 `RMQ_GM_KEY_FILE` 读取的 32 字节原始值或 64 位十六进制值；插件当前只支持一个主密钥。 |
| **key id** | 写入消息 annotation 的密钥标识，默认 `v1`；当前用于 AAD 和未来轮换设计，尚未实现多密钥热轮换。 |
| **FIPS** | 联邦信息处理标准。即使 OpenSSL 构建启用了 FIPS provider，RMQ 也不宣称 FIPS 认证或合规。 |
| **CVE parity** | 某密码库与其上游 OpenSSL 版本在 CVE 修复状态上的等价性。Tongsuo `8.5.0` 基于 OpenSSL `3.5.4`，RMQ **未审计**其与 OpenSSL `3.5.9` 的 CVE 等价性。 |
| **正式发布** | 具有不可移动 tag、GitHub Release、签名 digest 和发布清单的版本。`v4.4.0-rmq.1` 是历史标准变体，`v4.4.0-rmq.2` 是首个默认 Tongsuo 版本，`v4.4.0-rmq.3` 增加中文管理控制台 fork。 |
| **RMQ 管理控制台** | 基于 RabbitMQ 4.4.0 `rabbitmq_management` 静态 `priv/www` 的源级 fork；默认中文，可切英文，只替换 UI 静态资源，不改 management API。 |
| **控制台语言覆盖** | 显式 `t()` 包装的界面文本必须有 `zh-CN` 译文；协议字段、原始错误、API 文档和许可证文本保持英文，不宣称 100% 全量翻译。 |
