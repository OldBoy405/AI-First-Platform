# fork CI 与测试证据可信性修复 — 切片执行计划

> change：`2026-11-12-fork-ci-test-evidence-trust`（multica，thorough，长程 full_auto）
> 依据：`design.md`（含 R1/R2/R3 修订）、`specs/`、`test-plan.md`（22 TC：18 命令型 + 4 manual）、`stdd dependency-graph --format json`。

## Dependency Graph Summary

```
stdd dependency-graph: nodes=5  edges=0  cycles=0
zero_dependency = [ci-backend-environment, ci-credential-and-frontend-typecheck,
                   selection-reconciliation, test-ownership-and-ci-reconciliation,
                   workspace-delete-execution-tables]

规格层无依赖边；下列拓扑来自实现层的真实消费关系（文件/产物级）：

  S1 selection-decision ──────────────┐
  S2 tools-pin + ci.yml ref ──────────┤
  S3 go-test-env-contract ────────────┤
  S11 tools-access ───────────────────┼──→ S13 CI 接线 + 独立入口 ──→ Part C / Gate 3
  S12 views typecheck ────────────────┤
  S4 基线 + test-ownership ──→ S5 test-go.sh + ci-evidence ──┤
  S6 ci-provision ────────────────────┘
  S7 nonce 门禁逐条件（需一次性库）
  S8 WSD 清单 retain ──→ S9 WSD 删除行为 ──→ S10 禁新建探针（U3 可能触发上报）
```

**并行化说明**：
- A2e 判定 S1/S2/S3/S6/S11/S12 为零依赖、理论可并行。
- **本 change 实际不并行派发**，全部切片顺序执行，`并行组` 一律记 `—`。理由：S2 与 S13 改同一份 `ci.yml`；S4/S7/S8/S9/S10 共用本机唯一 podman 守护进程与容器清单对账，并行会破坏 EXP-2026-0004 要求的前后快照比较；S5 消费 S4 产出的 `test-ownership.json` 形状。因此 B3.5（并行合并验证）不触发。

## 授权与执行边界（切片期强制）

- 数据库验证只经 `run-selection.mjs` 自建一次性 podman 实例（TTL ≤3600s），运行前后核对 `podman ps -a`；基线为 `multica-postgres`、`multica-backend` 均 Exited，二者状态必须不变。
- **不执行 `quality.test` 配置的 `make test`**：它经 `scripts/ensure-postgres.sh` 拉起旧 `multica-postgres` 并连 `localhost:5432`，属 U5 明确排除项。替代口径见 Part C，并在 test-report 如实标注该配置命令未执行及原因。
- 不读取/打印/创建凭据，不改仓库 secret；`tools-access` 只消费已存在的环境变量且永不输出其值。
- Git 提交、推送、部署不在长程预授权内：U1 的 tools 推送与 U5 的"推送触发 CI"是设计级单独授权，执行前逐项列出提交与范围。
- 记录仓有大量他人未提交改动，只写本 change 目录，不清理、不混入。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟢 2 | M | — | TC-SEL-001, TC-SEL-002, TC-SEL-003 | `selection-decision.mjs::decideSelection` + `run-selection.mjs` 接线 | 无 |
| 2 | P0 | 🟢 2 | S | — | TC-CBE-003 | `.github/aifirst-tools-pin` + `tools-pin.mjs`(read/check) + `ci.yml` 现有 tools 检出改读 pin（第二个消费者由 S13 新建） | 无 |
| 3 | P1 | 🟢 1 | S | — | TC-CBE-004 | `go-test-env-contract.mjs` + 删 3 处 `CRCTL_MJS` 开发机默认值 + 1 处 `t.Skip`→`t.Fatal` | 无 |
| 4 | P0 | 🟢 2 | M | — | TC-TOR-001 | 一次性库整包基线 + `test-ownership.json` + `test-ownership.mjs`(check/skip-regex) | 无（需 podman） |
| 5 | P0 | 🟢 2 | M | — | TC-TOR-002, TC-TOR-003 | `test-go.sh --skip-regex/--json-out` + `ci-evidence.mjs` | 4 |
| 6 | P0 | 🟢 2 | M | — | TC-CBE-001 | `ci-provision.mjs`(up/down，R1 口令边界) | 无 |
| 7 | P0 | 🟢 1 | L | — | TC-CBE-002 | 两份门禁的逐条件表驱动测试 + identity selection | 4（需 podman） |
| 8 | P0 | 🟢 3 | L | — | TC-WSD-001 | 清单新增 `workspaceDeleteRetain` + 19 表登记 + retain 断言 | 4（需 podman） |
| 9 | P0 | 🟡 5 | L | — | TC-WSD-002, TC-WSD-003, TC-WSD-004 | `governance.DeleteWorkspaceExecutionRows` + `deleteSteps` 追加 + 行为/回滚测试 | 8 |
| 10 | P1 | 🟢 3 | M | — | TC-WSD-005 | 已删 workspace 的 selection 禁新建 reservation/command 探针 | 9 |
| 11 | P0 | 🟢 1 | S | — | TC-CCF-001 | `tools-access.mjs`（可注入 fetch，永不输出 token） | 无 |
| 12 | P0 | 🟢 1 | M | — | TC-CCF-002 | `use-logout.test.ts` 包导入 + views typecheck 0 TS6059 | 无 |
| 13 | P0 | 🟢 3 | L | — | TC-SEL-004, TC-TOR-004 | `ci.yml` provision/evidence/script-checks 接线 + `ci-paths.json` scope + 独立入口真实执行 | 2,5,6,7,8,9,10,11,12 |

manual TC（TC-CBE-005、TC-TOR-005、TC-CCF-003）不单独成切片：它们依赖真实 CI run、管理员动作与验收报告，在 Part C 以 `stdd agent confirm` 人工确认，未满足前置的如实记为未闭合。这样每个切片都有 >0 新增自动化测试（长程强制约束 #3）。

> **C1 更正（规划期断言被实测证伪，原文保留）**：上句「每个切片都有 >0 新增自动化测试」不成立。**S12 实测 `new_tests: 0`**（TC-CCF-002 在锁定证据计划里是 command 型，断言对象是 `tsc` 退出码与错误码计数，不是测试函数；另造冗余测试会把长程约束的形式置于证据实质之上）。该偏离已如实登记为 **ADJ-019**（minor，unresolved），并写入 `phase-context.md` Slice 12 与 `.stdd.yaml` 的 `slices_completed['12'].new_tests: 0`，未报「B3.4 三项全过」。约束 #5 的降级条件是**连续 3 切片**无新增测试：S11=15、S12=0、S13=4，**不触发降级**。

## Rationale

### Slice 1: selection 对账决策（P0，先行）
- **依赖关系**：`decideSelection` 是纯函数，不碰容器；先修它才能让后续所有 `run-selection` 真实执行的对账结果可信（否则 S4/S7–S10 的 PASS 行本身不可信）。
- **风险分析**：跨模块 +1、MODIFIED 且接口变更 +1 = 2。命中 EXP-2026-0003（逐行解析、不取首行）——`verifyGoTestSelection` 的流输入纪律必须保留。
- **工作量估算**：M。3 个 TC，新增 1 个源文件 + 1 个测试文件，改 `run-selection.mjs` 两处。
- **变异验证**：把 blocked 判断改回读 `.matched`/`.blocked` 必须变红，结果记入证据。

### Slice 2: 单一 tools pin（P0，先行）
- **依赖关系**：pin 是 S13 的 CI 接线与 S4 基线中 tools 相关测试的前置。
- **风险分析**：跨模块 +1、接口变更（ref 来源）+1 = 2。U1=α 要求 pin 指向 origin 上存在的提交；`e52b808` 未推送前 pin 完整性检查在真实 CI 必然红，本地单测用临时 fixture 目录验证，不冒充 CI 已验证。
- **工作量估算**：S。1 个 TC，1 个新源文件 + 1 个测试文件 + 1 个 pin 文件 + `ci.yml` 两处最小改动。

### Slice 3: 去开发机路径与 skip→Fatal（P1，先行）
- **依赖关系**：无。静态契约检查，纯源码扫描。
- **风险分析**：1（低风险）。契约检查自身必须能对注入旧默认路径/`t.Skip` 的样例变红，否则是空检查。
- **工作量估算**：S。1 个 TC，4 处 Go 源码最小改动。

### Slice 4: 整包基线与归属表（P0）
- **依赖关系**：基线证据是 `test-ownership.json` 除 3 个已知项以外条目的唯一合法来源（SC-TOR-001 AND）。S5 的 `ci-evidence` 消费该表形状。
- **风险分析**：跨模块 +1、复杂度（容器 + 整包枚举）+1 = 2。命中 EXP-2026-0004（失败路径也要释放实例、前后核对容器清单）。整包基线可能暴露更多"整包下不成立"的专项测试——只有带证据的才可入表。
- **工作量估算**：M。1 个 TC，但含一次真实整包运行与逐项证据整理。
- **附带**：design 未验证事实 #1、#2（TestMTick003）在本切片定位；判定树按 design 决策 11 执行，结论写入 pending-adjustments 或修订。

### Slice 5: test-go.sh 参数与 CI 证据对账（P0）
- **依赖关系**：依赖 S4 的 `test-ownership.json`（必需包与排除名单来源）。
- **风险分析**：跨模块 +1、接口变更（新增两个参数）+1 = 2。`test-go.sh` 是上游文件，只做挂钩点并标 `AIFIRST`；现有 `set -eu` 无 `pipefail`，`--json-out` 必须保证退出码透传。命中 EXP-2026-0003。
- **工作量估算**：M。2 个 TC，改 1 个上游脚本 + 其测试，新增 1 个源文件 + 1 个测试文件。

### Slice 6: ci-provision（P0）
- **依赖关系**：复用既有 `provision.mjs`，不依赖其他切片；S13 接线消费它。
- **风险分析**：跨模块 +1、安全敏感（凭据边界）+1 = 2。按 R1：handle 只存去口令的管理员 URL，`down` 从 job 级 `AIFI45_CI_ADMIN_URL` 取回；日志与 handle 不含明文口令，`GITHUB_ENV` 的 `DATABASE_URL` 是唯一允许带口令处且先 `::add-mask::`。命中 EXP-2026-0004（`up` 失败路径也要能 `down`）。
- **工作量估算**：M。1 个 TC，但拒绝分支多（marker 不符、handle 缺失、口令不外泄）。

### Slice 7: nonce 门禁逐条件测试（P0）
- **依赖关系**：需一次性库；S4 已验证容器路径可用。
- **风险分析**：1。命中 EXP-2026-0005（复制品只测一个失败条件）——本切片正是该经验的修复。按 R2，条件名由子测试承载，门禁实现一行不改。
- **工作量估算**：L。1 个 TC 但 11 个条件 × 2 份实现，且每条单独退化必须变红。

### Slice 8: workspace 删除清单 retain 分类（P0）
- **依赖关系**：S9 的行为测试依赖本切片的分类与断言。
- **风险分析**：EXP-2026-0001（high，常量 id 撞唯一键）+2、跨模块 +1 = 3。19 张表逐表登记依据来自迁移 643–648 头注释与 D2；retain 断言查 `pg_trigger`/`pg_constraint`。
- **工作量估算**：L。1 个 TC，改上游清单测试（只追加、标记、`CUSTOM.md` 登记）。

### Slice 9: 删除实现与行为测试（P0，最高风险）
- **依赖关系**：依赖 S8。
- **风险分析**：EXP-2026-0001 +2、EXP-2026-0002（high，check-then-act 与锁序）+2、跨模块 +1 = 5 → 🟡。真实 `DeleteWorkspace` 事务、retain 行逐字节不变、回滚不半删；测试数据用随机唯一键，不用常量 id。
- **工作量估算**：L。3 个 TC，新增自研函数 + 上游 `workspace.go` 一处挂钩 + handler 行为测试。

### Slice 10: 禁新建探针（P1，U3 上报点）
- **依赖关系**：依赖 S9（需要已删 workspace 与保留的 selection 行）。
- **风险分析**：EXP-2026-0001 +2、跨模块 +1 = 3。**若当前代码放行，红灯即为发现**：按 U3 停下上报，不静默修复、不放宽断言、不改触发器。
- **工作量估算**：M。1 个 TC。

### Slice 11: tools 凭据诊断（P0）
- **依赖关系**：无；S13 接线消费它。
- **风险分析**：1。安全红线：任何输出与错误信息不含 token 值，请求头只在 fetch 调用内使用。
- **工作量估算**：S。1 个 TC，7 种返回分支。

### Slice 12: views typecheck 恢复（P0）
- **依赖关系**：无。
- **风险分析**：1。U4 边界：只保证 typecheck 与本地 vitest；若暴露 `26f6c5b0a` 夹带前端功能的自身失败，先报告再裁定。
- **工作量估算**：M。1 个 TC，改 1 个测试文件的导入 + 可能 1 行 `core/package.json` exports（未验证事实 #5）。

### Slice 13: CI 接线与独立入口（P0，收口）
- **依赖关系**：消费 S2/S5/S6/S11 的产物，需要 S7–S10 的测试已存在才能被 CI 真跑。
- **风险分析**：跨模块 +1、接口变更 +1、真实 CI 行为未验证 +1 = 3；回归矩阵对 `ci.yml`/`ci-paths.json` 评级 🔴。改 `ci.yml` 会触发全部 scope，推送次数压到最少并先本地等价验证。
- **工作量估算**：L。2 个 TC（SEL-004 命令型、TOR-004 独立入口真实执行），含 WSL `AIFI-ISO` 与两个状态敏感 selection。
- **授权**：WSL 启动与 podman 实例由 U5 预授权；执行前说明、执行后核对容器清单。profile 失效则如实列为未覆盖，不用同 uid 对照冒充。