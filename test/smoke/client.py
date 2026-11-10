#!/usr/bin/env python3
import argparse
import base64
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

import pika


QUEUE = "rmq.persistence"


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise RuntimeError(f"missing environment variable: {name}")
    return value


def message() -> bytes:
    return env("AMQP_BODY", "rmq-persistence-check").encode()


def connection(retries: int = 30) -> pika.BlockingConnection:
    host = env("AMQP_HOST", "rmq-test")
    port = int(env("AMQP_PORT", "5672"))
    credentials = pika.PlainCredentials(env("AMQP_USER"), env("AMQP_PASSWORD"))

    ssl_options = None
    if env("AMQP_TLS", "0") == "1":
        context = ssl.create_default_context(cafile=env("AMQP_CAFILE"))
        context.check_hostname = True
        ssl_options = pika.SSLOptions(context, server_hostname=host)

    parameters = pika.ConnectionParameters(
        host=host,
        port=port,
        virtual_host=env("AMQP_VHOST", "/"),
        credentials=credentials,
        ssl_options=ssl_options,
        connection_attempts=5,
        retry_delay=1,
        socket_timeout=10,
        blocked_connection_timeout=15,
    )

    last_error = None
    for _ in range(retries):
        try:
            return pika.BlockingConnection(parameters)
        except pika.exceptions.AMQPConnectionError as exc:
            last_error = exc
            time.sleep(1)
    raise RuntimeError(f"could not connect to {host}:{port}: {last_error}")


def publish() -> None:
    with connection() as conn:
        channel = conn.channel()
        channel.queue_declare(queue=QUEUE, durable=True)
        channel.basic_publish(
            exchange="",
            routing_key=QUEUE,
            body=message(),
            properties=pika.BasicProperties(
                delivery_mode=2,
                content_type="text/plain",
            ),
        )
    print(f"published persistent message to {QUEUE}")


def consume() -> None:
    with connection() as conn:
        channel = conn.channel()
        method, properties, body = channel.basic_get(queue=QUEUE, auto_ack=False)
        if method is None:
            raise RuntimeError(f"no message returned from {QUEUE}")
        if body != message():
            raise RuntimeError(f"unexpected message body: {body!r}")
        if properties.delivery_mode != 2:
            raise RuntimeError("message was not published as persistent")
        channel.basic_ack(delivery_tag=method.delivery_tag)
    print("consumed persisted message")


def http_get(
    url: str,
    username: str | None = None,
    password: str | None = None,
    cafile: str | None = None,
) -> tuple[int, str]:
    if username is not None:
        request = urllib.request.Request(url, method="GET")
        request.add_header("Authorization", _basic_auth(username, password or ""))
    else:
        request = urllib.request.Request(url, method="GET")

    context = None
    if url.startswith("https://"):
        context = ssl.create_default_context(cafile=cafile)

    try:
        with urllib.request.urlopen(request, context=context, timeout=10) as response:
            return response.status, response.read(1024 * 1024).decode(
                "utf-8", errors="replace"
            )
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(1024 * 1024).decode("utf-8", errors="replace")


def _basic_auth(username: str, password: str) -> str:
    encoded = base64.b64encode(f"{username}:{password}".encode()).decode()
    return f"Basic {encoded}"


def http_checks() -> None:
    host = env("RMQ_HOST", "rmq-test")
    username = env("RMQ_USER")
    password = env("RMQ_PASSWORD")
    cafile = env("RMQ_CAFILE")

    status, body = http_get(f"http://{host}:15672/api/overview", username, password)
    if status != 200:
        raise RuntimeError(f"management HTTP API returned {status}: {body[:200]}")

    status, _ = http_get(f"http://{host}:15672/")
    if status != 200:
        raise RuntimeError(f"management UI returned {status}")

    status, _ = http_get(f"http://{host}:15672/api/overview", "guest", "guest")
    if status not in (401, 403):
        raise RuntimeError(f"remote guest access was not rejected: HTTP {status}")

    status, body = http_get(
        f"https://{host}:15671/api/overview",
        username,
        password,
        cafile,
    )
    if status != 200:
        raise RuntimeError(f"management HTTPS API returned {status}: {body[:200]}")

    status, body = http_get(f"http://{host}:15692/metrics")
    if status != 200 or "rabbitmq_" not in body:
        raise RuntimeError(
            f"Prometheus endpoint failed: HTTP {status}; body prefix={body[:200]!r}"
        )

    print("management HTTP/HTTPS, secure guest policy and metrics checks passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mode",
        choices=("publish", "consume", "http-checks"),
        nargs="?",
        default="http-checks",
    )
    args = parser.parse_args()

    if args.mode == "publish":
        publish()
    elif args.mode == "consume":
        consume()
    else:
        http_checks()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
