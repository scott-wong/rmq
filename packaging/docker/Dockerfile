# syntax=docker/dockerfile:1.7

ARG OPENEULER_BASE
ARG GOLANG_BASE
ARG RMQ_VERSION
ARG RABBITMQ_VERSION
ARG OTP_VERSION
ARG OPENSSL_VERSION
ARG GOSU_VERSION
ARG RABBITMQADMIN_VERSION
ARG OPENEULER_BASE_DIGEST

# ---------------------------------------------------------------------------
# gosu builder
# ---------------------------------------------------------------------------
FROM ${GOLANG_BASE} AS gosu-builder

ENV CGO_ENABLED=0
WORKDIR /opt/rmq

COPY scripts/baseline.env scripts/lib.sh scripts/build-gosu.sh /opt/rmq/scripts/
COPY distfiles/gosu-*.tar.gz /opt/rmq/distfiles/

RUN DISTFILES_DIR=/opt/rmq/distfiles \
    bash /opt/rmq/scripts/build-gosu.sh

# ---------------------------------------------------------------------------
# OpenSSL and Erlang/OTP builders
# ---------------------------------------------------------------------------
FROM ${OPENEULER_BASE} AS openssl-builder

WORKDIR /opt/rmq

COPY scripts/baseline.env scripts/lib.sh scripts/configure-openeuler-repo.sh \
     scripts/install-build-deps.sh /opt/rmq/scripts/
RUN bash /opt/rmq/scripts/install-build-deps.sh

COPY scripts/build-openssl.sh /opt/rmq/scripts/
COPY distfiles/openssl-*.tar.gz /opt/rmq/distfiles/
RUN DISTFILES_DIR=/opt/rmq/distfiles \
    bash /opt/rmq/scripts/build-openssl.sh

FROM openssl-builder AS erlang-builder

ENV PATH=/opt/openssl/bin:$PATH

COPY scripts/build-otp.sh /opt/rmq/scripts/
COPY distfiles/otp_src_*.tar.gz /opt/rmq/distfiles/
RUN DISTFILES_DIR=/opt/rmq/distfiles \
    bash /opt/rmq/scripts/build-otp.sh

# ---------------------------------------------------------------------------
# RabbitMQ generic Unix archive
# ---------------------------------------------------------------------------
FROM ${OPENEULER_BASE} AS rabbitmq-builder

# RPM versions are resolved from the signed openEuler SP4 repositories. The
# resulting image is immutable by digest; exact RPM versions are recorded by the
# SBOM rather than forty individual Dockerfile pins.
# hadolint ignore=DL3041
RUN dnf install -y --setopt=install_weak_deps=False tar xz \
    && dnf clean all

WORKDIR /opt/rmq
COPY scripts/baseline.env scripts/lib.sh scripts/extract-rabbitmq.sh /opt/rmq/scripts/
COPY distfiles/rabbitmq-server-generic-unix-*.tar.xz /opt/rmq/distfiles/
RUN DISTFILES_DIR=/opt/rmq/distfiles \
    bash /opt/rmq/scripts/extract-rabbitmq.sh

# ---------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------
FROM ${OPENEULER_BASE} AS rmq-final

ARG RMQ_VERSION
ARG RABBITMQ_VERSION
ARG OTP_VERSION
ARG OPENSSL_VERSION
ARG GOSU_VERSION
ARG RABBITMQADMIN_VERSION
ARG OPENEULER_BASE_DIGEST

LABEL org.opencontainers.image.title="RMQ" \
      org.opencontainers.image.description="RabbitMQ 4.4 management distribution for openEuler, based on RabbitMQ" \
      org.opencontainers.image.version="${RMQ_VERSION}" \
      org.opencontainers.image.url="https://github.com/scott-wong/rmq" \
      org.opencontainers.image.source="https://github.com/scott-wong/rmq" \
      org.opencontainers.image.documentation="https://github.com/scott-wong/rmq/blob/main/README.md" \
      org.opencontainers.image.licenses="Apache-2.0 AND MPL-2.0" \
      org.opencontainers.image.base.name="quay.io/openeuler/openeuler:24.03-lts-sp4" \
      org.opencontainers.image.base.digest="${OPENEULER_BASE_DIGEST}" \
      org.opencontainers.image.vendor="RMQ" \
      io.rmq.variant="openeuler" \
      io.rmq.rabbitmq.version="${RABBITMQ_VERSION}" \
      io.rmq.erlang.version="${OTP_VERSION}" \
      io.rmq.openssl.version="${OPENSSL_VERSION}" \
      io.rmq.gosu.version="${GOSU_VERSION}" \
      io.rmq.rabbitmqadmin.version="${RABBITMQADMIN_VERSION}" \
      io.rmq.security.guest-loopback-only="true" \
      io.rmq.healthcheck.built-in="false"

ENV PATH=/opt/rabbitmq/sbin:/opt/erlang/bin:/opt/openssl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    ERLANG_INSTALL_PATH_PREFIX=/opt/erlang \
    OPENSSL_INSTALL_PATH_PREFIX=/opt/openssl \
    RABBITMQ_DATA_DIR=/var/lib/rabbitmq \
    RABBITMQ_VERSION=${RABBITMQ_VERSION} \
    RABBITMQ_HOME=/opt/rabbitmq \
    HOME=/var/lib/rabbitmq \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RUNNING_UNDER_SYSTEMD=true \
    RMQ_VERSION=${RMQ_VERSION}

COPY scripts/baseline.env scripts/lib.sh scripts/configure-openeuler-repo.sh \
     scripts/install-runtime-deps.sh scripts/prepare-image.sh /opt/rmq/scripts/
RUN bash /opt/rmq/scripts/install-runtime-deps.sh

COPY --from=gosu-builder /out/gosu /usr/local/bin/gosu
COPY --from=openssl-builder /opt/openssl /opt/openssl
COPY --from=erlang-builder /opt/erlang /opt/erlang
COPY --from=rabbitmq-builder /opt/rabbitmq /opt/rabbitmq

COPY distfiles/rabbitmqadmin-* /usr/local/bin/rabbitmqadmin
COPY packaging/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY packaging/rabbitmq/10-defaults.conf /opt/rmq/stage/10-defaults.conf
COPY LICENSE THIRD_PARTY_NOTICES.md /usr/local/share/rmq/
COPY licenses/ /usr/local/share/rmq/licenses/

RUN chmod 0755 \
        /usr/local/bin/gosu \
        /usr/local/bin/rabbitmqadmin \
        /usr/local/bin/docker-entrypoint.sh \
    && RMQ_VERSION="$RMQ_VERSION" \
       RABBITMQ_VERSION="$RABBITMQ_VERSION" \
       OTP_VERSION="$OTP_VERSION" \
       OPENSSL_VERSION="$OPENSSL_VERSION" \
       GOSU_VERSION="$GOSU_VERSION" \
       RABBITMQADMIN_VERSION="$RABBITMQADMIN_VERSION" \
       OPENEULER_BASE_DIGEST="$OPENEULER_BASE_DIGEST" \
       bash /opt/rmq/scripts/prepare-image.sh

VOLUME /var/lib/rabbitmq

EXPOSE 4369 5671 5672 15671 15672 15691 15692 25672

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["rabbitmq-server"]
