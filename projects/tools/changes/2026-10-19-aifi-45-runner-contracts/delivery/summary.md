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

## 7. 还原、全量套件与修复（2026-10-27/28）

本 change 于 2026-10-27 先被归档、随后**还原**到 `changes/`（`stdd rollback`）。`rollback` 把 `current_phase` 重置为 `understand`，与已完成的 Gate 1/2/3 矛盾，已手工改回 `build`。

### 7.1 首轮全量（修复前，当前 HEAD）

范围补到真实规模 **52 文件**（crctl 48 + output-guard 3 + registry 1 = 1280 测试）：

| 平台 | 耗时 | pass | fail | skip |
|---|---|---|---|---|
| Windows 11 / Node 24.15.0 | 1458s | 1275 | 4 | 1 |
| WSL2 Linux / drvfs | 306s | 1270 | 9 | 1 |
| WSL2 Linux / 原生 ext4 | 154s | 1270 | 9 | 1 |

即：旧口径「35 文件全绿」不再成立，首轮并不绿。原生 ext4 与 drvfs 结果一致，排除了挂载因素。

### 7.2 修复（8 处，含 3 条 M003 回归）

| 项 | 形态 | 处置 |
|---|---|---|
| **POSIX 管道截断** | `crctl.mjs` 对 `--json` 信封与原生输出用 `process.stdout.write` 后立即 `process.exit`；POSIX 管道缓冲 65536 字节以上被丢弃（Windows 管道可整块接收，故只在 Linux 暴露） | 新增 `writeAllSync`（循环 `fs.writeSync`，容忍 EPIPE/EAGAIN），替换 `ok`/`fail`/信封/原生输出四处 |
| Linux 独有：2MiB、64MiB 大输出 | 同上截断的直接后果 | 由上条修复 |
| Linux 独有：CR073 `>1MiB` log | 测试自己的子进程 `process.stdout.write` 后 `process.exit(0)`，同样在 POSIX 丢输出 | 去掉子进程的 `process.exit(0)`，靠正常退出 flush |
| Linux 独有：SC-AUTH-004 `PATH_ESCAPE` | git 对逃逸的报法随平台不同（POSIX 报链接条目 `src/leak`，Windows junction 下钻 `src/leak/secret.txt`） | 断言改为「恰一条 `AUTH_SCOPE_PATH_ESCAPE`，路径为二者之一」，不锁死叶子拼写 |
| Linux 独有：AC-SUP-08 六类路径异常 | 原断言要求 `.items === []`，但同一夹具里还有 7 个已判异常，永远不可能成立（该分支仅在 POSIX 执行，故从未被发现） | 改为：先证明「新增未被引用的不可读文件不改变结论」，再让一个 CR 真正引用该文件并断言 `source-not-readable`；另加 root 守卫（root 可读 000） |
| 回归 1：`CR-2026-064 FR-11 断言③` | M003 `de9bf75` 新增夹具 `control-vectors.json` 未进入冻结的面快照 | 加入 fixtures 期望集合 |
| 回归 2：`TASK-09 单缝约束` | M003 改的 `lib/change-scope.mjs` 自行 `rev-parse ^{tree}` 做 zero-change 证明 | `workspace-transactions.mjs` 导出 `treeFactsFor` 作单一缝入口，`change-scope.mjs` 改为调用；全仓 `^{tree}` 仍恰一处 |
| 回归 3：`TC-EVD-007` | M003 新增「`not-applicable` 需 profile 显式批准」（规格 §38），旧用例声明未带批准位 | 测试声明补 `not_applicable_approved: true`，规则不变 |

### 7.3 修复后双平台全量

| 平台 | 运行时 | tests | pass | fail | skip | 证据 |
|---|---|---|---|---|---|---|
| Windows 11 / Node 24.15.0 | 1461s | 1291 | 1290 | **0** | 1 | `validation/win-full-20261028T063000Z.tap` |
| WSL2 Linux 6.18 / Node 24.15.0（原生 ext4，root + 受限身份） | — | 1291 | 1290 | **0** | 1 | `validation/linux-full-20261028T064500Z.tap` |

1291 比 1280 多出的 11 条来自 M003 的 isolation 测试：只有设置 `AIFI45_ISOLATION_PROFILE` / `AIFI45_ISOLATION_AGENT` 时才声明其 leaf。两轮均带 `995:994` / `994:993` 运行，即真实受限身份。

**两条 skip 互补**，合起来两个 leaf 都被真实执行：

| skip | 平台 | 原因 |
|---|---|---|
| `EXEC-12 受控文件自身为 symlink` | Windows | 无权限创建符号链接（EPERM）；Linux 侧执行通过 |
| `EXEC-15 junction 指向另一 CR` | Linux | 无 junction 原语；Windows 侧执行通过 |

### 7.4 仍不声称

- **Node 20** 未执行（仅 Node 24.15.0）。
- **独立 Linux 主机**未执行：Linux 列为 WSL2 内核 6.18 / 原生 ext4，非独立物理机。
- 本轮只覆盖 crctl/output-guard/registry 三处测试；`multica` 侧完整套件不在本 change 范围。
