# C2 阻塞记录 — 范围取证、stdd 问题总结与实测结果

> change：`2026-11-12-fork-ci-test-evidence-trust`｜记录时间：2026-11-13T07:30+08:00（本地 UTC+8）｜Windows
> 本文件只记录事实与待裁定项。**未执行、跳过或外部依赖未满足的检查一律不报通过。**
> 用户指令：stdd 仓不在本次修改范围内，**不要再动 stdd 仓的内容**。本文件不提议对 stdd 的任何写操作。

## 1. 本次任务的修改范围（三根归属）

| 根 | 路径 | 本次是否可写 |
|---|---|---|
| PROJECT_ROOT（业务仓） | `C:/Users/GOBAO/Downloads/AI/multica` | **可写**：本 change 的代码与测试，按其 `CUSTOM.md` 登记 |
| DATA_ROOT（记录仓） | `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica` | **可写**：仅本 change 目录内的记录；他人未提交改动不清理不混入 |
| RESOURCE_ROOT（方法论包） | `C:/Users/GOBAO/Downloads/AI/stdd` | **只读**，不在本次修改范围 |
| sibling tools 仓 | `C:/Users/GOBAO/Downloads/AI/tools` | **只读**（pin `e52b8081f159`，其 6 处既有未提交改动未触碰） |

## 2. 「我改了 stdd 仓哪些内容」——实测答案：**0 处**

本会话对 stdd 仓的全部操作都是**只读**：`Read`（`agent.py`、`evidence.py`、`ci.py`、`.stdd/skills/spec.md`、
`.stdd/version.yaml`）、`Grep`/`grep`、以及 `git rev-parse` / `git status` / `git log` / `git diff` / `git show` 只读查询。
**没有任何 `Edit`、`Write`、格式化、`git add/commit/checkout/restore/stash` 或安装/升级动作指向 stdd 路径。**

取证（全部只读命令，可复核）：

| 判据 | 命令 | 实测结果 |
|---|---|---|
| 未提交改动是否引用本 change | `git diff \| grep -c "2026-11-12-fork-ci-test-evidence-trust"` | **0**（88 个改动文件无一处引用本 change） |
| 未提交改动规模 | `git status --short \| wc -l`；`git diff --stat \| tail -3` | **117 项**；**88 files changed, 3647 insertions(+), 856 deletions(-)** |
| 缺陷是否 HEAD 就有 | `git show HEAD:stdd/cli/commands/agent.py \| grep -n 'planned_here = '` | **:197 同样是 `item["cp"]`** → 上游既有缺陷，非未提交改动引入，更非本轮引入 |
| 07:00 后仍在被写入的文件 | `find . -newermt "2026-11-13 07:00:00" -type f -not -path "./.git/*"` | 只有 `.pytest_cache/v/cache/nodeids` 与 `changes/projects/stdd/changes/**2026-11-12-stdd-lifecycle-quality**/validation/runs/LQ-FINAL-1/artifacts/coverage/.coverage.*` |

**结论**：stdd 仓那 117 项未提交改动是**用户自己的方法论在途工作**，与本 change 无关；07:00 后仍在写入的产物属
**另一个 change `2026-11-12-stdd-lifecycle-quality` 的 pytest coverage 运行**（说明该仓当时有活动进程）。
我未干涉、未清理、未混入、未提交。**本轮之后也不再对 stdd 做任何写操作。**

## 3. stdd 问题总结（按要求发用户；只描述，不修）

### P1 — 阻塞级：`agent verify` 对含 manual check 的证据计划必崩

- **位置**：`stdd/cli/commands/agent.py:206`（HEAD 版本为 `:197`）
  ```python
  planned_here = [item for item in planned if item["cp"] == step["id"]]
  ```
- **根因**：`planned = plan["checks"]`（`:173`）**无条件取全量** 22 条 check。锁定证据计划里 4 条 manual
  （TC-CBE-005 / TC-TOR-004 / TC-TOR-005 / TC-CCF-003）按其自身契约「manual 不绑定 CP」**没有 `cp` 键**，
  而 `item["cp"]` 出现在**过滤条件**里，对每条 item 都求值 → `KeyError: 'cp'`。
- **影响**：崩溃发生在**第一个 CP 动作执行之前**，18 个 command CP **一个都没跑**；`ci check-failures` 如实报
  **TC 当前执行覆盖 0/22**、`当前运行未完成`。**不是业务测试红**。
- **`--cp` 绕不开**：`--cp` 只过滤 `steps`（`:118`）与 `all_required`（`:171`），**不过滤 `planned`**。
- **对照证据（说明这是漏改一处，不是设计如此）**：`stdd/cli/evidence.py:596` 同样写 `item["cp"]`，但它在
  **输出表达式**位置且 comprehension 先按 `item["kind"] == "pytest"` 过滤，manual 项被提前排除，故 `start_run` 不崩
  （实测 run 目录与 `tc-evidence.json` 正常生成）。
- **最小修法（供 stdd 维护者参考，本轮不执行）**：`item.get("cp")`。
- **崩溃残留**：`validation/runs/97da35cc-fdac-4d9d-bbaa-60960538d76e/` 只有 `inputs/`（5 份 agent spec + `config.yaml` +
  `test-plan.md` 快照）与 `tc-evidence.json`，**无 `agent-verification-report.md`**。
- **值得肯定的一点**：崩溃后 `check-failures` **没有误报绿**，fail-closed 有效。

### P2 — 门禁前移缺失：Gate 2 批准路径不执行 (l) 锚定等级检查

- `.stdd/skills/spec.md:126-134` 明文：`financial=true → 至少 L4`；`level < 最低需求 → **Gate 2 阻塞**`。
- 但 (l) 的实现只在 `stdd/cli/commands/ci.py:1186-1222`（`check_anchoring_missing`），由 `ci check-failures` 消费；
  **Gate 2 批准路径未执行该项**。
- **后果（本 change 实测）**：canonical proposal 声明 `financial: true`（注释「私有库 Actions 额度」）→ 要求 L4，
  实际 `anchoring.level: L3` 且 `anchor_implementations: []`，**Gate 2 仍三次批准通过**（当前批准 `phases.spec`
  2026-11-12T23:54:09）。该缺口**在 Gate 2 时就存在，不是 BUILD 引入**。
- 建议（供维护者参考）：把 (l) 前移到 Gate 2 批准前置校验，否则同类缺口只能在 C2 才暴露。

### P3 — (b) 范围蔓延警告的口径待定性（不预判为真蔓延）

- `check-failures` 报 `⚠ (b) 范围蔓延: 37 个文件可能超出声明范围 (CUSTOM.md, packages/core/package.json,
  packages/views/auth/use-logout.test.ts...)`。
- 这三个文件都是本 change 的**必要改动**：`CUSTOM.md` 是 multica 强制的定制登记台账；后两个是 S12 恢复 views
  typecheck（SC-CCF-002）的唯一改动面。它们**不在锁定证据计划的 `inputs` 列表里**（`inputs` 只列了
  `packages/views/auth`，未列 `packages/core/package.json`，也未列仓库根 `CUSTOM.md`）。
- 因此这更像 **`inputs` 声明口径与实际必要改动面不一致**，而非真实范围蔓延。**留待 C4 逐项定性**，
  不在此处下结论，也不据此擅自改锁定 `inputs`。

## 4. 阻塞 B 的修订归属：**记录仓**，不是 multica、也不是 stdd

| 项 | 文件 | 所属仓 |
|---|---|---|
| `anchoring.level` / `anchor_implementations` / `critical.risk_assessment` | `projects/multica/changes/2026-11-12-fork-ci-test-evidence-trust/canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml`（`:140-152`） | **AI First Platform（记录仓）** |
| 4 条 manual check 的 `cp` 键（阻塞 A 的可选修法） | 同 change 目录 `test-plan.md`（锁定证据计划 `:390-691`） | **AI First Platform（记录仓）** |

两者**都是 Gate 2 `input_manifest` 的锁定输入**，任何改动都须按 revision 流程 `--reapprove` 重签，
不能静默修改后冒称原设计成立。L4 = **基准锚定**（`.stdd/templates/proposal.md:80`：L1 行为 / L2 接口 / L3 模式 / L4 基准；
`:82`：`anchor_implementations` 为「L4 时附参考代码路径」），**不是只改一个标签**，须附真实存在的参考实现路径。

## 5. C2 实测结果（逐项命令 + 退出码，不含推断）

| 检查 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| node harness 全量 | `node --test "scripts/aifi45-disposable/*.test.mjs"` | **tests 172 / pass 172 / fail 0** | **0** |
| ci-scope | `node --test --test-reporter=tap scripts/ci-scope.test.mjs` | **tests 49 / pass 49 / fail 0 / skipped 0** | **0** |
| `quality.lint` | `pnpm lint` | **7 successful, 7 total**，48.35s | **0** |
| `quality.typecheck`（全量） | `pnpm typecheck` | **Failed: `@multica/web#mdx`**；`Tasks: 0 successful, 5 total` | **1** |
| views typecheck（过滤口径） | `pnpm --filter @multica/views typecheck` | **0 条 `error TS`** | **0** |
| core typecheck（过滤口径） | `pnpm --filter @multica/core typecheck` | **0 条 `error TS`** | **0** |
| 同次执行证据 | `stdd agent verify ci-backend-environment --change … --run 97da35cc-…` | **KeyError: 'cp' 崩溃，18 个 command CP 全未执行** | **1** |
| 同 run id 对账 | `stdd ci check-failures … --run 97da35cc-…` | 通过 7 / 警告 1 / 跳过 0 / **错误 2**（TC 覆盖 **0/22**；(l) **L3 < L4**） | **1** |
| `quality.test` | `make test` | **未执行** | — |
| `quality.e2e` | `bash scripts/check.sh` | **未执行** | — |

### 5.1 `pnpm typecheck` 失败的定性（环境安装问题，非本 change 回归）

- 报错来自 `node_modules/.pnpm/esbuild@0.25.12/.../lib/main.js:1739`：
  `You installed esbuild for another platform than the one you're currently using.`，
  报文自身矛盾（「`@esbuild/win32-x64` 已存在，但本平台需要 `@esbuild/win32-x64`」），是**原生二进制安装/拷贝损坏**的典型表现
  （常见于 Windows 与 WSL 之间拷贝 `node_modules`）。
- 触发链是 `@multica/web:mdx` → `fumadocs-mdx` → esbuild，**在任何 TS 编译之前抛错**，因此**不可能由源码改动引起**。
- **`apps/` 下本 change 改动文件数 = 0**（`git status --short | grep -c "apps/"` 实测 0）；本 change 的前端改动只有
  `packages/core/package.json`（+1 行 exports）与 `packages/views/auth/use-logout.test.ts`（导入改写）。
- turbo 因该失败**中止整轮**（`0 successful, 5 total`），故全量口径**没有给出 views/core 的结果**；
  已用过滤口径补跑，两者 **exit 0、0 条 error TS**。**不以过滤口径冒充全量通过**：全量 `pnpm typecheck` 如实记 **exit 1**。
- **未修**：重装依赖（`pnpm install` / 删 `node_modules`）属超范围动作，且可能影响用户其他在途工作，**待裁定**。

### 5.2 未执行项的原因（不得报通过）

- **`make test` 未执行**：U5 明确排除。它经 `REQUIRE_ENV` → `scripts/ensure-postgres.sh` 连 **localhost:5432 旧库**
  并可能操作旧 `multica-postgres` 容器，违反「不连接旧库、不操作旧容器」硬边界。
  **替代口径**：受影响 Go 包经 runner 自建一次性 podman 实例执行（S4/S9/S10/S13 已逐名对账；本轮因 P1 未能经 verify 重跑）。
- **`bash scripts/check.sh`（e2e）未执行**：需 `.env` 且会拉起 backend/web，同样落到旧库与在跑服务，超出 U5 授权。
- **覆盖率**：锁定计划声明 `coverage.applicability = not_applicable`，理由「被测对象为 Go、Node、CI 配置与前端类型检查，
  覆盖率采集目前只支持 pytest-cov；项目配置 `quality.coverage.enabled=false`」。`check-failures` 的 (j) 项**已确认该豁免**
  （`✓ (j) 已声明无覆盖义务`）。**这是豁免，不是测量通过**。

### 5.3 容器与凭据边界（本轮）

- verify 崩溃前后 `podman ps -a` **同一清单**：只有 `multica-postgres`、`multica-backend` 两个既有 **Exited** 旧容器；
  `podman volume ls` 只有 `multica-pgdata`。**本轮零实例创建**（崩溃在任何 CP 动作之前）。
- 未连 localhost:5432、未操作旧容器、未触碰卷、未放宽 nonce 门禁（`ci-provision.mjs`/`provision.mjs` 一行未改）。
- 未读取、打印、创建或轮换任何凭据，未改仓库 secret。
- multica `HEAD = origin/main = 903a46c5ae9f`；`git status --short` = **22 modified + 27 untracked**，全属本 change。
- tools 仓与记录仓他人未提交改动未清理未混入；**stdd 仓 0 处改动**（见 §2）。**未提交、未推送、未部署。**

## 6. 待用户裁定（两项，均不在我可自行处置的范围）

- **阻塞 A**（P1 导致 18 个 command CP 未执行、覆盖 0/22）：修法一是改 stdd CLI —— **用户已明确排除，不再提议**。
  剩余路径：① 在**记录仓** `test-plan.md` 给 4 条 manual check 补 `"cp": null`（语义忠实于「manual 不绑定 CP」），
  按 revision 流程 `--reapprove` 重签 Gate 2；② 保持阻塞，C2 同次执行证据记为**未闭合**，
  在 `test-report.md` 与 Gate 3 如实呈报 0/22 与崩溃原文。
- **阻塞 B**（(l) L3 < L4）：① 在**记录仓** canonical proposal 补**真实 L4 基准锚定**（`anchor_implementations` 填
  经核实存在的参考代码路径）并升 `level: L4`，`--reapprove`；② 复核 `financial: true`（「私有库 Actions 额度」）
  分类是否正确 —— **这等于降低门禁要求，不为过检而建议**，仅在用户确认分类确实错误时据实修正并重签；
  ③ 保持 L3，(l) 如实记 **FAIL** 并由用户在 Gate 3 决定是否接受带缺口推进。

**在两项裁定落地前，不推进 Gate 3，不声称 C2 通过。**

---

## 7. 第二轮更新（2026-11-13，裁定已落地；§1–6 原文保留作历史记录）

### 7.1 三项裁定的执行结果

| 裁定 | 用户原文 | 执行结果 |
|---|---|---|
| 阻塞 A | 「我已经直接修改了stdd，将item["cp"]修为了item.get("cp")」 | 由**用户自己**在 stdd 侧修复。本会话只读核实 `agent.py:206` 现为 `item.get("cp")`；**本会话对 stdd 写入数 = 0**。原拟的记录仓补 `cp: null` 方案不再需要，`test-plan.md` 未被改动 |
| 阻塞 B | 「补真实 L4 基准锚定并重签（推荐）」 | 记录仓 canonical proposal `level: L3→L4`，`anchor_implementations` 填入 **11 条逐条核实为 multica tracked 文件**的基准路径；`financial: true` 等风险分类逐字未改 |
| typecheck | 「授权修 esbuild 二进制后重跑」 | 已修复并全量重跑通过，见 7.3 |

追加裁定（Gate 1 连锁 stale）：「同一裁定覆盖两道，依次重签（推荐）」→ `gate 1 --reapprove` exit 0、`gate 2 --reapprove` exit 0，旧批准回执保留。`gate status` 复核：Gate 1 confirmed **2026-11-13T09:46:15**、Gate 2 confirmed **2026-11-13T09:46:16**，均不再 stale，**Gate 3 仍 pending 未推进**。

首次 `gate 2 --reapprove` 曾被 CLI 拒绝（exit 1、未写入），原文「Gate 1 审批输入已 stale；保留原批准，拒绝新动作，不自动重签」。原因：锚定等级写在 canonical proposal 内，而它与 proposal.md 是 Gate 1 仅有的 2 项受审输入。

### 7.2 双轨与视图完整性

- `stdd canon verify`：修订后先 1/2（DC-HASH 不一致、DC-BODY 一致），按 CLI 指示执行 `canon generate` 后恢复 **2/2**。
- `canon generate` 只重写 `proposal.md`（`source_hash: dd59ac55294e83a1`）。哈希比对证明 `test-plan.md`、`design.md`、`tasks.md`、`slices.md`、`phase-context.md` 与 `canonical/.canon-index.yaml` **逐字节未变**，断言与命令未被生成动作改写。
- 诚实边界：`proposal.md` 在记录仓为 **UNTRACKED**，且只保留了生成前哈希、未保留字节，故**无法给出行级 diff**；不声称"逐行比对无变化"。该视图模板本身不渲染锚定章节。
- 证据：`canon-views-before.txt`、`canon-views-after.txt`。

### 7.3 esbuild 环境失败的真实根因与修复

- 根因实测：`node_modules/.pnpm/@esbuild+win32-x64@0.25.12/node_modules/@esbuild/win32-x64/` 只有 `README.md` 与 `package.json`，全 `.pnpm` 下 `find esbuild.exe` **为空**。esbuild 报错文本自相矛盾（"present but needs" 两侧同名），正是包目录在、二进制不在的特征。
- `pnpm rebuild esbuild` 是**空操作**：exit 0，但 `lib/`、平台包目录、`esbuild.exe`、`downloaded-*` 四项全部无变化。**不以退出码 0 当作修好**。
- 改为直接执行 esbuild 自己声明的 postinstall（`node install.js`），由其自带回退从**官方 `registry.npmjs.org`** 取包；未手写、未替换任何下载地址，未使用代理。
- 落点：`esbuild/lib/downloaded-@esbuild-win32-x64-esbuild.exe`，**10,617,344 字节**、可执行位就绪。平台包目录未改。
- 依赖声明零改动：`package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml` 的 git 差异为空、mtime 仍 2026-10-21。未重装全部依赖。
- **全量重跑结果：`EXIT_CODE=0`、`Tasks: 10 successful, 10 total`、`Cached: 0`、`error TS` 计数 0、耗时 1m19s**。任务总数由原先 5 变 10，证明此前是 turbo 早退、这次整图跑完，属**全量通过而非过滤口径**。
- 证据：`pnpm-typecheck.txt`（原 exit 1，保留）、`esbuild-rebuild.txt`、`esbuild-install.txt`、`pnpm-typecheck-after-fix.txt`。

### 7.4 同次执行证据（run `7cd120df-d9d1-4f31-a9b5-e26b5a13606a`）

`stdd agent verify` 与 `stdd ci check-failures` 使用**同一 run id**，两者之间未跑任何其他 verify。

- **`Results: 18 passed, 0 failed`** —— 18 个命令 CP 全部真实执行并通过，`agent-verification-report.md` 已生成。
- `tc-evidence.json` 实测：18 条 check、全部 `kind=command`、全部 `result=pass`、18 个不同 TC。
- 6 个自建一次性库的 selection 叶子结果（skip 全为 0）：`ci-gate-identity pass=16`、`handler-wsd-manifest pass=2`、`handler-wsd-delete pass=1`、`handler-wsd-retain pass=23`、`handler-wsd-atomic pass=1`、`handler-wsd-no-recreate pass=3`。
- verify 自身 `EXIT_CODE=1` 的原因是 **`REVIEW_PENDING`**（4 个人工 TC 待确认），**不是 CP 失败**。
- **容器边界已守住**：运行前后 `podman ps -a` 清单 `diff` 为 **IDENTICAL**，只有 `multica-postgres` 与 `multica-backend` 两个 **Exited** 旧容器，未被启动或访问；未连 localhost:5432；未放宽 nonce 门禁；未读取任何凭据。
- 证据：`run-id-round2.txt`、`inventory-before-round2.txt`、`inventory-after-round2.txt`、`agent-verify-round2.txt`、`ci-check-failures-round2.txt`。

### 7.5 ci 对账第二轮：8 通过 / 1 警告 / 0 跳过 / 1 错误

- **`(l) Anchoring: L4 >= L4` 已 PASS** —— 阻塞 B 消除。
- `(j)` 覆盖义务已声明 `not_applicable`（被测对象为 Go/Node/CI 配置/前端类型检查，采集只支持 pytest-cov）→ PASS，属**豁免**而非测量通过。
- `(b)` 仍 WARN 37 文件，**该警告不能作为范围蔓延证据**，口径缺陷已实测钉死（ADJ-041）：`git diff --stat HEAD~1` 报 38 files changed，正则解析出 39 个 token，**汇总行数字 `38` 被当成文件路径**，故 37 实为 36；文件源混入上一提交（HEAD=903a46c5a、HEAD~1=d5b348a17）；`git diff` 不含未跟踪文件，本 change **27 个新文件对该检查完全不可见**；`--stat` 截断长路径为 `.../suffix`；在范围判据只认 `.stdd/ tests/ docs/ .github/` 前缀或 `specs/<cap>/`、`commands/<cap>` 子串，multica 真实代码路径无一匹配。
- **真实范围手工核对结论**：49 个文件（22 改 + 27 新）全部可追溯到 C1–C10 或 constraints。`packages/core/package.json` 仅加一行 subpath export `./platform/storage`，是 C9 包导入改写的必要解析入口；`approval_crosscheck_test.go` 的 9 增 19 删是删除 `CRCTL_PATH` 别名与开发机相对路径回退、把 `t.Skip` 改为 `t.Fatal/t.Fatalf`，属**收紧而非放宽断言**。
- 唯一错误：**TC 覆盖 0/22**，理由「缺少或重复必需 check（当前运行未完成）」。判定条件已精确定位 `evidence.py:1033-1034`：`len(checks) != len(plan["checks"])` 即 raise，是**严格条数相等**（18 ≠ 22），整个 run 被判未完成、覆盖归零，**不是按已通过条数计 18/22**。详见 ADJ-040。

### 7.6 C2 义务逐项状态（如实，不以未执行冒充通过）

| 义务 | 状态 | 依据 |
|---|---|---|
| `quality.lint` = `pnpm lint` | **执行，exit 0** | 7 successful / 7 total，48.35s（`pnpm-lint.txt`） |
| `quality.typecheck` = `pnpm typecheck` | **执行，exit 0**（修复后全量） | 10/10、0 error TS（`pnpm-typecheck-after-fix.txt`）；原 exit 1 日志保留 |
| 覆盖义务 | **豁免 not_applicable，PASS** | 计划已声明理由；非测量通过 |
| 同次执行证据 | **已闭合（命令部分）** | 18/18 CP 通过，同一 run id 配对 |
| `quality.test` = `make test` | **NOT EXECUTED** | `make test` → `scripts/ensure-postgres.sh`，其 :71-72 明写「Ensuring shared PostgreSQL container is running on localhost:5432...」并执行 `docker compose up -d postgres`；:66 条件为 DATABASE_URL 空或 host 属 localhost/127.0.0.1/::1。**直接违反用户安全边界**（不连 localhost:5432 旧库、不操作旧 multica-postgres 容器），故不跑。受影响包已改由 runner 自建一次性实例执行（见 7.4） |
| e2e = `bash scripts/check.sh` | **NOT EXECUTED** | 该脚本 source `.env`、跑 `go run ./cmd/migrate up`、并拉起 `go run ./cmd/server` 与 `pnpm dev:web` 两个服务进程（:119、:129），同样触及旧库与在跑服务边界。`.env` 仅检查存在性，**未读内容** |
| TC 覆盖指标 | **0/22（CLI 判定）** | 4 个人工 TC 未确认导致 run 结构不完整；命令 CP 实为 18/18 通过。两个数字含义不同，Gate 3 须并列呈报 |

### 7.7 仍未闭合项（需外部动作或单独授权，不伪造确认）

`agent confirm` 写入的 `result` 固定为 `manual-pass`（`evidence.py:1071`），**确认即等于断言通过**，故前置未满足者一律不确认：

- **TC-CBE-005**：需真实 CI run → 推送须单独授权并消耗私有库 Actions 额度（U5）。
- **TC-TOR-004**：需 WSL AIFI-ISO 独立入口 → ADJ-024 半句 **UNCOVERED**。
- **TC-CCF-003**：需管理员更新 PAT → 外部动作，凭据不可读取。
- **TC-TOR-005**：需验收报告 → C7 产出后可如实确认（本会话可完成）。

**Gate 3 未推进。C2 的命令执行与质量检查已如实闭合，覆盖指标与 4 项人工 TC 仍为公开缺口，将在 test-report 与 Gate 3 并列呈报，不美化。**