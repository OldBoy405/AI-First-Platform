---
id: CR-2026-038-plan
type: PLAN
cr-ref: CR-2026-038
sdd-ref: "change-requests/CR-2026-038/sdd.md"
title: tools Writeback 原子化开发计划
target-version: tbd
status: draft
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:41:17+08:00"
total-estimate: 46h
---

# 开发计划

## 1. 目标与边界

在 CR-2026-038 的 tools worktree 内深化现有 `applyWriteback()` 与 `mergeCr()`：将 baseline 文件和 `merging -> writing-back` 状态纳入同一可恢复发布事务，把完整 candidate preflight 前置到 lock/journal 之前，并在 knowledge-base merge 中只替换目标 CR 的完整 backlog 条目。

严格复用 `crctl.mjs` 的状态/门禁、`workspace-transactions.mjs`、`durable-tx.mjs`、三个版本化 generator、现有 YAML block matcher 和原生 Git plumbing。不新增 npm 依赖、事务框架、manager、registry、YAML patch 平台、后台清理器或任意复合状态接口。不修改 Agent、README、状态机、gates、人工审批、Multica 或 knowledge-base baseline。

## 2. 交付里程碑

| 里程碑 | TASK | 产出 | 完成条件 |
|---|---|---|---|
| M1 Preflight 基础 | TASK-01 | 新 CLI 红测、固定 generator/candidate、manifest snapshot、advance preflight 与 planned-existing | 非法输入零 journal/authority；内部接口定型 |
| M2 Baseline 原子发布 | TASK-02 | 状态复合 write-set、稳定 transitionAt、journal input 绑定、origin-confirmed 投影与恢复 | 单 commit 同含 baseline/status；故障重放唯一 |
| M3 Backlog 语义 merge | TASK-03 | 条目替换纯函数、raw blob、synthetic merge tree、initial/rebuild 共用 prepare | 非目标 backlog 字节不变；最终 ancestry 保持 |
| M4 调用方迁移 | TASK-04 | 三个 Skill、feature-writeback Pipeline、crctl Skill/help/index 和旧测试调用收缩 | active 生产调用方零 candidate/generator/独立 advance |
| M5 回归与交付证据 | TASK-05 | 全量测试、双平台兼容断言、范围审计与验证记录 | AC-01～AC-12 可追溯且现有测试全绿 |

## 3. TASK 清单与估算

| TASK | 标题 | 估算 | 依赖 | 主要仓库 |
|---|---|---:|---|---|
| CR-2026-038-TASK-01 | 构建失败优先的 Writeback preflight 基础 | 10h | 无 | tools |
| CR-2026-038-TASK-02 | 实现 baseline 状态同批发布与恢复投影 | 14h | TASK-01 | tools |
| CR-2026-038-TASK-03 | 实现 backlog 条目语义 merge tree | 10h | TASK-02 | tools |
| CR-2026-038-TASK-04 | 一次性迁移 Writeback 调用方契约 | 6h | TASK-03 | tools |
| CR-2026-038-TASK-05 | 执行全量回归与交付范围审计 | 6h | TASK-04 | tools + knowledge-base evidence |

总估算：**46h**。`target-version` 因 PRD 未指定版本而保持 `tbd`，实施期不得自行猜测发布版本。

## 4. 依赖图与执行顺序

```text
TASK-01 -> TASK-02 -> TASK-03 -> TASK-04 -> TASK-05
```

逻辑上 baseline 与 merge 可分别验证，但 TASK-01～TASK-03 都修改 `workspace-transactions.mjs` 或共用 fixture，因此按文件所有权串行，避免并发覆盖。TASK-04 必须等内部接口与 merge 行为稳定后一次性切换全部 active 调用方；TASK-05 只做必要修复、全量验证和证据，不引入新功能。

## 5. 实施策略

### 5.1 失败优先

TASK-01 先通过内部 test seam/validator 单测固定 preflight、candidate snapshot 与 gate 契约，确认关键新断言在实现前失败，再写最小基础能力；此时不切换公共 dispatch。TASK-02～TASK-03 的新 writeback/merge 路径保持未接入生产，现有公共调用在中间提交继续可用。公共新 CLI、BAD_ARGS 契约和端到端黑盒测试只在 TASK-04 与全部调用方同批切换；恶意 manifest 始终通过内部 seam 覆盖，不恢复新公共 `--candidate` 参数。

### 5.2 最小代码路径

- `crctl.mjs` 只提炼状态候选、门禁 callback、CLI adapter 与投影 adapter；
- `workspace-transactions.mjs` 拥有固定 generator、candidate snapshot、writeback/merge Git 事务；
- `durable-tx.mjs` 只登记新的 fault point；
- backlog locator 仅在确需共享时下沉到现有 `yaml-subset.mjs`；
- 使用 Node 标准库、`spawnSync(shell:false)` 与原生 Git，不添加模块层级或依赖。

### 5.3 迁移策略

公共 CLI、三个 Skill、Pipeline、help/index 和旧生产测试在 TASK-04 同一提交切换：同一提交启用新业务输入 dispatch、删除旧 candidate dispatch 并迁移所有 active 调用方，不产生任何已提交的公共双入口或失效中间态。generator 的内部 `--candidate-out` ABI 与内容转换算法保持不变。

## 6. 资源与分工

- 开发负责人：Ray；测试负责人：Ray。
- 单人按 TASK 拓扑串行实施，无并行 runner 依赖。
- 代码只写入 `.rayai-worktrees/tools/requirement/CR-2026-038`；CR 文档和证据只写入对应 knowledge-base worktree。
- Multica worktree 和 `CUSTOM.md` 必须零修改。

## 7. 验收与验证矩阵

| 验证面 | TASK | PRD 验收 |
|---|---|---|
| 新 CLI、固定 generator/candidate、manifest 一次读取、零副作用 preflight | TASK-01 | AC-02、AC-05～AC-07、AC-11 |
| baseline 文件/status 同 commit，journal-created/apply/commit/push/projection 恢复 | TASK-02 | AC-01～AC-03、AC-06 |
| backlog 首/中/末、前后新增、缺失/重复、CRLF、最终 parents | TASK-03 | AC-08～AC-10 |
| Skill/Pipeline/help/index 无外泄参数与独立 advance | TASK-04 | AC-04、AC-07 |
| crctl/writeback 全量、Prompt lint、matrix、JSON、静态范围与跨平台检查 | TASK-05 | AC-11、AC-12 |

发布前执行：

```text
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
所有 pipeline-templates/*.json 可 JSON.parse
```

## 8. 风险与控制

| 风险 | 控制 |
|---|---|
| journal 创建后状态 after image 尚未保存即崩溃 | 使用 `journal.createdAt` 作为稳定 transitionAt，重放生成相同 text/hash |
| 恢复误续改变后的业务参数 | fixed-key canonical businessInputDigest 与 manifestDigest 共同绑定 journal inputDigest |
| planned-existing 放宽其他门禁 | 仅 `fileExists` 分支消费完整验证后的精确 Set |
| candidate TOCTOU 或路径越界 | manifest/blob 一次读入；containment、symlink parent、allowlist 与 hash 全校验 |
| backlog 覆盖其他并行 CR | 最新 trunk 为基底，只替换 source 中目标 CR 唯一完整块 |
| synthetic commit 改变发布 ancestry | synthetic 只计算 tree；最终 parents 固定为最新 trunk + 原 source |
| 调用方迁移不完整 | TASK-04 静态扫描 active CLI/Skill/Pipeline/tests 并同批切换 |
| Windows 行尾误判 | 解析前 CRLF→LF；backlog raw blob/原始偏移保真；Windows/Ubuntu 测试 |

## 9. 回滚与发布策略

### 9.1 代码回滚

- TASK-01～TASK-03 在 TASK-04 前无生产调用方，可按提交逆序 revert；
- TASK-04 的公共接口与所有调用方必须整体 revert，不允许只恢复 CLI 或只恢复 Skill；
- TASK-05 只允许修复回归，不以删除测试或放宽 gate 通过。

### 9.2 运行时恢复

- 预检失败：修正业务源后重跑同一命令；
- 未发布 origin stale：txws reset 到新 origin，重新生成 candidate；
- 已 commit 未 push：按原 journal 续推；
- origin confirmed 后投影失败：Git 事实保持，重放只补缺项；
- 已发布 baseline 原子 commit 不拆分、不自动 revert、不手改 journal 或账本。

### 9.3 发布 checklist

- [ ] 五张 TASK 均经 `crctl task done` 即时登记 done；
- [ ] tools 定向与全量测试、Prompt lint、Skill matrix、Pipeline JSON 全通过；
- [ ] active 调用方静态扫描无旧公共参数和独立 writing-back advance；
- [ ] changed-files 位于 SDD §1.5 白名单，Multica 零 diff；
- [ ] test-report、代码评审与人工审批证据完整后再进入 writeback。

## 10. 完成定义

- SDD FR 4/4 与 PRD AC 12/12 均有自动或静态验证证据；
- 同一 baseline writeback 最终最多一个 authority commit、status outbox 和 advance audit；
- merge 结果只替换目标 CR backlog 条目，final parents 契约不变；
- 不增加依赖、状态、gate、registry、manager 或范围外文档修改；
- 所有受控状态、TASK 进度和评审证据均由 crctl 写入。

## 11. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 5 个串行 TASK、46h；覆盖 preflight、baseline 原子事务、semantic merge、调用方迁移与全量回归 |
| 2026-08-14 | v0.2.0 | Ray | dev-plan attempt 1 回修 DP-BL-1/2：TASK-01～03 限定为未接入生产的内部路径，TASK-04 同批切换 CLI/调用方；TASK done 以受控索引为唯一进度事实 |
