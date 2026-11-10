# CI disposable DB 实施计划

**目标**：不削弱 `cmd/server` TestMain，为受保护测试提供真实独立数据库，最终修复 CI/local 入口；本次授权仅允许新建、销毁一个全新独占测试容器及其内部资源，不授权保留库、新部署或真实 CR。

**架构**：`scripts/aifi45-db/run.mjs` 增加显式封闭验证模式，旧 pinned 保全库路径和参数不变；新模式创建和核验全新、无持久数据的容器，只使用其精确 ID 及身份凭据。真正 CI provisioner 是另一个固定实现，验证模式必须调用同一份实现，而非模拟。权限、网络和原库数据不能从现有 runner 自动继承。CI 路由后续单独接线。

**已知边界**：单包 governance 的 migration Up/Down/Reapply 顶层测试要求不同初始状态，且其他测试会真实修改 migration 状态；单个专库不足以说明全包可用。`taskusagebackfill` 与 `backfill_codex_usage_cache` 创建子库，不可简单授予常规 NOCREATEDB 身份。完整 `cmd/migrate up` 及 PostgreSQL extension 权限需在新实例实测。

## 任务 1 — 安全实例生命周期

- [ ] 定义实例验证模式固定参数/镜像/本地引擎；不接受外部 URL、实例 ID 或任意命令，不访问保全实例；旧模式失败不回退新模式，反之亦然。
- [ ] 先增加 fake 测试并观察 RED：create 调用前意图落盘；nonce 名称、标签及 image ID 必须匹配；端口 loopback 动态分配；mount 不得落到已有数据；所有操作固定 argv，不泄漏密码。`expectedEnv` 包含明文 bootstrap secret，只可由可信调用层在内存生成与比对，禁止将其连同 target 序列化到 journal、meta、报错或输出；允许的环境列表来自固定 image 配置与该次显式 create，而非从待验证 inspect 抄录。
- [ ] 覆盖 create 成功但回执丢失、名称冲突、标签/镜像/端口/mount 改变、引擎失联及 stop/remove 失败。未知状态不是 absence；创建发生但 ack 丢失时不可重新 create，只允许识别完全匹配对象后收尾。SIGKILL 等不承诺自动清理，保留 journal 供人工处理。
- [ ] 分清 DB 身份与容器身份；结束并等待本次子进程后重新核对容器 ID、精确名称、labels、image 与配置，仅对该完整 ID 做普通 stop/rm；不可 force、prune、批量删除或清除其他卷/实例；证明精确 ID 与名称不存在。任何不确定/失败要失败并保留证据。
- [ ] 模拟 RED→实现→GREEN，关键归属检查变异 RED→恢复 SHA→GREEN；独立只读复审固定源码。只有完成该层及授权范围核查后才运行一个真实实例探针。实例控制验证不等于 provisioner 已验证。

## 任务 2 — 正式 provisioner 与真实数据库

- [ ] 先用 fake I/O 测试 nonce DB 与受限角色的创建、marker/OID/owner 确认、正式 `cmd/migrate up`、错误时资源保留和精确清理；CREATE/COMMENT 丢 ack 不能假定未创建，禁止 FORCE 或终止外部连接。
- [ ] 将任务 1 的受控模式接入真实 provisioner，限定仅本次独占实例，验证真实 TCP/身份、正式 migration 及账本、测试角色不具备超权、精确释放及 catalog 缺席；使用不同对照库测试权限和错误清理。数据库内部释放失败与外部容器销毁成功分开记录，前者不因后者而升级。
- [ ] 所有 Go DB 实测均通过 runner，断言选定测试实际执行、skip 0；先做正式迁移的真实最小验证和独立复审，不把静态或 fake 当作真实证据。

## 任务 3 — test-go/CI 接线

- [ ] 设计 governance migration lifecycle 测试各自隔离、CREATEDB 特殊包和其余 regular 测试权限；不丢失任何选定包，不绕过 guard。CI 的先行迁移、Makefile/check/release、path filters 全部检查。
- [ ] fake Go/provisioner 先锁定 `--race`、`--only` 两种顺序、无效参数、默认 regular/agent、guard sentinel 和失败传播；agent-only 不触库。若不能维持现有 single-go/并行语义，明确审查行为变化。
- [ ] 独立审查后再做授权范围内真实完整 CI 路径和清理验证；未验证前 CI BLOCK 不解除，既有 verdict 和 Gate3 不改变。

## 审查重点

1. 进程在 create 成功而回执丢失后如何定位、证明归属并拒绝误删。
2. container、role、database 各自身份和清理权限不得互相替代；engine 断联不得当成 not-found。
3. 主机端口/容器环境/数据目录不继承已有实例；生成凭据不进入日志、argv 或普通测试环境。
4. 中断、超时和清理失败不能产生假绿；SQL release 和销毁容器不能互相冒充。
5. 保留 `test-go.sh` 的 CLI、guard、包选择、skip 和并行契约；发现无法保持时停下明确范围，而非放宽 TestMain。
