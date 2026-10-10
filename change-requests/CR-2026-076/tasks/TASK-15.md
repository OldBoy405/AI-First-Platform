---
id: CR-2026-076-TASK-15
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "历史事实只读扫描与 validate 只读维度 owner-source-anomalies"
slug: owner-source-scan-readonly-dimension
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-13, CR-2026-076-TASK-14]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-SUP-08；AC-SUP-08；SDD §4.16 + §3.1）：交付一次性**只读**扫描（版本化脚本 + `validate` 只读维度 `owner-source-anomalies`），列出非终态 CR 的 owner 身份异常与 `source` 路径异常，每项至少给出 CR-ID、字段／角色、原值与异常原因。

背景与输入条件：TASK-13 提供 owner 值域定义（成员 `user_id`），TASK-14 提供 `source` 值域定义（知识库内相对路径或 `""`）与 containment 口径；`dep-19` 结论原文——`validate` 已有可扩展的只读维度面（`errors`／`warnings`／`checked`／`notChecked`），可直接承载新维度。状态从 `cr.md` 读取，**不假定** `_backlog.yml` 含 `status`。

明确不做：不自动修复、不写受控账本（`_backlog.yml`／`cr.md`／`approval.yml` 等）、不阻塞无关 CR、不建定时巡检／缓存／名单系统；修复只经既有受控入口（`handover-cr`／`owner-set`）由人工裁决。历史 CR 的 owner 数据**不做全量迁移**。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/owner-source-scan.mjs`：**新建**版本化只读扫描模块（结构参照既有 `lib/*.mjs` 模块形态）
- `skills/shared/crctl/scripts/crctl.mjs`：`function cmdValidateDimensions(ws, target)`（:1566）与 `function cmdValidate(ws, target, gates)`（:1620）新增只读维度 `owner-source-anomalies`
- `skills/shared/crctl/scripts/test/owner-source-scan.test.mjs`：**新建**单文件测试（plan §6.2 cmd-06 的第二个文件）
- `skills/shared/crctl/scripts/test/gate-registry.json`：**同批登记**面——`manifest.files` 追加 `owner-source-scan.test.mjs`，`manifest.cases` 追加该文件的整数基线（实测顶层用例数）；与上面新建的测试文件**同一变更内落盘**（plan §5.5「登记面所有权」第 1 条）
- `skills/shared/crctl/SKILL.md`：`validate` 维度与「只报告不修复」语义说明（与 TASK-03 的合同文本同步同批口径）

## 实现要点

1. 扫描范围与输出（SDD §4.16）：非终态 CR 逐条给出 ≥ 4 个字段——CR-ID、字段／角色、原值、异常原因；状态一律从该 CR 的 `cr.md` 读取。
2. 两类异常：① owner 身份异常（非 UUID 形状、非本 workspace 成员、显示名、membership ID）；② `source` 路径异常（不存在／非文件／不可读／containment 越界，含相邻目录前缀与符号链接）。
3. **只读约束**：扫描不写任何受控账本、不改 CR 状态、不占锁以外的资源；只报告。`validate` 维度输出形状沿用既有 `errors`／`warnings`／`checked`／`notChecked`，异常以只读报告项承载。
4. 版本化：扫描逻辑落入库内模块文件（可测试、可复用），**不得**做成会话内现写的一次性脚本。
5. 不建巡检：无定时、无后台、无缓存；一次性调用即得结论。
6. 与 TASK-06 口径一致：新维度不参与 `evaluatePassCondition`，不引入阻断。
7. **登记同批（B-1 判据）**：`skills/shared/crctl/scripts/test/` 是 `suite-gate` 的登记目录，磁盘集合与 `manifest.files` 是**严格集合相等**（`suite-gate.mjs:441`／`:531` 比较、`:442`／`:532` 触发 `SUITE_MANIFEST_FILE_DRIFT`；`assertion-sources.mjs:88-97` 非递归取该目录内全部 `*.test.mjs`）。因此新建文件与 `gate-registry.json#manifest.files`／`manifest.cases` 的登记必须在**同一变更**内完成；`manifest.cases` 缺项是非零退出（`suite-gate.mjs:452`），登记同批生效后该文件即进入 `cmd-11` 的 spawn 列表真实执行。

## 验收条件

1. **AC-SUP-08（cmd-09 + cmd-06）**：合同与检查同步；一次性历史扫描只输出异常、不改受控状态。`cmd-06` = `register-tx.test.mjs` + `owner-source-scan.test.mjs`（本 TASK 新建的同目录单文件）；`cmd-09` = tools 仓六文件（合同文本一致性）。
2. **输出字段完整性**：对每个异常项断言 4 个字段齐备（CR-ID、字段／角色、原值、异常原因），且不把「成员不存在」与「查询失败」混为一类。
3. **零写入断言**：扫描前后对 `change-requests/_backlog.yml`、各 `cr.md`、`approval.yml`、`review-annotations/*` 做哈希比对，断言逐字未变；不阻塞无关 CR（扫描不进入其他 CR 的判定链）。
4. **状态来源口径**：构造 `_backlog.yml` 不含 `status` 的输入，断言扫描仍能正确识别非终态（从 `cr.md` 读），不因缺字段报错或漏扫。
5. 运行范围以 plan §5.5 为唯一事实源：**不声称**扫描覆盖全量历史之外的运行时状态；真实执行输出落 `test-evidence/cmd-06.log`、`test-evidence/cmd-09.log`，不新增 plan 未列命令。

## 完成标志

- 版本化只读扫描模块与 `validate` 维度 `owner-source-anomalies` 落地，新测试文件建立；`cmd-06`、`cmd-09` 真实执行退出码 0 并留证；新测试文件与 `gate-registry.json` 的 `manifest.files`／`manifest.cases` 登记**同批落盘**（本 TASK 是 `owner-source-scan.test.mjs` 的登记 owner），且该批落盘后 `cmd-11` 的磁盘集合与登记集合仍严格相等；
- 零写入断言与「状态从 `cr.md` 读取」口径均有用例覆盖，仓库内无巡检／定时／缓存设施新增；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-13／TASK-14 产出，不得缩写）：
- owner 值域（E1）：`owners.{requirement,development,test}.id` 必须为当前 workspace 成员 `user_id`（UUID）；
- `source` 值域与 containment 口径（E1 + §4.15）：`""` 或知识库内相对路径且「注册时可读、containment 通过」；相邻目录前缀与符号链接按越界处理；
- `dep-19` 的 `cmdValidateDimensions`／`cmdValidate` 既有只读维度面（`errors`／`warnings`／`checked`／`notChecked`）。

产出（供 TASK-17 与后续 CR 消费，消费方不得缩写）：
- 新模块导出（逐字）：`skills/shared/crctl/scripts/lib/owner-source-scan.mjs` 的扫描入口（入参 = 知识库操作根；出参 = 异常项数组，每项含 `crId`、`field`／`role`、`value`、`reason`）；
- `function cmdValidateDimensions(ws, target)`（:1566）新增维度名（逐字）`owner-source-anomalies`；维度结果为只读报告，不产生非零退出（除非既有 `validate` 对结构非法的既有判定触发）；
- 测试文件 `skills/shared/crctl/scripts/test/owner-source-scan.test.mjs`（plan §6.2 cmd-06 声明的新文件，命名与路径为硬契约，不得改名）；
- 登记面产出：`gate-registry.json#manifest.files` 含 `owner-source-scan.test.mjs` 且 `manifest.cases` 含其整数基线——两处与文件创建**同批**，供 TASK-11（登记面 owner）与 `cmd-11` 消费（不得拆到其它卡或后续变更）；
- 「只报告不修复」是跨 TASK 契约：TASK-17 的实际发布生效核对与后续任何 TASK 都不得把该扫描改造成自动修复。
