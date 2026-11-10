# 匿名 OCI 获取器预检（2026-10-31）

**已匿名获取完整 OCI 布局；未导入 Podman，未运行数据库或 Podman machine。** 镜像为项目配置中的 `docker.io/pgvector/pgvector:pg17`，通过公共标签元数据选择 linux/amd64，固定清单 digest `sha256:cd4ccfdaf62cbfeb5c6ee19ef0dd663406d4ed740c320b324d016a90e85385b3`。清单 3337 bytes、16 层、压缩层总计 160545628 bytes、最大层 112869042 bytes，config 描述 11371 bytes；匿名 registry 的 config 和最大层响应将 blob 重定向至精确 HTTPS host `production.cloudfront.docker.com`。

实际获取在干净环境中启动 Node，exit 0、stderr 空、`status=complete`；不调用 Podman、WSL 或数据库，不读取宿主 registry 凭据。完成后用单独代码逐对象重读并重新计算大小和 SHA-256：**18 个对象，合计 160560336 bytes，全部匹配**（[获取输出](acquisition.stdout.txt)、[回执](acquisition-receipt.json)、[复算记录](independent-verification.json)）。获取器和离线测试的 LF 摘要在运行前后不变。对象及其 OCI index、layout 位于 `oci-acquisition-klAflO/oci-fetch-078cebc55f24122033fe67654390bda9/`，由本轮随机创建；父目录内专用 `.gitignore` 防止大镜像误入提交，已对 index 验证生效。对象尚未导入任何镜像仓库，也未验证引擎能否加载。

## 可运行检查

`anonymous-oci-fetch-draft.cjs` 使用 Node 内置库，仅固定 Docker Hub 仓库及精确 CDN、匿名令牌、TLS 校验、固定清单 digest、文件排他创建、长度与 SHA-256 校验及读回；失败不自动重试或清理。运行方必须提供干净 Node 环境。其 realpath 与排他创建不防同 UID 并发替换路径，Windows mode 位也不是 ACL；文件系统安全边界仍待解决。脚本不读取本机 auth 文件，也不运行镜像。下载完成也不证明 provenance、签名、镜像可用性或 PG 隔离。

`anonymous-oci-offline.test.cjs` 在 VM 中仅求值获取器的函数定义，网络和文件模块是内存替身；它不验证真实 TLS、磁盘、实际获取或恶意源码安全。干净环境下 `node --check` exit 0；指定离线测试 exit 0，**20 tests、20 pass、0 fail、0 skip**，执行前后获取器 LF SHA-256 为 `b98e793229b7f9378c22fe1ebf2c01e8292ad50aa07167a3e17ed7ff29491e94`，测试 LF SHA-256 为 `ddbdb7faef290ae3a6e3368003321a7ef6175cdb2184eb8c8bc60a1ca746674c`。stdout/stderr 在 `offline-check-YWjbdY/`，该目录为本轮创建并保留。

获取器经独立静态复审（requested：plan profile 默认 `GBClaude/claude-opus-5-5`；实际 backend 回执未核实，记 `unknown`）；复审发现的 CDN、限额、凭据转发、请求超时和临时文件归属问题分别以真实匿名元数据、代码修订或下述限制处理。离线检查不替代对整个下载器的端到端故障注入。

## 待办和范围

下载使用本轮随机新建目录、非覆盖式创建、静态 realpath 检查且无清理操作；**不能**据此声称对同 UID 恶意并发替换或操作后篡改有防护。复算是同机单独代码的读回，不是独立主机或持久断电验证，日后加载前须再次按 digest 验证。任何阶段失败仅保留本轮资源并上报，不碰旧容器、旧卷、旧引擎。Windows/WSL 全盘自动挂载等 machine 阻断详见 [Podman 预检](../podman-wsl-isolation-preflight-20261031.md)。
