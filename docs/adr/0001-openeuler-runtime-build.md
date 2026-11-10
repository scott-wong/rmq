# 从 openEuler 构建完整 RabbitMQ 运行时

RMQ 不从 `rabbitmq:4.4` 或 Ubuntu 镜像派生。最终镜像使用固定 digest 的
`quay.io/openeuler/openeuler:24.03-lts-sp4`，并在同发行版 builder 中编译
Tongsuo（默认；历史标准变体为 OpenSSL）与 Erlang/OTP，再安装校验过的
RabbitMQ generic Unix 包。

## Considered Options

- **直接改官方 Ubuntu 镜像的标签**：被否。操作系统、glibc 和包管理来源仍然
  是 Ubuntu，无法证明 openEuler 交付。
- **只使用 openEuler 仓库的 Erlang/RabbitMQ 包**：被否。版本和补丁节奏不受
  RMQ 控制，无法满足 RabbitMQ 4.4 的运行时组合。
- **在当前发行版内源码编译并在干净 final 阶段组装**：采用。构建工具与运行时
  隔离，Tongsuo/OTP 链接关系可验证。

## Consequences

- 构建时间和缓存空间显著增加。
- 组件版本、归档 SHA256 和基础镜像 digest 都是发布输入。
- Trivy 对 openEuler RPM 漏洞库覆盖有限，不能宣称零漏洞。
