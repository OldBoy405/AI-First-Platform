# Podman 新环境预检（2026-10-31）

**结论：尚未建机、启动容器或运行 PG。** 用户已同意为新 PG 创建专用 Podman machine、必要时下载其系统镜像及 PG 镜像；已说明可能读写 Podman 共享机器登记与连接配置。原事故数据库、容器、卷和旧引擎数据的 HOLD 未解除，不以新授权访问、清理或验证旧资源。

## 已做的有限观察

- 在本轮新建的临时控制目录中，用只含显式系统路径和该目录的进程环境执行安装版 `podman --version`、`podman machine init --help`、`podman machine start --help`；版本为 **5.8.3**。未显式执行 WSL、machine 创建/启动、容器引擎连接、inspect、清理或数据库命令。控制目录为 `C:/Users/GOBAO/AppData/Local/Temp/aifi45-podman-plan-X2fbel`，留存 help 输出，不自动清理。
- `machine init --help` 的默认 volume 显示宿主 `C:` 映射至 `/mnt/c`。官方 [5.8.3 init 文档](https://docs.podman.io/en/v5.8.3/markdown/podman-machine-init.1.html) 明确：WSL 启动时默认挂载所有驱动器，`--volume` 在 WSL 下没有效果；因此独立 machine 名称、独立 HOME 和独立镜像存储不能证明宿主文件不可见。
- [Microsoft WSL 配置文档](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) 说明，发行版的 `[automount] enabled` 默认 true；改成 false 仅禁止自动挂载，不能单独证明无法手动挂载；`[interop] enabled` 默认 true。不能将禁用一项自动挂载视为完整隔离。
- 只读审查 [Podman 5.8.3 WSL 实现](https://github.com/podman-container-tools/podman/blob/v5.8.3/pkg/machine/wsl/machine.go) 和 [WSL stubber](https://github.com/podman-container-tools/podman/blob/v5.8.3/pkg/machine/wsl/stubber.go)：导入发行版后，初始化流程即调用 WSL 内命令；实现还包含写 `/etc/wsl.conf`、失败自动清理和 WSL 不可用时可能请求提权安装的路径。初始安全策略必须覆盖首次启动和初始化，不可先启动再验证或仅在之后修改配置。
- 官方 [5.8.3 start 文档](https://docs.podman.io/en/v5.8.3/markdown/podman-machine-start.1.html) 称同一时间只能运行一台 machine；WSL stubber 的 `RequireExclusiveActive()` 返回 false，文档与具体 provider 实现存在需要解释的差异。未查询现有 machine 状态，不假定新旧可共存或旧状态未变化。
- 仅用可执行文件名查找及少量常见固定路径的存在性检查，未在 PATH 或这些路径找到 QEMU、VirtualBox 或 VMware 可执行文件；这不是全盘扫描，也不证明机器没有其他可用安装。尚未下载任何额外虚拟化软件。
- 仅读取公共 Docker Hub 标签元数据，在干净进程环境中匿名获取项目 `pgvector/pgvector:pg17` linux/amd64 清单并按实际字节验证 `sha256:cd4ccfdaf62cbfeb5c6ee19ef0dd663406d4ed740c320b324d016a90e85385b3`，发现 16 层；对 blob 重定向只记录 HTTPS CDN hostname，未输出 bearer、签名 URL 或宿主 registry 凭据。
- 随后通过独立获取器下载到本轮新建的 OCI 布局，18 对象、160560336 bytes 已按大小和 digest 逐一重读复算，详见 [获取报告](podman-independent-image-20261031/REPORT.md)。这不是 Podman 引擎内的镜像，也不证明引擎能加载或镜像可以安全执行。

## 后续边界

1. 独立于旧 Podman 引擎的 OCI 字节获取已完成，摘要经复算；但随机目录、排他创建及 realpath 检查不证明抵抗同 UID 并发替换。镜像获取不等于建立安全数据库。
2. WSL 默认宿主挂载、Windows interop、共享 WSL 网络和 API 转发的边界未解决；不执行 `machine init`、`machine start` 或 PG，直至首次启动及失败路径均有可验证方案。不得通过停止其他 machine 或修改其他发行版的方式消除冲突。
3. 原 RUN-003 入口不得运行或改向；新建空库、正式迁移和完整业务测试分别遵守已确认的设计与执行边界。原两侧 Gate3 仍 NO-GO。

本记录不声明历史 HOLD 对象未变化：按约束不查询它们，故没有此类观测证据。
