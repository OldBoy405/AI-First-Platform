---
cr: CR-2026-057
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-01T10:10:18+08:00"
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

## 分析区（CR-2026-057 TASK-11，机器证据核对与基线红例外）

**生成说明**：本区由 dev-agent 在 `crctl test` 机器区（marker 上方）之外补写，不覆盖机器证据；机器区 `generated-by: crctl-test`。本次为 approve-code 门禁 `RELEASE_SUBJECT_DRIFT` 后的 B-CODE-003 回修证据重建：status 经合法回退转换 `approve-code:reject -> implement-code` 回到 `developing`（`crctl advance --embedded`，随本证据同一提交），write-test-report reviewLoop 按 pass-at-max 口径自动开新 cycle（cycle 2 attempt 1），六命令在 tools HEAD `3f8b1fb` 重跑并重生成全部机器证据。cycle 1 三轮历史（attempt 1 误用主 checkout 旧二进制 / attempt 2 首次重跑 / attempt 3 B-CODE-001/002 回修证据）均留痕 review-loop.yml。

### 1. 六命令机器区核对（plan §5.1 / §5.3 规则 3/4）

- 六条命令 `exit-code: 0` × 6、`skipped: false` × 6、`status: pass`；generated-at `2026-09-01T10:10:18+08:00`；command-digest `9ed980e2…` 与上一轮全等（test-plan.json 未改，六命令顺序、统一 `--test-reporter=dot` 与 §5.3 skip-pattern 字面量不变）。
- `commands` 1-based 下标与覆盖矩阵 cmd-NN 全等：cmd-01（crctl.test.mjs，skip BR-1）、cmd-02（register-tx，AC-12 唯一证据）、cmd-03（writeback-tx，AC-14 唯一证据）、cmd-04（version-set，AC-15 唯一证据）、cmd-05（test-cr，AC-16 自动化侧唯一证据）、cmd-06（六文件全量，skip BR-1|BR-2，AC-18）。
- 六命令统一 `--test-reporter=dot`：五条冻结模式在 stdout/stderr 两段零命中，机器区 `skipped` 恒 false（FR-16）。

### 2. 基线红例外核对（plan §5.3 规则 1/2/5）

实施 HEAD（tools CR worktree，`crctl git rev-parse HEAD` = `3f8b1fb`，提交序列：TASK-01～07 `e8b8dc0`→`1c2aa5a`→`e27c9a8`→`cac84b5`→`24f8cca`→`bfb3a3f`→`45006b7` + 回修 `07b47da`（B-CODE-001）+ `3f8b1fb`（B-CODE-003））以 spec reporter、**不带** skip-pattern 完整重跑 BR-1/BR-2 所在两个测试文件，失败集合与例外表逐条全等，红计数 = 2 不因本 CR 增加（B-CODE-003 提交后重新实测）：

| BR-ID | 证据日志 | 完整重跑结果 | 与例外表核对 |
|---|---|---|---|
| BR-1 | `test-evidence/baseline-red-BR-1.log` | `crctl.test.mjs` 204 tests：203 pass / **1 fail**，失败用例 = `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引`（断言 `expected: /crctl task init/` 不命中——`pipeline-templates/code-implementation.pipeline.json` 文本不含 `crctl task init`，CR-2026-050 converge 改写所致） | 全等 ✓；本轮新增的白名单回归用例在完整重跑中 pass，未入失败集合 |
| BR-2 | `test-evidence/baseline-red-BR-2.log` | `archive-tx.test.mjs` 21 tests：20 pass / **1 fail**，失败用例 = `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖`（断言 `actual:[{code:EMIT_FAILED,event_kind:archive}]` vs `expected:[]`——archive dedup 重放路径既有缺陷） | 全等 ✓ |

**根因与 follow_up**：

- BR-1：pipeline-templates 文本与既有断言漂移。修复需动 `pipeline-templates/`，与本 CR §9 zero_diff（冻结面 6）冲突 → 根因修复另开 CR，建议 follow_up CR 同步收敛 pipeline 提示词与 crctl.test.mjs 断言。
- BR-2：archive dedup 重放路径既有缺陷（本 CR 不触 archive 事务）。→ follow_up CR 修复 archive dedup 重放与 EMIT_FAILED 断言。

两条均非本 CR 引入（基线 8c0a6db 实测同红，plan §5.3 例外表已冻结登记），B-CODE-003 回修未出现任何新红。

### 3. 四项静态核对（HEAD 3f8b1fb 复核）

1. **AC-4 contract-scan**：本次重跑 `contract-scan.test.mjs` 7/7 全绿——3 Pipeline + 11 SKILL 对四个禁止字段零命中（本轮提交未触碰 SKILL/pipeline 文本，结论与上一轮一致）。
2. **AC-17 diff 审阅**：tools diff（基线 8c0a6db..HEAD=`3f8b1fb`）共 22 文件，仍仅在 plan/SDD 批准面内；**本轮 delta（07b47da..3f8b1fb）恰 2 文件**——`workspace-transactions.mjs`（`verifyReleaseSubjects` allowed 集合 +1 条目及一行注释，无新 validator、无 schema 变化）与 `crctl.test.mjs`（+31 行回归测试）。`durable-tx.mjs` 零 diff → `FAULT_POINTS` 零新增。
3. **AC-11 gates 零改动**：`gates.json` 不在 diff 中；`deliveryIndexComplete` 行为不变。
4. **AC-13 frontmatter 全等**：本轮未改任何过程文档，cr.md / prd.md / sdd.md / plan.md / 全部 11 张 TASK 卡 `target-version: unassigned` 全等不变。

### 4. §9 zero_diff 冻结面核对（HEAD 3f8b1fb）

`8c0a6db..3f8b1fb` 全量 diff 变更文件列表中，冻结面八项零命中：`dir-graph.yaml`（状态机）、`gates.json`、`pipeline-templates/`（三条 CR Pipeline）、`durable-tx.mjs`、`yaml-subset.mjs`、`controlled-shell/rules.json`、`contract-scan.test.mjs` FORBIDDEN 清单、`REVIEW_REPAIR_TARGETS` 常量（位于 crctl.mjs，本轮未触碰该文件）。multica 仓零改动（PRD §7 范围排除）。

### 5. 接口签名汇总核对（TASK-11 实现要点 8，本轮未变）

- TASK-01 产出 → TASK-02/03/04 消费：`normalizeTargetVersion(raw, { allowUnassigned = true })` 三处消费一致（register 顶部校验 / guardWritebackVersion / cmdVersionSet `--to` 规范化）；`readCrMdTargetVersion(ws, cr)` 由 writeback 守卫消费。✓
- TASK-05 产出 → TASK-07 消费：机器区每 command `skipped: boolean`（additive）与 review-code「只读 `skipped`/`exit-code`/`timed-out` + 覆盖矩阵 `cmd-NN`」口径一致。✓
- TASK-04 错误码族与 SDD §3.3 一致：业务四枚 `VERSION_SET_INVALID` / `VERSION_SET_NOT_UNASSIGNED` / `VERSION_SET_STATE_INVALID` / `VERSION_SET_DERIVED_DRIFT` + 基础设施族三枚（镜像 `OWNER_*`）。✓

### 6. FR-23 交叉校验

`tasks/_index.yml` 全部 estimate 之和 = **84h**，与 plan §5.4 `totalEstimateHours=84` 一致（本轮未变）。✓

### 7. AC 覆盖小结（cmd-NN 证据关联）

- AC-12（register 版本校验正负向量与零写入）：cmd-02。
- AC-14（writeback 版本守卫时序与六项零观察点）：cmd-03。
- AC-15（version-set 全链同步/幂等/漂移拒绝/中断重试闭环）：cmd-04（含 B-CODE-001 非末条目回归）。
- AC-16（自动化侧 skipped 计算）：cmd-05，冻结模式表五条各命中 + CRLF 变体 + 两域外不命中 + 标记缺失/重复硬失败。
- AC-18（全量回归）：cmd-06（skip BR-1|BR-2 后 exit 0）+ §2 红计数=2 不增加。
- 本轮增量：`verifyReleaseSubjects` 白名单语义由 crctl.test.mjs 新用例直接覆盖（cmd-01 / cmd-06 内执行：crctl.test.mjs 204 用例中 203 通过，仅 BR-1 按例外表排除）。

### 8. 未覆盖风险

- 评审行为侧 AC（AC-1～AC-4、AC-6/7/9/10/16 评审侧）为模型行为夹具，证据载体是后续 review 轮的 `review-annotations/*.yml` 内容，不由本测试报告自动化断言（SDD §6.2）。
- BR-1/BR-2 根因修复不纳入本 CR（§5.3 例外表），follow_up 去向见 §2。

### 9. 回修历史

**B-CODE-001（review-code attempt-1 BLOCK，FR-15/AC-15，crctl.mjs `editBacklogTargetVersionLine` 块边界换行）**：块替换改为在权威区间 `norm.slice(block.start, block.end)` 上做单行定点替换，替换未命中一律 `LEDGER_PARSE_FAILED` 硬失败（纪律 #1）；集成回归（version-set.test.mjs）：目标条目非末项时后继条目逐字节不变、双投影可解析、恰 1 个新 commit。回修 commit `07b47da`。

**B-CODE-002（review-code attempt-1 BLOCK，测试证据可重放性，test-report.md 双 marker）**：分析区重复标记收敛为唯一一条，经合法 `crctl test` 路径重生成机器区、traceability、review-loop 与六个 cmd-NN 日志；`parseAnalysisMarker` 现恰好命中 1 条。

**B-CODE-003（approve-code 门禁 `RELEASE_SUBJECT_DRIFT` 零写入拒绝后的回修，verifyReleaseSubjects KB 白名单）**：

- 触发：人工 `crctl approve --stage code` 时，KB 提交 `9f96f57 [cr] update context` 触碰 `_context.md`，该路径当时不在 `verifyReleaseSubjects` 的 allowed 集合 → `post-review-path-drift` 拒绝且 approval.yml 零写入（门禁按设计工作，非 bug）。
- 修复（tools commit `3f8b1fb`）：KB allowed 集合新增 `change-requests/${cr}/_context.md`（注释：工作流上下文加速文件，每 run 收尾刷新、随 CR 提交，与 cr.md/traceability.yml 同类，评审后可变更）。白名单只豁免「发布漂移」这一道检查；文件照常每 run 提交、全程可审计，不再被门禁误伤。允许集合其余条目、multica/tools 的 head 相等性检查与工件 digest 检查一字未动。
- 回归测试（crctl.test.mjs 新增 1 条，独立双 fixture）：① 评审后仅提交 `_context.md` → `approve --stage code` 放行至 `code-approved`；② `_context2.md`（同类拼写但非白名单）→ `RELEASE_SUBJECT_DRIFT / post-review-path-drift` 拒绝且 approval.yml 零写入。
- 红/绿证据：新用例在 cmd-01 / cmd-06（HEAD 3f8b1fb）执行通过；crctl.test.mjs 完整重跑 204 tests = 203 pass + 1 fail（仅 BR-1，按 §5.3 例外表冻结口径）。

**范围外观察（follow_up，不纳入本 CR）**：同款 `slice(0, block.start) + join('\n') + slice(block.end)` 拼接形态仍存在于 `editBacklogSet` / `editBacklogOwnerProjection` / `editInboxEmit`（CR-2026-019/021/039 既有命令路径），非末条目 backlog 上同有粘连风险；建议 follow_up CR 统一收敛为区间定点替换。
