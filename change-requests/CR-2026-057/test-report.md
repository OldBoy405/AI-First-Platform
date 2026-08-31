---
cr: CR-2026-057
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-01T03:05:20+08:00"
command-digest: 9ed980e2da893df7a9e9bc457696dd474c0d2eafb3ffaa21101ed6e13f96cc0f
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引", skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/register-tx.test.mjs]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/version-set.test.mjs]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "(CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|TASK-01 RED-7：预存确定性 dedup 文件)", skills/shared/crctl/scripts/test/crctl.test.mjs, skills/shared/crctl/scripts/test/register-tx.test.mjs, skills/shared/crctl/scripts/test/writeback-tx.test.mjs, skills/shared/crctl/scripts/test/archive-tx.test.mjs, skills/shared/crctl/scripts/test/test-cr.test.mjs, skills/shared/crctl/scripts/test/version-set.test.mjs]
    timeout-seconds: 7200
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-057/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-057

<!-- crctl:analysis-below -->

<!-- crctl:analysis-below -->

## 分析区（CR-2026-057 TASK-11，机器证据核对与基线红例外）

**生成说明**：本区由 dev-agent 在 `crctl test` 机器区（marker 上方）之外补写，不覆盖机器证据；机器区 `generated-by: crctl-test`、attempt 2（attempt 1 为误用主 checkout 旧二进制生成、无 `skipped` 字段，已删 journal 用 CR worktree 二进制重跑，两轮 attempt 均留痕于 review-loop.yml）。

### 1. 六命令机器区核对（plan §5.1 / §5.3 规则 3/4）

- 六条命令 `exit-code: 0` × 6、`skipped: false` × 6、`status: pass` —— 机器区逐项核对通过。
- `commands` 1-based 下标与覆盖矩阵 cmd-NN 全等：cmd-01（crctl.test.mjs，skip BR-1）、cmd-02（register-tx，AC-12 唯一证据）、cmd-03（writeback-tx，AC-14 唯一证据）、cmd-04（version-set，AC-15 唯一证据）、cmd-05（test-cr，AC-16 自动化侧唯一证据）、cmd-06（六文件全量，skip BR-1|BR-2，AC-18）。
- 六命令统一 `--test-reporter=dot`：五条冻结模式在 stdout/stderr 两段零命中，机器区 `skipped` 恒 false（FR-16）。

### 2. 基线红例外核对（plan §5.3 规则 1/2/5）

实施 HEAD（tools CR worktree，`crctl git rev-parse HEAD` = `45006b7`，TASK-01～07 提交序列：`e8b8dc0`→`1c2aa5a`→`e27c9a8`→`cac84b5`→`24f8cca`→`bfb3a3f`→`45006b7`）以 spec reporter、**不带** skip-pattern 完整重跑 BR-1/BR-2 所在两个测试文件，失败集合与例外表逐条全等，红计数 = 2 不因本 CR 增加：

| BR-ID | 证据日志 | 完整重跑结果 | 与例外表核对 |
|---|---|---|---|
| BR-1 | `test-evidence/baseline-red-BR-1.log` | `crctl.test.mjs` 203 tests：202 pass / **1 fail**，失败用例 = `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引`（断言 `expected: /crctl task init/` 不命中——`pipeline-templates/code-implementation.pipeline.json` 文本不含 `crctl task init`，CR-2026-050 converge 改写所致） | 全等 ✓ |
| BR-2 | `test-evidence/baseline-red-BR-2.log` | `archive-tx.test.mjs` 21 tests：20 pass / **1 fail**，失败用例 = `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖`（断言 `actual:[{code:EMIT_FAILED,event_kind:archive}]` vs `expected:[]`——archive dedup 重放路径既有缺陷） | 全等 ✓ |

**根因与 follow_up**：

- BR-1：pipeline-templates 文本与既有断言漂移。修复需动 `pipeline-templates/`，与本 CR §9 zero_diff（冻结面 6）冲突 → 根因修复另开 CR，建议 follow_up CR 同步收敛 pipeline 提示词与 crctl.test.mjs 断言。
- BR-2：archive dedup 重放路径既有缺陷（本 CR 不触 archive 事务）。→ follow_up CR 修复 archive dedup 重放与 EMIT_FAILED 断言。

两条均非本 CR 引入（基线 8c0a6db 实测同红，plan §5.3 例外表已冻结登记），实施期未出现任何新红。

### 3. 四项静态核对

1. **AC-4 contract-scan**：`contract-scan.test.mjs` 7/7 全绿——3 Pipeline + 11 SKILL 对四个禁止字段零命中。
2. **AC-17 diff 审阅**：tools diff（基线 8c0a6db..HEAD）仅含 plan/SDD 批准面文件——新增确定性检查只有 FR-12/FR-14/FR-15 版本守卫与 FR-16 `skipped` 字段（P1-3 允许清单），无 PLAN symbol 存在性检查等未再次失败的新 validator；`durable-tx.mjs` 零 diff → `FAULT_POINTS` 零新增（version-set 测试复用既有 `tx-apply-between-rename`/`ledger-after-commit` 注入点）。
3. **AC-11 gates 零改动**：`gates.json` 不在 diff 中；`deliveryIndexComplete` 行为不变（archive-tx 既有用例除 BR-2 外全绿）。
4. **AC-13 frontmatter 全等**：cr.md / prd.md / sdd.md / plan.md / 全部 11 张 TASK 卡 `target-version: unassigned`，全等无 `tbd`。

### 4. 接口签名汇总核对（TASK-11 实现要点 8）

- TASK-01 产出 → TASK-02/03/04 消费：`normalizeTargetVersion(raw, { allowUnassigned = true }) → {ok:true,value}|{ok:false,reason}` 三处消费一致（register 顶部校验 / guardWritebackVersion / cmdVersionSet `--to` 规范化）；`readCrMdTargetVersion(ws, cr) → {ok:true,raw}|{ok:false,reason:'missing'}` 由 writeback 守卫消费。✓ 无 WARN。
- TASK-05 产出 → TASK-07 消费：机器区每 command `skipped: boolean`（additive）与 review-code「只读 `skipped`/`exit-code`/`timed-out` + 覆盖矩阵 `cmd-NN`」口径一致。✓
- TASK-04 错误码族与 SDD §3.3 一致：业务四枚 `VERSION_SET_INVALID` / `VERSION_SET_NOT_UNASSIGNED` / `VERSION_SET_STATE_INVALID` / `VERSION_SET_DERIVED_DRIFT` + 基础设施族 `VERSION_SET_WORKTREE_DIRTY` / `VERSION_SET_COMMIT_FAILED` / `VERSION_SET_COMMIT_ROLLBACK_FAILED`（镜像 `OWNER_*`）。✓

### 5. FR-23 交叉校验

`tasks/_index.yml` 全部 estimate 之和 = **84h**，与 plan §5.4 `totalEstimateHours=84` 一致。✓

### 6. AC 覆盖小结（cmd-NN 证据关联）

- AC-12（register 版本校验正负向量与零写入）：cmd-02，负向 7 类输入 `REGISTER_VERSION_INVALID` 零写入 + 正向 `unassigned`/`0.30`/`v0.30`（写入 `0.30`）+ 同 key 规范化幂等/异值 `REGISTRATION_INPUT_MISMATCH`。
- AC-14（writeback 版本守卫时序与六项零观察点）：cmd-03，三 stage × 三错误码各断言 specs 哈希/candidate 目录/journal/锁/authority/origin commit 数六项零观察点 + 同参重试同码 + drafting 夹具版本错误优先（AC-14.6）+ 缺 flag `BAD_ARGS` vs 显式空串 `WRITEBACK_VERSION_INVALID`（B-SDD-003）+ 回灌断言（B-SDD-002）。
- AC-15（version-set 全链同步/幂等/漂移拒绝/中断重试闭环）：cmd-04，正向六类文件全等 to.value + `merging`/终态 `VERSION_SET_STATE_INVALID` 零恢复 + 漂移/键隔离 + `tx-apply-between-rename` 中断重跑恰 1 commit 全程无 WORKTREE_DIRTY/DERIVED_DRIFT + `ledger-after-commit` 幂等确认（B-SDD-005）+ AC-13 全链同步断言。
- AC-16（自动化侧 skipped 计算）：cmd-05，冻结模式表五条各命中 + CRLF 变体 + non-zero/两域外不命中 + 标记缺失/重复 `TEST_LOG_MARKER_INVALID` 硬失败。
- AC-18（全量回归）：cmd-06（skip BR-1|BR-2 后 exit 0）+ §2 红计数=2 不增加。

### 7. 未覆盖风险

- 评审行为侧 AC（AC-1～AC-4、AC-6/7/9/10/16 评审侧）为模型行为夹具，证据载体是后续 review 轮的 `review-annotations/*.yml` 内容，不由本测试报告自动化断言（SDD §6.2）。
- BR-1/BR-2 根因修复不纳入本 CR（§5.3 例外表），follow_up 去向见 §2。
