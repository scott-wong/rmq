#!/usr/bin/env python3
import json
import pathlib
import re
import sys
from collections import Counter


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_catalog(path: pathlib.Path) -> tuple[dict[str, str], list[str]]:
    text = path.read_text(encoding="utf-8")
    marker = 'window.RMQ_LOCALES["zh-CN"] = '
    start = text.find(marker)
    if start < 0:
        fail(f"missing zh-CN catalog marker in {path}")
    start += len(marker)
    pairs: list[tuple[str, str]] = []

    def hook(items: list[tuple[str, str]]) -> dict[str, str]:
        nonlocal pairs
        pairs = items
        return dict(items)

    try:
        _, end = json.JSONDecoder(object_pairs_hook=hook).raw_decode(text[start:])
    except json.JSONDecodeError as exc:
        fail(f"invalid zh-CN catalog JSON: {exc}")
    if text[start + end :].strip() != ";":
        fail("unexpected content after zh-CN catalog object")
    duplicates = [
        key for key, count in Counter(k for k, _ in pairs).items() if count > 1
    ]
    return dict(pairs), duplicates


def literal_translation_keys(www: pathlib.Path) -> set[str]:
    paths = list((www / "js").rglob("*.js")) + list((www / "js/tmpl").glob("*.ejs"))
    keys: set[str] = set()
    pattern = re.compile(r"""\bt\(\s*(['"])((?:\\.|(?!\1).)*?)\1""")
    for path in paths:
        if path.name in {"rmq-i18n.js", "rmq-locales.js"} or path.name.endswith(
            ".min.js"
        ):
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        for match in pattern.finditer(source):
            keys.add(bytes(match.group(2), "utf-8").decode("unicode_escape"))
    return keys


def main() -> int:
    root = pathlib.Path(sys.argv[1]).resolve()
    ui = root / "packaging/management-ui"
    www = ui / "www"

    for relative in ("UPSTREAM.md", "README.md", "tools/precompile_ejs_templates"):
        if not (ui / relative).is_file():
            fail(f"management UI file missing: packaging/management-ui/{relative}")
    for relative in (
        "index.html",
        "js/rmq-i18n.js",
        "js/rmq-layout.js",
        "js/rmq-locales.js",
    ):
        if not (www / relative).is_file():
            fail(f"management UI asset missing: {relative}")
    for relative in (
        "img/rmq-logo-light.svg",
        "img/rmq-logo-dark.svg",
        "img/rmq-favicon.svg",
        "img/rmq-favicon-32.png",
    ):
        if not (www / relative).is_file():
            fail(f"RMQ management UI brand asset missing: {relative}")
    if (www / "js/management-ejs.js").exists():
        fail("generated management-ejs.js must not be committed")

    catalog, duplicates = load_catalog(www / "js/rmq-locales.js")
    if duplicates:
        fail(f"duplicate zh-CN catalog keys: {', '.join(duplicates)}")
    missing = sorted(literal_translation_keys(www) - set(catalog))
    if missing:
        fail("missing zh-CN translations: " + ", ".join(missing))
    empty = sorted(key for key, value in catalog.items() if not value.strip())
    if empty:
        fail("empty zh-CN translations: " + ", ".join(empty))

    index = (www / "index.html").read_text(encoding="utf-8")
    if "<title>RMQ</title>" not in index:
        fail("management UI document title must be RMQ")
    if "RabbitMQ Management" in index:
        fail("upstream RabbitMQ title leaked into index.html")
    for script in (
        "rmq-locales.js",
        "rmq-i18n.js",
        "rmq-layout.js",
        "rmq-build-info.js",
    ):
        if script not in index:
            fail(f"index.html does not load {script}")
    if "rmq-favicon.svg" not in index:
        fail("index.html does not use the RMQ favicon")

    for template in ("layout.ejs", "login.ejs", "login_oauth.ejs"):
        source = (www / "js/tmpl" / template).read_text(encoding="utf-8")
        if "rabbitmqlogo" in source:
            fail(f"{template} still references the RabbitMQ logo")
        if "rmq-logo-" not in source:
            fail(f"{template} does not reference an RMQ logo")

    print(f"[ok] management UI catalog ({len(catalog)} zh-CN strings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
