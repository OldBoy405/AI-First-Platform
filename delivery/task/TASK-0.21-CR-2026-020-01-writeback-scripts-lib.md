---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-020-TASK-01
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: lib.mjs 公共库（CRLF 归一 / frontmatter 读改 / 锚点断言 / dry-run diff / fail）
slug: writeback-scripts-lib
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

在 `tools/skills/writeback/scripts/` 下新建 `lib.mjs`，实现三个回写脚本共用的定向 YAML/文本处理原语（SDD §4.5）。这是 TASK-02/03/04 的前置依赖，必须先落地。

## 涉及文件 / 模块

- 新建 `tools/skills/writeback/scripts/lib.mjs`
- 参考（只读，不改）：`tools/skills/shared/crctl/scripts/crctl.mjs` 的 `parseYaml`/`fail`/`ok` 实现风格，用于对齐错误码与输出格式约定，不导入其代码（SDD §8 D2：不抽取 crctl 函数）

## 实现要点（引用 SDD §4.5、§3）

1. `normalize(text)` — `\r\n → \n`，纪律 #1。
2. `readFrontmatter(text)` / `patchFrontmatterField(text, field, value)` — 定位首个 `---...---` 块，按字段名行首锚定读取/替换；字段不存在时按 SDD §2.2 规则插入（PRD/SDD frontmatter 场景）；命中 0 次或 ≥2 次一律 `fail('ANCHOR_NOT_FOUND'|'ANCHOR_NOT_UNIQUE', ...)`，不静默降级。
3. `extractBlock(text, startPattern, indentSensitive)` — 缩进敏感的 YAML 块定向提取，供只读解析 `_backlog.yml` 的 `merge-commits[]`、`specs/_index.yml` 的 `features[]` 条目、`delivery/task/_index.yaml` 条目。
4. `unifiedDiff(oldText, newText)` — dry-run 模式下打印的简单统一 diff（不引入 diff 库，纯字符串行对比即可，SDD 未要求语义 diff）。
5. `ok(obj)` / `fail(code, message, extra)` — JSON 输出到 stdout/stderr + 对应退出码，风格与 crctl.mjs 的 `ok()`/`fail()` 一致（可读源码对齐格式，不 import）。
6. **硬边界**：本文件不得包含任何写 `_backlog.yml`/`_history.yml`/`cr.md`/CR 内 `tasks/_index.yml` 路径的函数（SDD §2.1 硬边界、NFR-5）。

## 验收条件

1. `node -e "require('./lib.mjs')"` 等价的 ESM 动态 import 冒烟通过（无语法错误、无循环依赖）。
2. 手工构造一个含 `\r\n` 的 frontmatter 样例文本，`patchFrontmatterField` 更新后输出不含 `\r`；对同一字段构造"命中两次"的样例，断言抛出 `ANCHOR_NOT_UNIQUE` 且非零退出（可用最小 `if (require.main)` 自检块或留给 TASK-05 覆盖，二选一但需在本 TASK 验收时手工跑一次确认）。
3. `grep -n "_backlog.yml\|_history.yml\|cr.md\|tasks/_index.yml" lib.mjs` 命中的都是注释/文档字符串，不是文件路径写操作。

## 完成标志

`lib.mjs` 落盘，上述 3 条验收手工跑通，commit 到 tools 仓（分支 `requirement/CR-2026-020`）。
