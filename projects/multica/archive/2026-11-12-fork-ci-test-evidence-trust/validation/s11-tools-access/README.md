# Slice 11 — tools 凭据诊断（TC-CCF-001 / SC-CCF-001 / CP-CCF-001）

STDD change：`2026-11-12-fork-ci-test-evidence-trust`
业务仓：`C:/Users/GOBAO/Downloads/AI/multica`，HEAD = origin/main = `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`
执行模式：`long_range.mode = full_auto`，`mode = thorough`
完成时间：**2026-11-13T00:48:42**（本机本地时间 UTC+8）
产物：`scripts/aifi45-disposable/tools-access.mjs`（新，109 行）、`scripts/aifi45-disposable/tools-access.test.mjs`（新，274 行）

---

## 1. 范围与授权

本切片只做 design.md:157 与 canonical SC-CCF-001 锁定的那一件事：**把 tools 凭据失败的原因区分开，且不泄漏凭据**。

授权来源是 Gate 2 确认（最新重签 `2026-11-12T23:54:09`）与 U5 预授权。**Gate 2 确认不等于 Gate 3 确认**，本切片不推进 Gate 3。

明确不在本切片范围内：

- **不改 `.github/workflows/ci.yml`**。把 `transitions-contract-check` 的「Require the tools read credential」一步替换为本诊断，属 **S13**。已核实：`git diff -- .github/workflows/ci.yml` 中 `tools-access` 出现 **0 次**，旧步骤仍在 `ci.yml:105`；该文件当前的 15 插入 / 1 删除全部来自 S2/S5。
- **不读取、不创建、不轮换任何凭据**（SC-CCF-003 明文 SHALL NOT）。管理员更新 PAT 属 SC-CCF-003，未闭合。
- 不碰 `packages/views`（属 S12）。

## 2. 锁定规格与验收断言

canonical `specs/code/ci-credential-and-frontend-typecheck.yaml` SC-CCF-001：

> given tools-access 可注入 fetch，when 分别返回：凭据为空、401、403、404、200、网络异常、其他状态。then SHALL 映射为 missing、rejected、no-access-or-pin-not-found、ok、inconclusive，非 ok 时非 0 退出；SHALL 任何输出与错误信息不含 token 值；请求头 SHALL 仅在 fetch 调用内使用。

canonical `specs/agent/…` CP-CCF-001（**两条断言一字未改**）：

| 项 | 锁定值 | 实测 |
|---|---|---|
| action | `node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs` | 原样执行 |
| 断言 1 | `exit_code 0` | **0** |
| 断言 2 | `stdout_contains '# fail 0'` | **`# fail 0`** |

## 3. RED — 如实定性为导入级

新模块尚不存在，RED 是**导入级**而非断言级：

```
node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs
→ ERR_MODULE_NOT_FOUND: …/scripts/aifi45-disposable/tools-access.mjs
→ exit 1，# tests 1 / # pass 0 / # fail 1
```

证据：`red/red.tap`。

**导入级 RED 不能证明断言有 teeth**（模块不存在时任何断言都「失败」）。为不让这一点被含糊过去，做了两件事：

1. **让 RED 对应最终测试字节**：实现与测试夹具修正完成后，把 `tools-access.mjs` 临时移到 `red/tools-access.mjs.aside`，用**最终**测试文件重跑取 `red/red-final-testbytes.tap`（exit 1 / fail 1），再移回并 `sha256sum -c` 核对两个文件逐字节还原（均 `OK`）。
2. **真实 teeth 由 §7 的 16 条变异验证提供**，逐条中和生产守卫并证明对应用例变红。

## 4. 实现契约

| 导出 | 契约 |
|---|---|
| `TOKEN_ENV` | `"AIFIRST_TOOLS_READ_TOKEN"` |
| `TOOLS_REPO` | `"OldBoy405/AI-First-tools"` |
| `checkToolsAccess({token, pin, fetchImpl = fetch})` | async → `{outcome, message, exitCode}`，**恰好三个键** |
| `runToolsAccessCli(argv, {fetchImpl, env, log, error})` | async → exitCode |

输入 → 结论映射（7 类输入，5 个结论）：

| 输入 | outcome | exitCode | 是否发请求 |
|---|---|---|---|
| `""` / `"   "` / `undefined` / `null` | `missing` | 1 | **否** |
| 401 | `rejected` | 1 | 是 |
| 403、404 | `no-access-or-pin-not-found` | 1 | 是 |
| 200 | `ok` | **0** | 是 |
| fetch 抛异常（网络） | `inconclusive` | 1 | 是（未完成） |
| 302 / 429 / 500 / 503 / 204 / 201 / 其余任何状态 | `inconclusive` | 1 | 是 |
| 坏 pin（空、非 hex、39 位、两行、大写） | **throw `/pin/i`** | CLI 转 1 | **否** |

关键实现决定：

- **pin 规则复用 `tools-pin.mjs` 的 `parsePin`**，不另写一份校验；`parsePin` 在发请求**之前**调用，坏 pin 不携带凭据出门。
- 请求恰好一次：`GET https://api.github.com/repos/OldBoy405/AI-First-tools/commits/<pin>`，`headers: { Authorization: "Bearer <token>" }`。**凭据只在这里出现**。
- `verdict(outcome, detail, exitCode = 1)` 统一让每条报文**以结论名开头**，CI 日志可直接 grep 结论而不依赖解释文案（这是首轮 GREEN 暴露的缺口，见 §5）。
- CLI：`--pin <40hex>` 与 `--pin-file <file>`（默认 `.github/aifirst-tools-pin`）；未知参数与缺值 flag 一律拒绝；**凭据缺失先于读 pin 文件报出**；带 main-module 守卫，导入不触发 CLI。

## 5. 首轮 GREEN 抓到的两处自身缺陷（均已修正，未放宽任何断言）

| # | 现象 | 根因 | 修正 | 性质 |
|---|---|---|---|---|
| 1 | `not ok 1`（文件级）+ `generated asynchronous activity after the test ended`，报文 `cannot read the tools pin file …Temp\aifi45-tools-access-JR2TAF\…` | **测试夹具缺陷**：`withPinFile(text, body)` 未 `await` 异步 body，`finally` 在断言跑完前就 `rmSync` 删掉临时目录 | `withPinFile` 改 `async` + `await body(...)`；真实子进程用例改 `async` 并 `await withPinFile(...)` | 夹具修正，**断言强度未降** |
| 2 | `not ok 11`：`The input did not match the regular expression /no-access-or-pin-not-found/`，实际输出 `tools access denied (403): no access to repository or pin not found (…)` | **实现缺陷**：报文只含解释文案，不含 canonical 的结论名 | 引入 `verdict()`，五条报文统一以结论名前置 | 实现修正，**断言未改** |

两处都是**先红后修**，不是把断言改松。第 2 处修正后，`missing`/`ok`/`rejected`/`no-access-or-pin-not-found`/`inconclusive` 五个结论名都能在 CLI 输出里直接 grep 到。

## 6. GREEN

```
node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs
exit=0
# tests 15 / # pass 15 / # fail 0 / # skipped 0
```

15 项全部 `ok`，逐项见 `green/green.tap`；按**最终字节**复跑留 `final/tools-access.tap`（exit 0，15/15/0）。

**CP-CCF-001 两条锁定断言均满足**（§2 表）。

15 项用例与 SC-CCF-001 的对应：

| # | 用例 | 覆盖的规格半句 |
|---|---|---|
| 1 | 空凭据 → missing、非 0、**零次 fetch** | 凭据为空 → missing |
| 2 | 401 → rejected、非 0 | 401 → rejected |
| 3 | 403 与 404 → no-access-or-pin-not-found | 403/404 合并结论 |
| 4 | 200 → ok、exit 0 | 200 → ok |
| 5 | 网络异常 → inconclusive、非 0 | 网络异常 → inconclusive |
| 6 | 302/429/500/503/204/201 → inconclusive | 其他状态 → inconclusive |
| 7 | URL、`Authorization` 头、`method` 逐项相等 | 请求头仅在 fetch 调用内使用 |
| 8 | 5 个状态 × 结果序列化 × URL × CLI 输出均不含 token；结果无 `headers`/`init`/`request`/`token` 键 | 任何输出不含 token 值 |
| 9 | 注入内嵌凭据的 leaky Error → 不回显 | 任何**错误信息**不含 token 值 |
| 10 | 5 种坏 pin → throw `/pin/i` 且零次 fetch；CLI 非 0 不泄漏 | pin 先于请求校验 |
| 11 | `--pin-file` × 5 个状态 → exit 0/1/1/1/1 且输出含结论名；不可读 pin 文件 → 非 0 | CLI 分支映射 |
| 12 | `--nope`、`--pin`（缺值）、`--pin-file`（缺值）、`--pin <pin> --bogus x` → 非 0 | 输入边界 |
| 13 | 凭据缺失 + 不存在的 pin 文件 → exit 1、报文含 missing 与 `TOKEN_ENV` | 报出顺序 |
| 14 | **真实子进程**：空凭据 → 非 0 且点名 `TOKEN_ENV`；fixture 凭据 + 不可读 pin → 非 0 且不泄漏 | 真实进程边界 |
| 15 | 导入不跑 CLI；`TOOLS_REPO` 常量正确 | main-module 守卫 |

## 7. 变异验证 — 16/16 DETECTED，0 SURVIVED

驱动：`mutate.mjs`（证据工具，非产品代码）。每条：精确锚点替换（锚点命中数 ≠ 1 即硬失败）→ 跑测试 → 落 `patch.txt`/`red.tap` → 按原字节还原 → 核对 sha256（不一致即硬失败）。

| ID | 中和的守卫 | exit | pass/fail | 变红的用例 |
|---|---|---|---|---|
| M01 | 删掉 `checkToolsAccess` 的 missing 短路 | 1 | 14/1 | 空凭据 |
| M02 | `token.trim() !== ""` → `token !== ""` | 1 | 14/1 | 空凭据（空白串） |
| M03 | `status === 401` → `402` | 1 | 13/2 | 401 映射 + CLI 分支 |
| M04 | 去掉 `\|\| status === 404` | 1 | 13/2 | 403/404 + CLI 分支 |
| M05 | ok 的 `, 0)` 去掉（落回默认 1） | 1 | 13/2 | 200 → ok + CLI 分支 |
| M06 | 网络 catch 改成原样 rethrow | 1 | 13/2 | 网络异常 + leaky Error |
| M07 | 其余状态兜底改成 `ok`/0 | 1 | 13/2 | 其他状态 + CLI 分支 |
| M08 | `Authorization` 头不带 token | 1 | 14/1 | 请求头断言 |
| M09 | URL 追加 `?access_token=<token>` | 1 | 13/2 | 请求头 + 不泄漏 |
| M10 | catch 里回显 `failure.message` | 1 | 14/1 | leaky Error 不泄漏 |
| M11 | `parsePin(pin)` → 直接用 `pin` | 1 | 14/1 | 坏 pin |
| M12 | CLI 把凭据检查移到 `readPinFile` **之后** | 1 | 14/1 | 报出顺序 |
| M13 | 未知参数 `throw` → `continue` | 1 | 14/1 | 参数拒绝 |
| M14 | 缺值 flag `throw` → `break` | 1 | 14/1 | 参数拒绝 |
| M15 | ok 结果里附加 `token` 字段 | 1 | 14/1 | 结果不暴露 token |
| M16 | 删掉 main-module 守卫 | 1 | 15/1 | **文件级**父测试（导入即跑 CLI，污染 exitCode） |

汇总：`mutation/summary.json`。**16 条全部 DETECTED，无 SURVIVED**。

每条之后还原并核对 sha256，最终 pristine  digest：

```
e997d65a2df2ff508da3ddaff9c063395f1fd801c925ad7f2c6620ae14b31745  tools-access.mjs
b470091b6f1e9eeeaacd6bdbc8d794df9bc4acd23ecb3bb70c32fabf99da07cc  tools-access.test.mjs
```

`green/shipped-sha256.txt` 与 `final/` 复跑前的 `sha256sum -c` 均 `OK`。

**M16 的口径说明**：它不是被某一条具名子测试抓到，而是被**文件级父测试**抓到（导入触发 CLI → 多余输出 + `process.exitCode` 被改写）。用例 15 自称「导入不跑 CLI」，但它只检查自己的 recorder，**单独不足以钉住这条守卫**；这一点如实记录，不夸大为「用例 15 检出 M16」。

## 8. 整包回归 — 逐名对账，零回归

```
node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"
exit=0
# tests 171 / # suites 0 / # pass 171 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0
```

**171 = S10 的 156 + 本切片 15**。

对账不能只比总数。S10 基线用 **spec reporter**（`✔ name (12.3ms)`），本轮用 **TAP**（`ok N - name`），`reconcile.mjs` 两种格式都解析，按**测试名集合**比对：

```
baseline (S10, spec reporter) = 156 names
current  (S11, TAP reporter)  = 171 names
added = 15   removed = 0
```

新增 15 名**全部**是 `TC-CCF-001 …`，移除 **0** 名。证据：`final/regression-reconcile.txt`、`final/regression-directory.tap`。

> 第一轮对账脚本只解析 TAP，把 spec 格式的基线读成 0 名，得出「added=171」的假结论。已发现并修正为双格式解析，**未采信那次输出**。

## 9. 安全边界 — 凭据不泄漏的逐条证明

| 边界 | 实现手段 | 证明 |
|---|---|---|
| 凭据不进 URL | URL 只由 `TOOLS_REPO` 与 `parsePin` 后的 revision 拼成 | 用例 7 URL 全等；用例 8 断言 URL 不含 token；**M09 DETECTED** |
| 凭据只在 fetch 调用内使用 | 只出现在 `init.headers.Authorization` | 用例 7 逐项相等；**M08 DETECTED** |
| 返回值不携带请求上下文 | `verdict()` 只产 `outcome/message/exitCode` | 用例 8 断言无 `headers`/`init`/`request`/`token` 键 + `JSON.stringify` 不含 token；**M15 DETECTED** |
| 错误信息不回显凭据 | catch **不绑定** error、不回显 `error.message` | 用例 9 注入内嵌凭据的 leaky Error；**M10 DETECTED** |
| 空凭据不出门 | missing 短路在 `parsePin` 与 fetch 之前 | 用例 1 断言 `calls.length === 0`；**M01/M02 DETECTED** |
| 坏 pin 不携带凭据出门 | `parsePin` 在 fetch 之前 throw | 用例 10 断言 5 种坏 pin 均 `calls.length === 0`；**M11 DETECTED** |
| CLI 全部分支不泄漏 | 5 个状态 + 坏 pin + 不可读 pin + 4 种坏 argv + 真实子进程，逐处断言输出不含 token | 用例 8/10/11/12/13/14 |
| 报文不泄漏环境变量名以外的东西 | 报文只含 `TOKEN_ENV` **名**、repo、pin、状态码 | 用例 1/13 要求点名 `TOKEN_ENV`；用例 8 要求不含 token **值** |

**本切片使用的 token 是自造 fixture** `github_pat_FIXTURE_0123456789abcdefABCDEF`，刻意取独特形状以便泄漏在输出 diff 里一眼可见。**未读取、未打印任何真实凭据**。

## 10. 运行边界

- **未运行任何数据库**：本切片全部用注入 fetch，不新建 podman 实例、不连 localhost:5432、不操作 `multica-postgres`/`multica-backend`、未触碰卷 `multica-pgdata`、未放宽 nonce 门禁。
- **未发出任何真实网络请求**：`checkToolsAccess` 的每次调用都注入 `fetchImpl`；两个**真实子进程**用例分别在「凭据为空」（missing 短路）与「pin 文件不可读」（`readPinFile` throw）处终止，都到不了 fetch。
- 容器清单运行前后**完全相同**：

```
multica-postgres Exited (0) 292 years ago
multica-backend  Exited (0) 292 years ago
```

- multica HEAD = origin/main = `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`；`git status --short` 只含本 change 的文件（**17 modified + 27 untracked**，其中本切片新增 2 个）。
- tools 仓本切片**未触碰**（pin 仍是 `e52b8081f159`，其既有未提交改动未清理未混入）。
- 记录仓他人未提交改动**未清理、未混入**。
- **未提交、未推送、未部署**。

## 11. 编码与静态检查

| 检查 | 结果 |
|---|---|
| `node --check tools-access.mjs` | exit 0 |
| `node --check tools-access.test.mjs` | exit 0 |
| 行尾 | 两个文件均 **crlf=0 / bareLf=109、274**（纯 LF，与 `tools-pin.mjs` 一致；`.gitattributes` 对 `.mjs` 无强制） |
| 注释语言 | 英文，`// AIFIRST:` 头带真实 STDD change ID 与 Slice/SC 编号 |
| 归属 | 两个文件均 **fork 独有**（`scripts/aifi45-disposable/*`，M30 已登记），非上游挂钩点 |
| `CUSTOM.md` | 全 CRLF（crlf=1095 / bareLf=0），#328 为 **7 竖线**，汇总行 6 竖线，#327 字符数 4987 与改前一致 |

## 12. 记账

- `CUSTOM.md`：M31 头 `11 行：#317–#327` → **`12 行：#317–#328`**；汇总行 `#317–#327 | 11` → **`#317–#328 | 12`** 并在文件清单追加 `{tools-access,tools-access.test}.mjs`；新增明细行 **#328**（3304 字符）。**#317–#327 未改**。
- `tasks.md`：11.1 / 11.2 勾选并补实测，新增 **11.3**（变异、回归、边界、记账、B3.4、不得报通过）。
- `phase-context.md`：新增 Slice 11 记录。
- `.stdd.yaml`：`slices_completed['11'] = {status: done, tc_coverage: 1/1, new_tests: 15, verified_at: 2026-11-13T00:48:42}`。
- `pending-adjustments.yaml`：**本切片无新增偏离**。ADJ-005（major，未决）、ADJ-018（四数基线表台账欠债，未决）沿用，未自行裁定。
- **四数基线表本切片未重算**（与 #317–#327 一致）：两个新文件未跟踪，`git grep` 口径本就不计入；ADJ-018 待用户裁定，合并窗口前须重算补行。

## 13. B3.4 切片验证（三项）

| 检查 | 结果 |
|---|---|
| **TC 覆盖** | **1/1** — TC-CCF-001 有 15 个对应测试函数，SC-CCF-001 的 7 类输入与 3 条 SHALL 逐条有用例 |
| **产出物核对** | 通过 — slices.md 第 11 行要求「`tools-access.mjs`（可注入 fetch，永不输出 token）」，两个文件均存在、fetch 可注入，「永不输出 token」由 §9 的 8 条边界逐条证明（对应变异 M01/M02/M08/M09/M10/M11/M15 全部 DETECTED） |
| **测试运行** | 通过 — 新增 **15 > 0** 且**全部通过**；整包回归 171/0/0，逐名对账新增 15 移除 0 |

**无声明偏离**（与 S10 不同：S10 的「新增测试全部通过」因用户裁定保留红灯而不成立，本切片该条件真实成立）。

## 14. 未验证 / 未完成（不得报通过）

- **`ci.yml` 一行未改**：新诊断**尚未被任何 CI 步骤消费**。`transitions-contract-check` 仍在跑旧的「token 非空」单检查（`ci.yml:105`）。替换属 S13。
- **从未对真实 GitHub API 发过请求**：5 个结论的真实报文、真实凭据的行为、真实网络异常路径**均属未验证**。不得据此声称 transitions job 已修好。
- **SC-CCF-003 未闭合**：管理员按最小权限更新 `AIFIRST_TOOLS_READ_TOKEN` 属外部依赖，本 change 不读取/创建/轮换凭据；未重跑真实 `transitions-contract-check`。
- **TC-CBE-005**（ubuntu-latest 真实 CI run）须推送，另行授权，未执行。
- **SC-CCF-002 / TC-CCF-002**（views typecheck）属 S12，未执行。
- `make test` 未执行（U5 排除）。
- **ADJ-005（major）仍未决**：tools `rules.json` 未授予 `git show` 的 `test-report.md`/`trace.tests*`/`--name-only --format=` 形状；S13 设置 `MULTICA_CONTROLLED_SHELL_RULES` 前须用户裁定。
- **ADJ-018 未决**：四数基线表最后一行仍是 2026-11-10（#312），合并窗口前须重算补行。
- `TestChannelIsolation*` 未在 WSL AIFI-ISO 实跑（TC-TOR-004）。
- **Gate 3 未推进**，须另经用户明确确认。

## 15. 证据清单

```
validation/s11-tools-access/
├── README.md                        本文件
├── mutate.mjs                       变异驱动（证据工具）
├── reconcile.mjs                    双格式逐名对账（证据工具）
├── red/
│   ├── red.tap                      首次 RED（导入级，测试字节为修正前）
│   └── red-final-testbytes.tap      最终测试字节的 RED（模块临时移开后重跑，已移回并核对 sha256）
├── green/
│   ├── green.tap                    GREEN 15/15/0
│   └── shipped-sha256.txt           两个文件的 pristine digest
├── mutation/
│   ├── summary.json                 16 条汇总（含 pristine digest）
│   └── M01-missing-short-circuit/ … M16-main-module-guard/
│                                    各含 patch.txt / red.tap / restored-sha256.txt
└── final/
    ├── tools-access.tap             按最终字节复跑 CP-CCF-001（exit 0）
    ├── regression-directory.tap     目录全量 171/0/0
    └── regression-reconcile.txt     逐名对账：added 15 / removed 0
```