#!/usr/bin/env python3
import os
import pathlib
import re
import sys

from playwright.sync_api import Page, expect, sync_playwright


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise RuntimeError(f"missing environment variable: {name}")
    return value


def base_url() -> str:
    host = env("RMQ_HOST", "rmq-test")
    port = env("RMQ_PORT", "15671")
    scheme = env("RMQ_SCHEME", "https")
    return f"{scheme}://{host}:{port}/"


def artifact_dir() -> pathlib.Path:
    path = pathlib.Path(env("UI_ARTIFACTS_DIR", "/artifacts"))
    path.mkdir(parents=True, exist_ok=True)
    return path


def assert_rmq_shell(page: Page) -> None:
    title = page.title()
    if "RabbitMQ" in title:
        raise RuntimeError(f"RabbitMQ leaked into the document title: {title!r}")
    if "RMQ" not in title:
        raise RuntimeError(f"RMQ is missing from the document title: {title!r}")
    if page.locator('img[src*="rabbitmqlogo"]').count():
        raise RuntimeError("the RabbitMQ logo is still present")
    favicon = page.locator('link[rel="icon"]').first.get_attribute("href")
    if not favicon or "rmq-favicon" not in favicon:
        raise RuntimeError(f"unexpected favicon: {favicon!r}")


def assert_content_clears_header(page: Page) -> None:
    header = page.locator("#header").bounding_box()
    heading = page.locator("#main h1").bounding_box()
    if not header or not heading:
        raise RuntimeError("could not measure the management console layout")
    header_bottom = header["y"] + header["height"]
    if heading["y"] < header_bottom:
        raise RuntimeError(
            "management content overlaps the fixed header: "
            f"heading y={heading['y']:.1f}, header bottom={header_bottom:.1f}"
        )


def login(page: Page) -> None:
    expect(page.locator("#username")).to_be_visible()
    expect(page.locator("#login")).to_contain_text("用户名")
    expect(page.locator("#login")).to_contain_text("密码")
    expect(page.locator("#login")).to_contain_text("登录")
    logo = page.locator("#login .rmq-logo-light img")
    expect(logo).to_be_visible()
    expect(logo).to_have_js_property("naturalWidth", 204)

    page.locator("#username").fill(env("RMQ_USER"))
    page.locator("#password").fill(env("RMQ_PASSWORD"))
    page.locator("#login input[type=submit]").click()
    expect(page.locator("#tabs")).to_contain_text("概览", timeout=30000)


def switch_language(page: Page, language: str) -> None:
    page.locator("select[data-rmq-language]").select_option(language)
    page.wait_for_url(re.compile(rf"[?&]lang={re.escape(language)}(?:[&#]|$)"))
    page.wait_for_load_state("domcontentloaded")
    expect(page.locator("#tabs")).to_be_visible(timeout=30000)


def main() -> int:
    artifacts = artifact_dir()
    url = base_url()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(
            ignore_https_errors=True,
            color_scheme="light",
            locale="zh-CN",
            viewport={"width": 1440, "height": 1000},
        )
        page = context.new_page()

        page.goto(f"{url}?lang=zh-CN", wait_until="domcontentloaded")
        expect(page).to_have_title(re.compile("RMQ 管理控制台"))
        assert_rmq_shell(page)
        page.screenshot(path=artifacts / "login-zh-CN-light.png", full_page=True)

        page.locator("#login select[data-rmq-language]").select_option("en-US")
        page.wait_for_url(re.compile(r"[?&]lang=en-US(?:[&#]|$)"))
        page.wait_for_load_state("domcontentloaded")
        expect(page).to_have_title(re.compile("RMQ Management Console"))
        expect(page.locator("#login")).to_contain_text("Username")
        page.screenshot(path=artifacts / "login-en-US-light.png", full_page=True)
        page.locator("#login select[data-rmq-language]").select_option("zh-CN")
        page.wait_for_url(re.compile(r"[?&]lang=zh-CN(?:[&#]|$)"))
        page.wait_for_load_state("domcontentloaded")
        expect(page.locator("#username")).to_be_visible()
        login(page)

        expect(page.locator("#tabs")).to_contain_text("队列")
        expect(page.locator("#tabs")).to_contain_text("管理")
        assert_content_clears_header(page)
        footer_links = {
            text.strip() for text in page.locator("#footer a").all_inner_texts()
        }
        removed = {
            "新版本",
            "商业版",
            "商业支持",
            "讨论",
            "Discord",
            "插件",
            "GitHub",
        }
        leaked = sorted(removed & footer_links)
        if leaked:
            raise RuntimeError(f"removed footer links are still present: {leaked}")

        expected_version = env("RMQ_VERSION", "4.4.0-rmq.4")
        expect(page.locator("#versions")).to_contain_text(f"RMQ {expected_version}")
        if "RabbitMQ" in page.locator("#versions").inner_text():
            raise RuntimeError("RabbitMQ leaked into the header version badge")
        page.screenshot(
            path=artifacts / "overview-zh-CN-light.png",
            full_page=True,
        )

        page.evaluate("location.hash = '#/users'")
        expect(page.locator("#main h1")).to_contain_text("用户", timeout=30000)
        page.screenshot(path=artifacts / "users-zh-CN-light.png", full_page=True)

        page.evaluate("location.hash = '#/cluster-name'")
        expect(page.locator("#main h1")).to_contain_text("集群名称", timeout=30000)
        expect(page.locator("#main")).to_contain_text(
            "客户端可以通过 AMQP 连接使用集群名称识别集群"
        )
        expect(page.locator("#main input[type='submit']").last).to_have_value(
            "修改名称"
        )
        if "Change name" in page.locator("#main").inner_text():
            raise RuntimeError("cluster name page still contains English labels")
        page.screenshot(
            path=artifacts / "cluster-name-zh-CN-light.png",
            full_page=True,
        )

        page.evaluate("location.hash = '#/'")
        expect(page.locator("#main h1")).to_contain_text("概览", timeout=30000)
        switch_language(page, "en-US")
        expect(page).to_have_title(re.compile("RMQ Management Console"))
        expect(page.locator("#tabs")).to_contain_text("Overview")
        if page.locator("img[src*='rabbitmqlogo']").count():
            raise RuntimeError("RabbitMQ logo appeared after switching to English")
        page.screenshot(
            path=artifacts / "overview-en-US-light.png",
            full_page=True,
        )

        switch_language(page, "zh-CN")
        page.evaluate("localStorage.setItem('color-scheme', 'dark'); location.reload()")
        page.wait_for_load_state("domcontentloaded")
        expect(page.locator("html[data-rmq-theme='dark']")).to_be_attached(
            timeout=30000
        )
        expect(page.locator("#tabs")).to_contain_text("概览", timeout=30000)
        expect(page.locator("#logo .rmq-logo-dark img")).to_be_visible()
        page.screenshot(
            path=artifacts / "overview-zh-CN-dark.png",
            full_page=True,
        )

        stored = page.evaluate("localStorage.getItem('rmq-language')")
        if stored != "zh-CN":
            raise RuntimeError(f"language preference was not persisted: {stored!r}")
        if "lang=zh-CN" not in page.url:
            raise RuntimeError(f"language URL override missing: {page.url!r}")

        page.evaluate("localStorage.setItem('rmq-language', 'en-US')")
        page.goto(f"{url}?lang=zh-CN#/", wait_until="domcontentloaded")
        expect(page).to_have_title(re.compile("RMQ 管理控制台"))
        expect(page.locator("#tabs")).to_contain_text("概览", timeout=30000)

        context.close()
        browser.close()

    print("management UI browser checks passed")
    print("screenshots:")
    for path in sorted(artifacts.glob("*.png")):
        print(f"  {path}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
