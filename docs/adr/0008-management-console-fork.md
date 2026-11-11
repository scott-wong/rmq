# 管理控制台采用源级静态 fork

Accepted for `4.4.0-rmq.3`.

## Context

RabbitMQ 4.4.0 management 控制台没有内置 i18n 框架。界面由
`rabbitmq_management/priv/www` 下的 EJS 模板和 JavaScript 组成，构建时把
`js/tmpl/*.ejs` 预编译为 `js/management-ejs.js`。直接使用运行时 DOM 文本替换会
在动态刷新、表格、弹窗和错误提示中产生不可控的漏译和竞态。

RMQ 需要默认中文、英文切换、RMQ 品牌和可重复的镜像构建，但不希望 fork
RabbitMQ 的 Erlang 管理 API、认证或路由。

## Decision

- 把 RabbitMQ 4.4.0 的完整 `priv/www` 作为源级静态 fork 纳入
  `packaging/management-ui/www`。
- 使用英文源字符串作为 `t()` key，中文目录位于 `js/rmq-locales.js`；缺失 key
  回退英文。
- 默认 `zh-CN`，支持 `en-US`。优先级为 URL `?lang=` >
  `localStorage['rmq-language']` > `zh-CN`。
- 在 Docker 构建阶段的 Erlang 工具链中运行上游
  `precompile_ejs_templates`，最终镜像只包含生成后的 `management-ejs.js`。
- 构建完成后把静态资源覆盖到
  `plugins/rabbitmq_management-<version>/priv/www`；不修改任何 Erlang 模块或
  management API。
- 保留上游版本、commit、pristine tree digest、MPL-2.0 与全部第三方许可证。
- 用 Playwright Chromium 对真实 HTTPS 控制台做验收，覆盖中文、英文、浅色、
  深色、登录、概览、用户页、标题、logo、favicon 和语言持久化。

## Consequences

- 管理界面与上游 `priv/www` 不再逐字节一致，后续 RabbitMQ 升级必须人工查看
  `scripts/diff-management-ui-upstream.sh` 的差异并移植翻译。
- 控制台翻译是核心页面的显式覆盖，不宣称 100% 全量；协议字段、原始错误和 API
  文档保持英文。
- 控制台静态资源受 RabbitMQ MPL-2.0 约束，fork 及其修改声明必须随镜像分发。
- 管理 API、权限、认证和 Erlang 路由仍由上游管理插件提供，不能因为 UI 重品牌
  而宣称是 RabbitMQ 官方控制台。
