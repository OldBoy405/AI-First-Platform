---
id: CR-2026-022-TASK-19
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 收尾 — 三台账同步 + 自检回归 + 口径 25/47 核查 + 文档更新（FR-33/34）
slug: closing-audit
status: pending
estimate: 10h
depends-on: [CR-2026-022-TASK-01, CR-2026-022-TASK-02, CR-2026-022-TASK-03, CR-2026-022-TASK-04, CR-2026-022-TASK-05, CR-2026-022-TASK-06, CR-2026-022-TASK-07, CR-2026-022-TASK-08, CR-2026-022-TASK-09, CR-2026-022-TASK-10, CR-2026-022-TASK-11, CR-2026-022-TASK-12, CR-2026-022-TASK-13, CR-2026-022-TASK-14, CR-2026-022-TASK-15, CR-2026-022-TASK-16, CR-2026-022-TASK-17, CR-2026-022-TASK-18]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

收尾（报告 §三 收尾 + §6.4 文档更新）：三台账同步、全量自检回归、状态机口径 25/47 全仓核查、97 条发现勾验清单、端到端验收三场景。

## 涉及文件 / 模块

- `skills/_index.yml`、`agents/_index.yml`、`agent-skill-matrix.yml` 三台账（含批 2/4 删除条目、新增 shared 条目）
- `tools/ARCHITECTURE.md`：§3 代码地图（cr-init 新旗标/--cr/口径 25/47）、§8 维护规则登记本 CR
- `skills/shared/crctl/SKILL.md`：cr-init 新旗标、`--cr` 旗标、checkpoint-add 全非终态、approve 回退说明
- `lint-prompts.mjs` 头部规则说明（R6/R7 + 豁免范围契约）
- 主仓 `AGENTS.md`：#2 状态数口径（23→25 声明 / 45→47 展开）、#6 历史注脚不动、抽 shared 原则（报告 §6.4 批 4 落地后）
- 报告 `docs/analysis/prompt-audit-report-2026-08-05.md`：97 条勾验状态标注（建议在报告尾部加落地核对表，不覆盖正文）

## 实现要点

1. 三台账同步：删 cr-status-set/record-adr/write-insight-brief/run-competitive-analysis 条目（批 2/4 已删文件）、新增 shared 片段条目（批 4 新建）
2. 回归套件全跑：`crctl.test.mjs`、`lint-prompts.test.mjs`、`check-skill-matrix.mjs`、改过的 pipeline JSON 解析自检、writeback.test.mjs（若有）
3. 口径核查：`grep -rn "23 条声明\|45 条"` 全仓（tools + 主仓）清零旧口径，更新为 25/47
4. 97 条发现勾验：对照报告 §二 修改清单逐项打勾（done），未覆盖项必须说明原因
5. 端到端验收（报告 §6.2 三场景）：场景 1 完整 CR 生命周期（含本 CR 自身作为灰度消费者——本 CR 后续流程就是演练）；场景 2 通知链两事件；场景 3 lint 三类违规注入
6. 灰度演练（NFR-5）：cr-init 新旗标注册 + drafting 态 checkpoint-add + decline 回退三条新路径用测试 CR 走通

## 验收条件

1. 三台账与文件系统一致（check-skill-matrix.mjs 绿 + 人工核对）
2. 全部回归套件绿
3. 全仓无 23/45 旧口径（历史注脚除外，主仓 AGENTS.md #6 是历史背景可保留但需标注）
4. 97 条发现勾验表 100% 闭合
5. 端到端三场景验证通过记录入 test-report
6. ARCHITECTURE.md/crctl SKILL/AGENTS.md 更新落地

## 完成标志

验收 1~6 通过 + 向审批人提交 test-report（供 approve-code 使用）。
