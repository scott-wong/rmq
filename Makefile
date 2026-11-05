SHELL := /bin/bash

VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(firstword $(subst -, ,$(VERSION)))
IMAGE ?= rmq:$(VERSION)-openeuler
PLATFORM ?= linux/amd64
DOCKER ?= docker

.PHONY: help verify fetch check build smoke clean print-build-args

help:
	@printf 'RMQ %s\n' '$(VERSION)'
	@printf '%s\n' \
		'  fetch            Download and verify every pinned source archive' \
		'  verify           Run repository static checks' \
		'  build            Build the local linux/amd64 image' \
		'  smoke            Run container acceptance tests against IMAGE' \
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

check:
	bash scripts/check-prereqs.sh

smoke:
	test -n "$(IMAGE)"
	bash scripts/smoke-docker.sh "$(IMAGE)"

clean:
	rm -rf distfiles artifacts out .release test/certs
