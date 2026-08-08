---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-025-TASK-04
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 项① checker 检查 4（external 引用点校验）+ 解析守卫与首测
slug: external-ref-check
status: pending
estimate: 2h
depends-on: [CR-2026-025-TASK-03]
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

`check-skill-matrix.mjs` 新增第 4 项检查：actor 级 `external` 声明必须在扫描范围内有至少一处引用点，零引用报红；同步补行尾规范化与三段空结构硬失败守卫；新建该脚本首个测试文件（PRD 项①，SDD §4.1）。实施前提（024 批次一已合入 `custom/main` commit `18358df`）已满足。

## 2. 涉及文件

- 修改：`tools/skills/shared/crctl/scripts/check-skill-matrix.mjs`
- 新建：`tools/skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs`

## 3. 实现要点

- **解析扩展**：`external` 收集保持全局 `externalSkills` Set（检查 2 不变）的同时新增 `externalByActor`（actor → 技能名[]）供检查 4 错误文案（FR-3）。
- **行尾纪律**：新增 `readNorm(path)`（readFileSync → `replaceAll('\r\n','\n')`），三个读入点改经该函数；三个逐行入口 `split('\n')` 改 `split(/\r?\n/)`（FR-3）。
- **空结构硬失败守卫（TD-BL-2）**：`activeSkills.size === 0` / `Object.keys(ownsByActor).length === 0` / `## 主责矩阵` 切分缺失或表格行零命中 → `console.error` + `process.exit(1)`；只判解析产物为空，不重复检查 1/2 的单条目职责。
- **检查 4**：扫描 `skills/`+`pipeline-templates/` 递归，`.md/.json`，目录级排除 `openwiki/old/node_modules/.git`，`agent-skill-matrix.yml`/`AGENT-SKILL-MATRIX.md` 自身不计引用点；子串匹配（I-3）；零引用 → 错误文案含技能名与全部声明 actor，退出非 0（FR-1/FR-2）。文件头注释"检查项"清单补第 4 条（AC-3）。
- **测试**（FR-5/D-8）：`node --test` + `spawnSync` 黑盒，`mkdtempSync` 夹具（NFR-7），零第三方依赖；六类向量：①有引用点通过；②零引用退出非 0 含技能名；③多 actor 声明+有引用（brainstorming 形态）通过；④多 actor 声明+零引用列出全部 actor；⑤CRLF/LF 同内容结果一致；⑥既有三检查回归各 ≥1 条；另加三份输入各自空结构硬失败夹具（TD-BL-2 后半）。

## 4. 验收条件

1. 上述六类 + 空结构向量全过（AC-1/AC-2/AC-3/AC-6）。
2. 在 024 批次一已合入的真实 tools 仓上运行 `node check-skill-matrix.mjs` 通过（AC-5：4 项声明均有引用点）。
3. 只在 `openwiki/` 出现的名称仍判红；只在 `pipeline-templates/*.json` prompt 出现的名称判绿（AC-2）。

## 5. 完成标志

`check-skill-matrix.test.mjs` 全绿 + 真实仓实跑通过 + `_index.yml` 登记 done。

## 6. 接口契约

- 消费：无上游 TASK 产出（与 TASK-01~03 无代码依赖，depends-on 仅为批次顺序）。
- 产出：`check-skill-matrix.mjs` 退出码契约扩展（新增一类报红），供 TASK-06 的用途表/文档同步引用；测试文件供 TASK-07 纳入 FR-22 三测试文件清单。
