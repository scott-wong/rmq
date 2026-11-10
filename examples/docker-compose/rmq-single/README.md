# RMQ single-node Compose example

This example exposes AMQP, the management UI and Prometheus metrics on the
host. Do not publish these ports on an untrusted network.

```sh
cp .env.example .env
${EDITOR:-vi} .env
openssl rand -hex 32 > gm.key
chmod 600 gm.key
docker compose up --pull always
```

The RMQ image deliberately restricts the built-in `guest` account to loopback.
The explicitly supplied `RABBITMQ_DEFAULT_USER` is therefore required for the
management UI and remote AMQP clients.

The default image requires the GM storage key mounted at
`/etc/rabbitmq/gm.key`. Keep `gm.key` out of version control and back it up
separately from the data volume; losing it makes encrypted message bodies
unreadable.

`RABBITMQ_DEFAULT_*` is documented upstream as suitable for development and CI,
not as a production user-management strategy. Production deployments should
provision users through controlled configuration/definitions and a secret
manager rather than long-lived container environment variables.

This example is a single-node deployment only. It does not test RabbitMQ
cluster formation, quorum queues across nodes or rolling upgrades.
