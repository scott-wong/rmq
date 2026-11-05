# 默认限制 guest 为 loopback

官方 RabbitMQ Docker 镜像通过 `10-defaults.conf` 设置
`loopback_users.guest = false`。它适合快速体验，但 management 镜像一旦发布
15672，默认 `guest/guest` 就成为远端可用账户。

RMQ 将 `loopback_users.guest` 设为 `true`。远端使用必须显式配置
`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` 或其他 RabbitMQ 用户配置。

## Consequences

- RMQ 与官方镜像的默认登录行为不同，必须显著记录。
- 冒烟测试从独立网络容器验证 guest 返回 401/403。
- 示例 Compose 强制要求用户和密码变量，不携带默认凭据。
