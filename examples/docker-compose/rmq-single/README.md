# RMQ single-node Compose example

This example exposes AMQP, the management UI and Prometheus metrics on the
host. Do not publish these ports on an untrusted network.

```sh
cp .env.example .env
${EDITOR:-vi} .env
docker compose up --pull always
```

The RMQ image deliberately restricts the built-in `guest` account to loopback.
The explicitly supplied `RABBITMQ_DEFAULT_USER` is therefore required for the
management UI and remote AMQP clients.

This example is a single-node deployment only. It does not test RabbitMQ
cluster formation, quorum queues across nodes or rolling upgrades.
