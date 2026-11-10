SHELL := /bin/bash

VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(firstword $(subst -, ,$(VERSION)))
IMAGE ?= rmq:$(VERSION)-tongsuo-openeuler
STANDARD_IMAGE ?= rmq:$(VERSION)-openeuler
PLATFORM ?= linux/amd64
DOCKER ?= docker

.PHONY: help verify fetch check build build-standard build-tongsuo \
        smoke smoke-standard smoke-tongsuo clean print-build-args

help:
	@printf 'RMQ %s\n' '$(VERSION)'
	@printf '%s\n' \
		'  fetch            Download and verify every pinned source archive' \
		'  verify           Run repository static checks' \
		'  build            Build the default linux/amd64 Tongsuo image' \
		'  smoke            Run acceptance tests against the default image' \
		'  build-standard   Build the historical OpenSSL image source' \
		'  smoke-standard   Run standard-image regression tests' \
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
			--load -t $(IMAGE) -f packaging/docker/Dockerfile.tongsuo .

build-standard: check
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
			--load -t $(STANDARD_IMAGE) -f packaging/docker/Dockerfile .

build-tongsuo: build

check:
	bash scripts/check-prereqs.sh

smoke: check
	test -n "$(IMAGE)"
	SSL_PREFIX=/opt/tongsuo \
	SSL_KIND=tongsuo \
	SSL_VERSION_PATTERN='Tongsuo: Tongsuo 8.5.0' \
	SSL_LICENSE_NAME=tongsuo \
	GM_STORAGE=1 \
	EXPECTED_VARIANT=tongsuo-openeuler \
		bash scripts/smoke-docker.sh "$(IMAGE)"

smoke-standard: check
	test -n "$(STANDARD_IMAGE)"
	bash scripts/smoke-docker.sh "$(STANDARD_IMAGE)"

smoke-tongsuo: smoke

clean:
	rm -rf distfiles artifacts out .release test/certs
