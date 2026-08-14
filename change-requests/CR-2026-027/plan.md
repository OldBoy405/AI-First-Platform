---
id: CR-2026-027-plan
type: PLAN
cr-ref: CR-2026-027
sdd-ref: "change-requests/CR-2026-027/sdd.md"
target-version: tbd
status: draft
created: "2026-08-09T23:30:00+08:00"
updated: "2026-08-09T23:30:00+08:00"
---

# 开发计划 — tools 流程优化 Phase 0+1：基线事实统一与正确性修复

## 1. 交付里程碑

| 里程碑 | 内容 | 涉及文件 | 估算 |
|---|---|---|---|
| M1 bootstrap + Phase 0 基线统一 | workspace `dir-graph.yaml` 加入 tools repo；从 `custom/main` 补建 tools worktree（记录 `bootstrap-base-sha`）；workspace `AGENTS.md` 状态机口径 27/49；tools `ARCHITECTURE.md` §3/§4/§5 修订（口径、单文件、crctl-Pipeline 依赖描述）；v2 方案文档删除 command module/通用上下文命令描述；优化指标基线固化 | workspace `dir-graph.yaml`、`AGENTS.md`、`docs/analysis/tools流程步骤优化v2.md`；tools `ARCHITECTURE.md` | 1.5 人天 |
| M2 approve 原子提交 | `approveAndAdvance` 内部 helper（TTY/grant 收敛）；evidence override seam（`readEvidenceDoc` 第 4 参 + `runGateChecks` opts.evidence）；`assertCandidateStatus` 独立校验（CANDIDATE_STATUS_MISMATCH）；两文件 casWriteMulti + 单次 commit + outbox 时序；拒绝路径保持 | tools `crctl.mjs`、`crctl.test.mjs` | 2 人天 |
| M3 TASK 门禁 + 幽灵清理 | `deliveryIndexComplete` 五步判定（TASK_INDEX_MISSING/TASK_LIST_EMPTY/TASK_STATUS_INCOMPLETE/DELIVERY_INDEX_MISSING）；`cmdMigrateBacklog` 幽灵块清理阶段（幂等 already-clean、GHOST_ENTRY_ORPHANED 硬失败） | tools `crctl.mjs`、`crctl.test.mjs` | 1.5 人天 |
| M4 archive-move 原子化 + 终态查询 | archive-move 三账本（backlog/history/index）同一 casWriteMulti + archive event 入 history notify-log + 收件人 owners 去重/legacy 回退/空收件人硬失败；重复调用 already-archived 幂等（含 finalStatus）；`inbox-emit` 空 `--to` → BAD_ARGS；终态只读 resolver（status/next fallback，CR_LOCATION_CONFLICT/history 硬失败/cr.md 漂移告警） | tools `crctl.mjs`、`crctl.test.mjs` | 2 人天 |
| M5 review-record + next freshness/上游重入 | 返回 files/attempt/route（按 stage 真值表）/repairTarget；pass 时 repairTarget=null；tech-design annotation 写 SDD subject digest；post-PASS upstream revision 自动开启新 review cycle；`cmdNext` 在 task-breakdown 从 dev-plan annotation 重算 repair/upstream，在 tech-design-review-pending 校验 SDD freshness；四个 review Skill 删除 traceability 二次读取 | tools `crctl.mjs`、`crctl.test.mjs`、`skills/{requirement,develop}/review-*.SKILL.md` | 1 人天 |
| M6 Skill 同步 + 全量验证 | `merge-feature-branch` 删除 tools 特例；`cr-archive` 对齐三账本 CAS 契约；ARCHITECTURE §8 登记；五项最小验证（diff-check/pipeline JSON parse/crctl tests/lint-prompts enforce/两项 grep）全绿 | tools `skills/writeback/merge-feature-branch/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`ARCHITECTURE.md` | 1 人天 |

**总估算：9 人天**（M1 1.5 + M2 2 + M3 1.5 + M4 2 + M5 1 + M6 1）

## 2. 任务依赖图

```text
M1（bootstrap + Phase 0 文档统一）——tools worktree 是一切 tools 改动的落点
  ├─> M2（approve 原子化）        # crctl.mjs 内，依赖 M1 worktree
  ├─> M3（TASK 门禁 + 幽灵清理）  # crctl.mjs 内，与 M2 文件分区不重叠
  ├─> M4（archive 原子化 + 终态查询）
  └─> M5（review-record + next freshness） # TASK-08 先产出 subject/cycle，TASK-07 再消费实现 next 路由
       └─> M6（Skill 同步 + 五项验证 + §8 登记）——全部代码落地后收尾
```

- M1 先行：tools worktree 未就位前禁止任何 tools 改动（FR-15 硬约束）。
- M2~M5 均在 `crctl.mjs` 内但函数面不重叠（cmdApprove 系 / deliveryIndexComplete+migrate / cmdArchiveMove+cmdInboxEmit+resolver / cmdReviewRecord），按提交批次原子性要求分批提交，可顺序串行推进。
- M5 的 review Skill 修改依赖 M5 的 crctl 输出契约先落定；M6 收尾含 lint-prompts enforce（改 Skill prompt 后必跑）。

## 3. 资源与分工

| 角色 | 职责 | 预计投入 |
|---|---|---|
| dev-agent（Ray） | M1~M6 全部：crctl.mjs 六处执行层改造、文档统一、Skill 同步、测试向量 | 9 人天 |
| quality-reviewer-agent | review-dev-plan 评审执行（can-call 角色） | 纳入评审阶段 |

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| approve 重构影响既有 TTY/grant 审批路径 | helper 收敛后四 stage 行为断言（一次提交/零写入/拒绝路径保持）全覆盖；现网审批流程先手工验证一轮 | 回退 crctl.mjs 单提交（M2） |
| archive-move 三账本 CAS 改动影响归档流程 | 测试覆盖三种终态 + 重复调用 + 中文 reason + 收件人边界；026 归档流程为实景参照 | 回退 crctl.mjs 单提交（M4） |
| 状态机口径 25/47→27/49 的文档断言遗漏 | AC-1 grep 判定（范围+上下文）在 M1 与 M6 各跑一次；lint/check 族在触及文件时按「改什么测什么」追加 | 回退对应文档提交 |
| ghost 清理误删在途 CR | GHOST_ENTRY_ORPHANED 硬失败（history 无对应归档不删）；AC-14 断言 CR-2026-017 字段恢复 | 回退 crctl.mjs 单提交（M3） |
| 旧 SDD PASS 或旧 review cycle 错误放行审批 | `cmdNext` 比对 SDD subject digest 与较新 dev-plan upstream blocker；新 cycle 保留旧 attempts、每 cycle 独立 maxAttempts=3；legacy 无 cycle/digest 有明确兼容规则 | 回退 M5 单提交，恢复旧 next/review-loop 解析 |
| 行尾纪律（CRLF） | 全部解析/哈希路径先 CRLF→LF 归一；git diff --check 纳入五项验证 | 按提交级 revert |

全部改动无数据迁移（除 ghost 清理本身）、无 schema 破坏；回滚均为单次 revert。

## 5. 验收与发布策略

发布前 checklist：
- [ ] tools worktree `requirement/CR-2026-027` 存在且 `bootstrap-base-sha` = custom/main HEAD；custom/main 无本 CR 直接提交（AC-22）
- [ ] grep 按 AC-1 判定：25/47「现状」表述与 tools 隐藏特例清零（M1 + M6 两次）
- [ ] 四 stage approve 一次提交、gate 失败零写入、`CANDIDATE_STATUS_MISMATCH` 零写入（AC-8~10）
- [ ] archived 五类 TASK 门禁失败 + 全 done 放行；rejected/withdrawn 不适用（AC-11~13）
- [ ] `crctl migrate-backlog` 幽灵块消失、CR-2026-017 恢复、`already-clean` 幂等（AC-14）
- [ ] archive-move 三账本同批 + 重复调用 `already-archived`；`inbox-emit` 空 to → BAD_ARGS（AC-15~16）
- [ ] 三种终态 status/next 可查、`next:null`（AC-17）
- [ ] review-record 返回 files/attempt/route/repairTarget；四 review Skill 无二次读取（AC-18）
- [ ] task-breakdown 无/畸形/PASS/repair/upstream/exhausted 路由正确；tech-design SDD stale/upstream blocker 不得建议审批；post-PASS revision 开启新 cycle 并保留旧 attempts（AC-23）
- [ ] 五项最小验证全绿（AC-19）；无新增第三方依赖/公共 Runner 库/新子命令（AC-20）
- [ ] 历史 CR 查询/归档行为兼容（AC-21）
- [ ] ARCHITECTURE.md §8 登记 + merge/archive Skill 同步完成（AC-5/AC-22）

发布策略：无 feature-flag（tools 包正确性修复，随 crctl 版本发布）；历史 CR 不要求新增证据文件（NFR-6）；ghost 清理为一次性迁移，实施期在主工作区执行一次并提交。
