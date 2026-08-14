---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-023-TASK-01
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 块 B — lint-prompts.mjs 新增 R9 规则（FR-7）
slug: r9-rule-impl
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

在 `lint-prompts.mjs` 实现 R9 规则：CR 上下文域 skill 的「下一步」提示必须收敛到 `crctl next {cr_id}`，禁止手写 skill/pipeline 名映射副本。级别 CONTRADICTS（enforce 阻断）。判据源直读 `skills/_index.yml` 提取全部 skill id。SDD §4.1 已给出四处改动的伪代码骨架。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lint-prompts.mjs`（四处改动，结构锚点见 SDD §4.1）

## 实现要点（SDD §4.1）

1. 常量区（L27-28 `CRCTL_PATH`/`INBOX_SKILL_PATH` 模式旁）追加 `SKILLS_INDEX_PATH = path.resolve(__dirname, '..', '..', '..', '_index.yml')`——`__dirname` 固定解析，不随 `--root` 变（SDD §5.2 决策）。
2. `loadJudgements()`（L32-46）追加：读 `SKILLS_INDEX_PATH` 先 `\r\n → \n` 规范化（纪律 #1），正则 `/^\s*-\s*id:\s*([\w-]+)/gm` 提取 skill id 入 `Set`，返回值追加 `skillIds`。
3. `runRules(para, ctx)`（L116 起）在 R8 块（L196 附近）后追加 R9 块：scope `/^skills\/(requirement|develop|writeback|sync|cr)\//` 且非 `/cr-show/`；逐行判定——含「下一步」且不含 `crctl next` 且（含任一 skill id 或命中 pipeline 名模式 `/\b(requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture)\s+pipeline\b/`）→ push `{ rule:'R9', level:'CONTRADICTS', ... }`。行号用 `para.startLine + li`（与 R7/R8 一致）。
4. 文件头注释规则清单（L14）追加「+ R9（CR 上下文『下一步』提示收敛 crctl next）」。

`<!-- lint-prompts:ignore -->` ±1 行豁免由既有段落级机制自动适用，R9 不新增豁免代码。`ctx = { ...loadJudgements() }`（L238）自动把 `skillIds` spread 进 ctx。

## 验收条件

1. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode report` 可正常执行不报错（规则语法正确）。
2. 手工构造一个 CR 上下文域 SKILL.md 含「下一步 : 执行 review-requirement」，`--mode report` 输出含 `R9` 与 `CONTRADICTS`。
3. 域外文件（如 `skills/planning/x/SKILL.md`）含同类文本不命中 R9。

## 完成标志

R9 规则代码落地 + `--mode report` 对构造违例命中、对域外零命中；本 TASK 与 TASK-02/03 同 commit 1 提交（NFR-1）。
