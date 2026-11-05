#!/usr/bin/env python3
import json
import os
import pathlib
import sys
import tempfile


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing environment variable: {name}")
    return value


def metadata(
    name: str,
    version: str,
    purl: str,
    license_value: str,
    source_url: str,
    source_sha256: str,
    description: str,
) -> dict:
    return {
        "name": name,
        "version": version,
        "purl": purl,
        "license": license_value,
        "source_url": source_url,
        "source_sha256": source_sha256,
        "description": description,
    }


def find_component(components: list[dict], name: str, purl_prefix: str) -> dict | None:
    for component in components:
        if component.get("name") == name:
            return component
        if component.get("purl", "").startswith(purl_prefix):
            return component
    return None


def upsert_component(
    components: list[dict], name: str, purl_prefix: str, info: dict
) -> dict:
    component = find_component(components, name, purl_prefix)
    if component is None:
        component = {"type": "application", "bom-ref": info["purl"]}
        components.append(component)

    component.update(
        {
            "type": "application",
            "name": info["name"],
            "version": info["version"],
            "purl": info["purl"],
            "scope": "required",
            "description": info["description"],
            "licenses": (
                [{"expression": info["license"]}]
                if " OR " in info["license"]
                else [{"license": {"id": info["license"]}}]
            ),
            "externalReferences": [
                {"type": "distribution", "url": info["source_url"]},
            ],
        }
    )

    properties = {
        item["name"]: item for item in component.get("properties", []) if "name" in item
    }
    properties["rmq:source-archive-sha256"] = {
        "name": "rmq:source-archive-sha256",
        "value": info["source_sha256"],
    }
    component["properties"] = list(properties.values())
    return component


def main() -> int:
    if len(sys.argv) != 2:
        raise RuntimeError("usage: enrich-sbom.py SBOM.json")

    sbom_path = pathlib.Path(sys.argv[1])
    document = json.loads(sbom_path.read_text(encoding="utf-8"))
    if document.get("bomFormat") != "CycloneDX":
        raise RuntimeError("input is not a CycloneDX document")

    components = document.setdefault("components", [])
    image_version = os.environ.get("IMAGE_VERSION") or (
        f"{env('RMQ_VERSION')}-openeuler"
    )
    image_component = document.setdefault("metadata", {}).setdefault("component", {})
    image_purl = f"pkg:oci/rmq@{image_version}"
    image_component.update(
        {
            "type": "container",
            "bom-ref": image_purl,
            "name": "rmq",
            "version": image_version,
            "purl": image_purl,
        }
    )

    inputs = [
        metadata(
            name="rabbitmq",
            version=env("RABBITMQ_VERSION"),
            purl=f"pkg:generic/rabbitmq@{env('RABBITMQ_VERSION')}",
            license_value="MPL-2.0",
            source_url=env("RABBITMQ_TARBALL_URL"),
            source_sha256=env("RABBITMQ_TARBALL_SHA256"),
            description="RabbitMQ generic Unix distribution",
        ),
        metadata(
            name="rabbitmqadmin",
            version=env("RABBITMQADMIN_VERSION"),
            purl=(
                f"pkg:generic/rabbitmqadmin@{env('RABBITMQADMIN_VERSION')}"
                "?arch=x86_64&os=linux"
            ),
            license_value="Apache-2.0 OR MIT",
            source_url=env("RABBITMQADMIN_URL"),
            source_sha256=env("RABBITMQADMIN_SHA256"),
            description="rabbitmqadmin-ng command-line client",
        ),
        metadata(
            name="erlang",
            version=env("OTP_VERSION"),
            purl=f"pkg:generic/erlang@{env('OTP_VERSION')}",
            license_value="Apache-2.0",
            source_url=env("OTP_URL"),
            source_sha256=env("OTP_SHA256"),
            description="Erlang/OTP runtime",
        ),
        metadata(
            name="openssl",
            version=env("OPENSSL_VERSION"),
            purl=f"pkg:generic/openssl@{env('OPENSSL_VERSION')}",
            license_value="Apache-2.0",
            source_url=env("OPENSSL_URL"),
            source_sha256=env("OPENSSL_SHA256"),
            description="OpenSSL runtime and FIPS provider build",
        ),
        metadata(
            name="gosu",
            version=env("GOSU_VERSION"),
            purl=f"pkg:golang/github.com/tianon/gosu@{env('GOSU_VERSION')}",
            license_value="Apache-2.0",
            source_url=env("GOSU_SOURCE_URL"),
            source_sha256=env("GOSU_SOURCE_SHA256"),
            description="setuid-less process privilege switcher",
        ),
    ]

    for info in inputs:
        upsert_component(components, info["name"], info["purl"], info)

    required_names = {item["name"] for item in inputs}
    actual_names = {component.get("name") for component in components}
    missing = required_names - actual_names
    if missing:
        raise RuntimeError(f"SBOM enrichment missing components: {sorted(missing)}")

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=sbom_path.parent,
        prefix=f".{sbom_path.name}.",
        delete=False,
    ) as temporary:
        json.dump(document, temporary, indent=2, ensure_ascii=False)
        temporary.write("\n")
        temporary_path = pathlib.Path(temporary.name)
    temporary_path.replace(sbom_path)

    print(
        f"Enriched CycloneDX SBOM with {len(inputs)} pinned components: "
        f"{', '.join(sorted(required_names))}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
