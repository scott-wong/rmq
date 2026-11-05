# openEuler RPM 版本在构建时解析，最终镜像按 digest 固定

openEuler 基础镜像只固定 OCI tag 对应的 index digest；`dnf install` 的 RPM 具体
版本仍由签名仓库的当前内容决定。RMQ 不把数十个 RPM 的版本写死在 Dockerfile，
因为跨 OS/update/everything 仓库的 transitive dependency 集合会频繁变化，逐包
锁定会制造更脆弱的伪精确版本。

## Controls

- 基础镜像以 index digest 固定，tag 漂移由 CI 检测。
- RPM 仓库只接受 HTTPS，并通过基础镜像自带的 openEuler GPG key 校验签名。
- 每个最终镜像按不可变 digest 发布，SBOM 记录实际安装的 RPM 集合。
- `VERSION` 的 `rmq.N` 修订用于安全重建；重建与旧镜像在 digest 上明确不同。

## Consequence

同一 git commit 在不同日期重建可能得到不同的 RPM patch level。这是已知且显式
记录的构建非确定性，不以“同版本号即可复现字节级镜像”作承诺。若未来需要完全
可复现构建，必须先引入签名 RPM snapshot 或独立制品库，再进行新的 ADR。
