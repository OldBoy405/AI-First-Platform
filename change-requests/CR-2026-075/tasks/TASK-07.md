---
id: CR-2026-075-TASK-07
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: engineering-docs 合同与北京时间日期
slug: engineering-docs-contract-and-beijing-date
status: pending
estimate: 4h
depends-on: []
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

修订 engineering-docs 的合同文本与日期规则（FR-06、FR-07；SDD §4.4/§4.6/§4.7）：删除「frontmatter 必须通用委派」与固定 `owClient.writeFile` 表述，明确参考模板与完整执行的区别；工程文档侧 `today()` 改为固定 UTC+8（北京时间）规则，`isoDate` pattern 不动；规划/竞品不再请求不存在的 DESIGN-DOC/COMPETITIVE 通用类型。本 TASK 产出 TASK-04/05 调用的 SKILL 文本基线。

## 涉及文件 / 模块

- `skills/shared/engineering-docs/scripts/src/utils/slug.ts` — `today()` 签名与实现。
- `skills/shared/engineering-docs/scripts/src/generators/base.ts` — 两个消费点（`:134`、`:196`）。
- `skills/shared/engineering-docs/scripts/src/validators/index-sync.ts` — 消费点（`:49`）。
- `skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts`、`skills/shared/engineering-docs/scripts/src/__tests__/validators.test.ts` — 北京时间跨日与宿主时区向量（两者均为本 CR 声明发布的 in-scope 测试文件，属 `cmd-11` 期望集）。
- `skills/shared/engineering-docs/SKILL.md` — 合同文本（触发描述 `:3`、步骤 3 模板节、步骤 5 `owClient.writeFile` 表述）。

## 实现要点

- 日期唯一规则（SDD §4.7，DEC-6）：`beijingDate(now) = new Date(now.getTime() + 8h)` 取 UTC 日历字段拼 `YYYY-MM-DD`；`beijingIso(now)` 同法拼 `YYYY-MM-DDTHH:mm:ss+08:00`。工程文档侧 `today()` 改为 `today(now = new Date())` 走同一规则，**不依赖宿主时区、不依赖 tzdata、不使用 `TZ` 环境变量**；`isoDate` pattern（`dep-14`）不动。
- 消费点随之修正：`src/generators/base.ts:134/:196` 与 `src/validators/index-sync.ts:49` 的调用形态改为可注入时钟（测试可固定 `now`），默认参数保持向后兼容。
- 工程文档类型面保持 `dep-13`：不为规划/竞品新增 DESIGN-DOC/COMPETITIVE 通用类型；不批量重写存量文档；不调整前端 UTC 显示行为。
- 合同文本（SDD §4.6）：删除「frontmatter 必须通用委派」与固定 `owClient.writeFile` 表述；明确参考模板（只读模板/骨架）与完整执行（实际落盘路径由调用方 Skill 或受控入口承担，如 `crctl planning-entry` / `crctl competitive-report`）的区别；`validate-doc` 的触发条件口径与 TASK-06 一致（调用方步骤规定或用户显式请求）。
- 测试：新增北京时间向量至少覆盖跨日边界（UTC 前一日 16:00 与当日 15:59 两侧）与宿主时区差异（在非 UTC+8 宿主时区下渲染结果一致）；断言业务 timestamp 侧保持（`ISO8601` 含 `+08:00` 偏移，不写成纯日期或 UTC）。
- 环境前提（plan §5）：`skills/shared/engineering-docs/scripts/` 下需先安装依赖（`pnpm install`），该目录 `.gitignore` 已忽略 `node_modules/`、`dist/`、`.tmp-test/`，安装后 worktree 仍 `dirty=false`。

## 验收条件

1. 在 `skills/shared/engineering-docs/scripts` 目录执行证据命令 `cmd-07`（plan §6.2 原样：repo=tools、cwd=`skills/shared/engineering-docs/scripts`、executable=`node`、args=`["node_modules/vitest/vitest.mjs","run"]`、timeout=600）：全绿。真实运行范围 = 该 TS 包自身的 vitest 全量（`vitest run`，等价于该包 `test` 脚本），**不声称 tools 仓全量**。新增/调整向量覆盖：
   - AC-B8（日期面）：北京时间跨日边界两侧渲染匹配既有 `isoDate` schema；宿主时区差异下结果一致（含非 UTC+8 宿主的固定时钟向量）。
   - 默认参数兼容：不传 `now` 时 `today()` 仍返回当日北京时间日期。
2. 业务 timestamp 侧的同规则由 TASK-04/05 产出的 `beijingDate(now)`/`beijingIso(now)` 实现，证据命令 `cmd-02`（`node --test skills/shared/crctl/scripts/test/planning-entry.test.mjs`）与 `cmd-03`（`node --test skills/shared/crctl/scripts/test/competitive-report.test.mjs`）在各自 TASK 内断言；本 TASK 只声明同一规则、不重复实现、不在本 TASK 内运行这两个命令。FR-07 的联合证据（cmd-07 + cmd-02 + cmd-03）由 TASK-10 汇总复跑并在 test-report 的 FR-07 行记录。
3. 合同文本断言（静态）：`skills/shared/engineering-docs/SKILL.md` 不再出现「frontmatter 必须通用委派」与固定 `owClient.writeFile` 落盘表述；`cmd-06`（`node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs skills/shared/crctl/scripts/test/contract-scan.test.mjs skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/check-agents-contract.test.mjs skills/shared/crctl/scripts/test/lint-prompts.test.mjs skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`，timeout=300，cwd=tools CR worktree 根）保持全绿。本 TASK 不新增命令行。
4. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的六个文件（`node_modules/`、`dist/`、`.tmp-test/` 为已忽略项，不出现）。status 仅证明文件集。

## 完成标志

- `cmd-07` 全绿且跨日/时区向量逐条可见；`isoDate` pattern 未改。
- `today(now = new Date())` 在工程文档侧与 crctl lib 侧使用同一 UTC+8 固定偏移规则；两处实现各为其包内唯一来源，不互相依赖包（DEC-6）。
- 合同文本修订完成且 `cmd-06` 全绿；未新增 DESIGN-DOC/COMPETITIVE 通用类型、未批量重写存量文档。
- 产物已落盘并提交，commit 自含其新增测试；不改 `crctl.mjs`（与 TASK-01/03/04/06 无文件重叠）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- `src/utils/slug.ts:9` 既有 `today(): string`（宿主时区实现）与同文件 `toSlug`/`pad3`/`pad2`：本 TASK 只改 `today` 的签名与实现，其余导出不动。
- `src/generators/base.ts:11` 的 `import { today, titleCase, pad3 } from "../utils/slug.js"`；消费点 `:134`（frontmatter `today` 值）与 `:196`（`updated`）。
- `src/validators/index-sync.ts:6` 的 `import { today } from "../utils/slug.js"`；消费点 `:49`（`updated` 缺省值）。
- `src/validators/frontmatter.ts` 的 `isoDate` pattern（`dep-14`）：只读沿用，不改。
- `skills/shared/engineering-docs/SKILL.md` 现有文本：`:3` 描述中的 `owClient.writeFile`、步骤 3 模板节、步骤 5「调用 owClient 落盘」段落是本 TASK 的改写对象；模板文件与 `<%= var %>` 替换机制保留。

**产出**：

```typescript
// src/utils/slug.ts
export function today(now: Date = new Date()): string
// 实现 = 北京时间日历：new Date(now.getTime() + 8 * 3600 * 1000) 的 UTC 年/月/日，拼 YYYY-MM-DD
```

- 工程文档侧与业务 timestamp 侧的唯一日期规则（`beijingDate(now)`/`beijingIso(now)`，SDD §4.7）是共享契约：TASK-04/05 的 crctl lib 侧实现同一规则，两处必须通过同一组边界向量（本 TASK 的 vitest 向量 + TASK-04/05 的 crctl 侧向量），任一处漂移即红。
- 合同文本契约：`engineering-docs` 只维护调用方声明路径的索引（SDD §4.6）；规划/竞品不再请求不存在的通用类型；下游调用方（TASK-04/05 的调用面文本、TASK-08 的登记）引用同一份口径，不得缩写。
