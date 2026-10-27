# DELIVER — AIFI-45 四阶段统一 Runner（multica 平台侧）

> 本文件为收尾补记（2026-10-27）：该 change 的 BUILD 于 2026-10-20 完成，但 `deliver` 阶段一直停在 `pending`、没有交付记录，因此当时无法归档。

## 1. 范围

`specs/` 下 10 个 capability：

`approval-ack`、`delivery-runner`、`dev-phase-runner`、`four-phase-runner-dispatch`、`kb-resource-adoption`、`node-execution-binding`、`periodic-runner-resume`、`persistent-stage-handoff`、`public-key-grant-delivery`、`task-recovery`

解决的问题（proposal 原文）：四阶段只有需求与技术设计接进 Runner，其余阶段靠协调者转述/作者启动/CLI 续接，导致 KB 未采集、ack 报 leader-missing 拖住同批记录、设计期 `RUNNER_SKILL_MISSING`、一次唤醒失败后长期停住等非业务阻断。

## 2. 证据入口

该 change 早于本工作区的 `validation/` 约定，证据以各切片报告落在 change 根目录：

| 报告 | 覆盖 |
|---|---|
| `M00-db-baseline.md` | 基线 |
| `M10-`、`M11-`、`M12-`、`M13-M15-`、`M20-M22-`、`M23-M25-`、`M26-M28-`、`M30-M34-`、`M35-M39-`、`M40-M43-build-report.md` | 各里程碑 BUILD |
| `M10-review.md`、`M11-review.md` | 评审 |
| `ACK-006-legacy-continuation-drill.md` | ack 续接演练 |
| `implementation-notes.md` | 实现说明 |

## 3. 阶段状态

| 阶段 | 状态 | 记录 |
|---|---|---|
| understand（Gate 1） | completed | `confirmed_by=dialog`，2026-10-19 |
| spec（Gate 2） | completed | `confirmed_by=dialog`，2026-10-19 |
| build（Gate 3） | completed | `confirmed_by=cli`，2026-10-20；**确认原文当时未落盘**（字段留着占位符 `<确认原文>`），本次收尾已改为如实标注，未虚构内容 |
| deliver | 本次补记 | 见本文件 |

## 4. 交付判定

- 任务清单 `tasks.md`：**69/69 全部勾选，无未勾项**；
- 无 `validation/`、无 checker 证据行——该 change 的验收方式是各切片 build/review 报告，不是 M003 那套 `channel-evidence.mjs` label 体系，两者不可混用口径；
- 本次收尾**未新增任何实现或测试**，只补交付记录与状态。

## 5. 与后续 change 的关系

`2026-10-22-aifi-45-authorized-execution` 是接续它的下一段工作（授权执行链），仍停在 `build`（multica 36/65、tools 30/59），**未归档**。本 change 归档不影响那段的状态，也不代表 AIFI-45 整体收口（41/49 仍未回填）。

## 6. 归档

按 M003 的同一口径执行 `stdd archive --yes --skip-specs`：不把 `specs/*.md` 合并进 `projects/multica/specs/`（该目录从未存在，工作区级 `specs/` 才是 CR 回写基线），规格文件随 change 留在归档目录内。

## 7. 还原、残余项与原报告误报更正（2026-10-27）

本 change 于同一天先被归档、随后**还原**到 `changes/`（`stdd rollback`），原因：归档后复查发现 BUILD 虽全勾，但报告里记着若干未闭环的残余项，归档会让它们失去可见性。

`stdd rollback` 把 `current_phase` 重置为 `understand`，与已完成的 Gate 1/2/3 矛盾，已手工改回 `build`；`deliver` 改回 `pending`。Gate 3 的确认原文当时未落盘，仍是如实标注、未虚构。

### 7.1 原报告记载但实际已闭环（误报，不再列为待办）

按当前源码逐条核实，以下条目在同一次提交 `0d6b4e9f9` 内已关掉，报告只记录了写作那一刻的状态：

| 报告原文 | 当前源码事实 |
|---|---|
| `M35-M39-build-report.md`「`internal/handler` 精确 `TestMKb001`、`TestMKb004` 未新增」 | **已存在**：`handler/daemon_test.go:5111`、`:5169`；同报告后段「handler 两处收口」小节即记录了补入 |
| 同报告「仍 MISSING 4」个 CP：`TestMDelivery002/004`、`TestMDev002/003` | **4 个都存在**：`daemon/pipeline_task_test.go`、`governance/dev_phase_cp_test.go` |
| `implementation-notes.md`「`local_directory_snapshot` 行为未实现/未验证」 | **已实现**：`handler/daemon.go`、`pkg/protocol/messages.go` 及测试 |
| 「`TestMDispatch001/005` 未原生 PASS，TC-MDISPATCH-007 的 CP 悬空」 | **已存在**：`four_phase_dispatch_cp_test.go:181`、`runner_contract_test.go:458` |
| 「batch/timeout 待隔离实测」 | 常量已落地（`runtime_sweeper.go`：500/500/500/500/100/100） |
| 「registry 生成物与 tools 漂移」 | `generate-gate-nodes.mjs --check` **exit 0** |

### 7.2 BUILD 后追加完成（本轮，见 `validation/closeout-plan.md`）

1. **C-4 断言补强**：MKey004 增真实文件系统写失败子用例；MKey005 增 grant `key_id` 与 server `public_key` 不一致的失败关闭子用例；MKey006 改断言交付前后 porcelain 差集（新增仅白名单 key，无删除）。四条变异 m94/m95/m96 全部打红后恢复。
2. **C-5 生成器溯源**：`generate-gate-nodes.mjs` 原先取 tools HEAD 作 BASE 却读工作树，模板有未提交改动时会谎称干净提交；现按 `pipeline-templates/*.pipeline.json` 的 dirty 状态输出 `BASE <sha>+dirty`，并重新生成 4 个 gen 文件（BASE 前进到 `de9bf75`）。变异 m97 打红。
3. **V 类 CP 复核**：35 个 CP 定位符在当前 HEAD 上逐包重跑并全部通过（daemon 43 叶子、governance 48、handler 3、service 8、pkg/taskfailure 单测），全部 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`。

### 7.3 仍不声称（非待办，属边界）

- **恢复时限**：`design.md` 明确「数值需隔离实测，当前不许宣称恢复时限」。常量存在不等于时限已证。
- **runtime 实际 Agent UUID 隔离**：`implementation-notes.md` 的该条出自 BUILD 前的只读核实笔记；M1 已按 `node_id` 落地执行绑定，但「runtime 使用的 Agent ≠ 调用者」这一具体断言目前没有对应测试。列为不声称，未验证。
