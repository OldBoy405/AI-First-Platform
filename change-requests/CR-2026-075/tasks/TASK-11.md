---
id: CR-2026-075-TASK-11
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: suite-gate 覆盖型安全网误判修复（人类授权范围修正）
slug: suite-gate-coverage-safety-net-fix
status: pending
estimate: 2h
depends-on: []
created: 2026-10-06T14:50:00+08:00
---

## 任务描述

修复 `skills/shared/crctl/scripts/test/suite-gate.mjs` 的「非零退出码安全网」误判：当某文件的失败被**未到期例外全部覆盖**时，例外机制不再产生任何 trigger，而该文件自身仍以非零退出码结束；安全网据此把「全部失败已登记例外」误判为「TAP 未暴露任何失败」，落 `SUITE_REPORT_UNPARSEABLE` 使聚合门禁转红——即「豁免某文件的全部失败」在现状下反而比部分豁免更红。

本 TASK 是**人类 owner 授权的范围修正**：目标文件不在 `sdd.md` §9 `scope_in` 的文件集内（同 R12 的处置口径「要动 `scope_in` 外的文件属批准范围扩张」），故经 `crctl task append` 以 developing 期 hardening TASK 登记，不重开 `prd.md`/`sdd.md`、不改门禁/状态机/`rules.json`。

### 授权与交接来源

- owner 授权原文（Ray，2026-10-06）：
  > 授权 CR-2026-075 最小扩范围修复：修正 `suite-gate.mjs` 对「失败全部被有效例外覆盖」的误判。未登记失败、异常退出和无法解析的报告仍须阻断；不修改那4个既有失败测试，不放宽 `crctl.mjs` 的工作区校验。保留已授权例外及到期时间。线上 crctl skill 副本由我按修复后的仓库版本同步。
- 协调者交接：issue `AIFI-41` 评论 `01a10ff0-980e-7600-a471-a132ea266826`（2026-10-06T06:39:48Z，`code-implementation → dev-agent`）。
- 上游根因证据：作者评论 `01a10fda-a703-7204-8d09-2e39e8990508` + `test-evidence/cmd-11-exception-registration-R17.md`（登记 R17 4 条例外后 `cmd-11` 仍未转绿，新增 block 理由 = `SUITE_REPORT_UNPARSEABLE`）。
- 授权范围**不含**：线上平台副本同步（`tasks/TASK-09.md` 已定：执行人 = 人类 owner，本 CR 不代执行、不写平台配置）。

## 根因

`safe net` 判据 = `records.some((r) => r.exit_code !== 0) && triggers.length === 0`（`suite-gate.mjs:469`）。判据的第二项问的是「本次运行有没有任何 trigger」，而不是「该文件自己的 TAP 是否暴露了失败」：

1. 4 例 R17 既有失败被 4 条未到期 `suite-failure` 例外全量覆盖 → `SUITE_FAILURES_UNREGISTERED` 不产生 trigger；
2. 但被豁免文件仍以 `exit_code=1` 结束（失败客观存在），`EXCEPTION_NOT_OBSERVED` 也不产生（4 条例外全部被观测到）；
3. 于是 `triggers.length === 0` 成立 + 存在非零退出码，安全网把「报告结构不完整」这一**唯一**适用场景扩大到了「报告完整且失败已被全部豁免」，落 `SUITE_REPORT_UNPARSEABLE`。

即安全网缺少「本次运行已暴露的失败集合」这一维度（对照：非收敛分支的 `SUITE_NONCONVERGENCE` 有 `suppressed_by` 通道）。

## 涉及文件

- `skills/shared/crctl/scripts/test/suite-gate.mjs`（唯一实现改动：安全网判据由「运行级 trigger 为空」改为「该文件退出非零且自身 TAP 未暴露失败」）。
- `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（新增 2 条回归用例，沿用既有 probe-root + `--report` 机制，不新增测试文件、不改 manifest 文件集）。

## 验收条件

1. **绿侧（本 TASK 的修复目标）**：失败被未到期例外全部覆盖的 `--report` 复现件 → `verdict=pass`、退出码 0、`SUITE_FAILURES_UNREGISTERED.ok=true`、`SUITE_REPORT_UNPARSEABLE.ok=true`。
2. **红侧（授权明文要求「异常退出仍须阻断」）**：非零退出码 + 该文件 TAP 未暴露任何失败（无例外覆盖）→ 仍落 `SUITE_REPORT_UNPARSEABLE`、退出码非零。
3. **回归红绿**：新增用例在修复前红、修复后绿；两次原始输出归档（`test-evidence/safety-net-coverage-regression-red.txt` / `-green.txt`）。
4. **全量复验**：`cmd-11`（`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`，cwd = tools CR worktree，timeout 3600）→ `verdict=pass`、退出码 0，`files_executed=28`、`cases_executed` 与登记前同集（R17 4 例仍为既有基线红例、不得被读作已修复）。
5. **边界零改动**：`gate-registry.json` 的 4 条例外与到期时间逐字保留；`crctl-summary.test.mjs` 的 4 例既有失败测试零改动；`crctl.mjs` 的显式 `--workspace` 校验（FR-04 语义）零改动。

## 产出

- `test-evidence/suite-gate-coverage-safety-net-fix.md`（根因 + 改动面 + 红/绿/全量三次原始结果 + 边界与副作用声明）。
- `test-evidence/safety-net-coverage-regression-red.txt`、`test-evidence/safety-net-coverage-regression-green.txt`。
- `test-evidence/cmd-11-rerun-after-safety-net-fix.txt`（`cmd-11` 原始输出）。
- 本 TASK 卡 + `tasks/_index.yml` 条目（`crctl task append` / `crctl task done` 写入）。

## 完成标志

上述 5 条验收条件全部取得原始证据；`crctl task done CR-2026-075 --task CR-2026-075-TASK-11` 落账；tools 与 knowledge-base 两个 CR worktree 的改动同批 commit（同一交付集合）。

## 已知副作用（如实登记，不在本 TASK 内消除）

追加本 TASK 会改变 dev-plan composite subject（`plan.md` + `tasks/TASK-*.md` 的合成摘要），使 `review-annotations/dev-plan.yml#subject-sha256` 相对当前 TASK 集过期，`crctl status` 的 `gateBlockers.developing` 将出现 `dev-plan digest 漂移`。本 TASK **不清除也不重跑** `review-dev-plan`（该 loop 剩余轮次 1/3，是否消耗由人类 owner 裁决）；该漂移不阻断 `code-reviewing` / `code-approved` 门禁（其 passCondition 指向 `review-code`，不消费 dev-plan digest）。

## 边界

- 不修改 R17 的 4 例既有失败测试；不放宽 `crctl.mjs` 工作区校验；不改 `rules.json`；不改状态机/gates/Pipeline。
- 不写平台配置、不同步线上 crctl skill 副本（人类 owner 执行；同步前 `cmd-10` 仍因 `gate-registry.json` 副本漂移而红）。
- 不新增证据命令 ID（`plan.md` §8 0.12 已声明「不增删证据 ID」），本 TASK 的复验沿用 `cmd-11` 既有 executable/args/cwd/timeout。
