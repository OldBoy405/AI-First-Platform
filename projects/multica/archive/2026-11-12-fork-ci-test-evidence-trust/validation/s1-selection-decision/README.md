# Slice 1 证据 — selection 对账决策（TC-SEL-001 / TC-SEL-002 / TC-SEL-003）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12T16:56 本地｜Node v24.15.0｜Windows
> 业务仓 HEAD：`903a46c5a`（= origin/main），切片开始前工作区干净。
> 本切片不创建任何容器、不连接任何数据库，全部为离线纯函数与子进程边界测试。

## 缺陷与修复

`verifyGoTestSelection`（`scripts/aifi45-disposable/selection.mjs:2-3`）只返回
`{status:'matched'}` 或 `{status:'blocked', reason}`。修复前 `run-selection.mjs` 读的是
`.matched` 与 `.blocked`：

- 旧第 141 行 `reconciliation?.matched !== false` 中 `.matched` 恒为 `undefined`，
  表达式恒真 → **对账结果从不参与判定**，缺测试/多测试/重复事件的流仍报 PASS。
- 旧第 165-166 行 `result.reconciliation.matched === false` 恒假 → `blocked=` 永不输出；
  该分支一旦命中还会因 `.blocked` 不存在而抛异常。

修复：新增 `selection-decision.mjs`，导出 `decideSelection` 与 `selectionLine`；
`run-selection.mjs` 只调用它们。`expected` 未配置时判定与输出行逐字不变。

## 命令与结果（原始 TAP 见同目录）

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `node --test --test-reporter=tap scripts/aifi45-disposable/selection-decision.test.mjs` | 0 | 12 | 12 | 0 | 0 | `tc-sel-001-003.tap` |
| `node --test --test-reporter=tap scripts/aifi45-disposable/run-selection.test.mjs` | 0 | 11 | 11 | 0 | 0 | `tc-sel-002.tap` |
| `node --test --test-reporter=tap --test-name-pattern=EXPECTED_INVALID scripts/aifi45-disposable/selection-decision.test.mjs` | 0 | 4 | 4 | 0 | 0 | `tc-sel-003-pattern.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（全量回归） | 0 | 60 | 60 | 0 | 0 | `regression-directory.tap` |

新增测试 18 项：`selection-decision.test.mjs` 12 项 + `run-selection.test.mjs` 追加 6 项。
`run-selection.test.mjs` 既有 5 项断言逐字保留、未改弱；`selection.test.mjs` 未改动。

## RED

实现前运行 `selection-decision.test.mjs` → `ERR_MODULE_NOT_FOUND`
（`selection-decision.mjs` 不存在），退出码 1、fail 1。

## 变异验证（TC-SEL-001 AND 条款）

把 `decideSelection` 的原因判定改回旧写法：

```js
const reason = reconciliation?.matched === false ? reconciliation.blocked.join(",") : null;
```

结果：退出码 **1**，12 项中 **10 项变红**（`mutation-old-matched-blocked.tap`）：

```
not ok 3  - TC-SEL-001 missing declared child fails with blocked=SELECTION_MISMATCH
not ok 4  - TC-SEL-001 extra passing test fails with blocked=SELECTION_MISMATCH
not ok 5  - TC-SEL-001 duplicate child pass fails with blocked=EVENT_ORDER
not ok 6  - TC-SEL-001 skipped child fails with blocked=TEST_NOT_PASSED
not ok 7  - TC-SEL-001 an unconfirmed process is reported with its own reason
not ok 8  - TC-SEL-003 EXPECTED_INVALID for an empty declared manifest
not ok 9  - TC-SEL-003 EXPECTED_INVALID for a non-array declared manifest
not ok 10 - TC-SEL-003 EXPECTED_INVALID for illegal manifest elements
not ok 11 - TC-SEL-003 EXPECTED_INVALID is not silently treated as unconfigured
not ok 12 - TC-SEL-003 a failing process does not hide an unusable declared manifest
```

其中 3/4/5 三项的流仍满足 `exit=0 / fail=0 / skip=0 / pass>0`，**只有对账能让它们变红**，
因此该变异确实证明了旧写法的失效面，而不是被 totals 判定顺带掩盖。

恢复后复跑：退出码 0、12/12 通过（`restored-after-mutation.tap`）。
`grep -c "matched === false"` 在 `selection-decision.mjs` 与 `run-selection.mjs` 均为 0。

## 真实返回值纪律

单测中所有 `reconciliation` 均由 `verifyGoTestSelection(...)` 现场计算，不手写
`{matched, blocked}`。另有一项断言直接检查真实结果**不含** `matched`/`blocked` 自有属性，
把契约错配本身固定为回归用例。

## 逐字不变的输出行（TC-SEL-002）

`run-selection.test.mjs` 中以修复前的字面量断言：

- `PASS legacy pass=2 fail=0 skip=0`
- `FAIL legacy pass=1 fail=1 skip=0` / `FAIL legacy pass=1 fail=0 skip=1` / `FAIL legacy pass=0 fail=0 skip=0`
- migrate 阶段无 totals → `FAIL legacy`（保留原 `.trim()` 行为）
- 另有一项 3×3×2×2 = 36 组合的穷举，断言未配置时
  `ok === (code===0 && fail===0 && skip===0 && pass>0)` 且 `reconciliationLine === ""`。

## 执行环境坑（供 Slice 13 CI 接线使用）

Node 24 在 Windows 下把 `node --test scripts/aifi45-disposable`（目录参数，带或不带尾斜杠）
当作模块解析并报 `MODULE_NOT_FOUND`，退出码 1。**这不是测试失败，是入口形式问题。**
可用形式为 glob：`node --test "scripts/aifi45-disposable/*.test.mjs"`（60/60 通过）。
CI 步骤须采用 glob 形式，不得照抄目录形式后把该失败当作业务红灯。

## 未做 / 边界

- 未执行 `quality.test` 配置的 `make test`（U5 排除：会拉起旧 `multica-postgres` 并连 localhost:5432）。
- 未创建/释放任何容器，未连接任何数据库；本切片不需要前后容器清单对账。
- 未提交、未推送。`CUSTOM.md` 已登记 M31 / 行 #317。
- `decideSelection` 在 `expected` 为非空数组时直接读 `reconciliation.status`；
  调用方 `run-selection.mjs` 的既有条件保证此时必有对账结果，缺失即抛错硬失败，不静默放行。