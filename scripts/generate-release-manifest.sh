#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

: "${IMAGE_REPO:?IMAGE_REPO is required}"
: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"
: "${SBOM_PATH:?SBOM_PATH is required}"
: "${TRIVY_SARIF_PATH:?TRIVY_SARIF_PATH is required}"
: "${TRIVY_TEXT_PATH:?TRIVY_TEXT_PATH is required}"
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${WORKFLOW_RUN:?WORKFLOW_RUN is required}"

output="${OUTPUT:-release-manifest.json}"
version="$(tr -d ' \n' < "$ROOT_DIR/VERSION")"
upstream="${version%%-*}"
ssl_kind="${SSL_KIND:-tongsuo}"

case "$ssl_kind" in
    openssl)
        variant_suffix="openeuler"
        ;;
    tongsuo)
        variant_suffix="tongsuo-openeuler"
        ;;
    *)
        die "unsupported SSL_KIND: $ssl_kind"
        ;;
esac

[[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "IMAGE_DIGEST is invalid: $IMAGE_DIGEST"
[ -s "$SBOM_PATH" ] || die "SBOM not found: $SBOM_PATH"
[ -s "$TRIVY_SARIF_PATH" ] || die "Trivy SARIF not found: $TRIVY_SARIF_PATH"
[ -s "$TRIVY_TEXT_PATH" ] || die "Trivy text report not found: $TRIVY_TEXT_PATH"

jq -n \
    --arg schemaVersion "1" \
    --arg project "RMQ" \
    --arg version "$version" \
    --arg upstream "$upstream" \
    --arg sslKind "$ssl_kind" \
    --arg variantSuffix "$variant_suffix" \
    --arg repo "$IMAGE_REPO" \
    --arg digest "$IMAGE_DIGEST" \
    --arg sourceCommit "$SOURCE_COMMIT" \
    --arg workflowRun "$WORKFLOW_RUN" \
    --arg publishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg baseImage "quay.io/openeuler/openeuler:${OPENEULER_RELEASE}" \
    --arg baseDigest "$OPENEULER_BASE_DIGEST" \
    --arg rabbitmqVersion "$RABBITMQ_VERSION" \
    --arg rabbitmqSha "$RABBITMQ_TARBALL_SHA256" \
    --arg otpVersion "$OTP_VERSION" \
    --arg otpSha "$OTP_SHA256" \
    --arg opensslVersion "$OPENSSL_VERSION" \
    --arg opensslSha "$OPENSSL_SHA256" \
    --arg tongsuoVersion "$TONGSHUO_VERSION" \
    --arg tongsuoSha "$TONGSHUO_SHA256" \
    --arg tongsuoOpensslVersion "$TONGSHUO_OPENSSL_VERSION" \
    --arg gosuVersion "$GOSU_VERSION" \
    --arg gosuSha "$GOSU_SOURCE_SHA256" \
    --arg adminVersion "$RABBITMQADMIN_VERSION" \
    --arg adminSha "$RABBITMQADMIN_SHA256" \
    --arg sbom "$(basename "$SBOM_PATH")" \
    --arg trivySarif "$(basename "$TRIVY_SARIF_PATH")" \
    --arg trivyText "$(basename "$TRIVY_TEXT_PATH")" \
    '{
      schemaVersion: ($schemaVersion | tonumber),
      project: $project,
      version: $version,
      upstreamVersion: $upstream,
      publishedAt: $publishedAt,
      source: {
        repository: "https://github.com/scott-wong/rmq",
        commit: $sourceCommit,
        workflowRun: $workflowRun
      },
      image: {
        repository: $repo,
        immutableTag: ($version + "-" + $variantSuffix),
        digest: $digest,
        platform: "linux/amd64"
      },
      base: {
        image: $baseImage,
        digest: $baseDigest
      },
      components: (
        if $sslKind == "tongsuo" then {
          rabbitmq: { version: $rabbitmqVersion, archiveSha256: $rabbitmqSha },
          erlangOtp: { version: $otpVersion, archiveSha256: $otpSha },
          tongsuo: {
            version: $tongsuoVersion,
            archiveSha256: $tongsuoSha,
            opensslSourceBaseline: $tongsuoOpensslVersion,
            cveParityWithStandardOpenSSL: "not-audited"
          },
          gosu: { version: $gosuVersion, archiveSha256: $gosuSha },
          rabbitmqadmin: { version: $adminVersion, archiveSha256: $adminSha }
        } else {
          rabbitmq: { version: $rabbitmqVersion, archiveSha256: $rabbitmqSha },
          erlangOtp: { version: $otpVersion, archiveSha256: $otpSha },
          openssl: { version: $opensslVersion, archiveSha256: $opensslSha },
          gosu: { version: $gosuVersion, archiveSha256: $gosuSha },
          rabbitmqadmin: { version: $adminVersion, archiveSha256: $adminSha }
        } end
      ),
      tests: ({
        singleNode: "passed",
        amqp: "passed",
        amqp10: "passed",
        amqps: "passed",
        managementHttp: "passed",
        managementHttps: "passed",
        prometheus: "passed",
        persistenceAfterRestart: "passed",
        guestLoopbackOnly: "passed"
      } + (if $sslKind == "tongsuo" then {
        gmMessageBodyStorage: "passed",
        gmAmqp10MessageBodyStorage: "passed"
      } else {} end)),
      artifacts: {
        sbomCycloneDx: $sbom,
        trivySarif: $trivySarif,
        trivyText: $trivyText
      },
      security: {
        trivyGate: "HIGH,CRITICAL with fixed vulnerabilities blocking",
        unfixedVulnerabilities: "reported, not claimed cleared",
        openEulerRpmCoverage: "limited; Trivy OS coverage unsupported",
        cosignKeylessSigned: true,
        sbomAttestation: true
      },
      deviations: ({
        guestLoopbackOnly: true,
        builtInHealthcheck: false
      } + (if $sslKind == "tongsuo" then {
        messageBodyStorageEncryption: true,
        amqp10BodyStorageEncryption: true
      } else {} end)),
      claims: {
        officialRabbitmqImage: false,
        rabbitmqVendorSupport: false,
        nationalCryptographyTls: false,
        nationalCryptographyStorage: ($sslKind == "tongsuo"),
        nationalCryptographyAmqp10Storage: ($sslKind == "tongsuo"),
        fipsCompliance: false,
        clusterTested: false,
        kubernetesTested: false
      }
    }' > "$output"

jq empty "$output"
printf 'Release manifest written to %s\n' "$output"
