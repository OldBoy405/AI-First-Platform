# DELIVER — AIFI-45 四阶段 Registry 合同与提示词对齐（tools 侧）

> 本文件为收尾补记（2026-10-27）：该 change 的 BUILD 于 2026-10-20 完成，但 `deliver` 阶段一直停在 `pending`、没有交付记录，因此当时无法归档。配对 change 见 `projects/multica/.../2026-10-19-aifi-45-four-phase-runner`。

## 1. 范围

`specs/` 下 6 个 capability：

`agent-prompts`、`approve-skills`、`four-phase-templates`、`node-execution-binding-contract`、`pipeline-registry-export`、`test-execution-reliability`

解决的问题（proposal 原文）：registry 导出与前缀合同只覆盖需求/技术设计两段；派发仍把调用者当全部节点的执行者（设计期 `RUNNER_SKILL_MISSING` 的直接原因）；coding 与 writeback 模板的输入、canonical 结果、reviewLoop 与 `crctl` 深原语（`spec_id`/`target_version`、release-subjects、`testCr`）存在漂移；agents 与 Skill 提示词里保留评论委派、审批后自行 start 等重复编排。

## 2. 证据入口

该 change 早于本工作区的 `validation/` 约定，证据以切片报告落在 change 根目录：

| 报告 | 覆盖 |
|---|---|
| `S0-build-report.md`、`S0-final-report.md`、`S0-review.md` | S0a–S0c 基线、Authority 根因、全量复测 |
| `T01-T02-build-report.md`、`T01-T03-review.md` | S1 节点绑定合同 |
| `T03-build-report.md` | S2 四 Registry / digest / loop |
| `T04b-cross-repo-checkpoint.md` | S3–S4 跨仓检查点 |
| `T05-s5-test-report.md` | S5 整体质量验证 |
| `TREG-handoff.md` | registry 交接 |
| `execution-policy.md` | 执行策略 |

## 3. 阶段状态

| 阶段 | 状态 | 记录 |
|---|---|---|
| understand（Gate 1） | completed | `confirmed_by=dialog`，2026-10-19 |
| spec（Gate 2） | completed | `confirmed_by=dialog`，2026-10-19 |
| build（Gate 3） | completed | `confirmed_by=cli`，2026-10-20；**确认原文当时未落盘**（占位符 `<确认原文>`），本次收尾已改为如实标注 |
| deliver | 本次补记 | 见本文件 |

## 4. 交付判定

- `tasks.md`：**22/22 全部勾选，无未勾项**；
- 无 `validation/`、无 checker 证据行——验收方式为上述切片报告，不是 M003 的 label 体系；
- 本次收尾**未新增实现或测试**。

## 5. 与后续 change 的关系

tools 侧 `2026-10-22-aifi-45-authorized-execution` 仍停在 `build`（30/59），未归档；本 change 归档不代表 AIFI-45 整体收口。

## 6. 归档

`stdd archive --yes --skip-specs`，理由同配对 change：不新建 `projects/tools/specs/` 这第二个基线位置，规格随 change 留在归档目录内。

## 7. 还原与 V 类实况（2026-10-27）

本 change 于同一天先被归档、随后**还原**到 `changes/`（`stdd rollback`）。`rollback` 把 `current_phase` 重置为 `understand`，与已完成的 Gate 1/2/3 矛盾，已手工改回 `build`；`deliver` 改回 `pending`。

### 7.1 全量套件在当前 HEAD 的实际结果

原遗留项写的是「最终版全量 35 文件未闭环，且仅 Windows/Node24」。本轮已把范围补到**当前真实规模 52 个文件**（crctl 48 + output-guard 3 + registry 1），两个平台各跑一次：

| 平台 | 运行时 | tests | pass | fail | skip | 证据 |
|---|---|---|---|---|---|---|
| Windows 11 / Node 24.15.0 | 1458s | 1280 | 1275 | **4** | 1 | `validation/win-full-20261028T040000Z.tap` |
| WSL2 Linux 6.18 / Node 24.15.0（`/mnt/c` drvfs） | 306s | 1280 | 1270 | **9** | 1 | `validation/linux-full-20261028T050500Z.tap` |
| WSL2 Linux 6.18 / Node 24.15.0（原生 ext4） | 154s | 1280 | 1270 | **9** | 1 | `validation/linux-native-20261028T052500Z.tap` |

**结论：套件在当前 HEAD 上不是绿的。**「35 文件全绿」的旧口径不再成立，52 文件下的真实状态是上面的数字。

### 7.2 失败归因

四个平台共用失败项，其中三个指向 `de9bf75`（M003 trusted T verdict channel 的 Node 侧提交，即本 change 之后的工作）：

| 失败项 | 归因 |
|---|---|
| `CR-2026-064 FR-11 结构断言③` | `de9bf75` 新增夹具 `fixtures/control-vectors.json`，未纳入该断言冻结的扫描面 |
| `TASK-09 单缝约束` | `de9bf75` 改动的 `lib/change-scope.mjs` 命中「tree 比较只允许一处」扫描 |
| `TC-EVD-007` | `de9bf75` 在 `lib/component-readiness.mjs` 新增 `EVIDENCE_COMPONENT_NOT_APPLICABLE_UNAPPROVED`，旧测试用例的 profile 未显式批准 `tools` 组件 |
| `isolation 需要真实受限身份` | 环境绑定：需 `AIFI45_ISOLATION_PROFILE` / `AIFI45_ISOLATION_AGENT`；Windows 无受限身份可用 |
| `EXEC-12 symlink 拒绝写入`（skip） | 环境绑定：Windows 无符号链接权限（EPERM） |

Linux 独有 5 项（原生 ext4 同样复现，排除 drvfs 因素）：

| 失败项 | 形态 |
|---|---|
| `SC-AUTH-004 wiring … PATH_ESCAPE` | 符号链接逃逸（Windows 侧因无法建链而不执行） |
| `CR-2026-076 AC-SUP-08 六类路径异常` | 同上，含符号链接越界 |
| `AIFI-63 包 C：2MiB diff 不截断` | 大输出经管道时的信封形状 |
| `AIFI-63 包 C：64MiB 上限 → ENOBUFS` | 同上 |
| `CR073 long output complete：>1MiB` | 同上 |

即：Linux 列不是「通过」，而是 5 条只有 Linux 才暴露的差异。这些不在本 change 的实现范围内（crctl 输出/符号链接属既有契约），不得据此宣称跨平台通过。

### 7.3 因此不声称

- 52 文件套件任一侧全绿。
- 「仅 Windows/Node24」已升级：Windows + Linux(WSL2) 双平台均已执行，但**两侧都有失败**，不构成跨平台通过。
- Node 20 未执行。
- 独立 Linux 主机（非 WSL）未执行。
