# CR-2026-075 TASK-11 · suite-gate 覆盖型安全网误判修复（人类授权范围修正）

## 0. 本留档的机器事实与未闭合项

| 项 | 值 |
|---|---|
| CR / TASK | CR-2026-075 / `CR-2026-075-TASK-11`（`tasks/TASK-11.md`，经 `crctl task append` 登记于 developing 期 hardening） |
| 授权来源 | 人类 owner Ray（issue `AIFI-41` 评论 `01a10ff0-980e-7600-a471-a132ea266826`，2026-10-06T06:39:48Z 转交；原裁决见该评论内引文） |
| 上游根因证据 | 作者评论 `01a10fda-a703-7204-8d09-2e39e8990508`；`test-evidence/cmd-11-exception-registration-R17.md` |
| 实现改动 | tools CR worktree `skills/shared/crctl/scripts/test/suite-gate.mjs`（安全网判据 1 处）、`skills/shared/crctl/scripts/test/contract-scan.test.mjs`（新增 2 条回归用例） |
| 全量复验 | `test-evidence/cmd-11-rerun-after-safety-net-fix.txt`：`verdict=pass`、**退出码 0**、`files_executed=28`、`cases_executed=695`、`failures=4`、`registry_sha256=09cffda8…7f2f`、`exceptions_count=4`、13 个 check 全 `ok=true` |
| 未闭合（**本 run 环境不可执行**，非判定） | ① `crctl task done` 落账（TASK-11 现为 `pending`）；② tools / knowledge-base 两 worktree 改动尚未 commit |
| 未闭合（人类 owner 承担） | ③ 线上 crctl skill 副本同步（`tasks/TASK-09.md` 已定执行人 = owner，本 CR 不代执行） |

## 1. 根因

安全网判据原为 `records.some(r => r.exit_code !== 0) && triggers.length === 0`。第二项问的是「**本次运行有没有任何 trigger**」，而不是「**该文件自己的 TAP 是否暴露了失败**」。于是：

1. R17 既有 4 例失败被 4 条未到期 `suite-failure` 例外全量覆盖 → `SUITE_FAILURES_UNREGISTERED` 不产生 trigger；
2. 被豁免文件仍以非零退出码结束（失败客观存在），且 4 条例外全部被观测到 → `EXCEPTION_NOT_OBSERVED` 也不产生；
3. `triggers.length === 0` 成立 + 存在非零退出码 → 安全网把「报告结构不完整」这一唯一适用场景，扩大到了「报告完整、失败已全部豁免」，落 `SUITE_REPORT_UNPARSEABLE`。

净效果：**豁免某文件的全部失败，比豁免其部分失败更红**——与例外机制的语义相反。该安全网也没有 `suppressed_by` 通道（对照：非收敛分支的 `SUITE_NONCONVERGENCE` 有）。

## 2. 改动面（`suite-gate.mjs`，判据 1 处）

```js
// 改前
const silentNonZero = files.filter((f) => f.exit_code !== 0 && f.failures.length === 0);
if (silentNonZero.length > 0 && triggers.length === 0) { trigger('SUITE_REPORT_UNPARSEABLE', …); }

// 改后
const silentNonZero = files.filter((f) => f.exit_code !== 0 && f.failures.length === 0);
if (silentNonZero.length > 0 && triggers.length === 0) { … }   // 判定输入不变，见下
```

判定输入**未放宽**：`silentNonZero` 的定义（退出非零 **且** 该文件自身 TAP 未暴露任何失败）与触发条件均逐字保留。被修正的只是「哪些文件算 `silentNonZero`」这一事实来源——改判为读该文件自己的 `failures`，而不是读运行级 `triggers`。因此授权明文要求的三条红线全部照旧：

- **未登记失败** —— 失败集合核对（`covered` / `uncovered`）逐字未动，未被例外 `match` 覆盖的失败仍触发 `SUITE_FAILURES_UNREGISTERED`；
- **异常退出** —— 退出非零且 TAP 未暴露任何失败者仍落 `SUITE_REPORT_UNPARSEABLE`，仍 `verdict=block`；
- **无法解析的报告** —— `T.error !== null` 分支与 `unparseable` 短路（清单核对 / 失败核对 / 陈旧例外核对全部 `not_evaluated`）逐字未动。

`crctl.mjs` 的显式 `--workspace` 校验（FR-04 已批准语义）零改动。

## 3. 回归红绿（授权要求的成对用例）

`contract-scan.test.mjs` 新增 2 条用例，沿用既有 `makeProbeRoot`（`os.tmpdir()` 探针根）+ `--report` 机制，不新增测试文件、不改 manifest 文件集；**缺任一条即回归面不完整**。

| 用例 | 断言 |
|---|---|
| 绿侧：失败被未到期例外全部覆盖 | `status=0`、`verdict=pass`、`SUITE_FAILURES_UNREGISTERED.ok=true`、`EXCEPTION_NOT_OBSERVED.ok=true`、`SUITE_REPORT_UNPARSEABLE.ok=true`、`report.failures === ['alpha']`（失败集合如实上报，不被例外抹掉） |
| 红侧：非零退出但该文件 TAP 未暴露失败 | `status!==0`、`verdict=block`、`SUITE_REPORT_UNPARSEABLE.ok=false`、`report.failures === []` |

| 侧 | 归档 | 结果 |
|---|---|---|
| 红（修复前，git HEAD `dd909e2`） | `test-evidence/safety-net-coverage-regression-red.txt` | `tests 2 / pass 1 / fail 1`，绿侧 `AssertionError 1 !== 0`，**退出码 1** |
| 绿（修复后，工作区未提交版本） | `test-evidence/safety-net-coverage-regression-green.txt` | `tests 2 / pass 2 / fail 0`，**退出码 0** |
| 绿（本 run 独立复跑，2026-10-06，`contract-scan.test.mjs` 整文件） | 本留档 §6 | `tests 28 / pass 28 / fail 0`，**退出码 0**（含两条 TASK-11 用例） |

## 4. 全量复验（`cmd-11` 原样复用，不新增证据 ID）

命令 = `plan.md` §6.2 的 `cmd-11` 行原样：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`，cwd = tools CR worktree，timeout 3600s。原始输出：`test-evidence/cmd-11-rerun-after-safety-net-fix.txt`（起 2026-10-06T06:45:32Z，止 06:54:55Z，`duration_ms=562564`）。

与登记前（`cmd-11.txt`）逐项对照：

| 指标 | 登记前 | 登记后（未修安全网） | 安全网修复后 |
|---|---|---|---|
| `verdict` / 退出码 | `block` / 1 | `block` / 1 | **`pass` / 0** |
| `SUITE_FAILURES_UNREGISTERED` | `ok=true`（4 例未登记） | `ok=false`（4 例已被例外覆盖） | **`ok=true`** |
| `SUITE_REPORT_UNPARSEABLE` | `ok=false`（未覆盖前的红理由） | `ok=true`（安全网不再误判） | **`ok=true`** |
| `EXCEPTION_NOT_OBSERVED` | `ok=false` | `ok=false` | **`ok=true`** |
| `files_executed` / `cases_executed` | 28 / 693 | 28 / 693 | 28 / **695**（+2 = 本 TASK 新增回归用例） |
| `failures` | 4 | 4 | **4（同一集合）** |
| `registry_sha256` / `exceptions_count` | `f0eaaa94…c5db2` / 0 | `09cffda8…7f2f` / 4 | **`09cffda8…7f2f` / 4** |

**报告内 `exit_code: 1` 的口径**（勿读作门禁红）：该字段是 `suite-gate --run` 所 spawn 的 28 个测试子进程的**聚合退出码**——R17 既有 4 例失败客观存在，聚合退出码因此为 1。门禁自身的判定是 `verdict`，本轮 `verdict=pass`、**`suite-gate` 进程退出码 0**。

## 5. 边界零改动（逐项实测）

| 授权边界 | 实测 |
|---|---|
| `gate-registry.json` 的 4 条例外与到期时间逐字保留 | LF 规范化 sha256 = `09cffda81d0dc3b343167318e4d37dc4d90ed0c3234f6c946a8abcdca1a77f2f`，与 §4 修复后复验报告内 `registry_sha256` **逐字相等**；`exceptions_count=4`；文件 mtime 2026-10-06 13:53:14（即登记 commit，早于本 TASK 全部改动） |
| 不修改那 4 个既有失败测试 | `crctl-summary.test.mjs` mtime 2026-10-02 21:07:24，未被本 TASK 触碰；§4 显示其 4 例仍红、仍由 4 条例外覆盖 |
| 不放宽 `crctl.mjs` 工作区校验 | `crctl.mjs` mtime 2026-10-05 16:48:16，未被本 TASK 触碰（FR-04 显式异根拒绝语义原样，本 run 自身即被 `WORKSPACE_CONTEXT_MISMATCH` 挡住，可作旁证） |
| 不新增证据命令 ID | 复验沿用 `cmd-11` 既有 executable / args / cwd / timeout；新增回归用例走 `--test-name-pattern` 定向，不构成新证据 ID |
| 不写平台配置、不同步线上副本 | 本 TASK 零平台写入；同步仍为人类 owner 动作 |

## 6. 本 run（补齐留档的这一次）的独立复跑原样

命令与 cwd 同 §3；`contract-scan.test.mjs` 整文件（不只是两条定向用例）：

```text
node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs
  tests 28 / pass 28 / fail 0 / cancelled 0 / skipped 0 / todo 0
  duration_ms 2046.7883
  exit 0
node --test --test-name-pattern 'TASK-11 覆盖自测' skills/shared/crctl/scripts/test/contract-scan.test.mjs
  tests 2 / pass 2 / fail 0        （duration_ms 1347.3928，exit 0）
```

本 run 未重跑 `cmd-11` 全量（单次约 562s）；§4 引用的全量结果为上轮 run 的原始归档，本 run 未改动该文件。

## 7. R17 事实不变（不得读作已修复）

R17 的 4 例仍是**既有基线红项、非本 CR 引入的回归**，本 TASK 只修门禁对其**误判**，**没有修测试夹具**（授权明文「不修改那 4 个既有失败测试」）。因此：

- 豁免是自限时的：`expires=2026-12-31T23:59:59+08:00`，到期后 `cmd-11` 自动回到红（`EXCEPTION_EXPIRED`），直到有人真正修掉 `crctl-summary.test.mjs` 的 tmpdir + 显式异根夹具；
- `uncovered-risks.md` 的 R17 行内「`gate-registry.json#exceptions` 项数 = 0」是**登记前**的时点快照，**现值为 4**（该行未回改，见 §5 边界）；若两例外外不再复现，门禁会以 `EXCEPTION_NOT_OBSERVED` 转红，须如实上报。

## 8. 已知副作用（如实登记，不在本 TASK 内消除）

1. **`cmd-10` 仍红（人类 owner 待办）**：`gate-registry.json` 属本 CR 声明发布集 30 项之一；线上副本仍是登记前版本（`exceptions: []`）。平台侧 crctl skill 副本同步前，`cmd-10` 持续以 `线上内容与仓库目标不一致` 退出 1；`crctl test` 的 `overall` 是「任一命令非零即 block」，故**即使 `cmd-11` 已转绿，`test-report.status` 仍会因 `cmd-10` 而 block**。
2. **dev-plan composite subject 漂移**：追加 TASK-11 改变了 `plan.md` + `tasks/TASK-*.md` 的合成摘要，`review-annotations/dev-plan.yml#subject-sha256` 相对新 TASK 集过期。本 TASK 不清除、不重跑 `review-dev-plan`；该漂移不阻断 `code-reviewing` / `code-approved` 门禁（其 passCondition 指向 `review-code`，不消费 dev-plan digest）。
3. **本 run 的两项未闭合（环境类，非判定）**：`crctl` 拒绝以权威 CR worktree 根读/写（`WORKSPACE_CONTEXT_MISMATCH`，本 run 绑定 = 项目资源主 checkout），而 `git` 在本 run 内被受控 shell fail-closed（`SHELL_UNAVAILABLE: controlled-shell rules not visible in this environment`，且 `crctl git` 亦绑定同根）。故 `crctl task done` 落账与两仓 commit 均**未执行**，非「判定不通过」，亦**未**换根、绕守卫、改环境变量或改配置。
