# C3 逐文件 Diff 审查记录

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 执行日期：2026-11-13
- 业务仓：`C:\Users\GOBAO\Downloads\AI\multica`，HEAD=`903a46c5ae9fa6c3ee644fa4740d189d739dcc91`，分支 `main`
- 审查范围：本 change 全部 **49 个文件（22 个修改 + 27 个新增）**，无抽样
- 结论：**内容审查完成 49/49**；新增 1 条待裁定发现 ADJ-042；无调试残留、无死代码、无注释掉的旧逻辑

---

## 1. 方法

- 修改文件：逐个 `git diff -- <path>` 读完整 hunk，不以 `--stat` 摘要代替逐行审查。
- 新增文件：全文读取（27 个，行数指纹见 §5）。
- 残留扫描：对 49 个文件扫 `console.log(` / `debugger` / `TODO` / `FIXME` / `XXX` / `fmt.Println` / 注释掉的旧逻辑。
- fork 规则核对：新逻辑落新文件，上游文件只留最小 `// AIFIRST:` 挂钩，代码注释英文，CUSTOM.md 用真实 STDD change ID 登记。
- **未跑 `gofmt -w`**：本机 gofmt 标记 65 个文件（含本 change 未触碰的），属仓库既有状态，不在本 change 内批量改写。
- `core.autocrlf=true`，numstat 比对在 git 规范化口径下进行。

---

## 2. 22 个修改文件逐项结论

| 文件 | 增/删 | 结论 |
|---|---|---|
| `.github/ci-paths.json` | 2/0 | `scripts/aifi45-disposable/**` 映射到 scripts + backend scope，SC-SEL-004 落地 |
| `.github/workflows/ci.yml` | 113/12 | 凭据诊断 fail-closed；单一 pin 读取 + 完整性校验；checkout `ref` 由 pin 驱动（替换字面量 `9e41ad74ce63`）；移除 `DATABASE_URL` 改 `AIFI45_CI_ADMIN_URL`；Node 22 + 按 `package.json` 声明版本装 pg；provision up / drop `always()`；skip-regex 由归属表生成；script-checks 增 `node --test`。接线已实测核对，非假定 |
| `CUSTOM.md` | 24/1 | M31 里程碑行 + change-index 行 + 替换 M13 #87 行（原登记 10 张 fork 表为 `delete`）+ M31 明细 16 行 #317–#332。列数与表头一致；5 行多余竖线经实测全部为已转义 `\|`，realCols 恒为 6 |
| `packages/core/package.json` | 1/0 | 新增 subpath export `./platform/storage`，是 C9 把相对导入改回包导入的必要解析入口 |
| `packages/views/auth/use-logout.test.ts` | 7/5 | 相对导入改回包导入 |
| `scripts/aifi45-disposable/run-selection.mjs` | 27/11 | 接 `decideSelection`/`selectionLine`；新增 `--evidence-dir`；显式拒绝 `--admin-url`。**发现 ADJ-042（parseArgs fail-open）** |
| `scripts/aifi45-disposable/run-selection.test.mjs` | 84/1 | 既有断言全部保留、未削弱；新增 `--evidence-dir` 缺值与后接 flag 的拒绝断言 |
| `scripts/aifi45-disposable/selections.identity.json` | 10/0 | 新增条目 |
| `scripts/aifi45-disposable/selections.json` | 45/0 | 新增条目；当前全部条目未设 `expected`，与 SC-SEL-002 的 given「当前全部条目」一致 |
| `scripts/ci-scope.test.mjs` | 111/1 | scope 命中断言 |
| `scripts/test-go.sh` | 51/2 | `--skip-regex`/`--json-out` 均拒绝 `''\|--*` 并 exit 2；`: >"$json_out"` 只截断一次，两半追加同一流。**观察：`set -o pipefail` 在函数内设置会全局生效**，此处后续无管道，无实际影响，不构成缺陷 |
| `scripts/test-go.test.sh` | 84/0 | 假 go 增 `MULTICA_TEST_GO_TEST_OUTPUT/STATUS` 驱动；4 正向断言（skip-regex 逐字透传、json-out 保留流且同时打印、退出码 3 不被吞、两半共 2 行）+ 4 用法失败断言。新增 `exit` 默认 0，与先前隐式退出等价，无回归 |
| `server/internal/governance/approval_crosscheck_test.go` | 9/19 | 删 `CRCTL_PATH` 别名与开发机相对路径回退，`t.Skip`→`t.Fatal/t.Fatalf`，属收紧 |
| `…/execution_authorization_revoke_interop_test.go` | 1/1 | 同类收紧 |
| `…/execution_authorization_test.go` | 1/1 | 同类收紧 |
| `…/execution_binding_issue_test.go` | 1/1 | 同类收紧 |
| `…/execution_contract_selection_test.go` | 10/0 | 新增断言 |
| `…/execution_control_reservation.go` | 15/0 | 新增 `ErrReservationWorkspaceGone` + 一处非锁定 `SELECT EXISTS` workspace 存在性检查。注释已明确申报「只关闭顺序拆除场景，并发未提交的 DeleteWorkspace 仍可能绕过，SC-WSD-005 不要求」，与规格范围一致，无缺陷 |
| `…/execution_migration_roundtrip_test.go` | 7/3 | 往返断言调整 |
| `…/execution_trust_install_test.go` | 1/1 | 同类收紧 |
| `server/internal/handler/workspace.go` | 11/0 | 新增 `delete execution control routing` 阶段，置于 rollup lock **之前**，4246 争用时随事务一起回滚，不留 stranded 行 |
| `server/internal/handler/workspace_delete_manifest_test.go` | 38/10 | 19 张 `cr_execution_*` 表分类：**11 retain / 6 keep / 2 delete**；新增 `workspaceDeleteRetain` 动作。10 处删除为同一 map 内 gofmt 对齐，非语义变更 |

---

## 3. 27 个新增文件

按切片归属，全部全文读取，无占位实现、无空壳测试：

- **S1 selection 对账决策**：`selection-decision.mjs`(36)、`selection-decision.test.mjs`(171)、`selection-evidence.mjs`(14)、`selection-evidence.test.mjs`(41)
- **S2 单一 tools pin**：`tools-pin.mjs`(76)、`tools-pin.test.mjs`(182)、`.github/aifirst-tools-pin`(0 行 / 40 字节)
- **S3 去开发机路径与 skip→Fatal**：`go-test-env-contract.mjs`(105)、`go-test-env-contract.test.mjs`(142)
- **S4 整包基线与归属表**：`test-ownership.json`(67)、`test-ownership.mjs`(145)、`test-ownership.test.mjs`(293)、`selections.baseline.json`(8)
- **S5 CI 证据对账**：`ci-evidence.mjs`(204)、`ci-evidence.test.mjs`(354)
- **S6 ci-provision**：`ci-provision.mjs`(167)、`ci-provision.test.mjs`(375)
- **S7 nonce 门禁逐条件**：`server/cmd/server/disposable_identity_conditions_test.go`(214)、`server/internal/governance/disposable_identity_conditions_test.go`(214)
- **S9/S10 workspace 删除**：`server/internal/governance/workspace_delete_execution.go`(32)、`server/internal/handler/workspace_delete_execution_test.go`(492)、`workspace_delete_no_recreate_test.go`(244)、`workspace_delete_retention_test.go`(183)
- **ADJ-014 迁移守卫**：`server/migrations/649_cr_execution_truncate_guard.up.sql`(16)、`.down.sql`(6)

---

## 4. 发现与处置

### 4.1 新发现：ADJ-042（已记入 pending-adjustments.yaml，待裁定）

`run-selection.mjs:28-46` 的 `parseArgs` if/else-if 链**没有最终 else**，未知参数被静默丢弃。本 change 新增的 `--evidence-dir` 放大后果：flag 名拼错时 `options.evidenceDir` 保持 `null`，`:176` 的 `if (options.evidenceDir !== null)` 不成立 → **证据完全不写，而 selection 仍输出 PASS**。这与本 change「测试证据可信性」目标相反。

影响面已实测收敛：`ci.yml` 不含 `run-selection`/`--evidence-dir` 调用，`test-ownership.json` 独立入口只传 `--selections/--only`，故 **CI 路径不受影响**，风险限于人工运行拼错 flag。定级 minor，本轮未修（修法为补最终 else 抛错 + 一条断言，属行为收紧，需裁定是否纳入本 change）。

### 4.2 不重复记录的既有发现

**对账门禁曾是死代码**：`selection.mjs` 在 HEAD 未修改，返回 `{status, reason}`，故旧写法读 `.matched` 恒为 `undefined`，`undefined !== false` 恒真 → 门禁永不生效。该发现已由 `validation/s1-selection-decision/README.md` 记录并附变异证据（改回旧写法 exit 1、12 项中 10 项变红），**不另立 ADJ**。

### 4.3 两条已撤回的误报（保留以免后人重犯）

1. **「expected 无任何真实消费者」**：撤回。`canonical/specs/code/selection-reconciliation.yaml` SC-SEL-002 的 given 明写「当前全部条目」未设 expected，属规格预期状态，不是缺陷。
2. **「CUSTOM.md 存在未转义竖线导致列数错位」**：撤回。首轮测量因 bash 双引号吃掉反斜杠正则而得出「1582 字符行含 1583 个转义竖线」的物理不可能结果，已判该测量无效并重测；用 `String.fromCharCode(92)` 构造正则后，5 行的多余竖线数与已转义 `\|` 数**逐一精确相等**，realCols 恒为 6。

### 4.4 观察项（不构成缺陷，不立 ADJ）

- `test-go.sh` 的 `set -o pipefail` 写在函数内会全局生效（shell 选项非函数作用域）；该脚本后续无管道，无实际影响。
- 测试夹具中的 `devPath` 属 fixture 常量，非开发机路径回退。

---

## 5. 事故与恢复：审查中途业务仓被外部清理删除

**事实**：C3 进行期间，`C:\Users\GOBAO\Downloads\AI\multica` 被一次外部 C 盘清理操作删除。发现时 `git diff` 报 "Not a git repository"，只读核查确认工作区仅剩 163 个业务文件、`.git` 只剩 `lfs`/`logs`、本 change 49 个文件 0/49。当时**立即停止**，未修复、未 `git init`、未 clone 覆盖、未删任何文件、未杀进程，并向用户报告。

**用户报告的「已还原」经实测不成立**：11:12:01 仍为 163 文件、0/49，关键文件与目录缺失。已如实报告差异，未采信口头结论、未继续推进 change。

**恢复来源**：`D:\C_Cleanup_Backup_20261113\D04\v11\projects\94bfd4d8820769039cac137309ab95c0\`。`manifest.csv` 第 9 行显示 D04 = `MOVE_DIR` of `C:\Users\GOBAO\AppData\Local\pnpm\store`；multica 从未列入清理清单，它是 pnpm store 的 `v11/projects/<hash>` 镜像被 robocopy 展开为真实副本时顺带保留下来的。

**另一会话的结论有两处被实测推翻**：①「本机没有任何可用的源」——D04 存有完整副本；②「transcript 不在本机 / 精确 25,455,213 字节的文件全盘无匹配」——该文件实测存在于 `C:\Users\GOBAO\.qoder\projects\c--Users-GOBAO-Downloads-AI-AI-First-Platform\f7c9cec4-7545-4dbc-81c1-cced02856554.jsonl`，字节数精确相符。

**用户裁定的恢复方案**：「先护副本，再原地恢复」。执行与核验：

| 步骤 | 动作 | 结果 |
|---|---|---|
| 1 | 只读复制 D04 镜像 → `D:\multica-rescue-20261113`（排除 node_modules） | robocopy 8717 文件 / 1022.57 MB，**失败 0**，exit 1 |
| 2 | 护副本指纹核验 | HEAD 一致、numstat 22/22、行数 27/27、pin 40 字节、status = 27`??`+163`D`+22`M` |
| 3 | 破损 `.git` 移入 `D:\multica-residual-20261113\git-broken` | 可逆移动，lfs/logs 齐全，**未删除** |
| 4 | 163 个残留业务文件与 node_modules **原地不动** | 残留 163、node_modules 201 条目 |
| 5 | 护副本 → `C:\Users\GOBAO\Downloads\AI\multica`（`/E`，无 `/PURGE`） | robocopy 8717 文件，**失败 0**，exit 3（复制 + 目标有额外文件，即刻意保留的残留） |
| 6 | 恢复后全量指纹核验 | 见下表 |

**恢复后核验（全部通过）**：

| 核验项 | 期望（删除前实测） | 恢复后实测 |
|---|---|---|
| HEAD | 903a46c5ae9f… | `903a46c5ae9fa6c3ee644fa4740d189d739dcc91` |
| 分支 | main | main |
| 22 个修改文件 numstat | 逐行增删数 | **22/22 精确一致** |
| 27 个新增文件行数 | 逐文件 wc -l | **27/27 精确一致** |
| `.github/aifirst-tools-pin` | 40 字节 / e52b8081f159… | 40 字节 / `e52b8081f159d581bf62f82447c76f818fc52426` |
| HEAD 树已跟踪文件 | 7336 | 7336 |
| `ls-files --deleted` | 0 | **0** |
| `status --porcelain` | 27`??` + 22`M` | **27`??` + 22`M`，无其他** |
| node_modules | 保留 | 201 条目未动 |

163 个残留文件被 git 判为未修改，证明其与 HEAD 一致，无需再从对象还原；护副本中缺失的这 163 个文件此前已用 `cat-file --batch-check` 逐个确认对象存在（**163/163，missing=0，类型全为 blob**），故两条路径都可还原。

**对审查有效性的影响**：删除前已完成约 20/22 个修改文件与全部 27 个新增文件的审查及残留扫描。剩余 2 个（`execution_control_reservation.go`、`test-go.test.sh`）在恢复后补审，其中 diff 读取自已通过指纹核验的护副本，内容与删除前状态由 numstat 逐行证明一致。**49/49 审查结论均基于与删除前逐字节一致的内容。**

**遗留风险（已上报用户）**：`RESTORE.md` 第七节选项 C 建议把 D01/D02/D03/D04 当「纯缓存」删除以释放约 22 GB，而 D04 正是唯一存活副本所在。恢复稳定确认前不得按该条清理。当前副本共三份：D04 原备份（全程未写入）、`D:\multica-rescue-20261113`、C 盘工作区。

**边界守住**：全程未读取或打印任何凭据；未连接 localhost:5432 旧库、未操作旧 multica-postgres 容器；未提交、未推送、未部署；对 stdd 仓写入次数 **0**；记录仓他人未提交改动未清理、未混入；**Gate 3 未推进**。

---

## 6. C3 结论

- 49/49 文件逐一审完，变更与 canonical 规格一致，无超范围改动。
- 无调试残留、无死代码、无注释掉的旧逻辑（扫描命中项均为合法内容：CUSTOM.md 历史叙述中的 "TODO"、规格要求逐字不变的 `console.log` PASS/FAIL 输出、mktemp 的 `XXXXXX` 模板）。
- 1 条新发现 **ADJ-042** 已如实记录，`resolved: false`，待用户裁定，未自行修改代码。
- 2 条误报已撤回并留痕，1 条既有死代码发现不重复立项。
- 业务仓遭外部删除后已按用户授权恢复，并以删除前实测指纹逐项证明内容一致；事故与恢复过程完整留痕于本文件 §5。