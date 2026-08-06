---
id: CR-2026-023-plan
type: PLAN
cr-ref: CR-2026-023
sdd-ref: "change-requests/CR-2026-023/sdd.md"
target-version: tbd
status: draft
created: "2026-08-07T00:30:00+08:00"
updated: "2026-08-07T00:30:00+08:00"
---

# PLAN — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）

## 1. 交付里程碑

| 里程碑 | 提交批次 | TASK | 内容 | 估算 |
|---|---|---|---|---|
| M1 块 B：R9 护栏 + 存量清零 | commit 1（原子） | TASK-01~03 | lint-prompts R9 规则 + 三类测试向量 + 17 处存量清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 第 7 条 | 13h |
| M2 块 A：评审 LLM 选择暂停节点 | commit 2 | TASK-04~05 | pipeline JSON（review_llm 输入 + 0013 human_approval 节点 + review-code prompt 头部）+ `_index.yml` nodes 12→13 + README 节点表/mermaid 同步 | 8h |
| M3 收尾验收 | commit 1/2 后 | TASK-06 | 五步自检 + pre-commit 三件套 + 溯源标注 + 端到端验收（AC-11 两场景） | 4h |

估算总工时：25h（约 3.1 人天）；TASK 级求和与里程碑分段核对一致（M1 4+3+6=13 + M2 5+3=8 + M3 4）。

## 2. 任务依赖图（与 tasks/_index.yml depends-on 一致）

```
M1 块 B：TASK-01（R9 规则）→ TASK-02（测试向量，依赖规则落地）→ TASK-03（17 处清零，需 R9 上线后 --mode report 核对命中恰为 17）
         TASK-01/02/03 三者同 commit 1 原子提交（NFR-1：规则 + 测试 + 清零拆分提交会让 pre-commit enforce 自阻断）
M2 块 A：TASK-04（pipeline JSON）→ TASK-05（_index.yml + README 同步，nodes 计数以 TASK-04 结果为准）
         M2 依赖 M1（护栏先行，SDD §4.3；pipeline-templates/ 不在 R9 scope，块 A 不触发 R9，但顺序上 commit 1 先于 commit 2）
M3 收尾：TASK-06 依赖 TASK-01~05 全部完成（FR-13 五步自检 + AC-11 端到端）
```

关键链：TASK-01 → TASK-02 → TASK-03（块 B 内串行，同 commit）；TASK-04 → TASK-05（块 A 内串行）；M1 整体先于 M2（护栏先行）；TASK-06 收尾依赖全部。

## 3. 资源与分工

- 开发：Ray（全部 TASK，tools 仓单仓作业）
- 测试：Ray（TASK-06 回归 + 各 TASK 验收条件）
- 评审：Ray（人工审批节点；本 CR 已过需求/技术设计审批）

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 17 处清零漏改/多改导致 enforce 自阻断 | TASK-03 上线前 `--mode report` 核对命中恰为 17（对照附件2 §4.2 表），行号以内容锚点定位（纪律 #4） | revert commit 1 恢复旧基线 |
| tools 仓 3 处未提交 pipeline JSON 与本 CR 同文件冲突 | TASK-04 前与用户确认归属，按 hunk 拆分 add（SDD §4.3 基线协调） | 仅 revert 本 CR hunk |
| R9 误报（短名 skill 子串匹配普通文本） | TASK-02 域外反向用例 + TASK-03 逐行人工核对；pipeline 名模式要求 `pipeline` 词尾共现收窄 | 调整 R9 命中条件后重跑 |
| README mermaid 图遗漏同步（附件1 §2.6 只提节点表） | TASK-05 显式列入 mermaid D8→新节点→D9（SDD §4.2 实跑核对 L425-426） | revert README 改动 |
| 块 B 原子提交过大难以 review | commit 1 内按文件分 hunk 清晰标注（R9 / 清零 / 配套三类），commit message 列清单 | — |

## 5. 验收与发布策略

- 验收：AC-1~AC-11 逐条对照 PRD；TASK 级验收条件见各 TASK 文件
- 发布：tools 仓改动合入 `custom/main`（CR-2026-022 先例，tools 不在 repositories 声明、不派生 worktree）
- feature-flag：无（R9 为 lint 规则，enforce 级别即生效开关；如需灰度可先 `--mode report` 观察）
- 估算交叉校验（FR-23）：plan 总工时 25h 与 TASK 级 estimate 求和一致，无 WARN
