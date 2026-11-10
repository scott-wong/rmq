SHELL := /bin/bash

VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(firstword $(subst -, ,$(VERSION)))
IMAGE ?= rmq:$(VERSION)-openeuler
TONGSUO_IMAGE ?= rmq:$(VERSION)-tongsuo-openeuler
PLATFORM ?= linux/amd64
DOCKER ?= docker

.PHONY: help verify fetch check build build-tongsuo smoke smoke-tongsuo \
        clean print-build-args

help:
	@printf 'RMQ %s\n' '$(VERSION)'
	@printf '%s\n' \
		'  fetch            Download and verify every pinned source archive' \
		'  verify           Run repository static checks' \
		'  build            Build the local linux/amd64 standard image' \
		'  build-tongsuo    Build the local linux/amd64 Tongsuo image' \
		'  smoke            Run container acceptance tests against IMAGE' \
		'  smoke-tongsuo    Run Tongsuo storage/plugin acceptance tests' \
		'  print-build-args Print the immutable Docker build arguments' \
		'  clean            Remove downloaded sources and build outputs'

verify:
	bash scripts/static-checks.sh

fetch:
	bash scripts/fetch-sources.sh

print-build-args:
	bash scripts/print-build-args.sh

build: check
	@set -euo pipefail; \
		source scripts/baseline.env; \
		$(DOCKER) buildx build \
			--platform $(PLATFORM) \
			--target rmq-final \
			--build-arg OPENEULER_BASE="$${OPENEULER_BASE}" \
			--build-arg OPENEULER_BASE_DIGEST="$${OPENEULER_BASE_DIGEST}" \
			--build-arg GOLANG_BASE="$${GOLANG_BASE}" \
			--build-arg RMQ_VERSION="$(VERSION)" \
			--build-arg RABBITMQ_VERSION="$${RABBITMQ_VERSION}" \
			--build-arg OTP_VERSION="$${OTP_VERSION}" \
			--build-arg OPENSSL_VERSION="$${OPENSSL_VERSION}" \
			--build-arg GOSU_VERSION="$${GOSU_VERSION}" \
			--build-arg RABBITMQADMIN_VERSION="$${RABBITMQADMIN_VERSION}" \
			--provenance=false --sbom=false \
			--load -t $(IMAGE) -f packaging/docker/Dockerfile .

build-tongsuo: check
	@set -euo pipefail; \
		source scripts/baseline.env; \
		$(DOCKER) buildx build \
			--platform $(PLATFORM) \
			--target rmq-tongsuo-final \
			--build-arg OPENEULER_BASE="$${OPENEULER_BASE}" \
			--build-arg OPENEULER_BASE_DIGEST="$${OPENEULER_BASE_DIGEST}" \
			--build-arg GOLANG_BASE="$${GOLANG_BASE}" \
			--build-arg RMQ_VERSION="$(VERSION)" \
			--build-arg RABBITMQ_VERSION="$${RABBITMQ_VERSION}" \
			--build-arg OTP_VERSION="$${OTP_VERSION}" \
			--build-arg OPENSSL_VERSION="$${OPENSSL_VERSION}" \
			--build-arg TONGSHUO_VERSION="$${TONGSHUO_VERSION}" \
			--build-arg TONGSHUO_OPENSSL_VERSION="$${TONGSHUO_OPENSSL_VERSION}" \
			--build-arg GOSU_VERSION="$${GOSU_VERSION}" \
			--build-arg RABBITMQADMIN_VERSION="$${RABBITMQADMIN_VERSION}" \
			--provenance=false --sbom=false \
			--load -t $(TONGSUO_IMAGE) -f packaging/docker/Dockerfile.tongsuo .

check:
	bash scripts/check-prereqs.sh

smoke:
	test -n "$(IMAGE)"
	bash scripts/smoke-docker.sh "$(IMAGE)"

smoke-tongsuo:
	test -n "$(TONGSUO_IMAGE)"
	SSL_PREFIX=/opt/tongsuo \
	SSL_KIND=tongsuo \
	SSL_VERSION_PATTERN='Tongsuo: Tongsuo 8.5.0' \
	SSL_LICENSE_NAME=tongsuo \
	GM_STORAGE=1 \
	EXPECTED_VARIANT=tongsuo-openeuler \
		bash scripts/smoke-docker.sh "$(TONGSUO_IMAGE)"

clean:
	rm -rf distfiles artifacts out .release test/certs
