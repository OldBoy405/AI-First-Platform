---
id: CR-2026-076-TASK-17
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "实际发布生效核对：平台取用版本、已安装入口与真实 run 行为证据"
slug: effective-release-verification
status: pending
estimate: 16h
depends-on: [CR-2026-076-TASK-01, CR-2026-076-TASK-02, CR-2026-076-TASK-03, CR-2026-076-TASK-04, CR-2026-076-TASK-05, CR-2026-076-TASK-06, CR-2026-076-TASK-07, CR-2026-076-TASK-08, CR-2026-076-TASK-09, CR-2026-076-TASK-10, CR-2026-076-TASK-11, CR-2026-076-TASK-12, CR-2026-076-TASK-13, CR-2026-076-TASK-14, CR-2026-076-TASK-15, CR-2026-076-TASK-16]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-14；AC-24 主赔偿面；SDD §4.13 + SDD-CLOSE-08，并承接 §5.4 的人类动作窗口）：把「交付完成」的判据固定为「**安装后新 run 的目标行为证据 + 实际取用版本记录**」，并交付平台同步清单与已安装入口版本核对，替代「源码已改即算完成」。

背景与输入条件：`dep-8` 结论原文——架构期启动受平台投影门禁约束（本 CR 不修改该门禁，也不把投影事实当作本节点成败依据）；`dep-30` 结论原文——审计根与操作根分离是既有事实（诊断与校验不得把二者不同判为绑定冲突）。源码合入、构建成功或仓库镜像更新**不单独**算实际交付完成。

明确不做：不接受逐节点人肉代跑，只接受 plan §5.4 列明的一次有边界的人工启动前置；正式治理只用已发布、已验证入口，候选 CLI 仅用于隔离 fixture 或明确受控测试；稳定入口不可用则技术中止，不盲目重投；不新增平台配置写入（平台侧写入动作全部由有权限的人类 owner 执行）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs`：**新建**只读单文件测试（tools 仓 CR worktree，`cwd=.`；plan §6.2 cmd-14 声明的新文件，路径与命名为硬契约）
- `change-requests/CR-2026-076/test-evidence/effective-version.md`：**新建**平台 Skill／instructions **实际取用版本**记录（含每项 origin `repo／ref／path` 与内容 `sha256`）
- `change-requests/CR-2026-076/test-evidence/fr14-launch-receipt.md`：由人类 owner（Ray）提供原样启动回执，本 TASK 原样落盘（不加工、不改写）
- `change-requests/CR-2026-076/test-evidence/fr14-run-behavior.md`：同上，该次 run 在安装环境留下的目标行为证据原样结果
- 平台同步清单依据（只读）：SDD §8 变更 Skill 集合 + 三份 CR Agent instructions（`agents/dev-agent.md`、`agents/quality-reviewer-agent.md`、`agents/requirement-writer.md`，TASK-07 已同步）

## 实现要点

1. `cmd-14`（`publish-effectiveness.test.mjs`）行为：对 SDD §8 变更的 Skill 集合，逐项取 `multica skill get --with-content` 的**线上内容**与 tools CR worktree 目标文件**逐字比较**（`\r\n → \n` 归一、尾空行归一），并打印每项 `origin`（`repo`／`ref`／`path`）与内容 `sha256`；对三份 CR Agent instructions 只**打印**线上版本 `sha256`（**记录型观测**，不做相等断言——plan §5.4 说明③：其平台部署副本通道 `multica/cr-prompts-revised/*.md` 不在 SDD §1.5 变更面内）。
2. `cmd-15`（KB worktree 根目录只读脚本）行为：spawn `multica --version` 与 `multica daemon status --output json`，打印现场版本并断言两者同版本；断言 `fr14-launch-receipt.md` 非空且**载明现场入口版本**；断言 `fr14-run-behavior.md` 非空。**不声称**覆盖被启动 run 的业务结果正确性（该事实由行为证据原样文本承载，由人工与评审消费）。
3. 消费者切换顺序（§5.3）：tools 合同文本 → 平台 Skill 取用 → multica CLI／daemon 安装；生产者先兼容新合同再切消费者。回退不使用开关，按 §4 逆拓扑 revert。
4. 人类动作与窗口（plan §5.4，责任方 = 人类 owner）：① 按维护来源既有导入／发布流程把本 CR §8 变更的 Skill 目标文本同步到平台；② 构建并安装 multica CLI／daemon 的 CR 版本到安装根；③ 重启桌面监督（daemon）一次；④ 以更新后的**已发布**入口启动一次真实 run（受控任务）；⑤ 提供该次 run 的目标行为证据原样结果。窗口 = M7、本 TASK 执行窗口内、**早于代码审批**，不依赖 merge／writeback。
5. 证据纪律：①「已人工启动」的自述**不构成证据**，只有可核验产物计入；②平台侧写入动作全部由有权限的人类 owner 执行，agent 不写平台配置；③`test-evidence/` 内不出现未执行却声称通过的行。
6. 技术中止只修同一环境／事务且不重复 bump；真实 BLOCK 按正常回修；证据 ID 稳定、不机械重编号。

## 验收条件

1. **AC-24（cmd-14 + cmd-15）**：Windows 文档链非零准确 `docCount`（由 TASK-12 的 `cmd-12` 提供）**且**实际部署后新 run 使用已验证版本并记录版本与行为证据。
2. **cmd-14**：逐项 Skill 的实际取用版本与仓库目标逐字一致（`\r\n → \n` 归一），每项 origin 与 `sha256` 打印落盘；三份 instructions 仅打印 `sha256` 且**无**相等断言。
3. **cmd-15**：已安装 CLI 与 daemon 版本一致且与启动回执载明的现场入口版本一致；`fr14-launch-receipt.md` 与 `fr14-run-behavior.md` 非空原样在位。
4. **人类动作完成事实**：plan §5.4 五条动作逐条有可核验产物（Skill 取用记录 / `multica --version` 输出 / `daemon status` 输出 / 启动回执 / 行为证据）；窗口早于代码审批的时序事实写入 `effective-version.md`。
5. **范围声明**：`cmd-14` **不声称**覆盖未在 SDD §8 声明变更的 Skill；真实执行输出落 `test-evidence/cmd-14.log`、`test-evidence/cmd-15.log`，不新增 plan 未列命令。

## 完成标志

- `publish-effectiveness.test.mjs` 落地，`cmd-14`、`cmd-15` 真实执行退出码 0 并留证；`effective-version.md`、`fr14-launch-receipt.md`、`fr14-run-behavior.md` 三份证据原样在位；
- 平台同步清单（SDD §8 集合 → 实际取用版本 → origin）完整，且清单可被人类 owner 按同一目标文本回退；
- 未由 agent 执行任何平台配置写入；本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-01～TASK-16 产出，不得缩写）：
- TASK-01／TASK-02 的绑定三元组与叠加式 Git trust 生效事实（**安装后**新 run 的现场证据是判据，源码事实不构成判据）；
- TASK-07 的平台 Skill 集合变更清单（SDD §8 逐行）——`cmd-14` 的比较目标集合以该清单为唯一来源；
- TASK-12 的 `cmd-12`（Windows 文档链 `docCount` 断言）作为 AC-24 的文档链部分证据；
- TASK-16 的 `prd-handover-check.md`（交接完整性机械事实）。

产出（供人类代码审批与回写期消费，消费方不得缩写）：
- 证据文件（路径为硬契约）：`change-requests/CR-2026-076/test-evidence/{effective-version.md, fr14-launch-receipt.md, fr14-run-behavior.md, cmd-14.log, cmd-15.log}`；
- `publish-effectiveness.test.mjs` 的比较结论形状：逐项 `{ skill, origin: {repo, ref, path}, sha256Repository, sha256Remote, equal }`（Skill）与 `{ instruction, sha256Remote }`（三份 instructions，仅打印）；
- 判据契约（SDD-CLOSE-08，逐字口径）：交付完成 = 「安装后新 run 的目标行为证据 + 实际取用版本记录」；源码合入／构建成功／镜像更新**不构成**完成；
- 回退契约（plan §4 风险表）：本 TASK 证据与同步清单同批 revert；平台侧消费者切换由人类 owner 按同一清单以仓库目标文本回退。
