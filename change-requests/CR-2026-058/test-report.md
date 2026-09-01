---
cr: CR-2026-058
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-01T20:41:24+08:00"
command-digest: 6cc25bdd8162426cfbe8fa48e0b59e3a66466dd567ff1dff666e82b3a579cc12
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引", skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 1200
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-058/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-058/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "(CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|TASK-01 RED-7：预存确定性 dedup 文件)", skills/shared/crctl/scripts/test/crctl.test.mjs, skills/shared/crctl/scripts/test/writeback-tx.test.mjs, skills/shared/crctl/scripts/test/archive-tx.test.mjs, skills/shared/crctl/scripts/test/register-tx.test.mjs, skills/shared/crctl/scripts/test/version-set.test.mjs, skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 2400
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-058/test-evidence/cmd-03.log
---

# 测试报告 · CR-2026-058

<!-- crctl:analysis-below -->

## 测试摘要（TASK 验收条件对照）

| TASK | 验收条件 | 证据 | 结果 |
|---|---|---|---|
| TASK-01 窄解析器 + guard 判定表（FR-1/FR-3） | guard 六行向量 + authority 快照 + source 两分支 + UNASSIGNED 新文案 | cmd-01（crctl.test.mjs `CR-2026-058 TASK-01`）+ 集成层 AC-1.1/1.2/1.3 | ✅ |
| TASK-02 planVersionRefill + 行级编辑（FR-2.1） | 语义复核四分支 / backlog 预检五向量 / 同源断言 / 行级编辑硬失败 + CRLF 等价 | cmd-01（`CR-2026-058 TASK-02` ×3）+ 集成层 AC-2.2 | ✅ |
| TASK-03 applyWritebackAtomic 集成（FR-2/2.2/6） | payload 冻结 / entries 合成 / 恢复协议 / baseline 单条目合成；zero_diff 面零改动 | cmd-02（AC-2.1/2.3 三故障点 + 1b）+ 集成层 AC-6 | ✅ |
| TASK-04 merge-fixture 参数化 + writeback-tx 改写（FR-4） | AC-1/AC-2/AC-3/AC-6 全夹具；UNASSIGNED 期望收敛冻结向量 | cmd-02（27 用例全绿） | ✅ |
| TASK-05 crctl.test.mjs 同源断言 + AC-4 静态核对 | 正反语义向量证明 / 错误码收敛 / snapshotSixPoints 保留 | cmd-01（`CR-2026-058 TASK-05` ×2） | ✅ |
| TASK-06 README 行 22/76 + 静态文案断言（FR-5） | 禁止串零命中 + writeback 事务限定 + 回灌语义 | cmd-01（`CR-2026-058 TASK-06`） | ✅ |
| TASK-07 全量回归 + 测试报告 | cmd-01~03 exit 0 且 skipped=false；BR-1/BR-2 按 §5.3 例外表排除 | 本报告机器区 + test-evidence/cmd-01~03.log | ✅ |

## 验证命令与结果解读

- **cmd-01**（crctl.test.mjs，BR-1 skip）：exit 0，dot reporter 下 `skipped=false`；新增 guard/plan/同源/静态断言向量全绿，既有用例除 BR-1（§5.3 例外表）外无新增失败。
- **cmd-02**（writeback-tx.test.mjs）：exit 0，`skipped=false`；既有 14 用例（含改写后的 AC-14 MISMATCH/INVALID 向量）+ 新增回灌夹具（AC-1.1/1.2/1.3、AC-2.1/2.2/2.3+1b、AC-3.1/3.2、AC-6.1/6.2）全绿；AC-1/AC-2/AC-3/AC-6 唯一证据面。
- **cmd-03**（六文件全量回归，BR-1/BR-2 skip）：exit 0，`skipped=false`；writeback/archive/register/version-set/test-cr 既有用例不新增失败（红计数 = 基线两条 BR，未增加）。

## 错误码与契约核对

- 新增公开错误码仅 PRD FR-2.1 允许的两个：`WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`；`WRITEBACK_AUTHORITY_DRIFT` 零残留（cmd-01 静态断言）。
- 同源绑定硬失败复用既有 `WRITEBACK_STATE_MISMATCH`（extra 保持既有 `{cr, phase}` 形状，证据进 message）；guard 调用签名 `(ctx, cr, inputTargetRaw)` 不变。
- zero_diff 面零改动：`crctl.mjs`（dispatch/flag 面/`fail()`/`ok()`/`runTxAsync`）、`durable-tx.mjs` 全部导出与 `FAULT_POINTS`、`yaml-subset.mjs`、writeback 三 generator、`statusTransition` 既有字段、`verifyReleaseSubjects` 白名单——`git diff --name-only` 仅含 5 个实施文件（见下）。

## 新增/修改测试与代码文件（tools CR worktree，分支 requirement/CR-2026-058）

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（TASK-01/02/03：`resolveWritebackAuthorityPath` / `guardWritebackVersion` 重写 / `planVersionRefill` + 两个行级编辑 export / `applyWritebackAtomic` 回灌集成）
- `skills/shared/crctl/scripts/test/merge-fixture.mjs`（TASK-04：`makeCodeApprovedFixture({targetVersion})` 参数化）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（TASK-04：AC-1~AC-6 回灌夹具 + AC-14 改写）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（TASK-01/02/05/06：guard/plan/同源/静态断言向量）
- `README.md`（TASK-06：行 22/行 76 FR-5 改写）

## 未覆盖风险与不适用说明

- **基线红 BR-1/BR-2**（cmd-01/cmd-03 skip-pattern 排除，plan.md §5.3 例外表）：与 CR-2026-057 计划同两条，根因修复不纳入本 CR（SDD §9 follow_up 同类），红计数未增加。
- **authority 快照绑定 throw 位（§4.4 第 5.5 步 opWs=txws 而快照=worktree 的分歧现场）**：集成层经 AC-3.2（opWs=cr-worktree 既有 throw 位）与单测层同源断言（planVersionRefill ⓪）覆盖；守卫与 opWs 的解析条件同源，实际运行不可达的分歧窗口由 5.5 检查兜底（防御位）。
- **traceability complete-replay 分支**：本 CR 未触及（零改动），既有 TASK-02 用例覆盖。

## 下一步建议

`crctl next` = implement-code（本节点收敛）；测试证据 pass 后按常规闭环由 quality-reviewer-agent 执行 `review-code`（评审评论分 Blockers / Suggestions 两区）。