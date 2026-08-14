---
id: CR-2026-021-plan
type: PLAN
cr-ref: CR-2026-021
sdd-ref: "change-requests/CR-2026-021/sdd.md"
target-version: tbd
status: draft
created: "2026-08-05T11:50:00+08:00"
updated: "2026-08-05T11:50:00+08:00"
---

# PLAN — prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）

> target-version 保持 tbd（SDD §8-D3 决策：tools 包无自有 semver，不绑产品版本线，按治理里程碑 **T1.3** 追踪，延续 CR-2026-019 T1.1 / CR-2026-020 T1.2）。

## 1. 交付里程碑

| 阶段 | 内容 | 估算 |
|---|---|---|
| 设计 | PRD + SDD（已完成，各 1 轮评审自修复：需求 REQ-BLOCK-001、技术 SDD-BLOCK-001） | — |
| M0 crctl 核心（Phase 0，9 写 + 2 读 + 1 扩展子命令 + D13 调查） | TASK-01~10 | 34h |
| M1 漂移防线（lint-prompts + 两层 gate） | TASK-11~12 | 10h |
| M2 P0 prompt 修正（Phase 1，不依赖 M0，可并行） | TASK-13~15 | 8h |
| M3 cr-status-set 清退（Phase 2） | TASK-16 | 5h |
| M4 账本写入迁移（Phase 3，依赖 M0） | TASK-17~21 | 20h |
| M5 冗余精简收尾（Phase 4） | TASK-22 | 5h |
| 联调/验收 | 全量 `crctl.test.mjs` + `lint-prompts.test.mjs` 跑绿 + 挑一次真实 CR 走完整 pipeline 验证 | 4h |

**估算总工时：86h（约 11 人天）**——按 TASK 列表求和（FR-21/D15 精简后的口径，本 plan 自身即示范）。

## 2. 任务依赖图

```
TASK-01 (D13 溯源调查，门槛但不阻塞其余)  ─────────────────────┐
                                                              │
TASK-02 (S1 review-record)   ─┐                              │
TASK-03 (S2 review-note)      │                              │
TASK-04 (S3/S4/S5)            ├─→ TASK-10 (文档+rules.json#git│
TASK-05 (inbox-emit)          │      白名单收尾，依赖 02~09)  │
TASK-06 (S6+S8 合并)          │            │                  │
TASK-07 (S7 task allocate)    │            │                  │
TASK-08 (S9+S11 只读)         │            │                  │
TASK-09 (S10 git --template)  ─┘            │                  │
                                            ↓                  │
TASK-11 (lint-prompts.mjs) ──→ TASK-12 (两层 gate 接入)        │
                                                              │
TASK-13 (D7+approve-*)  ─┐  （M2，不依赖 M0，可与上方并行）    │
TASK-15 (D3 test-report) ─┤                                   │
TASK-14 (裸 git→crctl git，依赖 TASK-10 白名单)                │
                                                              │
TASK-16 (cr-status-set 清退，不依赖 M0)                        │
                                                              │
TASK-17 (review-*/write-test-report → S1)     依赖 TASK-02     │
TASK-18 (cr-review-record/handover-cr/                        │
         push-progress/write-requirement-prd/inbox-emit skill)│
         依赖 TASK-03/04/05                                    │
TASK-19 (requirement-register 全量改造)        依赖 TASK-06/08/09
TASK-20 (write-dev-tasks + worktree-path 去重 + commit template)
         依赖 TASK-07/08/09
TASK-21 (dashboard→S11；validate-doc 视 D13)   依赖 TASK-08 + TASK-01 结论 ──┘

TASK-22 (D8 去重 + 冗余精简 + 回写清单新增项，Phase 4，收尾)   依赖 TASK-17~21 完成
```

关键路径：TASK-02~09（并行）→ TASK-10 → TASK-14；TASK-02~09 → TASK-17~21（并行）→ TASK-22。TASK-01/11/12/13/15/16 不在关键路径上，可穿插并行。

## 3. 资源与分工

单人（Ray）串行执行。建议顺序：TASK-01（先起头，产出结论前不阻塞别的）→ {TASK-02~09 并行实现，逐个提交} → TASK-10（收尾核对）→ {TASK-11→12} 与 {TASK-13/15、TASK-16} 穿插 → TASK-14（等 TASK-10 白名单补齐后）→ {TASK-17~21 并行，各自依赖对应 crctl 子命令已落地} → TASK-22（最后收尾）。

## 4. 风险与回滚策略

| 风险 | 应对 |
|---|---|
| SDD §8 三处偏差（D1 归档 gate 挂点纠正 / D2 cr-init 分配语义 / D3 target-version 不绑产品版本）在实现中发现仍不成立 | 已在 SDD 评审 attempt 1 人工确认；若编码中发现新证据推翻，回到 write-tech-design 补一轮 reviewLoop，不得在 TASK 里静默改设计 |
| **CI cr-guard enforcement 是否真接线生效**（tech-design 评审 suggestion-1，遗留风险，非阻断） | TASK-12 验收条件要求**实测确认**：静态核查 CI workflow 是否实际调用 `cr-guard.template.yml`；若发现只是模板未接线，TASK-12 范围扩大到把它接上，不能只在 SDD 里理论声明。若受限于本环境无法验证 CI 真实触发，需在 TASK-12 完成摘要中显式标注该残余风险，不得静默视为已解决 |
| **D13（PRD/SDD schema validator）调查结论未知，可能改变设计** | TASK-01 独立先跑，产出「复活/不复活」结论；TASK-21 的 validate-doc 部分按结论分支处理，若复活需要新的设计小节（在 TASK-21 描述中已预留）——不在 SDD 定案前臆造实现 |
| **lint-prompts R1 对 pipeline JSON 的段落切分粒度未定**（tech-design 评审 suggestion-3） | TASK-11 验收条件要求：先定义切分规则（pipeline node 的 prompt 字符串按空行/编号列表切分为段，而非整个 prompt 视为一段），并用至少 1 个 fixture 验证边界情况（同一 prompt 内既有正确调用又有手写案例） |
| Phase 3 迁移期间遗漏某个孤儿写入未被 R1 覆盖 | TASK-22 最终跑一次 `lint-prompts --mode report` 全仓扫描，人工核对输出为 0 CONTRADICTS/STALE-REF 才算 M5 完成 |
| lint-prompts gate 若在漂移未清零阶段被误设为 enforce，会拦死本 CR 自身开发期提交 | TASK-12 严格按 SDD §4.4 分阶段：M1~M4 期间 pre-commit 用 `--mode report`；确认 TASK-22 完成、`lint-prompts` 输出零漂移后，才把 pre-commit 切到 `--mode enforce`（作为 TASK-22 的最后一步，而非 TASK-12 内） |
| cr-init 分配语义变更（SDD 0.1.1，内部分配返回 id）与既有 requirement-register 手写流程衔接遗漏 | TASK-19 验收条件要求验证 requirement-register 改造后不再传入显式 cr-id 给 cr-init，且并发测试（复用 TASK-06 的组件级 mismatch-hash 手法）覆盖 |
| 回滚 | 全部改动限定在 tools 仓独立 commit，未合并前可随时 `git reset`；已迁移的 SKILL/pipeline 文件通过 git revert 单 commit 回退 |

## 5. 验收与发布策略

- 每个 crctl 子命令 TASK 落地后立即跑 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增用例）。
- M1 完成后跑 `node skills/shared/crctl/scripts/lint-prompts.mjs --mode report` 确认能正确检出「已知漂移 fixture」且不误报正确示范文本。
- M4 全部 Phase 3 迁移完成后，`lint-prompts --mode report` 对全仓扫描应输出 0 CONTRADICTS/STALE-REF；此时（且仅此时）TASK-22 把 `.githooks/pre-commit` 切到 `--mode enforce`。
- 发布前 checklist：PRD AC-1~15 逐条核对 + SDD FR→AC 映射（§6）逐条核对 + `crctl.test.mjs`/`lint-prompts.test.mjs` 全绿 + 挑一次真实小型注册流程（走 requirement-register→...→cr-dashboard）验证新子命令链路可用。
- 无 feature-flag 需求：新增子命令是纯增量能力，旧 SKILL 手工描述在对应 commit 切换前仍可用；发布即替换 SKILL 描述，无需灰度。里程碑 T1.3 归档时按 §8 维护规则同步 `ARCHITECTURE.md`。
