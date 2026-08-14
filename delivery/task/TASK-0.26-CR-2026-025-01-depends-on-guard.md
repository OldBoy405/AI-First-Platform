---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-025-TASK-01
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 项② task done 一跳依赖守卫
slug: depends-on-guard
status: pending
estimate: 2h
depends-on: []
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

在 `crctl task done` 的 CAS 写入前新增直接 `depends-on`（一跳）依赖守卫，把 implement-code 的 prompt 层拓扑排序升级为账本机械强制（PRD 项②，SDD §4.2）。

## 2. 涉及文件

- 修改：`tools/skills/shared/crctl/scripts/crctl.mjs`（`cmdTaskDone`）
- 修改：`tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（追加向量）

## 3. 实现要点

- 新增纯函数 `guardDependsOn(normText, taskId)`：入参为 `cmdTaskDone` 已读入并 CRLF 规范化的 `_index.yml` 文本，不重复读盘；复用既有 `parseYaml`（FR-8，禁新写解析/正则提取）。
- 判定顺序（SDD §4.2）：`depends-on` 缺失或 `[]` → 放行（D-5）；引用不存在 TASK → `DEPENDS_ON_UNKNOWN`；存在 `status != done` 前置 → `DEPENDS_ON_NOT_DONE`，detail 列出每个未完成前置的 `{id, status}`，message 末尾追加"若前置互相等待，检查 depends-on 是否成环"。
- `depends-on` 解析出非数组形态 → 复用既有 `SCHEMA_INVALID`，detail 指向该字段；**不新增** `DEPENDS_ON_SHAPE`（TD-BL-3）。
- 守卫插入位置：既有三项前置校验之后、`casWrite` 之前；拒写时 `_index.yml` 不得有任何字节变化。

## 4. 验收条件

1. FR-10 五类向量全过：①前置未 done → `DEPENDS_ON_NOT_DONE`、退出非 0、`_index.yml` sha256 不变（AC-7）；②前置全 done → 正常写 `status: done` + `done-at`（AC-8）；③缺失/`[]` 放行（AC-9）；④悬空引用 → `DEPENDS_ON_UNKNOWN`；⑤带引号 `["ID"]` 与不带引号等价（钉 parseYaml unquote）。
2. 补一条非数组形态向量 → `SCHEMA_INVALID`；补 A→B→A 与 A→A 环夹具 → 有限时间返回 `DEPENDS_ON_NOT_DONE`（AC-10）。
3. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿。

## 5. 完成标志

上述向量全绿 + `crctl.test.mjs` 既有用例零回归 + 任务状态在 `_index.yml` 登记 done。

## 6. 接口契约

- 消费：既有 `parseYaml(text): object`、`fail(code, message, extra)`、`casWrite(p, expectedHash, newText)`（均不改签名）。
- 产出：`guardDependsOn(normText: string, taskId: string): void`（内部函数，失败即 `fail()`，无返回值）——TASK-03 的 review-record 重构不消费本函数，仅共享同文件提交纪律。
