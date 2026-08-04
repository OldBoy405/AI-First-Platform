---
id: CR-2026-020-TASK-05
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: test/writeback.test.mjs 回归自检套件
slug: writeback-scripts-test
status: pending
estimate: 4h
depends-on: [CR-2026-020-TASK-02, CR-2026-020-TASK-03, CR-2026-020-TASK-04]
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

把 TASK-02/03/04 手工验收过的场景固化为 `node --test` 自动化用例，覆盖幂等、锚点唯一性、CRLF 归一、硬失败路径（NFR-6、AC-8）。

## 涉及文件 / 模块

- 新建 `tools/skills/writeback/scripts/test/writeback.test.mjs`
- 覆盖 `lib.mjs`、`writeback-prd-sdd.mjs`、`writeback-tasks.mjs`、`writeback-traceability.mjs`

## 实现要点（引用 SDD NFR-6、AC-8）

1. 用 Node 内建 `node:test` + `node:assert`，不引入测试框架，测试数据用临时目录（`node:fs.mkdtempSync`），不依赖外部固定状态。
2. 覆盖场景（对应 TASK-02/03/04 验收条件的自动化版本）：
   - lib.mjs：CRLF 归一、frontmatter 字段命中 0/1/≥2 次的三种断言结果
   - writeback-prd-sdd：首次回写、增量追加+既有内容不变、重复执行 noop、dry-run 不落盘
   - writeback-tasks：slug 有/无两种命名、SDD-BLOCK-001 场景（slug 后补重跑不产生重复文件）、索引全量重建顺序、重复执行 noop
   - writeback-traceability：merge-commits 提取正确性、milestone-file 结构校验失败、既有历史段字节级不变、merge-commits 缺失硬失败、重复执行 noop
3. 显式断言：`grep`-等价方式检查三脚本源码不包含对 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml` 的写路径引用（对应 AC-4，用字符串扫描源码文本实现，不需要真正执行写操作）。

## 验收条件

1. `node --test tools/skills/writeback/scripts/test/writeback.test.mjs` 全绿，一次运行不依赖外部状态（自建临时目录、结束时清理）。
2. 用例数覆盖上述"实现要点 2"列出的全部场景（每个子点至少 1 个用例）。
3. AC-4 的账本路径隔离断言包含在用例中且通过。
4. `node --test tools/skills/shared/crctl/scripts/test/crctl.test.mjs` 仍全绿（确认未误碰 crctl 现有代码或测试）。

## 完成标志

测试文件落盘，`node --test` 两个套件（本套件 + crctl 既有套件）均全绿，commit 到 tools 仓。
