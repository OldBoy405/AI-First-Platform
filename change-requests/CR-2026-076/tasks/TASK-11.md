---
id: CR-2026-076-TASK-11
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "suite-gate 数量下降降为 warning 与四个 summary 宿主例外根因收敛"
slug: suite-gate-count-warning-fixtures
status: pending
estimate: 16h
depends-on: [CR-2026-076-TASK-03]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-12；AC-23；SDD §4.11）：把「逐文件用例数低于登记基线」从失败改为 warning `SUITE_COUNT_BELOW_BASELINE_WARN`（不阻断），同时保留全部仍须拒绝的面；并对 `gate-registry.json#exceptions` 中四个 summary 宿主环境例外做定点根因收敛，转绿后**撤销登记条目**。

背景与输入条件：`dep-22` 结论原文——逐文件 TAP 解析、例外 schema／期限校验与显式登记表已存在；登记表当前含 4 个 summary 宿主环境例外（`kind=suite-failure`，根因：夹具用系统临时目录 + 显式异根 `--workspace`）。根因与 TASK-03 的绑定拒绝语义直接相关（plan §2 依赖说明）。

明确不做：不自动改基线、不建数量审批流程、不造新豁免、不静默续期、不在生产任务全局清可信绑定变量；保留已完成的两处 fixture 修复回归，不重复实施。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/suite-gate.mjs`：`parseFileTap`、`validateExceptions`、`EXCEPTION_KINDS`、`CODES`、`registry.manifest`、`registry.exceptions`（`dep-22`）
- `skills/shared/crctl/scripts/test/gate-registry.json`：四个 summary 例外条目（`summary-03`～`summary-06`）的根因收敛与撤销；同时作为**登记面 owner** 维护 `manifest.files`／`manifest.cases` 的登记面自洽（含在本变更内把 `manifest.cases` 全部条目据实收口一次）
- `skills/shared/crctl/scripts/test/fixtures/`：夹具改为**同安装根内**的临时根（或经绑定归一提供操作根），在隔离子进程内复用既有 `baseEnv`
- `skills/shared/crctl/scripts/test/crctl-summary.test.mjs`

## 实现要点

1. 数量下降判据：逐文件用例数低于登记基线 → warning `SUITE_COUNT_BELOW_BASELINE_WARN`（不阻断）；warning 形状与承载口径与 TASK-06 统一（`{code,message,ref?}`）。
2. 仍失败面（一条都不能放宽）：必需文件零有效执行、少跑／未登记文件、文件集合不一致、加载失败、TAP 不可判／未收敛、真实未豁免失败、登记 schema／基线字段／例外结构或期限非法。
3. 摘要口径：不得把有效例外中的实际失败说成「所有测试通过」（§4.11）。
4. 四个 summary 例外的定点修法：夹具改为**同安装根内**的临时根（或经绑定归一提供操作根），在隔离子进程内复用既有 `baseEnv`；根因转绿后撤销对应例外条目（到期即清、不得静默续期）；修法与撤销同批完成，不留「已转绿但条目仍在」的中间态。
5. 登记面同步（plan §5.5「登记面所有权」）：`manifest`／`exceptions` 的改动必须在同一变更内与夹具改动一致（回滚单位 = 登记面与夹具同批，plan §4 风险表）；本 TASK 是**登记面 owner**——(a) 保持 `SUITE_MANIFEST_FILE_DRIFT`（磁盘集合 ≠ `manifest.files`）与「零有效执行」仍为**硬失败**，不随 FR-12 的数量下降 warning 一并放宽；(b) 在其变更内把 `manifest.cases` 全部条目（含 `crctl.test.mjs`）据实收口为该文件真实顶层用例数并留证；(c) 新建测试文件的登记责任不在本 TASK，由产生文件的那张卡同批落盘（本 CR：TASK-15／TASK-17——`manifest.cases` 缺项是非零退出，见 `suite-gate.mjs:452`）。

## 验收条件

1. **AC-23（cmd-10 + cmd-11）**：数量下降仅提示；少跑／未登记／集合不一致／零执行／真实失败／非法例外仍拒绝；四个宿主例外逐项复现 → 根因回归 → 转绿并撤销对应例外条目。
   - `cmd-10` = `skills/shared/crctl/scripts/test/crctl-summary.test.mjs` 单文件（四个 summary 例外根因修复后的转绿判据），**不声称**覆盖其他文件；
   - `cmd-11` = `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`（**本 CR 唯一全仓命令**，依据 AC-23 明确要求的文件集合一致性／零有效执行／例外登记面三个判定面）。
2. **撤销后无残余**：断言 `gate-registry.json#exceptions` 中 `summary-03`～`summary-06` 条目已删除，且 `cmd-11` 在无豁免下通过（若某条目因根因未收敛而保留，必须给出未收敛事实与复现命令，不得静默续期）。
3. **拒绝面回归**：构造少跑／未登记文件／集合不一致／零有效执行／非法例外的输入，断言 `cmd-11` 相应非零退出（正反两面在同一命令面内可观测）。
4. 运行范围以 plan §5.5 为唯一事实源：`cmd-11` 不声称覆盖未登记在 `manifest.files` 的文件，也不把上游同步（`CUSTOM.md` 全量 + Windows 已知失败原文）口径混入本 CR 的绿色判据。真实执行输出落 `test-evidence/cmd-10.log`、`test-evidence/cmd-11.log`。

## 完成标志

- 数量下降降级为 warning 且全部仍拒绝面有用例覆盖；四个 summary 宿主例外根因收敛、条目撤销，`cmd-10` 与 `cmd-11` 真实执行退出码 0 并留证；
- `gate-registry.json` 的 manifest／exceptions 与夹具改动同批落盘（回滚单位一致）；登记面自洽：`manifest.files` 与本 TASK 完成时刻磁盘测试文件集合严格相等、`manifest.cases` 每条目均为该文件真实顶层用例数且无缺项（收口事实与实测值写入结果）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-03 产出的绑定归一与失败关闭口径，不得缩写）：
- `bindTaskWorkspace` 的拒绝语义（`WORKSPACE_CONTEXT_MISMATCH`／`WORKSPACE_REQUIRED`）与 `\\?\`／尾分隔符别名归一——这是 summary 例外根因（系统临时目录 + 显式异根 `--workspace`）被判失败的判据来源；
- `manifest.files` 登记集与 `exceptions[]` 既有 schema（`kind=suite-failure`、期限字段）。

产出（供 TASK-17 与后续 CR 消费，消费方不得缩写）：
- `skills/shared/crctl/scripts/test/suite-gate.mjs` 新增 warning code `SUITE_COUNT_BELOW_BASELINE_WARN`（SDD §2.2 code 枚举，`{code,message,ref?}` 形状）并保留既有 `CODES`／`EXCEPTION_KINDS` 语义；
- `gate-registry.json`：`exceptions` 中四个 summary 宿主条目撤销后的空集（或按实际收敛结论据实登记，并写明未收敛原因）；`manifest` 与 `stateMachine`（由 TASK-07 更新为 transitions=32）互不影响；登记面契约（供 TASK-15／TASK-17 消费，不得缩写）：`manifest.files`／`manifest.cases` 是「磁盘集合 ≡ 登记集合」的严格相等面，新建测试文件的卡必须与文件同批登记，本 TASK 负责该面的硬失败语义与基线收口；
- 夹具契约：临时根位于同一安装根内、复用既有 `baseEnv`、隔离子进程内执行——TASK-17 的实际发布生效核对不得复用旧「系统临时目录」夹具形态。
