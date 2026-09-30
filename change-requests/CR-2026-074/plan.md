---
id: CR-2026-074-plan
type: PLAN
cr-ref: CR-2026-074
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
status: draft
created: 2026-10-01T00:35:38+08:00
updated: 2026-10-01T01:35:00+08:00
---

# CR-2026-074 开发计划

承接已审批 `sdd.md` v0.2（tech-design attempt 2/3 PASS，Blockers 0）。范围：FR-1～FR-10、AC-01～AC-12 全部（SDD §9 scope_in）。交付仓分工：tools 全部生产代码/测试/文档；knowledge-base 承载本 CR 受控文档（由各 Pipeline 节点生成，不占开发 TASK）；multica 无代码变更。本文 TASK 编号即 canonical 完整 id（`CR-2026-074-TASK-NN`），与后续 `tasks/_index.yml` 的 id 集一致。计划层不含步骤粒度表述；步骤切分在 write-dev-tasks / implement-code 按 coding-discipline §2 执行。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 预估（人天当量） |
|---|---|---|---|
| M1 实现 | 模块代码 + 所属测试入口定向用例 | TASK-01～TASK-07 | 2.0 |
| M2 集成验证与文档同步 | 端到端 writeback 变体；说明/命令发现/计数同步 | TASK-08、TASK-09 | 1.0 |
| M3 收尾与评审 | ARCHITECTURE 地图维护；全量证据回归（cmd-01～cmd-06）；test-report；review-code | TASK-10 + 全量回归 | 0.5 |
| M4 发布 | review-code PASS → 人工 approve-code → 交付回写 | reviewer / delivery-agent | — |

M4 由 Pipeline 门禁承载，不属于开发 TASK；阶段发布由 reviewer 在评审 PASS 分支内一次闭合。

## 2. 任务依赖图

```text
TASK-01 kb init 入口/CLI/前置/发布重入（crctl.mjs + crctl.test.mjs init 用例）
  ├─→ TASK-02 ensure create 自忽略（workspace-transactions.mjs + register-tx.test.mjs 场景用例）
  │       [依赖 TASK-01 的 kb init 入口]
  │     └─→ TASK-03 source 空缺省 + 历史指纹矩阵（register-tx.test.mjs）
  │             [同测试文件，顺序编辑]
  └─→ TASK-07 rules.json 裸提交 shape + controlled-shell SKILL 同步（+ crctl.test.mjs 受控入口用例）
          [与 TASK-01 同测试文件，顺序编辑；逻辑独立]

TASK-04 buildIndex 缺文件首写 + features 前置校验（writeback-prd-sdd.mjs + writeback.test.mjs）
  └─→ TASK-05 两规范表提取（writeback-traceability.mjs + writeback.test.mjs）
        └─→ TASK-06 YAML trunk 解释（同上）
              [TASK-05/06 与 TASK-04 无逻辑耦合，仅同测试文件顺序编辑]

TASK-04/05/06 ─→ TASK-08 writeback-tx 无索引/证据齐全集成变体
TASK-01、TASK-03～TASK-08 ─→ TASK-09 说明/命令发现/计数同步
TASK-01、TASK-09 ─→ TASK-10 ARCHITECTURE.md 地图维护
        [TASK-10 消费 TASK-09 完成后的 SKILL/README/HELP 最终形态，须待 TASK-09 完成]
全部 TASK ─→ 全量证据回归 cmd-01～cmd-06 ─→ review-code
```

## 3. 资源与分工

单一执行 Agent：dev-agent（owners.development：Ray，人工审批人）。

| 仓库 | 分工 | 承载 TASK |
|---|---|---|
| tools | 全部生产代码、定向测试、文档同步 | TASK-01～TASK-10 全部 |
| knowledge-base | 本 CR 受控文档（plan/tasks/test-report 等） | Pipeline 节点受控生成，不占开发工时 |
| multica | 无代码变更（zero_diff） | 无 |

工时分配（人天当量）：M1 内 TASK-01 0.75、TASK-02 0.15、TASK-03 0.10、TASK-04 0.40、TASK-05 0.25、TASK-06 0.25、TASK-07 0.10；M2 内 TASK-08 0.60、TASK-09 0.40；M3 内 TASK-10 0.10、全量回归与报告 0.40。合计 3.5 人天当量。

## 4. 风险与回滚策略

| # | 风险 | 缓解 | 回滚 |
|---|---|---|---|
| R1 | rules.json 新 shape 扩大受控 Git 面 | 仅追加一条 merge-base shape，与两条旧 shape 并存；两旧 shape 单独回归，非法形态须不匹配全部三条才拒绝（SDD §4.6） | revert TASK-07，独立无下游 |
| R2 | source 缺省值变更影响注册指纹 | 历史 `manual` 不迁移、不做全局别名；冲突按 SDD §2.3 矩阵报原错误，零账本重写 | revert TASK-03；恢复旧默认后新空 source 历史仍不迁移 |
| R3 | features 前置校验对既有索引误拒 | 判据固定 `line.trimStart()==='features:'`，不新增其他收紧项；四类畸形负测覆盖（SDD §4.3、AC-05） | revert TASK-04 及其用例；TASK-05/06 无逻辑耦合 |
| R4 | 共享测试文件（crctl.test.mjs / register-tx.test.mjs / writeback.test.mjs）跨 TASK 编辑 | 依赖图约束顺序编辑；revert 按逆拓扑顺序 | 逆拓扑回滚顺序：TASK-10 → TASK-09 → TASK-08 → TASK-06 → TASK-05 → TASK-04 → TASK-03 → TASK-02 → TASK-07 → TASK-01 |
| R5 | kb init 无跨阶段事务隔离 | 合法模板/暂存/本地 commit 保留是接口合同；远端竞争由普通非快进 push 拒绝；重跑重新执行全部前置（SDD §4.1/§5.3） | 无自动 rollback；失败残留按 §3.2 错误边界报告 |
| R6 | 发布后缺陷 | 发布由门禁承载；不手改受控账本、不 force trunk、不改 durable-tx/apply | 正常 Git revert / 新 CR |
| R7 | ARCHITECTURE.md 地图遗漏 | TASK-10 明确列入 code review 检查项（SDD §8） | revert TASK-10 |

## 5. 验收与发布策略

- **环境静态前提**：无需常驻服务、浏览器或数据库。验收环境 = tools CR worktree（Pipeline `resources[].worktreePath`，`workspace inspect` 为 healthy 且 dirty=false 即就绪）+ Node ≥18 + Git；测试 fixture 均在临时目录自建仓，不触及用户全局 Git 身份。
- **环境 owner 与可获得性**：owner 为 dev-agent；worktree 由 Pipeline resources 建立，缺失/不健康时按 `ENVIRONMENT_MISMATCH` 中止并报告所需建立动作（该标签的唯一详细事实源是 implement-code，此处只引用不复述）。
- **readiness 证据**：复用证据命令表既有 `cmd-01`（其通过即证明 Node/Git/测试入口就绪），不新增命令行，不放宽「验收证据 ↔ 证据ID」双向唯一映射。
- **发布策略**：零新依赖 CLI，无 feature flag；review-code PASS → 人工 approve-code → delivery-agent 交付回写；阶段发布由 reviewer 在评审 PASS 分支一次闭合。

## 6. 两张稳定表

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 | §1/§3.1/§4.1 kb init 入口特判、输出与帮助 | CR-2026-074-TASK-01 | cmd-01 | revert TASK-01；连带下游 TASK-02/03 同批回退（其测试场景依赖 kb init），不声明为单点回滚 |
| FR-2 | §3.2/§4.1 前置顺序、错误优先级与失败残留 | CR-2026-074-TASK-01 | cmd-01 | 同 FR-1 |
| FR-3 | §2.1/§3.1/§4.1 两账本模板、独占创建、发布与重入 | CR-2026-074-TASK-01 / TASK-02 | cmd-01 + cmd-02 | revert TASK-01 与 TASK-02，按逆拓扑顺序先 02 后 01 |
| FR-4 | §4.2 ensure create 自忽略 | CR-2026-074-TASK-02 | cmd-02 | revert TASK-02（TASK-03 用例不依赖其行为，单点可回滚） |
| FR-5 | §2.2/§4.3 缺索引首写与全部既有索引 features 前置校验 | CR-2026-074-TASK-04 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-04；TASK-08 为其下游消费者 |
| FR-6 | §4.4 两规范表提取 | CR-2026-074-TASK-05 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-05 |
| FR-7 | §4.5 YAML trunk 解释 | CR-2026-074-TASK-06 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-06 |
| FR-8 | §8 说明/命令发现/测试计数同步 + §8 ARCHITECTURE.md 地图行（dep-15） | CR-2026-074-TASK-09 / TASK-10 | cmd-05 + cmd-06；地图内容由 review-code R7 检查项核验（SDD §8「随代码评审检查」） | revert TASK-10 → TASK-09（逆拓扑见 R4；TASK-10 为 TASK-09 下游） |
| FR-9 | §4.6 merge-base 裸提交 shape | CR-2026-074-TASK-07 | cmd-01 | revert TASK-07，独立无下游 |
| FR-10 | §2.3/§4.2 source 空缺省与历史指纹边界 | CR-2026-074-TASK-03 | cmd-02 | revert TASK-03，独立无下游 |

### 6.2 证据命令表（稳定表 2/2）

`cwd` 为 tools CR worktree 内相对路径，`.` 即该仓根；`args` 为 JSON token 数组。

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"] | 600 |
| cmd-02 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/register-tx.test.mjs"] | 600 |
| cmd-03 | tools | . | node | ["--test","skills/writeback/scripts/test/writeback.test.mjs"] | 600 |
| cmd-04 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/writeback-tx.test.mjs"] | 600 |
| cmd-05 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/caller-contract.test.mjs"] | 300 |
| cmd-06 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/lint-prompts.test.mjs"] | 300 |

命令算法唯一事实源为本表行；测试入口与证据范围对应 SDD §5.2 测试表。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01 init 精确模板/提交 tree/远端首 trunk/输出/二次 noop | §2.1/§3.1/§4.1/§5.2（dep-16 fixture） | CR-2026-074-TASK-01 | cmd-01 |
| AC-02 前置检查有序、错误 code/reason 固定 | §3.2 | CR-2026-074-TASK-01 | cmd-01 |
| AC-03 wx/续跑/失败残留与去注入恢复 | §4.1/§5.2 | CR-2026-074-TASK-01 | cmd-01 |
| AC-04 init 后首 CR：worktree、runtime ignore、主 KB clean | §4.2/§5.2（dep-16） | CR-2026-074-TASK-02 | cmd-02 |
| AC-05 缺索引首写与四类畸形 STRUCTURE_MISMATCH、apply 不重复 | §2.2/§4.3/§5.2 + apply fixture（dep-17/18） | CR-2026-074-TASK-08（主责：用户可观察的首写/隔离/幂等端到端面，writeback-tx apply 层产生该结果）；TASK-04 关联协作（buildIndex 结构负例与首写模块语义，断言全部保留于 cmd-03） | cmd-03 + cmd-04 |
| AC-06 规范表链/命令 ID 提取与空位/管道/诱饵 | §4.4 | CR-2026-074-TASK-05 | cmd-03 |
| AC-07 表结构正负、LF/CRLF 等价、authority 不变 | §4.4/§5.2 | CR-2026-074-TASK-05 | cmd-03 |
| AC-08 YAML trunk 解析与 TRUNK_UNKNOWN | §4.5 | CR-2026-074-TASK-06 | cmd-03 |
| AC-09 手工模板删除/保留、命令发现与计数一致 | §8 | CR-2026-074-TASK-09 | cmd-05 + cmd-06 |
| AC-10 裸提交祖先判定与拒绝形态 | §4.6 | CR-2026-074-TASK-07 | cmd-01 |
| AC-11 source 空缺省、显式合同不变、历史指纹矩阵 | §2.3/§4.2/§5.2 | CR-2026-074-TASK-03 | cmd-02 |
| AC-12 无索引 merge→三阶段→archive、独立 trace 重放 | §4.3～§4.5/§5.2（dep-17/18） | CR-2026-074-TASK-08 | cmd-04 |
