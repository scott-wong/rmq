# rabbitmq_gm

`rabbitmq_gm` 是 RMQ 的 RabbitMQ 消息体存储加密插件。插件在消息进入队列前
加密 body，在消费者取走消息时解密；队列索引、消息属性和 Mnesia 元数据不由
该插件处理。

当前实现针对 RabbitMQ `4.4.x`，使用 RabbitMQ 内部的 `mc`、
`rabbit_msg_interceptor` 和 `mc_amqp` 接口。它不是 RabbitMQ 上游支持的稳定
扩展 API，升级 RabbitMQ 后必须重新编译并运行回归测试。

## 协议和消息体

插件支持：

- AMQP 0-9-1 消息的 `#content{}` body；
- AMQP 1.0 的 `data`、`amqp-value` 和 `amqp-sequence` body。

AMQP 1.0 listener 需要启用 `rabbitmq_amqp1_0`。插件加密 AMQP 1.0 body 时，
把原始 body section 序列化后加密，并在队列中保存为一个 `data` section；消费时
恢复原始 section 和 body descriptor code。

不加密的内容包括：

- AMQP headers、properties、application properties 和 message annotations；
- AMQP 1.0 footer；
- routing key、exchange/queue 名称和 queue index；
- Mnesia 元数据和数据目录中的其他文件。

因此本插件提供的是消息 body 的静态存储保护，不是全盘加密，也不是传输层加密。

## 加密格式

- 算法：SM4-GCM；
- nonce：每个消息随机生成 12 字节；
- tag：16 字节；
- 密钥派生：`HMAC-SM3(master_key, nonce)` 的前 16 字节作为 SM4 密钥；
- 附加认证数据：`rmq-gm-v1:<key_id>:<nonce>`；
- 主密钥：32 字节原始值，或 64 位十六进制文本。

默认 key id 为 `v1`。当前 key id 会写入消息 annotation 并参与 AAD，但实现只加载
一个主密钥，不包含多密钥轮换或 KMS 集成。

key id 一旦用于生产消息，必须与主密钥一起保持稳定；修改 key id 会导致旧消息
无法用当前配置解密。

## 启动配置

插件从 `RMQ_GM_KEY_FILE` 读取密钥文件；未设置时默认读取
`/etc/rabbitmq/gm.key`。密钥文件必须是 32 字节原始值或 64 位十六进制文本。

```sh
openssl rand -hex 32 > gm.key
chmod 600 gm.key
```

容器运行时挂载密钥：

```sh
docker run --detach \
  --name rmq-gm \
  --hostname rmq-gm \
  --env RABBITMQ_DEFAULT_USER=rmq-admin \
  --env RABBITMQ_DEFAULT_PASS='replace-with-a-long-random-password' \
  --env RMQ_GM_KEY_FILE=/etc/rabbitmq/gm.key \
  --mount type=bind,src="$PWD/gm.key",dst=/etc/rabbitmq/gm.key,readonly \
  --publish 5672:5672 \
  --publish 15672:15672 \
  --publish 15692:15692 \
  --volume rmq-gm-data:/var/lib/rabbitmq \
  ghcr.io/scott-wong/rmq:4.4.0-rmq.3-tongsuo-openeuler
```

RMQ 入口脚本会把只读密钥复制到 `/run/rmq/gm.key`，再交给 `rabbitmq` 用户。
不要使用可被容器内其他进程读取的世界可读密钥文件。

`RMQ_GM_KEY_ID` 可覆盖 key id：

```sh
--env RMQ_GM_KEY_ID=v1
```

以下情况插件启动失败，broker 不会以明文模式继续运行：

- 找不到密钥文件；
- 密钥长度或十六进制格式无效；
- OTP `crypto` 不支持 `sm3` 或 `sm4_gcm`。

## 启停和构建

RMQ Tongsuo 镜像默认启用插件。手工安装时：

```sh
rabbitmq-plugins enable rabbitmq_amqp1_0 rabbitmq_gm
```

从本仓库编译：

```sh
mkdir -p ebin
erlc -o ebin \
  -I /opt/rabbitmq/plugins/rabbit-4.4.0/include \
  -I /opt/rabbitmq/plugins/rabbit_common-4.4.0/include \
  src/*.erl
cp src/rabbitmq_gm.app ebin/
```

完整镜像构建和验收使用仓库根目录：

```sh
make fetch
make build
make smoke
```

`make smoke` 覆盖 AMQP 0-9-1 和 AMQP 1.0 三类 body 的加密落盘、重启恢复、
TLS 消费和明文 marker 扫描。

## Broker annotations

加密元数据只存放在 broker-owned `mc` annotations 中，插件不使用客户端可写的
AMQP headers 作为信任来源：

- `rmq_gm_marker`：消息已加密的标记；
- `rmq_gm_alg`：`SM4-GCM-SM3`；
- `rmq_gm_key_id`：密钥标识；
- `rmq_gm_nonce`：GCM nonce；
- `rmq_gm_tag`：GCM tag；
- `rmq_gm_amqp10_body_code`：原始 AMQP 1.0 body descriptor code。

消费者不会看到这些 annotation。对于无法识别的 AMQP 1.0 body 布局，插件在入队
前拒绝消息，避免静默写入明文；解密认证失败时也不会把伪造或损坏的密文当作明文
返回。

## 边界

- 不实现 TLCP、SM2 双证书传输或 management TLCP；
- 不宣称 FIPS、全盘加密、KMS、多密钥轮换、集群或 Kubernetes 验证；
- 不覆盖队列索引、Mnesia、headers、properties、application properties、
  annotations、footer 和磁盘密钥文件；
- Tongsuo 的库层 NTLS 能力不等于 RabbitMQ listener 已完成 TLCP 握手。

密钥丢失后，已加密消息 body 无法恢复。生产环境应把密钥与数据卷分开备份，并
限制读取权限。
