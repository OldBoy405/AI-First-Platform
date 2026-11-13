# 验收报告 — 2026-11-12-fork-ci-test-evidence-trust

| 项 | 值 |
|---|---|
| **change** | `2026-11-12-fork-ci-test-evidence-trust` |
| **项目 / PROJECT_ROOT** | multica / `C:\Users\GOBAO\Downloads\AI\multica` |
| **commit（本轮实测）** | `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`（branch `main`，tracked 7336，22 `M` + 27 `??`，0 deleted） |
| **记录根 / DATA_ROOT** | `C:\Users\GOBAO\Downloads\AI\AI First Platform\projects\multica` |
| **选定 evidence run** | `add97e96-1676-4191-ae65-2ebd6524d585`（**第 5 轮：用户裁定 B 路径、计划分母 22 → 19 后重跑**；第 3 轮 `dfb7aad8-7539-486b-aa59-297d57a87d1a` 因 `test-plan.md` 变更按 `_materials_match` 失效，更早的 `7cd120df-d9d1-4f31-a9b5-e26b5a13606a` 见 §6.3；**旧 run 数据仅作历史，见 §0**） |
| **报告时间** | 2026-11-13T18:37:51+08:00（第 5 轮更新） |
| **阶段** | Phase 3 BUILD / Part C / C7 |
| **模式** | `thorough`，`long_range.mode: full_auto` |
| **本报告服务的 TC** | **TC-TOR-005**（manual，文档类验收，人工逐项核对） |

## 0. 第 5 轮重跑（范围收窄后，**当前有效轮次**）

**2026-11-13 用户裁定 B 路径（ADJ-046 / ADJ-047）后，本 change 的验收面已正式收窄**：

- 3 个外部前置未满足的场景**移交后续 change**：TC-CBE-005（真实 CI run）、TC-TOR-004（WSL 隔离）、TC-CCF-003（管理员 PAT 更新）。移交原文与入口条件见 `validation/handoff/handoff-to-successor-change.md`；`test-plan.md` §七 有可见移交表，3 个 TC 的原定义在原位 HTML 注释中保留。
- 证据计划分母 **22 → 19**（18 command + 1 manual TC-TOR-005）；Gate 2 于 `2026-11-13T18:33:41` 以 `--reapprove` + 用户原文重签。
- **旧 run `dfb7aad8-7539-486b-aa59-297d57a87d1a` 已失效**（`_materials_match`：当前 `test-plan.md` 摘要 ≠ 该 run 留存快照）。本报告 §2 正文中引用该 run 的实例 id 与原始输出均属**第 3 轮历史**，不得当作当前证据；本轮以 **§2.1′** 与 **§2.4′** 为准。

**当前有效 run：`add97e96-1676-4191-ae65-2ebd6524d585`**（2026-11-13T18:33:30 启动）

| 项 | 实测 |
|---|---|
| 命令 CP | **18 passed, 0 failed**（18/18 `exit_code=0`、`result=pass`、`assertions_passed=true`） |
| `VERIFY_EXIT` | **1**，唯一原因 `REVIEW_PENDING`——待确认项只有 **TC-TOR-005/main**（不再含已移交的 3 项） |
| 报告产物 | `validation/runs/add97e96…/agent-verification-report.md`，sha256 `c58c545d211d6e2465350a3781580acbf4742ac66f38f68dcc7a3f0ea52506b5`（与第 3 轮逐字节相同：正文只含 18 行 PASS，不嵌 run id） |
| 输入快照 | `inputs` **823** 项；`coverage_files` `[]`（覆盖率豁免） |
| 同 run `ci check-failures` | ✅8 ⚠1 ⏭0 ❌1；❌ **TC 当前执行覆盖不足 0/19**，理由「当前执行证据无效: 缺少或重复必需 check」——**结构原因同 ADJ-040**：18 ≠ 19，须先 `agent confirm` TC-TOR-005 补齐第 19 条；`CHECKFAILURES_EXIT=1`（`validation/gate3-followup/ci-check-failures-scopeB.txt`） |
| 容器边界 | 运行前后 `podman ps -a` **IDENTICAL**（`multica-backend`、`multica-postgres` 始终 `Exited (0)`，未触碰）；6 个一次性实例全部 `released … remaining=0` |

### 2.1′ 真库 selection（第 5 轮实测，逐条取自 `validation/gate3-followup/agent-verify-scopeB.txt`）

| # | TC / CP | 退出码 | 通过 | 失败 | 跳过 | 一次性实例 |
|---|---|---|---|---|---|---|
| 1 | TC-CBE-002 / CP-CBE-002 | 0 | 16 | 0 | 0 | `14823ba4ec89`（released） |
| 2 | TC-WSD-001 / CP-WSD-001 | 0 | 2 | 0 | 0 | `38833fb83200`（released） |
| 3 | TC-WSD-002 / CP-WSD-002 | 0 | 1 | 0 | 0 | `c1c8a42bef7d`（released） |
| 4 | TC-WSD-003 / CP-WSD-003 | 0 | 23 | 0 | 0 | `c21cb37c4be2`（released） |
| 5 | TC-WSD-004 / CP-WSD-004 | 0 | 1 | 0 | 0 | `085b4a3ff3f4`（released） |
| 6 | TC-WSD-005 / CP-WSD-005 | 0 | 3 | 0 | 0 | `6f1531d249b8`（released） |

叶子合计 **46**，失败 0，跳过 0（与第 3 轮计数相同，实例 id 不同）。

### 2.4′ 第 5 轮汇总原文（逐字）

```
  Results: 18 passed, 0 failed
  Report: C:\Users\GOBAO\Downloads\AI\AI First Platform\projects\multica\changes\2026-11-12-fork-ci-test-evidence-trust\validation\runs\add97e96-1676-4191-ae65-2ebd6524d585\agent-verification-report.md
  REVIEW_PENDING: 需人工审阅后提交本次 run 的确认原文
    - TC-TOR-005/main
    stdd agent confirm ci-backend-environment --change 2026-11-12-fork-ci-test-evidence-trust --run add97e96-1676-4191-ae65-2ebd6524d585 --statement "<审阅结论原文>"
VERIFY_EXIT=1
```

**仍需 TC-TOR-005 的人工核对**：请按 §1（CI run = 0）、§2 与 §2.1′（18 条命令 CP 与真库计数）、§5 / §6（未覆盖项）逐项确认本报告没有把未执行项标成通过。**范围收窄不等于通过**：移交的 3 个场景在本 change 内未验证。

**人工核对已由用户完成，但结论尚未写入证据**（ADJ-048）：用户原文「已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过」。执行 `stdd agent confirm … --run add97e96… --statement "<该原文>"` 时工具抛 **`KeyError: 'cp'`（`stdd/cli/evidence.py:762`）**，`CONFIRM_EXIT=1`，**未写入任何内容**（run 仍 18 条、`manual` 为 null）。缺陷原因：`_CHECK_FIELDS` 含 `cp`，`confirm_manual` 用 `item[key]` 强取，而 manual 计划项按约定没有 `cp`。**本报告因此仍处于「用户已核对、工具未记录」的状态**；修好该一行后重试即可，无需重跑本报告的任何一个命令。

---

**TC-TOR-005 预期结果原文**（`test-plan.md:167-179`）：

> SHALL 逐项列出实际执行的 CI run 与本地命令、退出码、通过/失败/跳过数、测试范围与未覆盖项；对 skip 大于 0 的包 SHALL 逐个说明；SHALL NOT 出现未执行却标通过的项。

**本报告的口径声明**：

1. **任何未执行、跳过或外部依赖未满足的检查，一律不报通过。** 未执行项在 §1、§5、§6 明确标注。
2. 每条命令的 `command` / `cwd` / `exit_code` / `result` / `assertions_passed` **逐字取自选定 run 的 `tc-evidence.json`**，不凭记忆填写。
3. **粒度限制如实声明**：`tc-evidence.json` 的条目**不含 stdout 字段**（实测条目键为 `tc, case_id, requirement, scenarios, cp, kind, applicability, command, interpreter, interpreter_role, cwd, exit_code, result, assertions_passed`）。因此 TAP 类命令的**精确通过/跳过数不在选定 run 产物内**；`agent-verify-round3.txt` 的控制台捕获亦被截断。本报告对这类命令只填**可证的粒度**（exit 0 + `# fail 0` 断言通过），并在 §3 另行给出**同命令的 C2 全量执行**精确计数，**明确标注为另一次执行**，不冒充选定 run 的数字。
4. `stdd canon verify` 2/2 与各类 dry-run 预览**不等于业务测试已执行**，不计入任何通过数。

---

## 1. 实际执行的 CI run

### 1.1 结论：**真实 CI run 执行数 = 0**

**本 change 至今未执行任何真实 GitHub Actions run。** 按 TC-CBE-005「验收报告 SHALL 记录 run id、commit、各 job 结论」的要求，如实记录如下：

| 字段 | 值 |
|---|---|
| **CI run id** | **无（未执行）** |
| **CI run 所对应的 commit** | **无（未执行）**。本地工作树 commit 为 `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`，**尚未提交本 change 的 49 个文件改动，亦未推送** |
| **各 job 结论** | **无（未执行）**。`backend-tests`、`script-checks`、`transitions-contract-check` 等 job **均未在 CI 上运行过**，不得填写任何结论 |
| **触发方式** | 未触发。**multica** 的推送须单独授权并消耗私有库 Actions 额度；Gate 3 确认不自动推导该授权 |

### 1.2 两个前置的当前实测状态（本轮重新核实）

| 前置 | 实测结果 | 影响 |
|---|---|---|
| **multica 推送授权** | **未取得**。multica 的 Git 提交、推送、部署均**未执行**（HEAD = `origin/main` = `903a46c5ae9f`，49 个改动路径全在工作区） | 无法触发 CI |
| **tools pin 在 origin 上可用** | **是（本轮已闭合）**。用户原话「ADJ-025 授权执行推送 e52b808」，推送已执行。实测 tools `HEAD` = `origin/main` = `git ls-remote origin refs/heads/main` = **`e52b8081f159d581bf62f82447c76f818fc52426`**，`git merge-base --is-ancestor e52b808… origin/main` → **YES** | ADJ-025 的「pin 在 origin 不可达」阻塞**已消除**；`ci.yml` 两个消费者从 `.github/aifirst-tools-pin` 读到的 ref 现在在 origin 上真实存在。**但这只解除 pin 可达性，不等于 CI 已运行**——仍需 multica 提交并推送才会触发 |

**tools 推送的边界（如实记录）**：只推送了 `e52b808` 这一个提交到 `origin/main`；tools 工作区另有 **6 个未提交改动路径**，**未夹带、未提交、未清理**。multica 侧**未提交、未推送、未部署**。

### 1.3 本地等价验证 ≠ CI 已验证

本 change 对 CI 接线只做了**本地等价验证与变异测试**，如实列明其边界：

| 本地验证 | 结果 | **不能**证明什么 |
|---|---|---|
| `tools-pin read` | 输出 `e52b808…`，exit 0 | 不证明 origin 上有该 commit（origin 可达性由**另一条独立命令** `git ls-remote origin refs/heads/main` 证明，见 §1.2） |
| `tools-pin check`（对本地 tools checkout） | `complete (3 required files present)`，exit 0 | **只证明本地 checkout 完整**，不证明 CI 上可 checkout |
| `ci-scope.test.mjs` 的 backend-tests 完整接线断言（env 键、Setup Node.js、10 步顺序、各步 run 正文与 if 条件） | 49/49 通过；3 条变异全 DETECTED，`ci.yml` 逐字节还原 | 不证明这些步骤在 ubuntu-latest 上真实成功 |
| `ci.yml` 两处 ref 变异为 `main` 的缺口证明 | 旧测试照样绿（15/15/0）→ 强化后 RED（14/1）→ 还原 GREEN（15/15/0） | 属断言 teeth 证明，非 CI 运行 |

**U1 路径 β 的适用性（本轮更新）**：TC-CBE-005 预期结果原文（`test-plan.md:105`）中的 β 分支是**条件句**——「若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿」。**tools 已推送（§1.2），故 β 分支不再适用**，不得再据此声称「pin 完整性检查失败」。但该 TC 的**主句义务仍未满足**：「SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip」与「验收报告 SHALL 记录 run id、commit、各 job 结论」都要求**真实 CI run**，而真实 run 数 = **0**（§1.1）。因此 **TC-CBE-005 仍为未闭合的人工 TC**，本报告不报其通过。

### 1.4 ADJ-025 后半句「把 pin 可达性检查前移到 checkout 之前」——实测已满足，**未改 `ci.yml`**

用户原话要求前移可达性检查。**先测量再动手**的结果是：两个 job 的**凭据可达性诊断步骤本来就排在 tools checkout 之前**，无需改动。

| job | 可达性诊断步骤序号 | tools checkout 步骤序号 | 前移条件 |
|---|---|---|---|
| `transitions-contract-check` | **3**（`Diagnose the tools read credential`） | **5**（`Checkout the pinned tools contract revision`） | **3 < 5 → true** |
| `backend-tests` | **10**（同上） | **12**（同上） | **10 < 12 → true** |

证据：`validation/gate3-followup/pin-reachability-order.txt:10`、`:35`（逐字 `=> reachability step index 3 < tools checkout index 5 : true` / `=> reachability step index 10 < tools checkout index 12 : true`，含两 job 的完整步骤清单）。

**结论与自我更正**：此前报告中「建议重排 `ci.yml` 步骤」的说法**被实测推翻**，已更正记录；本轮**未对 `ci.yml` 做任何编辑**（本轮实测 sha256 `72c16f6b9302bb976402a57ddbf8c557e2444881aa8b5b390e9ac26725e1c43e`，与 C1 变异还原后记录的值一致）。此处如实标注为**「要求已被现状满足，无代码改动」**，不冒充为一次修复。

---

## 2. 实际执行的本地命令（选定 run 的 18 条命令型 CP，逐项）

**共同字段（实测，18 条全部一致）**：

- `cwd` = `C:\Users\GOBAO\Downloads\AI\multica`
- `interpreter_role` = `runner`
- `exit_code` = **0**（18/18）
- `result` = **pass**（18/18）
- `assertions_passed` = **true**（18/18）
- `kind` = `command`，`applicability` = `required`
- `coverage_files` = **`[]`**（覆盖率豁免，见 §3.4）
- `artifacts` = `agent-report` → `validation/runs/add97e96…/agent-verification-report.md`，sha256 `c58c545d211d6e2465350a3781580acbf4742ac66f38f68dcc7a3f0ea52506b5`（第 5 轮实测）
- `inputs` = **823** 项快照；`checks` = **18**（`kind=command`），**manual 型 0 条**（TC-TOR-005 待人工确认，见 §0；其余 3 项已移交）

**产物哈希与旧 run 相同的说明（如实标注，不是复制旧产物）**：新 run 的 `agent-verification-report.md` 实测 sha256 与旧 run **完全一致**。原因是该报告正文**只含 18 行 `CP-xxx: PASS (exit_code=0)`，不嵌入 run id**（实测 `grep -c "dfb7aad8\|7cd120df"` → **0**），18 条 CP 的结论两轮相同故逐字节相同。**run id 的区分依据是 `tc-evidence.json` 的 `run_id` 字段与 `validation/runs/<id>/` 目录名**，不是产物哈希。

### 2.1 真库 selection（**第 3 轮历史数据**；当前有效数据见 §2.1′）

这 6 条的计数**直接来自第 3 轮 run 的 verify 输出原文**（`validation/gate3-followup/agent-verify-round3.txt`），且**全部使用 runner 自建的一次性 podman 实例**。**该表所属 run 已失效**（见 §0），第 5 轮同命令的计数与实例见 §2.1′。

| # | TC / CP | 命令（逐字） | 退出码 | 通过 | 失败 | 跳过 | 一次性实例 | 测试范围 |
|---|---|---|---|---|---|---|---|---|
| 1 | TC-CBE-002 / CP-CBE-002 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only ci-gate-identity` | 0 | **16** | **0** | **0** | `d979348e09b0`（released） | nonce 门禁：SC-CBE-002 每一条单独退化都被拒绝，且由**独立命名子测试逐条归因**；合法 nonce 库通过 |
| 2 | TC-WSD-001 / CP-WSD-001 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-manifest` | 0 | **2** | **0** | **0** | `8c5ac051aaa9`（released） | 公共 schema 每张表有且仅有一个分类，19 张 `cr_execution_*` 表分类清单 |
| 3 | TC-WSD-002 / CP-WSD-002 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-delete` | 0 | **1** | **0** | **0** | `9aaf08ec1a0c`（released） | A 的 `cr_execution_notice` 与 `cr_execution_dispa…` 删除行为 |
| 4 | TC-WSD-003 / CP-WSD-003 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-retain` | 0 | **23** | **0** | **0** | `1622bc487691`（released） | retain 类 A 行**逐字节不变（含 digest 列）**；keep 类行行为 |
| 5 | TC-WSD-004 / CP-WSD-004 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-atomic` | 0 | **1** | **0** | **0** | `266f7910fdf5`（released） | A 的 notice 与 dispatch_root 行恢复，且 A 的其他行**未被半删**（原子性） |
| 6 | TC-WSD-005 / CP-WSD-005 | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-no-recreate` | 0 | **3** | **0** | **0** | `65a73d2293eb`（released） | reservation 半句被拒绝（`CreateReservationTx` 加 workspace 存在性检查）；**command 半句按 R5 裁定不在本 change 内修复，断言原样保留并登记为已知失败** |

**真库叶子测试合计 = 16 + 2 + 1 + 23 + 1 + 3 = 46，失败 0，跳过 0。**

原文佐证（逐字）：`PASS ci-gate-identity pass=16 fail=0 skip=0`、`PASS handler-wsd-manifest pass=2 fail=0 skip=0`、`PASS handler-wsd-delete pass=1 fail=0 skip=0`、`PASS handler-wsd-retain pass=23 fail=0 skip=0`、`PASS handler-wsd-atomic pass=1 fail=0 skip=0`、`PASS handler-wsd-no-recreate pass=3 fail=0 skip=0`。

### 2.2 TAP 类命令（10 条，**精确通过/跳过数不在选定 run 产物内**）

按 §1 口径声明第 3 条，这 10 条只填**可证粒度**：`exit_code=0`、`result=pass`、`assertions_passed=true`，且 verify 的 `stdout_contains` 断言 **`# fail 0` 已通过**（即执行当时失败数为 0）。**精确 pass/skip 数见 §3.1–§3.2 的另一次全量执行**，不在此冒充。

| # | TC / CP | 命令（逐字） | 退出码 | 失败数（可证） | 通过/跳过数 | 测试范围 |
|---|---|---|---|---|---|---|
| 7 | TC-CBE-001 / CP-CBE-001 | `node --test --test-reporter=tap scripts/aifi45-disposable/ci-provision.test.mjs` | 0 | **0**（`# fail 0` 断言通过） | 选定 run 未存 stdout；见 §3.1 | up 建出符合 TestMain 身份检查的 nonce 库并**先 mask 口令再写 GITHUB_ENV**；down 按 marker 删除，handle 缺失时 0 退出；日志与 handle 不含明文口令（**口径例外见 §7.2**） |
| 8 | TC-CBE-003 / CP-CBE-003 | `node --test --test-reporter=tap scripts/aifi45-disposable/tools-pin.test.mjs` | 0 | **0** | 见 §3.1；C1 强化后该文件 **15/15/0** | `read` 对非 40 位 hex 或多行文件**硬失败**；`check` 在任一必需文件缺失时失败；**ci.yml 的 checkout ref 必须取自 pin 步骤输出**（ADJ-034 强化） |
| 9 | TC-CBE-004 / CP-CBE-004 | `node --test --test-reporter=tap scripts/aifi45-disposable/go-test-env-contract.test.mjs` | 0 | **0** | 见 §3.1；C1 修复后该文件 **12/12/0** | 源码中不含开发机绝对路径默认值；缺失 `CRCTL_MJS` 或 `AIFI45_…` 时硬失败；治理范围为 governance 与 crosslang_test；**不得再出现 `os.Getenv("CRCTL_PATH")`**（ADJ-027 新守卫） |
| 10 | TC-TOR-001 / CP-TOR-001 | `node --test --test-reporter=tap scripts/aifi45-disposable/test-ownership.test.mjs` | 0 | **0** | 见 §3.1；S10 GREEN 该文件 **18/18/0** | `check` 对不存在、缺 reason、重复的条目**非 0 退出并指名**；通过时输出名单与数量；`skip-regex` 输出 `^(A|B|…)$` 且正则元字符被转义 |
| 11 | TC-TOR-003 / CP-TOR-003 | `node --test --test-reporter=tap scripts/aifi45-disposable/ci-evidence.test.mjs` | 0 | **0** | 见 §3.1 | 前五种违规每一种**单独非 0 退出并指明包或测试**；合规流退出 0；逐项对账 |
| 12 | TC-SEL-001 / CP-SEL-001 | `node --test --test-reporter=tap scripts/aifi45-disposable/selection-decision.test.mjs` | 0 | **0** | 见 §3.1；S1 该文件 **12/12/0** | `status` 不是 `matched` 时 `ok=false`，`reasons` 含该 reason |
| 13 | TC-SEL-002 / CP-SEL-002 | `node --test --test-reporter=tap scripts/aifi45-disposable/run-selection.test.mjs` | 0 | **0** | 见 §3.1；ADJ-042 修复后该文件 **14/14/0**（S1 期为 11/11/0） | **沿用旧判定**：`test.code` 为 0 且 fail 为 0 且 skip 为 0 且…；输出行逐字不变、既有断言不被改弱（含 `TC-DTI-002 --admin-url is rejected before any instance…`）；**ADJ-042 新增 1 个测试函数：未知参数在建实例前按名硬失败** |
| 14 | TC-SEL-003 / CP-SEL-003 | `node --test --test-reporter=tap --test-name-pattern=EXPECTED_INVALID scripts/aifi45-disposable/selection-decision.test.mjs` | 0 | **0** | 见 §3.1；S1 该 pattern **4/4/0** | `ok=false` 且 `reasons` 含 **`EXPECTED_INVALID`**（空 declared manifest）；verify 另有独立 `stdout_contains: EXPECTED_INVALID` 断言通过 |
| 15 | TC-SEL-004 / CP-SEL-004 | `node --test --test-reporter=tap scripts/ci-scope.test.mjs` | 0 | **0** | 见 §3.2（**同命令** C2 全量 **49/49/0/0**） | 该变更命中 scripts 与 backend scope；script-checks 跑 harness 且 pg 取失败不能存活；PR 与 main 只选受影响 scope |
| 16 | TC-CCF-001 / CP-CCF-001 | `node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs` | 0 | **0** | 见 §3.1；S11 该文件 **15/15/0** | 凭据状态映射为 `missing`、`rejected`、`no-access-or-pin-not-fo…`；**空凭据映射为 missing** |

### 2.3 非 TAP 命令（2 条）

| # | TC / CP | 命令（逐字） | 退出码 | 通过 / 失败 / 跳过 | 测试范围 |
|---|---|---|---|---|---|
| 17 | TC-TOR-002 / CP-TOR-002 | `bash scripts/test-go.test.sh` | 0 | **4 个具名用例 PASS，0 失败**；该脚本**非 TAP，无 pass/fail/skip 汇总行**，故不填汇总数 | `--skip-regex` 原样传给 `go test -skip`；`--json` 行为。原文逐字：`TC-TWG-001: PASS`、`TC-TWG-003: PASS`、`TC-TWG-002: PASS`、`TC-TOR-002: PASS` |
| 18 | TC-CCF-002 / CP-CCF-002 | `pnpm --filter @multica/views typecheck` | 0 | **类型检查，无测试计数**；断言为 **0 条 TS6059**（RED 时为 60 条） | SC-CCF-002：typecheck 0 条 TS6059；`use-logout.test.ts` 保持 2/2。**该 CP 在证据计划中是 command 型，断言对象是 tsc 退出码与错误码计数，不是某个测试函数**（ADJ-019） |

### 2.4 **第 3 轮**选定 run 的汇总原文（逐字，取自 `validation/gate3-followup/agent-verify-round3.txt`；**该 run 已失效，当前见 §2.4′**）

```
  Results: 18 passed, 0 failed
  Report: C:\Users\GOBAO\Downloads\AI\AI First Platform\projects\multica\changes\2026-11-12-fork-ci-test-evidence-trust\validation\runs\dfb7aad8-7539-486b-aa59-297d57a87d1a\agent-verification-report.md
  REVIEW_PENDING: 需人工审阅后提交本次 run 的确认原文
    - TC-CBE-005/main
    - TC-TOR-004/main
    - TC-TOR-005/main
    - TC-CCF-003/main
    stdd agent confirm ci-backend-environment --change 2026-11-12-fork-ci-test-evidence-trust --run dfb7aad8-7539-486b-aa59-297d57a87d1a --statement "<审阅结论原文>"
VERIFY_EXIT=1
```

**`VERIFY_EXIT=1` 的原因是 `REVIEW_PENDING`（4 项人工 TC 待确认），不是任何 CP 失败。** 18 个命令 CP 全部 `exit_code=0`、`result=pass`。

**同 run 的 `stdd ci check-failures` 判定（逐字摘要，取自 `validation/gate3-followup/ci-check-failures-round3.txt`）**：✅8 ⚠1 ⏭0 ❌1；自动化检查覆盖 **10/10**；`(l) Anchoring: L4 >= L4` 通过；`13 个切片均有验证证据` 通过；⚠ `(b) 范围蔓延: 37 个文件可能超出声明范围`；❌ **TC 当前执行覆盖不足: 0/22**，理由「证据问题: 当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」；`CHECKFAILURES_EXIT=1`。

**同次执行纪律（第 3 轮实测）**：run id `dfb7aad8-7539-486b-aa59-297d57a87d1a` 由调用方自行生成，`stdd agent verify` 与紧随其后的 `stdd ci check-failures` **使用同一值**，两者之间**未插入任何其他 `agent verify`**；`inputs` 快照 **823 项**，不含 change 目录产物本身。第 5 轮以同样纪律执行（`add97e96…`，见 §0）。

**两个数字必须同时读，不得互相冒充**：命令 CP **18/18 通过**（有报告与产物）／CLI 覆盖判定 **0/22**（`evidence.py:1033-1034` 要求 `len(checks) == len(plan["checks"])`，18 ≠ 22 即整个 run 结构上不完整、覆盖归零，**不是按已通过条数计 18/22，也不是执行失败**）。详见 ADJ-040。

---

## 3. 全量质量命令（C2 执行，**与选定 run 分开的另一次执行**）

**标注口径**：本节命令**不是**选定 run 的 CP，而是 C2 全量质量检查的独立执行。列出它们是为了补齐 §2.2 中「精确通过/跳过数不在选定 run 产物内」的粒度缺口，**不得据此声称选定 run 的 CP 有这些计数**。

### 3.1 harness 目录全量（覆盖 §2.2 的 10 个 TAP 测试文件的聚合）

| 项 | 值 |
|---|---|
| **命令** | `node --test "scripts/aifi45-disposable/*.test.mjs"`（**glob 形式**；`phase-context.md:107` 实测记录：Windows Node 24 上 `node --test <目录>` 会 `MODULE_NOT_FOUND`，必须用 glob，S13 的 CI 步骤沿用同一形式） |
| **输出格式** | spec reporter（日志为 `✔` / `ℹ` 行） |
| **tests** | **173** |
| **suites** | 0 |
| **pass** | **173** |
| **fail** | **0** |
| **cancelled** | **0** |
| **skipped** | **0** |
| **todo** | **0** |
| **duration_ms** | 2584.8845 |
| **EXIT_CODE** | **0** |
| **证据** | `validation/gate3-followup/harness-after-adj042.txt:174-181`（**本轮，依赖树重建 + ADJ-042 修复后**） |
| **测试范围** | `scripts/aifi45-disposable/` 下全部 `*.test.mjs`：ci-provision、tools-pin、go-test-env-contract、test-ownership、ci-evidence、selection-decision、run-selection、tools-access 等 |
| **演进** | 171 → 172（+1 = ADJ-027 的 `CRCTL_PATH` 别名回归守卫）→ **173**（+1 = ADJ-042 的未知参数硬失败守卫）。C1 两条 MAJOR 修复后为 **172/172/0/0 exit 0**（`validation/c1-review/harness-after-both-fixes.txt`）；旧值 172 与 duration 1962.7346 出自 `validation/c2-quality/harness-full.txt:173-181`，**已被本轮取代，不作为当前计数** |

**单文件精确计数（切片期执行，逐个可查）**：

| 测试文件 | tests / pass / fail / skipped | 证据 |
|---|---|---|
| `selection-decision.test.mjs` | **12 / 12 / 0 / 0** | `validation/s1-selection-decision/tc-sel-001-003.tap:75-80` |
| `run-selection.test.mjs`（ADJ-042 修复后） | **14 / 14 / 0 / 0** | `validation/gate3-followup/run-selection-after-fix.tap:87-93`（S1 期 11/11/0 见 `validation/s1-selection-decision/tc-sel-002.tap:69-74`） |
| `selection-decision.test.mjs --test-name-pattern=EXPECTED_INVALID` | **4 / 4 / 0 / 0** | `validation/s1-selection-decision/tc-sel-003-pattern.tap:27-32` |
| `test-ownership.test.mjs` | **18 / 18 / 0 / 0** | `validation/s10-wsd-no-recreate/green-ownership.tap:111-116` |
| `tools-access.test.mjs` | **15 / 15 / 0 / 0** | `validation/s11-tools-access/README.md:96` |
| `go-test-env-contract.test.mjs`（C1 修复后） | **12 / 12 / 0 / 0** | `validation/c1-review/green-crctl-alias.tap:75-80` |
| `tools-pin.test.mjs`（C1 强化后） | **15 / 15 / 0 / 0** | `validation/c1-review/green-ref-restored.tap:93-98` |

### 3.2 ci-scope 全量（**与 CP-SEL-004 同命令**）

| 项 | 值 |
|---|---|
| **命令** | `node --test --test-reporter=tap scripts/ci-scope.test.mjs` |
| **tests / pass / fail / skipped** | **49 / 49 / 0 / 0** |
| **EXIT_CODE** | **0** |
| **证据** | `validation/gate3-followup/ci-scope-after-adj042.tap:297-304`（**本轮**）；C1 修复后同值 `validation/c1-review/ci-scope-after-both-fixes.tap:297-302`；C2 首轮 `validation/c2-quality/ci-scope.txt:297-305` |
| **测试范围** | `.github/ci-paths.json` 的 scope 命中判定 + `ci.yml` 接线形状（含 ADJ-026 的 3 个计划外守卫） |
| **演进** | S13 RED **49 tests / 47 pass / 2 fail** → GREEN **49/49/0**（`validation/s13-ci-wiring/red-backend-wiring.txt:600-605`） |

### 3.3 类型检查与 lint

**本节全部为依赖树重建后的本轮重测**（`validation/c2-quality-round3/`）。重建前的旧值保留在 `validation/c2-quality/`，**不作为当前结论**。

| 命令 | 实际执行体 | 结果 | EXIT_CODE | 证据 |
|---|---|---|---|---|
| `pnpm --filter @multica/views typecheck` | `tsc --noEmit`（`packages/views`） | **0 条错误**（RED 时为 **60 条 TS6059**） | **0** | 选定 run 内 CP-CCF-002（§2.3 第 18 条）；重建后预检 `validation/gate3-followup/precheck-views-typecheck.txt` |
| `pnpm typecheck` | `turbo typecheck --filter=!@multica/mobile` | **Tasks 10 successful / 10 total**，**Cached 0 / 10**，Time **1m20.851s**；`grep -c "error TS"` → **0** | **0** | `validation/c2-quality-round3/pnpm-typecheck-force.txt`（末 4 行） |
| `pnpm lint` | `turbo lint --filter=!@multica/mobile` | **Tasks 7 successful / 7 total**，**Cached 0 / 7**，Time **29.296s**；**7 个包全部 `0 errors`**，仅 warning（`@multica/ui` 3、`@multica/core` 2、`@multica/views` 21，均为 unused eslint-disable directive 与 `react-hooks/exhaustive-deps`） | **0** | `validation/c2-quality-round3/pnpm-lint-force.txt:53`、`:72`、`:121` 及末 4 行 |

**重建前的旧值（保留原记录，已被上表取代）**：`pnpm --filter @multica/views typecheck` 0 错误 exit 0（`validation/c2-quality/typecheck-views.txt:6`）；`pnpm --filter @multica/core typecheck` 0 错误 exit 0（`typecheck-core.txt:6`，core 包本轮由全量 turbo 10/10 覆盖）；`pnpm typecheck` 10/10、Cached 0/10（`pnpm-typecheck-after-fix.txt:73-77`）；`pnpm lint` 7/7、Cached 0/7、Time 48.35s、0 errors（`pnpm-lint.txt:125-129`）。

**为什么用 `--force`（口径必须写明）**：本轮先按配置原样执行 `pnpm typecheck` / `pnpm lint`，两者均返回 **`Cached: 10 cached, 10 total` / `7 cached, 7 total`、`>>> FULL TURBO`**（`pnpm-typecheck.txt`、`pnpm-lint.txt`），即**turbo 缓存回放，并未真正执行 tsc/eslint**。缓存回放不能作为「重建后全量真跑」的证据，故追加 `pnpm typecheck --force` / `pnpm lint --force`（`--force` 由 pnpm 透传给 turbo，**root script 本身未改**），得到 **Cached 0** 的真实执行。**两组日志都保留**，不删除缓存回放那次。

**`@multica/mobile` 被显式排除**（`--filter=!@multica/mobile`），故上述 10/10 与 7/7 **不覆盖 mobile 包**，如实标注为未覆盖项（§5）。

**pnpm 环境前置（ADJ-045，两阶段修复）**：①`pnpm install --frozen-lockfile` 重建被清理事故波及的依赖树（`INSTALL_EXIT=0`，pg 8.20.0，manifests 无 git 改动）；②修复 pnpm CLI 自身的切版空壳（11.22.0 自动切版到项目 pin 的 10.28.2 时，store 内链接目录为空壳），**用重命名隔离而非删除**（`hollow-backup-20261113` 保留），随后 `pnpm --version` → **10.28.2**、`PNPM_VERSION_EXIT=0`（`validation/c2-quality-round3/pnpm-version.txt`）。**未改 PATH、未装 corepack shim、未降级全局 pnpm 11.22.0、未改任何 pnpm 配置或仓库文件。** 证据 `validation/gate3-followup/pnpm-install-restore.txt`、`pnpm-cli-restore.txt`。

**esbuild 前置修复（ADJ-039，用户授权「授权修 esbuild 二进制后重跑」）**：使用**官方 registry**，**未替换任何 URL 为临时代理地址**；含一次 **no-op 重建**的如实记录。证据 `validation/c2-quality/esbuild-install.txt`、`esbuild-rebuild.txt`。修复前日志 `pnpm-typecheck.txt` 保留原文，不删除。

### 3.3.1 views 全量 vitest（本轮实测，**1 条失败，不报通过**）

| 项 | 值 |
|---|---|
| **命令** | `pnpm --filter @multica/views test`（实际执行体 `vitest run`，vitest 4.1.0） |
| **Test Files** | **1 failed \| 505 passed (506)** |
| **Tests** | **1 failed \| 6371 passed (6372)** |
| **Duration** | 199.70s |
| **EXIT_CODE** | **1**（`ERR_PNPM_RECURSIVE_RUN_FIRST_FAIL`，`VITEST_EXIT=1`） |
| **证据** | `validation/c2-quality-round3/views-vitest.txt:8707`（FAIL 行）、`:8727-8730`（汇总） |
| **唯一失败项** | `chat/components/chat-window-messages.test.tsx > floating chat message lifetime > follows immediately on open, stops during exit, then reads new data on reopen`，`AssertionError: expected 1 to be +0`，位置 `chat-window-messages.test.tsx:84:25`（`expect(observers()).toBe(0)`） |
| **本 change 义务项** | `auth/use-logout.test.ts` **✓ 2 tests**（`views-vitest.txt:8161`），CP-CCF-002 的「`use-logout.test.ts` 保持 2/2」**成立** |

**归因（按名字对账，不笼统归为「上游 flake」）**：

1. **同名同位置在 HEAD 上已失败**：`validation/s12-views-typecheck/ab/views-vitest-head.txt:9366` 与 `:9375` 记录**同一文件、同一测试名、同一行 `:84:25`** 的失败，且该次运行是**两个 S12 文件均还原后**的 HEAD 基线。
2. **另一次全量运行中它通过**：`validation/s12-views-typecheck/full/views-vitest.txt:7873` → `✓ chat/components/chat-window-messages.test.tsx (4 tests)`。`s12-views-typecheck/README.md:181` 已把它列入「**仅 HEAD 失败（2，带改动反而通过）**」。
3. **本轮单文件重跑通过**：`pnpm --filter @multica/views exec vitest run chat/components/chat-window-messages.test.tsx` → **Test Files 1 passed (1)、Tests 4 passed (4)**、Duration 1.81s、**`SINGLE_EXIT=0`**（`validation/c2-quality-round3/vitest-single-chat-window.txt`）。
4. **测试总数未变**：本轮 6372 / 506 与 ADJ-020 两次全量的 6372 / 506 **完全相同**，本 change 未增删 views 测试。

**结论与边界**：该失败是 **ADJ-020 已登记的、HEAD 上既有的负载敏感 flake 集合中的一个具名成员**，非本 change 引入；单文件重跑绿支持「负载敏感」而非「固定坏断言」。**但本轮失败形态是 `AssertionError`，与 ADJ-020 记录的以 `Test timed out in 5000ms` 为主不同**，如实标注这一差异，不声称形态一致。**未确立的部分**：单次重跑不足以测量 flake 率；未在 ubuntu-latest 上跑过 views 全量，故不能声称 CI 不受影响。按 **U4「先报告再裁定范围」**，**未改任何 views 生产代码或测试断言、未调 timeout/retry/并行度、未新增 skip 或排除**，该项留为未决发现（ADJ-020）。

### 3.4 覆盖率义务

| 项 | 值 |
|---|---|
| **计划声明** | `coverage.applicability = not_applicable`（**豁免**） |
| **理由（逐字）** | 「被测对象为 Go、Node、CI 配置与前端类型检查，覆盖率采集目前只支持 pytest-cov；项目配置 `quality.coverage.enabled=false`」 |
| **CLI 判定** | `ci check-failures` 的 **(j) 项 PASS**（按计划的 `not_applicable` 声明判定） |
| **`coverage_files`** | 选定 run 实测 **`[]`** |
| **结论** | **无行覆盖率 / 分支覆盖率保证**。这是**豁免**，不是「覆盖率达标」，不得表述为通过覆盖率检查 |

### 3.5 其他实际执行的验证命令（C1 修复期，实测退出码）

| 命令 | 结果 | 退出码 |
|---|---|---|
| 契约 CLI 对真实仓库扫描 | **`119 file(s), 0 violations`** | **0** |
| `go vet ./internal/governance/ ./internal/handler/` | 无输出 | **0** |
| `test-ownership check` | **`5 entry(ies)`** + **`allowed skips: 4`** | **0** |
| `test-ownership skip-regex` | 输出含第 5 个名字，形如 `^(A|B|…)$` | **0** |
| 真库 crosscheck（变量齐备，一次性实例） | **`PASS crosscheck-crctl pass=13 fail=0 skip=0`**（与 S4 基线 **7+3+3=13 逐名一致**，零回归） | **0** |
| 真库 crosscheck（`env -u CRCTL_MJS`，保留 `AIFI45_TOOLS_ROOT` 隔离单变量） | **`FAIL pass=0 fail=3 skip=0`**，三个调用方各自打印 `CRCTL_MJS is required` 于 `:213`/`:384`/`:176`；**`skip=0` 证明不再走 skip** | **1**（预期红） |
| `tools-pin read` | 输出 `e52b808…` | **0** |
| `tools-pin check`（本地 tools checkout） | `complete (3 required files present)` | **0** |

**注**：crosscheck 两条件的 selection 定义放在**证据目录**，**未改仓内 `selections.json`**。`gofmt -l` 在本机**有点名输出**（既有 CRLF 现象：工作树 2466 个 `.go` 中 2206 个 CRLF，未触碰的 `cmd/migrate/main.go` 同样被点名），**如实声明「`gofmt -l` 无输出」在本机不成立**；已核实 `gofmt` 输出与去 CR 原文逐字节一致，**未执行 `gofmt -w`**。

---

## 4. 对 skip 大于 0 的包逐个说明（TC-TOR-005 明文要求）

### 4.1 实测结论：**本次执行中未观测到任何 skip > 0 的包**

| 执行体 | skip / skipped 实测 | 证据 |
|---|---|---|
| 真库 6 个 selection（46 个叶子测试） | **全部 `skip=0`** | `gate3-followup/agent-verify-round3.txt` 逐条原文 `pass=16/2/1/23/1/3 fail=0 skip=0`（与上一轮逐名同值，零回归） |
| harness 目录全量（**173** 个测试） | **`skipped 0`**（另 `cancelled 0`、`todo 0`） | `gate3-followup/harness-after-adj042.txt:174-181` |
| ci-scope 全量（49 个测试） | **`skipped 0`** | `gate3-followup/ci-scope-after-adj042.tap:297-304` |
| 真库 crosscheck 两条件 | 齐备 **`skip=0`**；缺变量 **`skip=0`**（改为 fail=3，**证明不再走 skip**） | `validation/c1-review/crosscheck-env-present.txt`、`crosscheck-env-absent.txt` |

**因此「skip > 0 的包」集合为空，无需逐个说明观测到的 skip。** 这是实测结论，不是省略。

### 4.2 但必须区分：**声明的 allowed-skips（4 条）≠ 观测到的 skip**

`scripts/aifi45-disposable/test-ownership.json` 实测结构：顶层键 `required-packages`、`entries`（**5 条**）、`allowed-skips`（**4 条**）。这 4 条是**预先声明的排除名单**，用于 CI-linux 上 `ci-evidence` rule 2 的对账，**不是本次执行观测到的 skip**。逐条说明如下（reason 取自该文件原文）：

| # | 包 | 测试 | 排除理由（原文摘要） | 证据性质 |
|---|---|---|---|---|
| 1 | `./internal/governance` | `TestReconcileLiveGitHub` | `reconcile_live_test.go:21` 在缺 `KNOWLEDGE_BASE_REMOTE_URL` / `KNOWLEDGE_BASE_TOKEN` 时 skip；**CI 不持有 KB 凭据** | **基线观测**（baseline-observed） |
| 2 | `./internal/handler` | `TestFetchFromSkillsSh_AnthropicPptxIntegration` | `skill_test.go:989` 除非 `MULTICA_RUN_SKILLS_SH_INTEGRATION=1` 否则 skip；**CI 未选择启用** | **基线观测**（baseline-observed） |
| 3 | `./internal/daemon` | `TestChannelIsolationChild` | `execution_control_isolation_test.go:116`，`helper process; the parent drives it` | **⚠ 源码推导，非基线观测**：该文件是 `//go:build linux`，**Windows 基线从未编译它**。reason 中已明标 `Source-derived, not baseline-observed`。真实证明须在 **WSL 隔离入口**下取得（ADJ-024，当前 **UNCOVERED**） |
| 4 | `./internal/daemon` | `TestExecutionBindingRelayHelperProcess` | `execution_binding_relay_test.go:26`，`relay helper child only`，除非父进程设置 `AIFI45_RELAY_HELPER_MODE` | helper 子进程语义；同属 Linux-only daemon 文件 |

### 4.3 该名单的性质与未闭合点（不得当作 CI 的完整 skip 清单）

- **名单是 CI-linux 真实 skip 集合的「下界」而非终态**（ADJ-003）。最终全集须由 **TC-CBE-005（真实 CI 运行）** 确认，**当前未确认**。
- **ADJ-007**：`daemon.TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover` 在基线失败，**未排除、未定性、未修改**，须由真实 CI-linux 运行定性。它与 ADJ-003 共同说明名单只是下界。
- **ADJ-006**：handler 的 presenter/search 两个上游测试在 Windows 基线因时钟粒度失败，**未排除**；且 **handler 整包回归不能以「全绿」或失败计数当信号**——受害集合会在运行之间移动，须**按测试名逐条比对基线**（`validation/s8-wsd-manifest/regression-handler-failing-diff.txt`）。CI-linux 是否复现**仍未验证**，不提前报绿。
- **4 个 Linux-only daemon 测试文件在本机从未编译**，故本机任何「skip=0」结论**都不覆盖它们**（§5）。

---

## 5. 测试范围与未覆盖项（逐项，**一律不报通过**）

### 5.1 已覆盖范围（实测）

| 范围 | 覆盖方式 | 实测结果 |
|---|---|---|
| `scripts/aifi45-disposable/` 全部 `*.test.mjs` | harness 目录全量 + 10 个 TAP 型 CP | **173/173，fail 0，skipped 0** |
| `scripts/ci-scope.test.mjs`（scope 命中 + `ci.yml` 接线形状） | CP-SEL-004 + C2 全量 | **49/49，fail 0，skipped 0** |
| `scripts/test-go.sh` 参数契约 | CP-TOR-002（`bash scripts/test-go.test.sh`） | **4 个具名用例 PASS** |
| nonce 门禁逐条件退化 | CP-CBE-002（真库一次性实例） | **pass=16 fail=0 skip=0** |
| workspace 删除清单 / 删除 / retain / 原子性 / 禁新建 | CP-WSD-001…005（真库一次性实例） | **pass=2/1/23/1/3，fail=0，skip=0** |
| `packages/views`、`packages/core` 类型检查 | CP-CCF-002 + 全量 turbo | **exit 0，0 条 TS6059**（`grep -c "error TS"` → 0） |
| monorepo 类型检查（除 mobile） | `pnpm typecheck --force` | **10/10 successful，Cached 0/10**，Time 1m20.851s |
| monorepo lint（除 mobile） | `pnpm lint --force` | **7/7 successful，Cached 0/7，0 errors**，Time 29.296s |
| `packages/views` 全量 vitest | `pnpm --filter @multica/views test` | **6371/6372 通过，1 失败**（`chat-window-messages`，HEAD 既存具名 flake；单文件重跑 **4/4 exit 0**）。**整体 exit 1，不报通过**，见 §3.3.1 |
| `packages/views` `auth/use-logout.test.ts` | 同上全量运行内 | **✓ 2 tests**（CP-CCF-002 义务项成立） |
| Go 治理范围 env 契约 | 契约 CLI + `go vet` | **119 file(s), 0 violations**；vet exit 0 |
| `approval_crosscheck_test.go` 三调用方 | 真库两条件各一次 | 齐备 **13/0/0**；缺变量 **0/3/0**（skip=0） |

### 5.2 未覆盖 / 未执行项（**逐项标注，不得报通过**）

| # | 项 | 状态 | 原因 | 影响 | 补完计划 |
|---|---|---|---|---|---|
| 1 | **真实 GitHub Actions run（全部 job）** | **未执行（0 个 run）** | **multica 推送未授权**（提交/推送/部署均未执行）。tools pin 阻塞**已解除**：`e52b8081f159` 已推送，实测 `merge-base --is-ancestor` → **YES**（§1.2） | `backend-tests`、`script-checks`、`transitions-contract-check` 在 ubuntu-latest 的真实行为**全部未验证**；`ci.yml` 接线只有本地等价验证 | 取得 multica 提交+推送授权后真实跑一次，回填 run id / commit / 各 job 结论（TC-CBE-005） |
| 2 | **`TestChannelIsolation` 隔离性证明** | **UNCOVERED** | WSL AIFI-ISO 只做只读探针；未装 Go、未建 uid 995/gid 994 与 profile 根 | SC-TOR-004 的隔离半**未验证**。规格明文**不得以同 uid 对照代替**——本轮未做任何同 uid 或 1500/1501 替代对照 | 按 `wsl2-aifi45-v1` 重建隔离环境后真实运行（ADJ-024） |
| 3 | **4 个 Linux-only daemon 测试文件** | **本机从未编译** | `//go:build linux`，Windows 基线不编译 | 本机所有「skip=0 / 全绿」结论**不覆盖这些文件**；`TestChannelIsolationChild` 的 allowed-skip 是**源码推导** | 由 CI-linux 或 WSL 隔离入口真实编译运行后升级为「观测」 |
| 4 | **`make test` / `scripts/check.sh`** | **未执行** | 上游聚合入口依赖 Linux 工具链（U5 排除） | 不能声称上游聚合入口全绿 | 由真实 CI run 覆盖 |
| 5 | **`@multica/mobile` 包的 typecheck 与 lint** | **未执行** | 命令显式 `--filter=!@multica/mobile` | 10/10 与 7/7 **不含 mobile** | 如需覆盖须单独裁定范围 |
| 6 | **views 全量 vitest 在 ubuntu-latest** | **未执行** | 真实 CI 属 TC-CBE-005 | Windows 上存在 HEAD 既存的 506 文件并行负载 flake（ADJ-020）。**本轮实测 1 失败/6371 通过**，失败项 `chat-window-messages` 是已登记的具名成员（HEAD 基线同位置失败、另一次全量通过、本轮单文件重跑 4/4 exit 0）；**不能声称 CI 不受影响**，单次重跑也不足以测量 flake 率 | CI 接线后由 evidence 对账如实判定；若复现按新发现处理，**不得预先放宽门禁或加 retry 掩盖** |
| 7 | **管理员更新 `AIFIRST_TOOLS_READ_TOKEN`** | **未完成（外部依赖）** | 属管理员职责；本 change **SHALL NOT 读取、创建或轮换凭据** | `transitions-contract-check` job **未闭合**（TC-CCF-003） | 管理员按最小权限更新并推送后重跑该 job |
| 8 | **行覆盖率 / 分支覆盖率** | **豁免（`not_applicable`）** | 覆盖率采集目前只支持 pytest-cov；本 change 0 条 pytest check | **无覆盖率保证**，不是「覆盖率达标」 | 如需要须另行引入 Go/Node 覆盖率采集，属范围外 |
| 9 | **失败模式 `(c)(e)(h)(i)(m)(n)`** | **未执行** | **资源根无权威定义**（ADJ-044：14 vs 12 vs 8 vs 11/(a-k) 四处口径不一致，`ci.py` 只实现 8 个字母，`failure-check-report.md` 模板缺失） | **不能声称「14 类检查全量执行通过」** | 由 stdd 仓统一类别数与字母语义后再执行 |
| 10 | **`gofmt -w`** | **刻意未执行** | 工作树 2466 个 `.go` 中 2206 个 CRLF（`core.autocrlf=true`），执行会无关地翻转行尾 | 不引入全仓无关格式改动；已核实 `gofmt` 输出与去 CR 原文逐字节一致 | 保持现状；统一格式须单独裁定 |
| 11 | **tools 白名单下的 6 个测试** | **未在 CI 验证** | 修法在 tools 仓（ADJ-005，major 未决） | 若 S13 把 `MULTICA_CONTROLLED_SHELL_RULES` 指向 pin 的 `rules.json`，这 6 项会在 CI-linux **真实失败**。**未改 tools 白名单、未排除这 6 项** | 由用户裁定修法归属与 S13 接线范围 |

### 5.3 已知失败（断言原样保留，不放宽）

| 项 | 裁定 | 处置 |
|---|---|---|
| **SC-WSD-005 的 command 半句** | **R5 用户裁定：不在本 change 内修复** | **断言原样保留并登记为已知失败**；reservation 半句已修并由真库证明（`pass=3 fail=0 skip=0`）。CP-WSD-005 的 description 已按 R5 手工同步完整（132 字符） |
| **ADJ-028 reservation 非锁读 TOCTOU** | 只加 2 行英文注释声明边界 | **SQL 与锁语义一行未改**；`CreateReservationTx` 目前无生产调用方，648 禁新增 FK。是否加锁**待用户裁定** |
| **ADJ-042 parseArgs fail-open** | **用户裁定「ADJ-042 纳入本 change」→ 本轮已修** | `run-selection.mjs` 对未知参数**按名硬失败**（+3 行），新增 1 个测试函数；RED exit 1（1/0/1）→ GREEN exit 0（1/1/0），该文件 **14/14/0**、harness **173/173/0**。同目录 7 个含 `parseArgs` 的脚本**全部**已对未知参数抛错（实测 grep）。`ci.yml` 不含该调用，CI 路径本就受影响面为零；**未提交、未推送** |

---

## 6. 四个人工 TC 的闭合状态（**0 项已确认**）

| TC | 前置（原文摘要） | 状态 | 是否可确认 |
|---|---|---|---|
| **TC-CBE-005** | 「CI 的 backend-tests 在修复后的 `ci.yml` 下运行（需推送授权与 tools pin 可用，见 design U1）」 | **未执行** | **否**。无 run id / commit / job 结论可填（§1.1） |
| **TC-TOR-004** | 「`TestChannelIsolation` 经 WSL AIFI-ISO（root 加 `AIFI45_ISOLATION_PROFILE`），两个状态敏感探针经 run-selection 的 down/reapply 初始状态」 | **部分覆盖**：selection 半真实执行并通过；**隔离半 UNCOVERED** | **否**。规格要求「每项通过数不少于 1、skip 为 0」，隔离半无数据 |
| **TC-TOR-005** | 「change 的验收报告 `validation/acceptance-report.md`」 | **报告已生成（本文件），待人工逐项核对** | **否（尚未确认）**。`confirm_manual` 是计划级、全有或全无（§6.1）；**ADJ-047 后计划内只剩本项**，用户核对后即可单独确认，不再连带其他 3 项（已移交） |
| **TC-CCF-003** | 「管理员已按最小权限更新 `AIFIRST_TOOLS_READ_TOKEN`」 | **未闭合** | **否**。外部依赖未满足 |

**因此 CLI 覆盖判定恒为 0/19（ADJ-047 后；第 3/4 轮为 0/22）**，`verify` 的 `VERIFY_EXIT=1` 源于 `REVIEW_PENDING`——第 5 轮只列出 **TC-TOR-005** 一项（3 项已移交），**不是 CP 失败**。此前 0/22 的逐项说明作为历史保留。

### 6.1 人工确认的真实机制（**更正：不存在「只确认 TC-TOR-005」这条路径**）

本报告初稿在此处写「用户核对本文后，以同一 run id 执行 `stdd agent confirm …`」，**该措辞暗示可以单独确认 TC-TOR-005，是错的**。读 `stdd/cli/evidence.py` 的 `confirm_manual`（`:717-770`）实测：

- `:740` `manual = _manual_checks(plan)`，而 `_manual_checks`（`:697-699`）取的是**整个计划**里 `kind == "manual"` 且 `applicability == "required"` 的**全部**条目——本计划即 4 条，**无按 TC 选择的入参**。
- `:761-764` 一次把这 4 条**全部**追加为 `result: "manual-pass"`，共用同一个 `statement` 与 `statement_sha256`；`:765-768` 的 `record["manual"].checks` 同样列出全部 4 条。
- `:745-748` 同一 run 已有确认时，只有 `statement` 与 `subject` 完全相同才幂等返回，否则 `raise ValueError("本次 run 已有人工确认，拒绝静默覆盖")`——**不能分次补确认**。
- `:754-759` 还要求全部必需自动项已发布且 `result == "pass"`、`assertions_passed is True`。

**结论：`agent confirm` 是「计划级、全有或全无、一次性」的动作。** 只要 TC-CBE-005（真实 CI run）、TC-TOR-004（隔离半句）、TC-CCF-003（管理员 PAT）三项前置未闭合，调用它就等于**同时断言这三项也通过**，属伪造确认。因此：

- **本轮不执行任何 `stdd agent confirm`**，4 项人工 TC 一律保持未确认，CLI 覆盖判定保持 **0/22**。
- **TC-TOR-005 的验收证据由本文承担**：用户逐项核对本文（§6.2 清单）并在 Gate 3 给出确认原文，即为该文档类验收的人工审阅留痕；**不通过 CLI 的 `manual-pass` 记账**。
- 待三项外部前置全部闭合后，才可由用户以真实审阅原文一次性确认 4 项；届时若受审输入已变（`:735-739` 会重新快照并 `raise "受审输入自执行后已变化，需重新执行"`），须先重跑执行。

### 6.2 人工核对清单（供用户逐项打勾）

- [ ] §1：确认「真实 CI run = 0」如实，且未把本地等价验证当作 CI 通过；tools pin 已推送、multica 未推送
- [ ] §2.1：6 条真库 selection 的命令、退出码、pass/fail/skip 与实例 id 与原文一致
- [ ] §2.2：10 条 TAP 命令的**粒度限制**已如实声明（选定 run 不存 stdout），未编造精确通过数
- [ ] §2.3：`test-go.test.sh` 无 TAP 汇总行、`pnpm typecheck` 无测试计数，均未虚填
- [ ] §2.4 / §0：**18/18 与 0/19 两个数字并列**，含义各自说明，未互相冒充
- [ ] §3：C2 全量命令被明确标注为**另一次执行**，未冒充选定 run 的 CP 计数
- [ ] §3.3：typecheck/lint 为 **`--force` 真跑（Cached 0）**，缓存回放那次已如实标注并保留
- [ ] §3.3.1：views 全量 vitest **1 失败、exit 1，未报通过**；归因按名字对账，单文件重跑 4/4
- [ ] §3.4：覆盖率为**豁免**，明确「无覆盖率保证」
- [ ] §4：**未观测到 skip>0 的包**为实测结论；4 条 allowed-skips 是**声明排除**，其中 1 条为**源码推导**
- [ ] §5：11 项未覆盖/未执行项逐项标注，**无任何未执行项被标通过**
- [ ] §6：**在册人工 TC 只剩 TC-TOR-005 且未确认**（3 项已移交）；§6.1 已如实说明 `confirm_manual` 为**计划级全有或全无**，本轮**不执行任何 confirm**
- [ ] §6.3：旧 run 失效原因与新 run 整轮重执行、零回归证明如实
- [ ] §7：边界与授权声明与实测一致

### 6.3 为什么换 run id：旧 run 已失效，本轮为整轮重执行

| 项 | 实测 |
|---|---|
| **旧 run** | `7cd120df-d9d1-4f31-a9b5-e26b5a13606a`（18 条命令 CP 当时亦全 pass） |
| **失效原因** | `evidence.py:735-739` 在确认时**重新快照受审输入**；ADJ-042 修改了 `scripts/aifi45-disposable/run-selection.mjs` 与其测试文件，属声明输入范围，故旧 run 的输入指纹不再匹配，**不得沿用** |
| **另一处失效** | 依赖树被清理事故波及后重建（ADJ-045），旧 run 的执行环境已不存在，**旧结果不能代表当前环境** |
| **本轮处置** | 自行生成新 run id `dfb7aad8-7539-486b-aa59-297d57a87d1a`，**18 条命令 CP 整轮重跑**（含 views typecheck 与 6 条真库 selection），`agent verify` 与 `ci check-failures` 共用该 id，中间无其他 verify |
| **零回归证明** | 6 条真库 selection 的叶子计数 **16/2/1/23/1/3 = 46，fail 0，skip 0**，与旧 run **逐名同值**；harness 172 → **173**（+1 为 ADJ-042 新守卫），ci-scope **49/49** 不变 |
| **旧 run 产物的处理** | **保留不删**（`validation/runs/7cd120df…/`、`97da35cc…/`），作为历史留痕；本报告一切当前结论只引用新 run |

---

## 7. 边界与授权声明（本轮重新实测）

### 7.1 数据库与容器

| 项 | 实测 |
|---|---|
| 真库测试所用实例 | **全部 runner 自建的一次性 podman 实例**：`d979348e09b0`、`8c5ac051aaa9`、`9aaf08ec1a0c`、`1622bc487691`、`266f7910fdf5`、`65a73d2293eb`，输出均含 `released … remaining=0` |
| 是否连接 `localhost:5432` 旧库 | **否** |
| 是否操作旧 `multica-postgres` 容器 | **否** |
| 运行前后容器清单 diff | **IDENTICAL**（本轮 `diff podman-before-round2.txt podman-after-round2.txt` 无输出，逐字标记 `CONTAINER_LIST_IDENTICAL`） |
| 清单内容（逐字，本轮 `gate3-followup/podman-after-round2.txt`） | `multica-postgres Exited (0) 292 years ago`；`multica-backend Exited (0) 292 years ago`；`multica-pgdata`（卷） |
| 本轮结束时的只读复核 | 仍只有这 2 个旧容器且均 **Exited (0)**，**无残留一次性实例**；6 个一次性实例输出均含 `released … remaining=0` |
| 是否触碰卷 | **否**（卷仍只有既有 `multica-pgdata`，未创建、未删除） |
| 是否放宽 nonce 门禁 | **否**。`ci-provision.mjs` / `provision.mjs` 一行未改；`pass=16 fail=0 skip=0` |

### 7.2 凭据

- **未读取、未打印、未创建、未轮换任何凭据；未改仓库 secret。** secret 由管理员处理。
- 一次性库口令：`randomBytes(18)`、**job 级**、随服务容器销毁，**不复用于任何非一次性资源**；handle 与本 change 其他产物均不含明文口令。
- **唯一口径例外（ADJ-009，须一并呈报）**：`::add-mask::<角色口令>` 是 GitHub Actions 规定的遮蔽协议，runner 只遮蔽**它已见过的值**，故该命令本身必然先把口令送到原始 stdout。TC-CBE-001 的断言口径是「**除这一条 mask 命令外**，没有任何日志行携带角色口令或管理员口令」，**不是**「stdout 从头到尾不含口令」。若要求 stdout 全程无口令，须改用 runner 外部遮蔽机制，**超出本 change 范围，需用户裁定**。

### 7.3 仓库

| 仓库 | 本轮实测 | 处置 |
|---|---|---|
| **multica** | HEAD `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`、`main`、tracked **7336**、**22 `M` + 27 `??`、0 deleted** | 49 个文件（22 改 + 27 新）全属本 change；**未清理、未混入他人改动** |
| **tools** | HEAD = `origin/main` = `git ls-remote origin refs/heads/main` = **`e52b8081f159d581bf62f82447c76f818fc52426`**，`merge-base --is-ancestor` → **YES**，领先 **0** | **已按用户明确授权推送 `e52b808`**（ADJ-025）；**未改 pin 文件**；该仓 **6 处既有未提交改动未触碰、未夹带**。证据 `gate3-followup/tools-push-verified.txt` |
| **记录仓** | 存在大量他人未提交改动 | **不清理、不混入**；只写本 change 目录下记录 |
| **stdd 资源仓** | 用户明令不再改动 | **本 Agent 写入数 = 0**；全部 stdd 缺陷只登记不修（ADJ-036 由**用户本人**修改） |

### 7.4 授权

- **multica 的 Git 提交、推送、部署：均未执行**（HEAD = `origin/main` = `903a46c5ae9f`，49 个改动路径全在工作区），且**不从 Gate 确认自动推导授权**。本报告与 Gate 3 呈报**不构成**任何提交/推送/部署授权。
- **tools 的推送：已按用户明确授权执行**（原话「ADJ-025 授权执行推送 e52b808」），只推 `e52b808` 一个提交到 `origin/main`，**未夹带 tools 工作区另外 6 个未提交改动**。这是**独立授权**，不延伸到 multica。
- U5 已授权动作中，「推送触发 CI」（指 multica 推送以触发 Actions）与「管理员更新 PAT」**本轮均未行使**；「npm 安装 pg」以 `pnpm install --frozen-lockfile` 形式行使（**口径宽于字面，已在 ADJ-045 声明**，限于被忽略路径）。
- **U3**：S10 发现即上报，由用户裁定，未擅自扩大范围。
- **U4**：views typecheck 义务达成（0 错误）；本地 vitest **1 失败 / 6371 通过、exit 1，如实报告未报通过**，按名字对账归因为 HEAD 既存具名 flake，**先报告再裁定范围，未扩大范围**（未改生产代码/断言/timeout/retry/并行度，未加 skip）。
- **D2**：未开任何 append-only 触发器的删除例外；ADJ-014 的两张 retain 表 TRUNCATE 守卫按用户裁定补齐。
- **fork 规则**：新逻辑置于新文件，上游改动仅最小 `// AIFIRST:` 钩子，**代码注释用英文**，已按 `CUSTOM.md` 登记（**#317–#333 共 17 行**，每行 7 个未转义竖线 / 6 单元格，逐行字符扫描实测；#317–#332 逐字节未改），使用**真实 STDD change ID**，**未编造 CR 身份**（CR 索引记为「—（原生 STDD，非 CR）」）。
- **URL 纪律**：本轮**未调用任何需要 URL 的工具**（无 WebFetch/WebSearch/图像或站点类调用）。涉及网络的操作只有：①`git push` / `git ls-remote` 指向**已核实的真实远端** `https://github.com/OldBoy405/AI-First-tools.git`；②pnpm 自身从**官方 registry** `https://registry.npmjs.org/` 重新取包。**未替换为 routify 等任何临时代理地址**；esbuild 修复同样使用官方 registry。

### 7.5 事故与遗留提醒

- **外部删除事故**：C3 期间 multica 工作区被外部 C 盘清理删除（发现时仅 163 个业务文件、本 change **0/49**）。**立即停止**，未修复、未 `git init`、未 clone 覆盖、未删文件、未杀进程，并上报。用户报告的「已还原」经实测**不成立**（11:12:01 仍 163 文件 / 0/49），已如实报告差异。按用户裁定「**先护副本，再原地恢复**」执行，恢复后指纹核验 **22/22 numstat + 27/27 行数精确一致**，HEAD / tracked / status 全部回到基线。
- **⚠ 须持续呈报**：`D:\C_Cleanup_Backup_20261113\RESTORE.md` **§7 选项 C 把 D04 标为可删缓存**；**在恢复确认稳定前不得清理 D04**。三份副本：D04 原件（**全程未写入**）、`D:\multica-rescue-20261113`、C: 工作树。
- **事故的第二层损害（ADJ-045，本轮发现并修复）**：清理不仅删了 `node_modules`，还掏空了 **pnpm CLI 自身的切版 store**。全局 PATH 上的 pnpm 是 **11.22.0**，它按项目 `packageManager: pnpm@10.28.2` 自动切版，而切版目标链接目录是**空壳**（1307 个条目、无 `package.json`、`dist` 为空、只剩 `bin/*.cjs`），`store/v11/files` 仅 **48K**，故 `pnpm --version` 报 `VERSION_SWITCH_FAIL` / `spawnSync ENOENT`。**处置＝重命名隔离而非删除**（`hollow-backup-20261113` 保留可回滚），让 pnpm 从官方 registry 重新取包 → **10.28.2、exit 0**。**明确拒绝的替代方案**：装 corepack shim（会机器级遮蔽 PATH）、self-update（等于降级全局 pnpm）、关闭自动切版（会让冻结的 CP 命令在 pnpm 11 下执行）、改 CP 命令本身（属 Gate 2 冻结输入）。**未改 PATH、未改任何 pnpm 配置或仓库文件。**
- **修复后的残留义务已履行**：CP-CCF-002 的 views typecheck 与 6 条真库 selection 已随新 run id 整轮重跑（§6.3）；C2 全量 typecheck/lint 以 `--force` 真跑（§3.3）；views 全量 vitest 已重跑并如实记 1 失败（§3.3.1）。

---

## 8. 证据索引

路径相对 change 根 `projects/multica/changes/2026-11-12-fork-ci-test-evidence-trust/`。

| 类别 | 路径 |
|---|---|
| **选定 run 产物（第 5 轮）** | `validation/runs/add97e96-1676-4191-ae65-2ebd6524d585/tc-evidence.json`（`run_id` 同值；18 条 command，含 command/cwd/exit_code/result/assertions_passed；**无 stdout 字段**；`inputs` 823；`coverage_files: []`；artifact sha256 `c58c545d211d6e24…`） |
| | `validation/runs/add97e96-1676-4191-ae65-2ebd6524d585/agent-verification-report.md`（18 CP 各 `PASS (exit_code=0)`；**不嵌入 run id**，故哈希与第 3 轮相同，见 §0） |
| | `validation/runs/add97e96-1676-4191-ae65-2ebd6524d585/inputs/`（`agent-specs/` 5 个 capability YAML、`config.yaml`、`test-plan.md`＝**19 条 check 的新计划**） |
| **verify / ci 原文（第 5 轮）** | `validation/gate3-followup/agent-verify-scopeB.txt`、`ci-check-failures-scopeB.txt` |
| **容器清单（第 5 轮）** | `validation/gate3-followup/podman-after-scopeB.txt`（结束后实测两条旧容器仍 `Exited (0)`）；**运行前为控制台观察、未另存文件**，实测同值（IDENTICAL）。第 3 轮落盘对照见 `podman-before-round2.txt` / `podman-after-round2.txt` |
| **ADJ-042 / ADJ-025 / ADJ-045 证据** | `validation/gate3-followup/red-unknown-flag.tap`、`green-unknown-flag.tap`、`run-selection-after-fix.tap`、`harness-after-adj042.txt`、`ci-scope-after-adj042.tap`、`pin-reachability-order.txt`、`tools-push-verified.txt`、`pnpm-install-restore.txt`、`pnpm-cli-restore.txt`、`precheck-views-typecheck.txt`、`precheck-selection-identity.txt`、`podman-before.txt` |
| **全量质量日志（本轮，重建后）** | `validation/c2-quality-round3/pnpm-version.txt`、`pnpm-typecheck.txt`（缓存回放）、`pnpm-lint.txt`（缓存回放）、`pnpm-typecheck-force.txt`（**Cached 0/10**）、`pnpm-lint-force.txt`（**Cached 0/7**）、`views-vitest.txt`（**1 失败**）、`vitest-single-chat-window.txt`（**4/4 exit 0**） |
| **全量质量日志（重建前，保留不作当前结论）** | `validation/c2-quality/harness-full.txt`、`ci-scope.txt`、`typecheck-views.txt`、`typecheck-core.txt`、`pnpm-typecheck-after-fix.txt`、`pnpm-lint.txt`、`esbuild-install.txt`、`esbuild-rebuild.txt`、`agent-verify-round2.txt`、`ci-check-failures-round2.txt`、`inventory-before-round2.txt`、`inventory-after-round2.txt` |
| **C1 评审与修复** | `validation/c1-review/triage.md`、`red-crctl-alias.tap`、`green-crctl-alias.tap`、`mutation-crctl-alias.tap`、`mutation-ref-main-old-test.tap`、`red-ref-main-new-test.tap`、`green-ref-restored.tap`、`harness-after-both-fixes.txt`、`ci-scope-after-both-fixes.tap`、`crosscheck-env-present.txt`、`crosscheck-env-absent.txt`、`selections-crosscheck.json` |
| **C3 / C4 / C5** | `validation/c3-diff/README.md`（49/49）、`validation/c4-failure-modes/README.md`（8 项检查 / 2 命中 / 1 观察）、`validation/c5-experiences/`（EXP-2026-0006） |
| **切片证据** | `validation/s1-selection-decision/` … `validation/s13-ci-wiring/`（13 个目录） |
| **归属表** | multica `scripts/aifi45-disposable/test-ownership.json`（`entries` 5、`allowed-skips` 4） |
| **规格与计划** | `test-plan.md`（**在册 19 TC** = 18 command + 1 manual；3 个已移交见 §七；`:380-419` 附近的证据计划 fence 现为 **19 条 check**）、`canonical/specs/agent/*.yaml`（18 个 CP 的 action 原文）、`slices.md`、`tasks.md` |
| **调整记录** | `pending-adjustments.yaml`（**47 条**：26 已解决 / 21 未决；未决 major 5 条＝ADJ-005、ADJ-024、ADJ-038、ADJ-040、ADJ-046）、`design-adjustments.md`（C6 权威产物，§A/§D/§E 为后续 change 的取回点；ADJ-047 为本次范围收窄） |
| **移交包** | `validation/handoff/handoff-to-successor-change.md`（3 个场景 + 3 个 TC 原文、缺失前置、复现命令、后继 change 入口判据） |
| **测试报告** | `test-report.md`（§1–§12） |
| **旧 run（不可复用，保留留痕）** | `validation/runs/dfb7aad8-7539-486b-aa59-297d57a87d1a/`（**计划已变更，`_materials_match` 判失效**，见 §0）、`validation/runs/7cd120df-d9d1-4f31-a9b5-e26b5a13606a/`（受审输入已变 + 环境已重建，见 §6.3）、`validation/runs/97da35cc-fdac-4d9d-bbaa-60960538d76e/`（KeyError 崩溃） |

---

**报告结束。** 本报告如实记录（第 5 轮口径）：**真实 CI run 0 个**、**18 个命令 CP 全部 exit 0 / pass**（当前 run `add97e96…`，18 passed / 0 failed）、**CLI 覆盖判定 0/19**（18 ≠ 19，待 TC-TOR-005 人工确认后才可能变 19/19）、**1 个人工 TC（TC-TOR-005）尚未确认**、**3 个场景已移交后续 change 且本 change 不报通过**（TC-CBE-005 / TC-TOR-004 / TC-CCF-003）、**未覆盖/未执行项逐项标注**、**未观测到 skip>0 的包**（4 条 allowed-skips 为声明排除，其中 1 条源码推导）、**views 全量 vitest 1 失败 / 6371 通过、exit 1（未报通过）**、**typecheck 与 lint 以 `--force` 真跑 Cached 0、0 errors**。**任何未执行项均未标为通过。**