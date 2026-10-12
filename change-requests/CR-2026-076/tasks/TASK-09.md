---
id: CR-2026-076-TASK-09
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "单一 Git tree 比较缝、合入等价推进与发布 source 固定"
slug: workspace-transactions-compare-tree-seam
status: pending
estimate: 20h
depends-on: [CR-2026-076-TASK-06]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-08、FR-09、FR-11；AC-17／AC-20／AC-21／AC-22；SDD §4.8、§4.10 + D-02）：建立**唯一**的整棵 Git tree 内容比较缝，供 G05（合入对象核验）与 G06（同步后最小重验）两个消费目的共用；并按 §4.10 把发布事务的发布意图（source）固定。

背景与输入条件：`dep-14` 结论原文——参与仓解析、release-subjects 构造与重核、远端提交分类已集中在 `lib/workspace-transactions.mjs`，可作为 tree 等价比较与发布意图固定的单一落点；`dep-15` 结论原文——合入入口 `cmdMerge` 存在且含远端源／受控只读查询与失败回流，可挂载 G05 等价推进判定；`dep-21` 结论原文——远端发布事实由 `cmdCheckpoint` 收口，本地提交与远端发布已分层。

明确不做：不在 crctl 内双实现比较逻辑（D-02）；不设扩展名白名单、不设 `codeRoot`、不做语义哈希；不改签名算法、`rules.json` 白名单与受控路径 shape（§9 `zero_diff`）；不新增 Git 裸面调用，涉及 Git 的调用一律走 `rules.json` 已允许的受控入口。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：新增 `compareTree`；沿用 `resolveRepositories`（:81）、`deriveInstallRoot`（:47）、`buildReleaseSubjects`、`renderReleaseSubjects`（:1279）、`verifyReleaseSubjects`、`classifyRemoteCommit`（:518）、`classifyCheckpointRemote`（:531）
- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdMerge(ws, positional, flags)`（:3787）、`async function cmdCheckpoint(ws, cr, gates, flags)`（:2516）
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`、`test/checkpoint-tx.test.mjs`、`test/workspace-resolver.test.mjs`

## 实现要点

1. 比较缝签名与判据严格按 SDD §4.8（唯一实现，两个 purpose 共用）：
   ```text
   compareTree(ws, cr, {purpose}) → { perRepo: [{repo, refA, refB, equal, reason}], allEqual }
     purpose=g05: 被评审/批准代码源 vs 当前已提交源
     purpose=g06: 测试报告记录的源 vs 同步后源
   判据：git rev-parse <refA>^{tree} 与 <refB>^{tree} 相等（整个 tree：代码、测试、README、配置）
         不可判（对象缺失/工作区不健康/多仓任一不可判）→ 不宣称全仓等价
   ```
2. SHA 与内容的职责分离：SHA 继续承担历史追溯与发布事务身份；内容等价不抹掉版本信息（tree 相等 ≠ SHA 相等）。
3. G05 合入（§4.8 末段）：tree 相同 → 允许以额外空提交等内容等价源推进，**不因 HEAD 不同回实现**；tree 不同 → 先更新测试／代码评审证据并执行必要的原代码确认，不得直接合入。
4. 代码源不可判（FR-11）：先沿既有读取／同步路径恢复原 Git 对象；仍不可判则建立新测试、代码评审与必要代码确认事实，**不以当前 HEAD 补造历史 source**、不伪造原批准、不无理由重做实现。
5. 知识仓其他 CR 的已提交账本变化**不**算当前代码资源变化（AC-21）；当前 CR artifact 按合法本地／server-approve 规则分别核验（与 TASK-06 同判）。
6. 多仓（FR-08.4）：逐仓结论、逐仓 path authority 取 `resources[].worktreePath`；各仓分别提交、同批 `checkpoint` 纳管。
7. 发布意图固定（§4.10）：新发布事务固定本次实际发布 source；已有产生副作用的 journal 按原意图与 source 恢复，后来的等价 HEAD 或文档变化不得改变进行中的发布对象；一致面为批准入口、release-subjects 构造与重核、`merge` 远端源预检、后续 publish 消费者**同一口径**，不得只放宽单个 helper。

## 验收条件

1. **AC-17（cmd-07）**：HEAD 变但 tree 相同 → 合法本地路径可继续，并保留 SHA 追溯与签名检查（断言 `equal=true` 且下游不因 HEAD 不同回实现）。
2. **AC-20（cmd-05 + cmd-07）**：原代码源不可取得先恢复；不可判则建立新证据，不以当前 HEAD 补造历史 source。
3. **AC-21（cmd-07）**：知识仓其他 CR 的已提交账本变化不计为当前代码资源变化。
4. **AC-22（cmd-07）**：部分 publish 后恢复仍使用原 journal 固定的 source（后来的等价 HEAD／文档变化不改变发布对象）。
5. **单缝约束**：断言 `compareTree` 的实现只有 `lib/workspace-transactions.mjs` 一处（crctl 侧只调用不复制）。
6. 运行范围以 plan §6.2 为唯一事实源：`cmd-07` = 三文件（`merge-tx.test.mjs` + `checkpoint-tx.test.mjs` + `workspace-resolver.test.mjs`）；`cmd-05` 仅其与恢复分支相关的用例面。**不声称**覆盖 `workspace-transactions.mjs` 的其他命令面；真实执行输出落 `test-evidence/cmd-07.log`（需要时并附 `test-evidence/cmd-05.log`）。

## 完成标志

- `compareTree` 单缝落地，G05／G06 两个 purpose 共用同一实现；发布 source 固定在构造与重核两端一致；
- `cmd-07`（及关联 `cmd-05`）真实执行退出码 0 并留证；`rules.json` 未改动（结果中给出零改动声明）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-06 产出 + `dep-14`／`dep-15`／`dep-21`，不得缩写）：
- `runGateChecks` 的 `warnings[]` 分流口径（TASK-06 产出）：本 TASK 的等价推进不得放宽硬条件；
- `export function resolveRepositories(workspace)`（:81）、`export function deriveInstallRoot(opWs)`（:47）、`export function renderReleaseSubjects(rs)`（:1279）、`export function verifyReleaseSubjects(...)`、`export function classifyRemoteCommit({remoteSha, expectedBase, commitSha, commitIsRemoteAncestor, journalSaysPublished})`（:518）、`export function classifyCheckpointRemote({remoteSha, sourceSha, remoteIsSourceAncestor, sourceIsRemoteAncestor, journalSaysPublished})`（:531）。

产出（供 TASK-10／TASK-17 消费，消费方不得缩写）：
- `compareTree(ws, cr, { purpose })` → `{ perRepo: [{repo, refA, refB, equal, reason}], allEqual }`（逐字，SDD §4.8）；`purpose ∈ {g05, g06}`；不可判时 `equal` 不得为 `true`，且 `reason` 必须给出不可判原因；
- `async function cmdMerge(ws, positional, flags)`（:3787）新增等价推进分支：tree 等价 → 允许空提交等内容等价源推进；不等价 → 非零回流要求先更新测试／评审证据；
- `async function cmdCheckpoint(ws, cr, gates, flags)`（:2516）发布 source 固定语义：事务创建时固定，恢复时按原 journal 意图与 source，不随后续 HEAD／文档变化改变；
- 错误面：不可判 → 既有技术错误出口（§3.2），不新增同义错误码；dirty／diverged／unknown 仍按既有技术失败合同处理。
