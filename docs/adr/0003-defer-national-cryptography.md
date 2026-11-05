# 首版不实现国密/TLCP

RabbitMQ 的 TLS 行为主要经过 Erlang/OTP `ssl`，而不是直接暴露 OpenSSL
配置。把 OpenSSL 替换成 Tongsuo 并不等同于 RabbitMQ 自动获得 TLCP、
SM2 双证书或 SM3/SM4 支持。

首版使用与上游 4.4 镜像一致的 OpenSSL 3.5.9，并明确不宣称国密能力。

## Future gate

任何国密变体在发布前至少需要独立验证：

1. OTP `crypto` 与 Tongsuo 动态链接以及 SM2/SM3/SM4 算法可用性。
2. AMQP 0-9-1 over TLCP 的真实握手与消息收发。
3. management HTTP 在 TLCP 下的认证和 API 行为。
4. 集群节点间 TLS 的握手、证书链与节点信任。

如果上游 OTP/RabbitMQ 无法在不维护深度补丁的前提下完成上述验证，
应采用外部 TLCP 终止代理并明确其协议覆盖范围，而不是宣称镜像原生支持国密。
