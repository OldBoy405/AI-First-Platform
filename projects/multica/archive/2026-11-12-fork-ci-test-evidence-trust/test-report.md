# 测试报告

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 项目：multica（业务仓 `C:\Users\GOBAO\Downloads\AI\multica`，HEAD=`903a46c5ae9fa6c3ee644fa4740d189d739dcc91`，branch main）
- 记录根：`C:\Users\GOBAO\Downloads\AI\AI First Platform\projects\multica`
- 报告时间：2026-11-13T18:37:51+08:00（第 3 轮更新：依赖树重建 + ADJ-042 修复后整轮重执行；**第 4 轮追加：按用户裁定执行 Gate 3 approve 被 CLI 拒绝批准，见 §1.1 与 ADJ-046**；**第 5 轮追加：用户裁定 B 路径后范围收窄、Gate 2 重签、以新 run 整轮重跑，见 §1.2 与 ADJ-047**）
- 阶段：Phase 3 BUILD / Part C 步骤 C7
- 模式：`thorough`，长程 `full_auto`
- **选定 run**：**`add97e96-1676-4191-ae65-2ebd6524d585`**（第 5 轮，本报告全部覆盖判定均引用此 run；同次执行证据见 §6）。旧 run `dfb7aad8-7539-486b-aa59-297d57a87d1a` 因 `test-plan.md` 变更按 `_materials_match` **失效不得沿用**（§1.2），更早的 `7cd120df…` 见 §6.5
- 依据：`test-plan.md`（Gate 2 于 `2026-11-13T18:33:41` 重签，**在册 19 条 check** = 18 command + 1 manual；3 个场景已移交见 §七）、`.stdd.yaml` 的 `slices_completed`、`validation/` 各阶段原始输出、`pending-adjustments.yaml`（47 条）、`design-adjustments.md`

> 口径声明：本报告只写**实测结果**。任何未执行、跳过或外部依赖未满足的检查一律标注 NOT EXECUTED / SKIPPED / UNCOVERED / 未确认，并给出边界原因，**不报通过**。`stdd canon verify` 2/2 与证据计划 dry-run 可预览**不代表业务测试已执行**。记录不等于批准或执行。

---

## 1. 结论摘要

| 维度 | 实测结果 | 含义 |
|---|---|---|
| 命令 CP 执行 | **18 passed, 0 failed** | 18 个 command CP 真实执行且全部通过（**第 5 轮 run `add97e96…`**，18:33:30 启动），`agent-verification-report.md` 已生成 |
| `agent verify` 退出码 | **VERIFY_EXIT=1** | 源于 **REVIEW_PENDING**（**仅 1 项** TC-TOR-005 待确认；3 个已移交项不再出现），**不是 CP 失败** |
| CLI TC 覆盖判定 | **0/19** | 同 run 的 `ci check-failures` 判「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」；`evidence.py:1033-1034` 要求条数严格相等，18 ≠ 19 → 整个 run 无效、覆盖归零 |
| 人工 TC | **1 项未确认 + 3 项已移交** | TC-TOR-005 待用户人工核对；TC-CBE-005 / TC-TOR-004 / TC-CCF-003 **已移交后续 change，本 change 不作通过声明**（ADJ-047） |
| 切片完成度 | **13/13 done** | 每切片均有 `tc_coverage` / `new_tests` / `verified_at` 证据 |
| 全量回归 | **173/173，fail 0，skipped 0，EXIT_CODE=0** | harness 目录全量（172 → 173，+1 为 ADJ-042 新守卫） |
| 全量 typecheck | **10/10 tasks，Cached 0/10，error TS 0，EXIT_CODE=0** | 依赖树重建后以 `pnpm typecheck --force` **真跑**（Time 1m20.851s）；缓存回放那次已如实标注并保留 |
| 全量 lint | **7/7 tasks，Cached 0/7，0 errors，EXIT_CODE=0** | `pnpm lint --force` 真跑（Time 29.296s），仅既有 warning |
| views 全量 vitest | **1 failed / 6371 passed（6372），VITEST_EXIT=1** | **不报通过**。失败项 `chat-window-messages` 为 HEAD 既存具名 flake（ADJ-020），单文件重跑 **4/4 exit 0**；`use-logout.test.ts` **2/2 ✓** |
| 覆盖率义务 | **not_applicable（豁免）** | 见 §3，**本报告不提供行/分支覆盖率保证** |
| 失败模式 | CLI 确定性子集 **8 通过 / 1 警告 / 0 跳过 / 1 错误**；C4 语义检查 **8 项完成、2 命中、1 观察** | 见 §7；「14 类」无权威逐项定义，未定义类别标注未执行（ADJ-044） |
| 设计调整 | **48 条**：26 已处置、22 未决（**6 major** + 16 minor） | 见 `design-adjustments.md`；未决 major＝ADJ-005、ADJ-024、ADJ-038、ADJ-040、**ADJ-046**、**ADJ-048**；ADJ-047（范围收窄）已处置 |
| **Gate 3 批准** | **⛔ 仍为 `pending`；批准被 stdd 缺陷挡住（ADJ-048）** | 用户已给出人工核对原文与 Gate 3 确认原文，但 `agent confirm` 抛 `KeyError: 'cp'`（`evidence.py:762`），19 条 check 缺第 19 条。**代码已提交 `371e53167`**；归档、推送未执行。详见 §1.3 |

**三个数字必须同时读，不得互相冒充**：`18/18` 是**命令 CP 的真实执行结果**（有报告与产物）；`0/19` 是**CLI 的覆盖判定**（run 因 1 项人工未确认而结构上不完整）；`19` 是**收窄后的在册 TC 数**（3 个场景已移交，不在本 change 分母内）。**不得以 18/18 冒充覆盖通过，不得把 0/19 说成执行失败，也不得把「移交」说成「豁免」或「通过」。**（ADJ-040 / ADJ-047）

### 1.1 ⛔ 第 4 轮状态（历史）：approve 被拒绝，流程未通过（ADJ-046）

用户已给出确认原文「以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。」，本 Agent 据此执行：

```
stdd gate approve 2026-11-12-fork-ci-test-evidence-trust --gate 3 --confirmed-by dialog \
  --evidence "以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。" \
  --run dfb7aad8-7539-486b-aa59-297d57a87d1a
```

**实测结果（原文留存 `validation/gate3-followup/gate3-approve-refused.txt`）**：

```
当前执行证据无效: 缺少或重复必需 check（当前运行未完成）
  Gate 3 拒绝批准：选定 run 证据不足。
APPROVE_EXIT=1
```

- **批准前无任何写入**：复跑后 `stdd gate status` 仍 **Gate 3 ⬜ pending**（Gate 1/2 保持 `2026-11-13T09:46:15` / `09:46:16`），`.stdd.yaml` 内 `grep selected_evidence` **零命中**。`current_phase` 仍 `build`，**不得进入 DELIVER**；`tasks.md` 14.10 **保持未勾选**。
- **根因（实读源码 + 实测解析冻结 fence，非推断）**：① `gate.py:815-822` 把 `_gate3_selected_evidence` 的 problems 作为批准前置，而其判据正是 `evidence.py:1033-1034` 的 `len(checks) == len(plan["checks"])` → **18 条命令 CP 全通过也判整个 run 无效**；② 22 条 check 的 `applicability` 取值集合实测**只有 `["required"]`**，4 条 manual 全为 required，故 `:1055-1060` 的 `not_applicable` 分支**无豁免出口**；③ `confirm_manual`（`:697-699/740/761-768`）**计划级全有或全无**、每条 `result` **硬编码 `manual-pass`**、`:748` 拒绝静默覆盖 → **CLI 无法表达「人工已审阅但未闭合」**。
- **因此「18/18 命令 CP 通过 + 4 项人工未闭合」这一真实状态在现行 CLI 下无法被批准。** 这**更正了 ADJ-040 的影响范围判定**：不只是覆盖指标归零，而是**硬阻断 Gate 3**。
- **未采取任何绕过手段**：**未调用 `stdd agent confirm`（4 项人工 TC 确认数 = 0）**、未改 stdd 仓（**本会话写入数 = 0**）、未改 `test-plan.md` 或任何 Gate 1/2 manifest 项、未伪造 evidence、**未把拒绝写成通过**。3 项外部前置未满足时确认即等于为未执行项断言通过，被用户「任何未执行、跳过或外部依赖未满足的检查，都不得报通过」与 Skill Gate 3 硬防线禁止。
- **三条合法路径（须用户裁定，AI 不自行选择）**：**A** 闭合 3 项外部前置（multica 提交+推送授权、管理员 PAT、WSL AIFI-ISO 四项前置安装，均超出 U5）后一次性如实确认 4 项 → **唯一不削弱任何义务的路径**；**B** 正式缩小本 change 范围、把 3 个场景**移交后续 change**（不是标豁免）并改 plan/canonical，**须重签 Gate 2**（`--reapprove` + 非空 evidence）→ 本会话授权边界内唯一可完成的路径；**C** 修 stdd 支持非 pass 人工结论 → **根因修复，但用户已明示 stdd 项不在本次完成**。完整评估见 `design-adjustments.md` ADJ-046 的三路径表。
- **后续**：用户已裁定 **B**，执行结果见 **§1.2**。

### 1.2 ✅ B 路径已执行：范围收窄 + 移交记账 + Gate 2 重签 + 新 run 重跑（ADJ-047）

用户裁定原文：「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」

**执行（全部实测）**：

1. **范围收窄**：`test-plan.md` §六 fence 移除 `TC-CBE-005` / `TC-TOR-004` / `TC-CCF-003` 三条 manual check，分母 **22 → 19**（18 command + 1 manual `TC-TOR-005`）；3 个 TC 的**原定义在原位以 HTML 注释保留**，新增 §七 可见移交表。实测 `tc_definition_ids` = **19**，与计划 check 集合**完全相等**（脚本比对无差集）。
2. **为什么不标 `not_applicable`**：`finish_run`（`evidence.py:666-671`）支持非 required 项记 `not_applicable`，但 `check_tc_coverage`（`ci.py:1174-1186`）以可见 TC 定义为分母——若保留定义而只标豁免，覆盖会显示 **22/22 = 100%**，等于把移交伪造成已覆盖。故必须同时移出定义与 check。
3. **canonical 未删**：`canonical/specs/code` 的 3 个 Scenario 原样保留（后继 change 的验收对象）；`stdd canon verify` 复跑 **2/2 通过**。
4. **移交包**：`validation/handoff/handoff-to-successor-change.md` 逐字保留 3 个 Scenario 与 3 个 TC 定义（脚本比对一致），并写明缺失前置、复现命令与后继 change 的 5 条入口判据。
5. **Gate 2 重签**：`--reapprove` + 用户原文 → `GATE2_EXIT=0`；`gate status` 显示 **Gate 2 ✅ 2026-11-13T18:33:41**、无 stale；manifest 20 项，`test-plan.md` 的 sha256 `3f7f0ea8…` 与当前文件一致。
6. **旧 run 失效**：`_materials_match` 比对当前 `test-plan.md` 与 run 留存快照 → `dfb7aad8…` 失效。以新 run **`add97e96-1676-4191-ae65-2ebd6524d585`** 重跑 18 条 command CP → **`Results: 18 passed, 0 failed`**；`VERIFY_EXIT=1` **仅因 `REVIEW_PENDING`**，待确认项只有 **`TC-TOR-005/main`**。
7. **同 run `ci check-failures`**：✅8 ⚠1 ⏭0 ❌1；❌ **TC 覆盖 0/19**（18 ≠ 19），理由「当前执行证据无效: 缺少或重复必需 check」——**结构原因同 ADJ-040**，须先 `agent confirm` 才能变 19/19；`CHECKFAILURES_EXIT=1`。原文 `validation/gate3-followup/ci-check-failures-scopeB.txt`。
8. **容器边界**：运行前后清单一致（`multica-backend`、`multica-postgres` 始终 `Exited (0)`，未触碰）；6 个一次性实例全部 `released … remaining=0`。

**当前状态：Gate 3 仍 `pending`。** 剩余步骤只有两步，且都需要用户：① 对 `validation/acceptance-report.md` 的实际核对原文；② 该原文入 `agent confirm` 后，以新口径给出 Gate 3 确认原文。**范围收窄不等于通过**：3 个场景在本 change 内未验证，已移交。

### 1.3 ⛔ 人工确认执行被 stdd 缺陷挡住（ADJ-048，major，未决）；代码已提交

**用户已给出**：核对原文「已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过」+ Gate 3 确认原文「以「命令 CP 18/18 + TC-TOR-005 人工核对 + 3 项移交」确认 Gate 3」，并授权收尾、提交、合并、归档、推送。

**执行 `agent confirm` 的结果（实测）**：

```
stdd agent confirm ci-backend-environment \
  --change 2026-11-12-fork-ci-test-evidence-trust \
  --run add97e96-1676-4191-ae65-2ebd6524d585 \
  --statement "已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过"
→ KeyError: 'cp'  (stdd/cli/evidence.py:762)
CONFIRM_EXIT=1
```

- **根因**：`evidence.py:20` 的 `_CHECK_FIELDS` 含 `cp`，`confirm_manual` 在 `:761-764` 用 `item[key]` 强取；而 manual 计划项按本 change 约定**没有 `cp`**（`test-plan.md` §六「manual 不绑定 CP」）。**任何** manual 确认都会崩，与本 change 数据无关。这与 **ADJ-036**（`agent.py:206` 同类 `KeyError: cp`，已由用户自行修为 `item.get("cp")`）是同一类缺陷的**第二处实例**。
- **无任何写入**：崩溃在 `_publish` 之前；复核 run 仍 **18 条 checks、`manual` = null**，无第二份 run，`test-plan.md` 未改。**未绕过**：未改 stdd（写入 0）、未手写 `tc-evidence.json`、未伪造确认。
- **因此 Gate 3 仍 `pending`**：19 条 check 缺第 19 条，`gate approve --gate 3` 必被 `gate.py:815-822` 拒绝。**归档、推送均未执行。**

**代码提交（用户授权，已完成）**：`371e53167` `feat(ci): make fork CI and test evidence trustworthy (STDD 2026-11-12-fork-ci-test-evidence-trust)`，**49 files changed, 4848 insertions(+), 69 deletions(-)**，工作树干净；提交后重跑 `ci check-failures` 仍报 **18 ≠ 19**（输入校验通过，说明提交未改变冻结输入）。**分支合并不适用**：改动直接落在 `main`，无独立 change 分支。**推送未执行**（按用户给定顺序，推送在归档之后；两者都被 ADJ-048 挡住）。

---

## 2. TC 覆盖率：planned vs actual

### 2.1 计划口径（Gate 2 **2026-11-13T18:33:41 重签**，实测解析 `stdd-evidence-plan-v1` 块）

- check 总数 **19**，每个在册 TC 有且仅有一条 check。
- `kind` 分布：**command 18 / manual 1**。
- 唯一的 manual 是 **`TC-TOR-005`**（验收报告人工核对），不绑定 CP。
- 18 条 command 对应的 TC（实测去重后 18 个）：
  `TC-CBE-001`、`TC-CBE-002`、`TC-CBE-003`、`TC-CBE-004`、`TC-CCF-001`、`TC-CCF-002`、`TC-SEL-001`、`TC-SEL-002`、`TC-SEL-003`、`TC-SEL-004`、`TC-TOR-001`、`TC-TOR-002`、`TC-TOR-003`、`TC-WSD-001`、`TC-WSD-002`、`TC-WSD-003`、`TC-WSD-004`、`TC-WSD-005`。
- **已移交（不在本计划、不计入分母）**：`TC-CBE-005`（真实 CI run）、`TC-TOR-004`（WSL 隔离）、`TC-CCF-003`（管理员 PAT）。原文见 `test-plan.md` §七 与 `validation/handoff/handoff-to-successor-change.md`（ADJ-047）。
- **口径变更说明（原文保留）**：ADJ-047 之前为 22 条（18 command + 4 manual，上述 3 项 + TC-TOR-005）；用户裁定 B 路径后收窄为 19 条，Gate 2 已重签。

### 2.2 实际口径（三个数字，各有含义，不可混用）

| 口径 | 数值 | 来源与含义 |
|---|---|---|
| **CLI 覆盖判定（权威门禁口径）** | **0/19** | 第 5 轮 run 的 `ci check-failures` 原文（`ci-check-failures-scopeB.txt`）。证据问题为「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」。**这是条数严格相等导致的整 run 无效（18 ≠ 19，缺 TC-TOR-005 的人工结论），不是 18 个 TC 没跑** |
| **命令 CP 真实执行** | **18/18 通过** | 同 run `tc-evidence.json` 实测 18 条、全部 `kind=command`、全部 `result=pass`、18 个不同 TC；`agent-verification-report.md` 已生成 |
| **切片级 tc_coverage 之和** | **19/19** | `.stdd.yaml` 13 个切片的 `tc_coverage` 分子之和（见 §4）。**19 = 18 个 command TC + `TC-TOR-004`** |

**切片级 19/19 与计划级 19 的 19 不是同一个 19，必须如实说明**：切片级来自 S13 的 `tc_coverage: 2/2`，其中计入 `TC-SEL-004` 与 **`TC-TOR-004`**；而 `TC-TOR-004` 现已**移交**（ADJ-047），不在 19 条计划分母内、其 WSL 隔离半句仍 **UNCOVERED**（ADJ-024）。故切片级 19/19 **不等于**计划级通过，更不等于 CLI 覆盖通过。**本报告不以任何切片级数字冒充计划级或门禁级覆盖。**

### 2.3 人工 TC 的逐项状态（1 项待确认 + 3 项已移交）

| TC | 前置 | 状态 | 说明 |
|---|---|---|---|
| TC-CBE-005 | 真实 CI run（推送触发） | **已移交（ADJ-047）** | 推送 multica 须单独授权并消耗私有库 Actions 额度（U5），**本 change 未授权、未推送 multica**；管理员 PAT 仍未更新。tools pin 前置**已闭合**（`e52b8081f159` 已推送，ADJ-025 resolved）。移交包 §7.1 |
| TC-TOR-004 | WSL AIFI-ISO 独立入口 | **已移交（ADJ-047）** | ADJ-024：4 项前置缺失；U5 只授权启动 WSL，不等于授权其余前置。用户已采纳「保持 UNCOVERED」。移交包 §7.2 |
| TC-TOR-005 | 验收报告 | **未确认（报告已生成，待用户人工核对原文）** | `validation/acceptance-report.md` 已按第 5 轮 run 更新（§0 / §2.1′ / §2.4′）。**确认即等于对报告整体作 manual-pass 断言**，故必须由用户实际核对后提供原文 |
| TC-CCF-003 | 管理员更新 PAT | **已移交（ADJ-047）** | 外部动作；凭据不可读取、不得创建或修改，secret 由管理员处理。移交包 §7.3 |

`stdd agent confirm` 写入的 `result` 固定为 `manual-pass`（`evidence.py:763`，覆盖判定在 `:1071`），**确认即等于断言通过**，故不得为凑覆盖而伪造确认。

**机制说明（本轮复查，未变）**：`confirm_manual`（`evidence.py:717-770`）取的是 `_manual_checks(plan)`（`:697-699`）——**整个计划**的全部必需 manual 条目，**无按 TC 选择的入参**；`:761-764` 一次把全部条目写为 `manual-pass` 并共用同一 `statement`；`:745-748` 拒绝同一 run 的第二次不同确认。范围收窄后 `_manual_checks` 只剩 **TC-TOR-005 一条**，因此本轮若确认，断言的正是「验收报告已人工核对」这一件事，不再牵连其他 3 项。**本轮迄今不执行任何 `agent confirm`，确认数 = 0**。

---

## 3. 覆盖率义务状态

- **状态：豁免（`not_applicable`）**，不是 SKIP，也不是测量通过。
- 计划声明原文（`test-plan.md:388` 与证据计划 `coverage` 字段，两处一致）：
  - `applicability`: `not_applicable`
  - `reason`: 「被测对象为 Go、Node、CI 配置与前端类型检查，覆盖率采集目前只支持 pytest-cov；项目配置 `quality.coverage.enabled=false`」
- CLI 复核：选定 run 的 `(j)` 判 **PASS**，原文「已声明无覆盖义务: 被测对象为 Go、Node、CI 配置与前端类型检查，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false」。
- **保证边界（如实声明）**：本 change **无行覆盖率/分支覆盖率保证**。质量保障来自 22 条 TC 的断言、13 个切片的 per-slice 验证、173 项 harness 全量回归、变异验证（RED→GREEN→按原字节还原）与 C1/C3/C4 的人工与语义审查，**不来自覆盖率数字**。

---

## 4. 每切片验证状态（13/13）

数值逐字取自 `.stdd.yaml` 的 `phases.build.slices_completed`；TC 映射取自 `slices.md:43-55`。

| 切片 | status | tc_coverage | new_tests | verified_at | 覆盖的 TC |
|---|---|---|---|---|---|
| 1 | done | 3/3 | 18 | 2026-11-12T16:56:29 | TC-SEL-001, TC-SEL-002, TC-SEL-003 |
| 2 | done | 1/1 | 15 | 2026-11-12T17:21:27 | TC-CBE-003 |
| 3 | done | 1/1 | 11 | 2026-11-12T17:48:04 | TC-CBE-004 |
| 4 | done | 1/1 | 20 | 2026-11-12T18:47:54 | TC-TOR-001 |
| 5 | done | 2/2 | 30 | 2026-11-12T19:35:48 | TC-TOR-002, TC-TOR-003 |
| 6 | done | 1/1 | 26 | 2026-11-12T20:05:21 | TC-CBE-001 |
| 7 | done | 1/1 | 28 | 2026-11-12T20:51:44 | TC-CBE-002 |
| 8 | done | 1/1 | 1 | 2026-11-12T21:29:21 | TC-WSD-001 |
| 9 | done | 3/3 | 25 | 2026-11-12T23:01:31 | TC-WSD-002, TC-WSD-003, TC-WSD-004 |
| 10 | done | 1/1 | 8 | 2026-11-13T00:22:40 | TC-WSD-005 |
| 11 | done | 1/1 | 15 | 2026-11-13T00:48:42 | TC-CCF-001 |
| 12 | done | 1/1 | **0** | 2026-11-13T01:32:59 | TC-CCF-002 |
| 13 | done | 2/2 | 4 | 2026-11-13T02:34:17 | TC-SEL-004, **TC-TOR-004（manual，隔离半句 UNCOVERED）** |
| **合计** | 13 done | **19/19** | **201** | — | 19 个不同 TC（含 1 个 manual） |

- CLI 复核：选定 run 判 **「13 个切片均有验证证据」PASS**。
- **长程约束 #3 偏离（如实登记，不掩盖）**：S12 `new_tests: 0`。原因是 TC-CCF-002 在锁定证据计划里是 command 型，断言对象是 `tsc` 退出码与错误码计数，不是测试函数；另造冗余测试会把形式置于证据实质之上。已登记 **ADJ-019**（minor，未决），并写入 `phase-context.md` Slice 12 与 `.stdd.yaml`，**未报「B3.4 三项全过」**。`slices.md:57` 的规划期断言「每个切片都有 >0 新增自动化测试」被实测证伪，**原文保留并在 `slices.md:59` 标注 C1 更正**。
- **约束 #5 降级未触发**：条件是**连续 3 切片**无新增测试；实测 S11=15、S12=0、S13=4，不构成连续 3 次。
- **第三轮修复记录：无。** 实测 `phase-context.md` / `tasks.md` / `slices.md` 中「第三轮」零命中，13 个切片均未进入第三轮修复，故**未发生 strong 档派发，也无「未升档」记录**。本节按 Skill 要求如实写明「无第三轮修复」，不编造档位或派发事实。

---

## 5. 全量质量检查（C2）

### 5.1 已执行并通过（**本轮＝依赖树重建后重测**，`validation/c2-quality-round3/`）

| 命令 | 实测结果 | 退出码 | 证据 |
|---|---|---|---|
| harness 目录全量 `node --test` | **tests 173 / pass 173 / fail 0 / cancelled 0 / skipped 0 / todo 0**，duration 2584.8845 | **0** | `validation/gate3-followup/harness-after-adj042.txt:174-181` |
| `node --test scripts/ci-scope.test.mjs` | **tests 49 / pass 49 / fail 0 / skipped 0** | **0** | `validation/gate3-followup/ci-scope-after-adj042.tap:297-304` |
| `pnpm --filter @multica/views typecheck` | 通过，**0 条 TS6059** | **0** | 选定 run 内 CP-CCF-002；重建后预检 `validation/gate3-followup/precheck-views-typecheck.txt` |
| **全量** `pnpm typecheck --force` | **Tasks 10 successful / 10 total，Cached 0 / 10，`grep -c "error TS"` = 0**，耗时 **1m20.851s** | **0** | `validation/c2-quality-round3/pnpm-typecheck-force.txt`（末 4 行） |
| **全量** `pnpm lint --force` | **Tasks 7 successful / 7 total，Cached 0 / 7，7 个包全部 0 errors**（warning：ui 3、core 2、views 21），耗时 **29.296s** | **0** | `validation/c2-quality-round3/pnpm-lint-force.txt:53`、`:72`、`:121` |

**`--force` 的必要性（口径写明，不冒充真跑）**：本轮先按配置原样跑 `pnpm typecheck` / `pnpm lint`，两者均为 **`Cached: 10 cached, 10 total` / `7 cached, 7 total`、`>>> FULL TURBO`**，即**缓存回放、未真正执行 tsc/eslint**。故追加 `--force`（由 pnpm 透传给 turbo，**root script 未改**）取得 Cached 0 的真实执行。**两次日志都保留**：`c2-quality-round3/pnpm-typecheck.txt`、`pnpm-lint.txt`（回放）与 `*-force.txt`（真跑）。

**重建前的旧值（保留原记录，已被上表取代）**：harness 172/172（`c2-quality/harness-full.txt:173-181`）、ci-scope 49/49（`ci-scope.txt:297-305`）、views typecheck 0 错误（`typecheck-views.txt:6`）、core typecheck 通过（`typecheck-core.txt:6`，本轮由全量 turbo 10/10 覆盖）、全量 typecheck 10/10 Cached 0 耗时 1m19s（`pnpm-typecheck-after-fix.txt:73-77`）、全量 lint 7/7 Cached 0 耗时 48.35s（`pnpm-lint.txt:125-129`）。

### 5.1.1 已执行但**未通过**（如实记录，不报通过）

| 命令 | 实测结果 | 退出码 | 证据 |
|---|---|---|---|
| `pnpm --filter @multica/views test`（`vitest run`） | **Test Files 1 failed \| 505 passed (506)；Tests 1 failed \| 6371 passed (6372)**，Duration 199.70s | **1** | `validation/c2-quality-round3/views-vitest.txt:8707`、`:8727-8730` |
| 同上，单文件重跑 `vitest run chat/components/chat-window-messages.test.tsx` | **Test Files 1 passed (1)；Tests 4 passed (4)**，Duration 1.81s | **0** | `validation/c2-quality-round3/vitest-single-chat-window.txt` |

**唯一失败项**：`chat/components/chat-window-messages.test.tsx > floating chat message lifetime > follows immediately on open, stops during exit, then reads new data on reopen`，`AssertionError: expected 1 to be +0`，`:84:25`（`expect(observers()).toBe(0)`）。

**归因（按名字对账，不笼统归为上游 flake）**：①**同名同行在 HEAD 基线已失败**（`validation/s12-views-typecheck/ab/views-vitest-head.txt:9366`、`:9375`，该次两个 S12 文件均还原）；②**另一次全量运行中通过**（`s12-views-typecheck/full/views-vitest.txt:7873`），`s12-views-typecheck/README.md:181` 已将其列入「仅 HEAD 失败」；③**本轮单文件重跑 4/4 exit 0**；④**测试总数 6372 / 506 与 ADJ-020 两次全量完全相同**，本 change 未增删 views 测试。⑤本 change 义务项 `auth/use-logout.test.ts` **✓ 2 tests**（`views-vitest.txt:8161`）。

**结论**：属 **ADJ-020 已登记的 HEAD 既存负载敏感 flake 的具名成员**，非本 change 引入。**差异如实标注**：本轮形态是 `AssertionError`，与 ADJ-020 记录的以 `Test timed out in 5000ms` 为主不同，不声称形态一致。**未确立**：单次重跑不足以测量 flake 率；未在 ubuntu-latest 跑过，不能声称 CI 不受影响。按 **U4** 未改任何生产代码/断言/timeout/retry/并行度、未加 skip 或排除，留为未决发现。

- **全量 typecheck 的历史失败如实保留**：首轮 `pnpm typecheck` **exit 1**，根因是本机 esbuild 平台二进制缺失（`@multica/web:mdx`、`@multica/docs:mdx` 在 `generateBinPath` 抛错，turbo 早退 0 successful / 5 total，**error TS 计数 0**，失败发生在任何 TS 编译之前）。`apps/` 在本 change 改动文件数为 **0**，**非本 change 回归**。`pnpm rebuild esbuild` 实测为**空操作**（exit 0 但四项产物无变化），**不以退出码 0 当作修好**。经用户裁定「授权修 esbuild 二进制后重跑」后执行 esbuild 自带 postinstall（`node install.js`，官方 `registry.npmjs.org`，**未手写或替换任何下载地址**），修复只落在 `esbuild/lib/downloaded-@esbuild-win32-x64-esbuild.exe`（10617344 字节）；`package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml` 的 git 差异为空、mtime 仍 2026-10-21。详见 **ADJ-039**（已处置）。

### 5.2 未执行（NOT EXECUTED / SKIPPED，不报通过）

| 检查 | 状态 | 边界原因 |
|---|---|---|
| `make test` 全量 | **NOT EXECUTED** | `ensure-postgres.sh:71-72` 会 `docker compose up -d postgres` 连 **localhost:5432 旧库**，违反「只用 runner 自建一次性 podman 实例、不操作旧 multica-postgres 容器」 |
| `bash scripts/check.sh` | **NOT EXECUTED** | `check.sh:119` / `:129` 会启动 backend 与 web，属会打断在跑服务的动作，**未获授权** |
| 4 个 Linux-only daemon 文件的编译与运行 | **SKIPPED（本机不可编译）** | `//go:build linux`，Windows 基线不编译；真实证明属 WSL AIFI-ISO 独立入口（ADJ-024，隔离半句 UNCOVERED） |
| 真实 CI run（TC-CBE-005） | **SKIPPED** | **multica 推送须单独授权**并消耗私有库 Actions 额度，本轮未授权、未推送 multica。tools pin 前置**已闭合**（`e52b8081f159` 已推送 origin，ADJ-025 resolved） |
| 管理员 PAT 更新（TC-CCF-003） | **SKIPPED** | 外部动作，凭据不可读取、不得创建或修改 |
| `gofmt -w` | **未执行（刻意）** | 工作树 2466 个 `.go` 中 2206 个为 CRLF（`core.autocrlf=true`），`gofmt -l` 点名属既有现象，未触碰的 `cmd/migrate/main.go` 同样被点名；实测 gofmt 输出与去 CR 原文逐字节一致，故**不做全仓格式化以免混入无关改动** |

---

## 6. 同次执行证据（选定 run）

> **本轮口径（2026-11-13 第 5 轮）**：选定 run 为 **`add97e96-1676-4191-ae65-2ebd6524d585`**，`agent verify` 与 `ci check-failures` 使用同一值、之间未插入其他 `agent verify`。原文见 `validation/gate3-followup/agent-verify-scopeB.txt`（18 passed / 0 failed；`VERIFY_EXIT=1` 仅因 `REVIEW_PENDING`，仅 `TC-TOR-005`）与 `ci-check-failures-scopeB.txt`（✅8 ⚠1 ⏭0 ❌1；覆盖 **0/19**；`CHECKFAILURES_EXIT=1`）。结论与数字见 §1.2。
> **§6.1–§6.4 为第 3 轮 run `dfb7aad8…` 的实测记录（历史，已失效）**，保留用于对照；其中「22 条」口径与「4 项人工」均已随 ADJ-047 变更，不得当作当前证据。

**第 3 轮 run id（历史）：`dfb7aad8-7539-486b-aa59-297d57a87d1a`** —— 同一值分别传给 `stdd agent verify` 与 `stdd ci check-failures`，两者之间未再跑别的 `agent verify`。

### 6.1 `agent verify` 原文结论（`validation/gate3-followup/agent-verify-round3.txt`，末 10 行）

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

**`VERIFY_EXIT=1` 的原因是 REVIEW_PENDING（4 项人工待确认），不是任何 CP 失败。**

### 6.2 `ci check-failures` 原文结论（`validation/gate3-followup/ci-check-failures-round3.txt`）

```
  ✅ 通过: 8      ⚠ 警告: 1      ⏭ 跳过: 0      ❌ 错误: 1
  自动化检查覆盖: 10/10 项
CHECKFAILURES_EXIT=1
```

错误项原文：

```
✗ TC 当前执行覆盖不足: 0/22。缺失: TC-CBE-001, TC-CBE-002, TC-CBE-003, TC-CBE-004, TC-CBE-005...；
  证据问题: 当前执行证据无效: 缺少或重复必需 check（当前运行未完成）
```

通过项含 `(l) Anchoring: L4 >= L4`、`(j) 已声明无覆盖义务`、`(k) 契约一致 (5 capabilities)`、`13 个切片均有验证证据`；警告项为 `(b) 范围蔓延: 37 个文件可能超出声明范围`（口径缺陷见 ADJ-041）。

### 6.3 run 产物实测（本会话复核，非引用记忆）

| 项 | 实测 |
|---|---|
| `validation/runs/dfb7aad8…/` 内容 | `agent-verification-report.md`、`inputs/`、`tc-evidence.json` |
| `tc-evidence.json` 的 `run_id` | **`dfb7aad8-7539-486b-aa59-297d57a87d1a`**（与目录名、两条 CLI 命令所用值一致） |
| `tc-evidence.json` 条数 | **18** |
| `kind` 分布 | **command 18**（无 manual 条目） |
| `result` 分布 | **pass 18**（无 fail、无 skip） |
| 不同 TC 数 | **18** |
| `inputs` 快照项数 | **823** |
| `coverage_files` | **`[]`** |
| artifact | `agent-report` → 本 run 的 `agent-verification-report.md`，sha256 `c58c545d211d6e2465350a3781580acbf4742ac66f38f68dcc7a3f0ea52506b5` |
| **产物哈希与旧 run 相同的原因** | 该报告正文只有 18 行 `CP-xxx: PASS (exit_code=0)`，**不嵌入 run id**（实测 `grep -c "dfb7aad8\|7cd120df"` → **0**），两轮 18 条结论相同故逐字节相同。**区分依据是 `run_id` 字段与目录名，不是哈希**；不是复制旧产物 |
| 容器清单前后 diff | **IDENTICAL**（本轮实跑 `diff podman-before-round2.txt podman-after-round2.txt`，无输出，标记 `CONTAINER_LIST_IDENTICAL`） |
| 6 个一次性实例 | `d979348e09b0`、`8c5ac051aaa9`、`9aaf08ec1a0c`、`1622bc487691`、`266f7910fdf5`、`65a73d2293eb`，均 `released … remaining=0` |
| 真库叶子计数 | **16/2/1/23/1/3 = 46，fail 0，skip 0**，与上一轮**逐名同值**（零回归） |

### 6.4 inputs 边界（分记声明与工具快照，并更正一处无效判据）

- **计划声明的 inputs：11 条，实测全部 `root=project`**，无一条指向 change 目录或其产物：
  `scripts/aifi45-disposable`、`scripts/test-go.sh`、`scripts/test-go.test.sh`、`scripts/ci-scope.mjs`、`scripts/ci-scope.test.mjs`、`.github/workflows/ci.yml`、`.github/ci-paths.json`、`server/internal/governance`、`server/internal/handler`、`server/cmd/server`、`packages/views/auth`。
- **CLI 自身快照目录 `inputs/` 的实测内容**：5 个 agent spec YAML、`config.yaml`、`test-plan.md`。这是工具行为，**不由调用方注入**。
- **判据更正（如实记录）**：本会话最初用「`inputs` 下路径是否含 change 名」作判据，测得 0 命中；但该判据**只能证明路径字符串不含 change 名，不能证明来源**（快照文件不带原路径前缀）。故**不以该 0 命中作为「inputs 不含 change 产物」的证据**，改为以上「声明 11 条全为 project 路径」作为可核验依据。

### 6.5 旧 run 不得沿用（两个旧 run，各有失效原因）

| 旧 run | 失效原因 | 处置 |
|---|---|---|
| `97da35cc-fdac-4d9d-bbaa-60960538d76e` | `agent.py:206` 对 manual 条目抛 `KeyError: cp`，**0 个 CP 执行、覆盖 0/22、无 `agent-verification-report.md`**。该缺陷由**用户自行在 stdd 侧修复**为 `item.get("cp")`（本会话只读核实，写入数 0） | 保留留痕，**0/22 不得沿用为通过**（ADJ-036） |
| `7cd120df-d9d1-4f31-a9b5-e26b5a13606a` | 当时 18 条命令 CP 亦全 pass，但此后**两处变化使其失效**：①ADJ-042 修改了 `scripts/aifi45-disposable/run-selection.mjs` 与其测试文件，属声明输入范围，`evidence.py:735-739` 会重新快照受审输入并拒绝沿用；②依赖树被清理事故波及后重建（ADJ-045），**旧执行环境已不存在** | 保留留痕，**不得沿用、不得与新 run 混算**；本轮以新 run `dfb7aad8…` **整轮重跑 18 条命令 CP** |

**本轮重执行的零回归证明**：6 条真库 selection 叶子计数 **16/2/1/23/1/3 = 46，fail 0，skip 0**，与旧 run 逐名同值；harness **172 → 173**（+1 为 ADJ-042 新守卫）；ci-scope **49/49** 不变；容器清单前后 **IDENTICAL**。

---

## 7. 失败模式检查

### 7.1 CLI 确定性子集（选定 run，逐项原文）

| 检查 | 结果 | 原文要点 |
|---|---|---|
| (a) 必需文件 + Spec 文件存在 | **PASS** | 所有必需文件存在 + Spec 文件存在 |
| (b) 范围蔓延 | **WARN** | 「37 个文件可能超出声明范围 (CUSTOM.md, packages/core/package.json, packages/views/auth/use-logout.test.ts...)」——**该 WARN 不可采信**，四处口径缺陷见 ADJ-041；真实范围已手工核对 **49 文件（22 改 + 27 新）全部可追溯** |
| (d) TC-ID 唯一 | **PASS** | 22 个 |
| (f) 所有 THEN 含 SHALL | **PASS** | — |
| (g) AND 数量正常 | **PASS** | — |
| (j) 覆盖率义务 | **PASS** | 已声明无覆盖义务（`not_applicable`，理由见 §3） |
| (k) 契约一致 | **PASS** | 5 capabilities |
| (l) Anchoring | **PASS** | **L4 >= L4**（按裁定 B 从 L3 升级并填实 11 条真实基准，ADJ-035） |
| 切片验证证据 | **PASS** | 13 个切片均有验证证据 |
| TC 当前执行覆盖 | **FAIL** | **0/19**，证据无效（条数严格相等，18 ≠ 19，缺 TC-TOR-005 人工结论），见 §2.2 与 ADJ-040 |

合计 **8 通过 / 1 警告 / 0 跳过 / 1 错误**，自动化检查覆盖 **10/10** 项。

### 7.2 C4 语义检查（逐项实读代码与目录取证，无占位符）

依据 `validation/c4-failure-modes/README.md`，**8 项检查完成**：

| 类别 | 判定 | 关键取证 |
|---|---|---|
| EXP-2026-0001 常量 id 多链写入 | **PASS** | 649 迁移只新增两个语句级 `BEFORE TRUNCATE` 触发器，未引入唯一键或 id；新增行为测试随机 uuid 命中 27 + 3 处；retention 测试是纯目录/schema 测试（uuid 零命中已实读确认，非漏测） |
| EXP-2026-0002 序列化锁前的 check-then-act | **命中 1（已申报限制）** | `execution_control_reservation.go:88-96` 非锁读 `SELECT EXISTS`，全函数 grep `pg_advisory\|Lock\|FOR UPDATE` **零命中**；代码注释已主动申报，SC-WSD-005 不要求并发场景。**未命中**：`workspace.go` 新增 sweep 在 `LockWorkspaceForDelete`(:1141) 行锁**之内**，属正确设计 |
| EXP-2026-0003 多行输出只取首行 | **PASS** | `ci-evidence.mjs:110-119` 取 `[0]` 前有 `length===0` 与 `length>1` 两道守卫（正是本经验要求的 fail-closed 修法）；`:51-52` 解析失败**抛错硬失败** |
| EXP-2026-0004 清理只覆盖成功路径 | **新增代码 PASS + 命中 1（继承缺口）** | `run-selection.mjs` 三处 `finally`(:112/:155/:189)、CI Drop 步骤 `if: always()`、drop 前从服务器重读 marker 校验归属。**继承缺口**：`provision.mjs createDisposableDatabase` 部分失败只 `admin.end()` 不 drop 已建资源 → `HANDLE_ENV` 未写入 → down 走 no-op → 遗留 role+database；该文件**不在本 change 49 文件内**，影响被 job service-container / podman 实例销毁**收敛在单次生命周期内** |
| EXP-2026-0005 复制的身份检查只测一个拒绝分支 | **PASS（强于最低口径）** | 两份各 214 行、条件表 **11 条**且有 `len(conditions)!=11` 硬断言；`nonce-format` 再分 3 子例；双阳性对照；`changedIdentityColumns`+`slices.Equal` 断言只有目标列被退化。**计数陷阱已排除**：`grep -c 't\.Run('`=2 是循环驱动，非只有 2 个用例 |
| 锚定缺失 | **PASS** | L4，11 个锚点逐一核实为 tracked 文件；`ci.py:1186-1222` 只比较 level；Gate 2 已按裁定重签 |
| Agent CP 失败 | **命令 CP 无失败** | 18/18 通过（第 5 轮 run `add97e96…`）；`VERIFY_EXIT=1` 源于 REVIEW_PENDING（待确认项仅 TC-TOR-005）。**覆盖判定另计 0/19，不报通过** |
| 跨系统不一致 | **PASS** | canonical YAML ↔ `specs/*/spec.md` ↔ `test-plan.md` ↔ `CUSTOM.md` 三表 ↔ 实际代码逐项核对；CUSTOM.md 列数与表头一致，5 行多余竖线全为已转义 `\|`。**本轮按 #333 加入后重测 17 行**（`CUSTOM.md:1085-1101`）：每行**未转义竖线恰好 7 个 / 6 单元格**，含转义竖线的仍是同样 5 行（#319/#322/#329 各 1、#331/#332 各 2，共 7 处），#333 为 7/0；M31 表头与汇总均为 `#317–#333 / 17` |

**另有 1 项公开缺口**：证据覆盖结构不完整（**0/19**，18 ≠ 19），**不报通过**（ADJ-040）。

**1 项既有行为观察项（非本 change 引入，不立 ADJ）**：`run-selection.mjs:82` `catch { continue; }` 静默跳过不可解析行。实证为 HEAD 既有代码（`git show HEAD:` 中同一行在 `:76`，本 change diff 无相关增删）；SC-SEL-002 **明确要求既有行为逐字不变**，故本轮不得改动。**残留缺口如实呈报**：当前 `selections.json` 全部条目未设 `expected`，新的 fail-closed 对账路径**尚未激活**，生产路径仍走这条静默跳过的 legacy totals 循环；新增的 `ci-evidence.mjs` 已硬失败，两者口径不一致属**规格预期的过渡状态**（另见 ADJ-029）。

### 7.3 「14 类检查」的口径缺口（ADJ-044，不虚构通过）

Skill `build.md:308` 与 `revision-rules.md:41` 要求「**14 类检查全量执行**，每项注明所用 run 或明确标注未执行」。实测资源根内**不存在权威的逐项定义**：

| 来源 | 实测口径 |
|---|---|
| `build.md:308` / `revision-rules.md:41` | 称 **14 类** |
| `config.d/lite.yaml:105`（thorough） | `failure_modes` 只列 **a–l 共 12 个**（standard `:72` 同 12，lite `:42` 为 5） |
| `stdd/cli/commands/ci.py` | 只实现 **8 个**字母检查 `(a)(b)(d)(f)(g)(j)(k)(l)` |
| `specs/ci-integration/spec.md:48` / `:62` | 称「**11 类**确定性子集」/ 类别范围 **(a-k)** |
| `specs/ci-integration/spec.md:54` | 字母语义与实现**不符**：spec 的 (b)=TC-ID 唯一、(c)=SHALL 关键字、(d)=AND≤5、(e)=TC 数≥Scenario 数；实现的 (b)=范围蔓延、(d)=TC-ID 唯一、(f)=THEN 含 SHALL、(g)=AND 数量 |
| `specs/ci-integration/spec.md:61` 引用的模板 | `.stdd/templates/failure-check-report.md` **实测不存在（MISSING）** |
| 唯一列出 a–n 全 14 个字母处 | `onboarding/bootcamp/level_3/answer/specs/payment/test-report.md:7`，属**教学示例答案，非分类定义** |

**处置**：`(c)(e)(h)(i)(m)(n)` 一律标注 **未执行（资源根无权威定义、无 CLI 实现）**，**不给出任何通过/失败判定**。已执行部分按 §7.1（CLI 8 项，选定 run）与 §7.2（C4 语义 8 项，实读取证）分层如实呈报。**本报告不声称「14 类检查全量执行通过」。** 属 stdd 侧待办（本会话写入数 0）。

### 7.4 未执行 / SKIPPED 项

见 §5.2 表格（`make test`、`scripts/check.sh`、4 个 Linux-only daemon 文件、真实 CI run、管理员 PAT、`gofmt -w`），以及 §2.3 的 4 项人工 TC 未确认。**全部标注状态与边界原因，无一报通过。**

---

## 8. C1 三路评审与 C3 逐文件 Diff 审查

### 8.1 C1 多路并行技术评审（3 个代理均返回）

派发证据见 `validation/c1-review/triage.md §1`：先读 `_shared/model-dispatch.md`，在业务仓根运行 `stdd config models --format json`，派发前重新读取 `values.review` 与各代理 `tier`。**本轮未传任何选模参数**，`subagent_type` 仅按能力选择（`general-purpose`），不按档位选择；profile/agentId 的默认模型**不计为显式 requested**。**三路独立派发保留**，未合并、未跳过、未补造第四个代理、未开启专项 reviewer。configured / requested / actual 分记，缺运行元数据处 actual 标为 unknown。

| 代理 | blocker | major | minor | nit | 实际执行 |
|---|---|---|---|---|---|
| code | 0 | **1** | 2 | 2 | 只读核码（未跑测试，CI 行为属读码推断） |
| test_config | 0 | **1** | 1 | 3 | harness **171/171/0/0**、ci-scope **49/49/0/0**（派发时点），前后 `git status` 一致 |
| docs_skills | 0 | 0 | 4 | 2 | 只读核对；重算 Gate 2 全部 **20** 个 manifest 哈希 + fingerprint，18 处 raw 逐字节匹配 |

- **两个 major 均已 FIXED 并附四步验证**：
  - code MAJOR-1 → **ADJ-027**：`resolveCrosscheckCrctl` 改读受管的 `CRCTL_MJS`，删两条开发机相对回落与 `os.Stat` 探测，`t.Skip` 拆为两条 `t.Fatal/t.Fatalf`。RED exit 1（12/11/1，唯一红的是新守卫）→ GREEN exit 0（12/12/0）；契约 CLI 对真实仓库 exit 0「119 file(s), 0 violations」；`go vet` exit 0；**真库两条件各一次**（runner 自建一次性 podman 实例）：变量齐备 PASS `crosscheck-crctl pass=13 fail=0 skip=0`（与 S4 基线 7+3+3=13 逐名一致，零回归），`env -u CRCTL_MJS` 后 FAIL `pass=0 fail=3 skip=0 exit 1`（**skip=0 证明不再走 skip**）；变异 1 条 DETECTED，按原字节还原 sha256 match true。
  - test_config MAJOR-1 → **ADJ-034**：`tools-pin.test.mjs` 就地强化 ref 来源断言（新增函数 0）。变异证明缺口（两处 ref 改 `main`，旧测试 exit 0、15/15 全绿）→ RED exit 1（15/14/1，唯一红的是 #15）→ 还原 sha256 match true → GREEN 15/15/0。
- **修复后回归**：harness **172/172/0/0 exit 0**（171→+1，即 ADJ-027 的新守卫）、ci-scope **49/49/0 exit 0**。
- **其余 minor/nit 逐条处置**：FIXED / RECORDED（附规格条款依据）/ ALREADY-COVERED，见 `triage.md §3`；对应 ADJ-028…033、042 等。
- docs_skills 另强核实 **Gate 2 未被 BUILD 产物编辑弄脏**：20 个 `input_manifest` 哈希与 fingerprint 全部重算匹配，3 张旧回执 superseded；`tasks.md` / `slices.md` / `phase-context.md` / `pending-adjustments.yaml` **不在** gate 输入内。（该核实为 C1 时点；此后 ADJ-035 按用户裁定修订 proposal 并依次重签 Gate 1+2，旧批准回执保留。）

### 8.2 C3 逐文件 Diff 审查（49/49，无抽样）

- 范围：**49 个文件（22 修改 + 27 新增）**，**内容审查完成 49/49**。
- 结论：**无调试残留、无死代码、无注释掉的旧逻辑**；对 49 个文件扫 `console.log(` / `debugger` / `TODO` / `FIXME` / `XXX` / `fmt.Println` 与注释掉的旧逻辑。
- 新增 1 条待裁定发现：**ADJ-042**（`run-selection.mjs` parseArgs 无最终 else，flag 名拼错则证据不写而结论仍 PASS；CI 路径实测不受影响）。
- 两处关键改动的性质如实说明：`packages/core/package.json` 仅新增一行 subpath export `./platform/storage`（C9 把 `use-logout.test.ts` 相对导入改回包导入后的必要解析入口）；`approval_crosscheck_test.go` 的 **9 增 19 删**是删除 `CRCTL_PATH` 别名与开发机相对回落、`t.Skip`→`t.Fatal/t.Fatalf`，**属收紧而非放宽断言**。

### 8.3 C3 期间的外部删除事故与恢复（如实记录，不影响审查有效性）

- **事实**：C3 进行期间 `C:\Users\GOBAO\Downloads\AI\multica` 被一次外部 C 盘清理操作删除。发现时 `git diff` 报 "Not a git repository"，只读核查确认工作区仅剩 163 个业务文件、`.git` 只剩 `lfs`/`logs`、本 change **49 个文件 0/49**。当时**立即停止**，未修复、未 `git init`、未 clone 覆盖、未删任何文件、未杀进程，并向用户报告。
- **用户报告的「已还原」经实测不成立**：11:12:01 仍为 163 文件、0/49，关键文件与目录缺失。已如实报告差异，**未采信口头结论、未继续推进 change**。
- **恢复方式**：按用户裁定「先护副本，再原地恢复」执行；护副本 `D:\multica-rescue-20261113`，原始备份 `D:\C_Cleanup_Backup_20261113\`（**D04 原件全程未写入**）。
- **恢复后指纹核验**：22 个修改文件 numstat **22/22 精确一致**；27 个新增文件行数 **27/27 精确一致**；HEAD 恢复为 `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`、tracked 7336、27 `??` + 22 `M`、0 deleted。
- **对审查有效性的影响**：删除前已完成约 20/22 个修改文件与全部 27 个新增文件的审查及残留扫描；剩余 2 个（`execution_control_reservation.go`、`test-go.test.sh`）在恢复后补审，diff 读取自**已通过指纹核验的护副本**。**49/49 审查结论均基于与删除前逐字节一致的内容。**
- **遗留提醒**：`D:\C_Cleanup_Backup_20261113\RESTORE.md` §7 选项 C 把 D04 标为可删缓存；**在恢复确认稳定前不得清理**。现存三份副本：D04 原件（从未写入）、`D:\multica-rescue-20261113`、C: 工作树。

## 9. 已知问题与未完成项

口径：本节逐项给出**名称 / 原因 / 影响 / 补完计划**。「未决」= `pending-adjustments.yaml` 中 `resolved: false`，本轮从 YAML 重算实测 **20 条**（major 4、minor 16）；已解决 **25 条**不在本节重复列出。所有未决项均**未**在任何章节被报为通过。

**本轮状态变化（4 项，如实记录）**：ADJ-025 由 major 未决 → **已解决**（用户授权推送 `e52b808`，origin 可达性实测 YES）；ADJ-042 由 minor 未决 → **已解决**（用户裁定纳入本 change，RED→GREEN + 三组回归）；ADJ-030 / ADJ-031 由未决 → **已解决，但处置＝「决定不做」而非「已修复」**（不可达分支不加防御；扫描器扩围超出 SC-CBE-004 的 `when` 且需重签 Gate 2）。另新增 ADJ-045（环境修复）并当轮解决。故未决 major 由 5 → **4**、minor 由 19 → **16**、总数由 44 → **45**。

### 9.1 major 未决（4 条）

| ID | 名称 | 原因 | 影响 | 补完计划 |
|---|---|---|---|---|
| **ADJ-005** | tools `show` 白名单跨仓契约缺口（6 个测试） | 整包基线暴露 `TestProposedSnapshotReadShapes`、`TestM26B2TestFactsPayload`、`TestM26B2TestFactsPr…` 等 6 项在 pin 的 tools `rules.json` 形状下不合规；修法在 **tools 仓**（放宽 show 形状），不在 multica | 若 S13 把 `MULTICA_CONTROLLED_SHELL_RULES` 指向 pin 的 tools `rules.json`，这 6 项会在 **CI-linux 上真实失败**。本 change **未改 tools 白名单、未排除这 6 项**，不静默放宽 | 由用户裁定：①在 tools 仓放宽 show 形状（须单独变更与授权，且不夹带该仓既有未提交改动）；或②裁定 S13 是否设置该环境变量。裁定前不得声称 CI 全绿。关联 ADJ-025 / U1 |
| **ADJ-024** | `TestChannelIsolation` 隔离性证明 **UNCOVERED** | WSL AIFI-ISO 只做了**只读探针**（uid=0 可用、内核 6.18.5…），未装 Go、未建 uid 995/gid 994、未建 profile 根、未克隆仓库；同 uid 与 1500/1501 替代对照一律未做 | SC-TOR-004 的**隔离半未验证，不得报通过**；TC-TOR-004 记**部分覆盖**（两个状态敏感 selection 真实执行并通过，隔离半 UNCOVERED）。S12 之外的该切片 `tc_coverage: 2/2` 依据是 SC-TOR-004 明文把「如实列为未覆盖」本身作为要求处置，**不代表隔离性已验证**。CI 侧不受影响：该测试已由 `test-ownership.json` 第 1 条 `owner=independent` 排除，rule 3 核对排除生效 | 在 AIFI-ISO 内装 Go >= 1.26、按 `wsl2-aifi45-v1` 重建 uid 995/gid 994 与 `/var/lib/aifi45/daemo…` profile 根后真实运行 `TestChannelIsolation`，再把 TC-TOR-004 的隔离半从 UNCOVERED 改为实测结论。属外部前置，需用户授权 |
| **ADJ-038** | Gate 2 审批路径**不执行 (l) 锚定检查** | 外部 stdd 流程缺陷：Skill 正文声称锚定不足即阻塞 Gate 2，实现与声明不一致，导致 L3 在 `financial=true` 下仍**三次通过 Gate 2**（最后一次 2026-11-12T23:54:09），直到 BUILD 跑 `ci check-failures` 才暴露等级不足 | 任何 critical 变更都可能在锚定不足时通过 Gate 2，把缺口推迟到 BUILD。**按用户禁令未写 stdd（写入数 0）** | 属 **stdd 侧待办**，由该仓自己的变更修复。本 change 侧已按用户裁定「补真实 L4 基准锚定并重签」（ADJ-035）满足门禁要求，**不依赖该缺陷是否修复**；选定 run 的 (l) 实测 `Anchoring: L4 >= L4` 通过 |
| **ADJ-040** | CLI TC 覆盖判定 **0/22**（结构性，非执行失败；**ADJ-047 后分母为 19，当前实测 0/19**） | `evidence.py:1033-1034` 要求 `len(checks) == len(plan["checks"])`：18 != 22 即**整个 run 无效、覆盖归零**，而不是按已通过条数计 18/22 | run `dfb7aad8…` 真实执行 **18/18 命令 CP 全通过**（`tc-evidence.json` 实测 18 条、全部 `kind=command`、全部 `result=pass`、18 个不同 TC，报告已生成），但同 run `ci check-failures` 仍判 **0/22**，理由「缺少或重复必需 check（当前运行未完成）」。`verify` 自身 `VERIFY_EXIT=1` 亦源于 `REVIEW_PENDING`，**非 CP 失败** | 覆盖指标在 **4 项人工 TC 全部如实确认前恒为 0/22**。Gate 3 必须**同时呈报两个数字与各自含义**：命令 CP 18/18 通过（有报告与产物）／CLI 覆盖判定 0/22（run 因 4 项人工未确认而结构上不完整）。**不得以 18/18 冒充覆盖通过，也不得把 0/22 说成执行失败**。4 项前置见 §2.3 与 §9.3。**用户已按此口径给出 Gate 3 确认原话「命令 CP 18/18 + 4 个人工 TC 未闭合」**。**⚠ 影响范围已被 ADJ-046 实测更正：同一判据经 `gate.py:815-822` 还硬阻断 `gate approve --gate 3`，不止是指标归零——按该原话执行 approve 实测被拒（`APPROVE_EXIT=1`），见 §1.1** |
| **ADJ-046** | **Gate 3 approve 被 CLI 拒绝批准**（major，未决，**阻塞本 change 推进**） | `gate.py:810-823` 把 `evidence.py:1033-1034` 的条数判据作为批准前置；冻结计划 22 条 check 的 `applicability` 实测**全为 `required`**（无豁免出口）；`confirm_manual`（`:697-699/740/761-768`）全有或全无且 `result` 硬编码 `manual-pass`，`:748` 拒绝静默覆盖 → **CLI 无法记录「人工已审阅但未闭合」** | 按用户裁定原文执行 `gate approve … --gate 3 --confirmed-by dialog --evidence "以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。" --run dfb7aad8…` → **`APPROVE_EXIT=1`**，stderr「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」「Gate 3 拒绝批准：选定 run 证据不足。」（`gate3-followup/gate3-approve-refused.txt`）。**批准前无任何写入**：`gate status` 仍 **Gate 3 ⬜ pending**、`.stdd.yaml` 无 `selected_evidence` | **未采取任何绕过手段**：未调用 `agent confirm`（确认数 **0**）、未改 stdd（写入数 **0**）、未改 `test-plan.md` 或任何 Gate 1/2 manifest 项、未伪造 evidence。`tasks.md` 14.10 保持未勾选，`current_phase` 仍 `build`，**不得进入 DELIVER**。**三条合法路径 A/B/C 须用户裁定**（A 闭合外部前置／B 缩小范围移交后续 change 并重签 Gate 2／C 修 stdd——用户已明示不在本次），完整评估见 §1.1 与 `design-adjustments.md` ADJ-046 |

### 9.2 minor 未决（16 条）

| ID | 名称 | 原因 | 影响 | 补完计划 |
|---|---|---|---|---|
| ADJ-002 | `run-selection.mjs` 新增 `--evidence-dir` 与 ndjson 落盘 | 归属表要求「每项排除都带证据」，而失败原因、skip 理由、逐测试耗时只存在于 `-json` 流中；不保留流则 S4 证据义务无法事后取证 | **已实现**：新增可选参数（不改既有调用行为）、`runSelection` 返回 `{result, ndjson}`（migrate 失败分支 ndjson 为空串）、新增 `selection-evidence.mjs` 落盘 `<name>.ndjson`/`<name>.json`；原有 11 项参数/决策测试与输出行格式未改。属接口新增，登记待用户知悉 | Gate 3 呈报请用户确认该接口新增；S5/S13 复用同一落盘形状，无需再改 |
| ADJ-003 | `allowed-skips` 载体与「下界」性质 | design 只说「允许名单」未指定载体；与排除表同放 `test-ownership.json` 可共用「真实 func + 必填 reason + 不重复」校验 | **已实现**：初始 4 条 = **3 条基线观测 + 1 条源码推导**（`daemon.TestChannelIsolationChild`，reason 明标 `source-derived, not baseline-observed`）。名单是 CI-linux 真实 skip 集合的**下界而非终态** | 由 **TC-CBE-005（真实 CI 运行）** 最终确认全集；在此之前不得把 4 条当作 CI 的完整 skip 清单。与 ADJ-007 共同说明该性质 |
| ADJ-006 | handler presenter/search 基线 flake（Windows 时钟粒度） | `TestPresenterMemberRemovalLinkage` 与 `TestSearchIndexChangesScopeToWorkspace` 因 `user_emai…` 唯一键在基线失败；`UnixNano` 粒度不足已本机证伪 | 未改这两个上游测试、未排除它们；为 S9 增加实现约束：**不得沿用 UnixNano**，须用 crypto 随机或等价单调来源。**handler 整包回归不能以「全绿」或失败计数当信号**——受害集合会在运行之间移动 | S9/S10 整包对账**按测试名逐条比对基线**（口径见 `validation/s8-wsd-manifest/regression-handler-failing-diff.txt`），不得把计数差直接判为回归。CI-linux 是否复现**仍未验证**，须 TC-CBE-005 确认，**不提前报绿** |
| ADJ-007 | daemon `TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover` 基线失败未定性 | 基线失败于 runti… ，本轮**未排除、未定性、未修改**该测试 | 不能判定是真实缺陷还是环境因素；与 ADJ-003 共同说明 `allowed-skips` 只是下界 | 由**真实 CI-linux 运行（TC-CBE-005）**定性；若为真实缺陷则属上游行为问题，需另行裁定是否纳入范围 |
| ADJ-009 | `::add-mask::` 必然把口令送到原始 stdout | `::add-mask::` 是 GitHub Actions 规定的遮蔽协议，runner 只遮蔽**它已经见过的值**，故该命令本身必然先把口令写到原始 stdout，与「stdout 全程不含口令」的字面读法冲突 | 实现按 R1 **先发 mask 再写三行 `GITHUB_ENV`**；TC-CBE-001 断言口径为「**除这一条 mask 命令外**，没有任何日志行携带角色口令或管理员口令」，**不是**「stdout 从头到尾不含口令」。口令仍是 `randomBytes(18)`、job 级、随服务容器销毁，不复用于任何非一次性资源；handle 与本 change 其他产物均不含口令 | 本验收报告与 Gate 3 **一并呈报该口径**。若用户要求 stdout 全程无口令，须改用 runner 外部遮蔽机制，**超出本 change 范围，需用户裁定** |
| ADJ-018 | CUSTOM.md 四数基线表台账欠债 | ①差值跨 2026-11-10 之后全部落码（含已提交 AIFI-45 批次与本 change 在途改动），不能归因本切片；②`git grep` 口径限制；③无法如实补出一行 | S1–S10 均只在 M31 明细表登记（#317–#327），**未重算或追加四数基线表行**。S10 登记时实测当前工作树 **611 文件 / 1678 命中行 / 755 AIFIRST 行**。属台账欠债，**不影响本 change 任何规格、代码或测试结论** | 风险在**合并窗口**：基线表停在 2026-11-10，若合并时直接引用旧四数做「只能升不能降」核对会得出错误结论。已在 CUSTOM.md #327 合并注意写明实测值与三点限制，**不默认台账最新**；补账须单独裁定 |
| ADJ-019 | S12 `new_tests: 0`（长程约束 #3 未满足） | TC-CCF-002 在锁定证据计划里是 **command 型**，断言对象是 tsc 退出码与错误码计数，不是某个测试函数 | S12 未新增任何测试函数，`new_tests` **如实记 0**。改动仅两处：`packages/core/package.json` +1 行 exports；`use-logout.test.ts` 导入改写（7 插/5 删），**原有 2 条测试标题与全部 expect 断言一字未改**，改前改后均 2/2。**不报「B3.4 三项全过」**。约束 #5「连续 3 切片无新增测试」**不触发**（S11=15、S12=0、S13=4） | TC 覆盖仍 1/1（由命令证据覆盖，非新测试函数）。断言 teeth 由四项替代证据提供：①RED 60×TS6059 → GREEN exit 0 且 0 条任何错误码；②diff 中 0 条 `expect(` 改动、两条 `it()` 标题不变；③HEAD 版本另存临时文件独立跑亦 2/2（临时文件已删除并核实不存在）；④views 全量 A/B 逐名对账（ADJ-020）。Gate 3 呈报请用户知悉 |
| ADJ-020 | views 全量 Windows 并行负载 flake（HEAD 既存） | 三组实测（`validation/s12-views-typecheck/full/`，`reconcile.mjs` 可重跑 exit 0）：还原两个 S12 文件后**仍红** | **非 S12 引入、亦非 typecheck 修复新暴露**。未改任何 views 生产代码/测试断言，未调 `testTimeout`/retry/并行度，未新增 skip 或排除。S12 自身义务已达成（typecheck exit 0／0 错误、`use-logout.test.ts` 2/2、断言等价、core 全量绿）。**未确立**：两次运行不足以测量 flake 率，不能声称频率未变；未在 ubuntu-latest 跑过 views 全量，**不能声称 CI 不受影响** | 按 U4「先报告再裁定范围」已上报，依「范围外遗留项上报待定」**不扩大范围**。风险在 CI 接线后：若同一负载敏感在 ubuntu-latest 复现，S13 evidence 对账会**如实判红**，届时按新发现处理，**不得预先放宽门禁或加 retry 掩盖** |
| ADJ-028 | reservation workspace 存在性检查为非锁读（TOCTOU） | C1 代码评审 MINOR-1：`execution_control_reservation.go:90-96` 用 `SELECT EXISTS` 未加 `FOR SHARE`/`FOR UPDATE`；READ COMMITTED 下与并发未提交 `DeleteWorkspace`（`workspace.go:1141` 持 `FOR UPDATE`）之间存在窗口 | **实际风险低**：`CreateReservationTx` 目前**无生产调用方**（仅测试消费，#327 已记），648:51-52 声明 reservation 惰性。本轮**只追加两行英文注释**说明非锁读只闭合顺序 teardown 场景，**SQL 与锁语义一行未改**。SC-WSD-005 顺序场景已由 S10 真库证明（`PASS handler-wsd-no-recreate pass=3 fail=0 skip=0`） | 若将来接线生产调用方或要求并发安全，须**先裁定 `FOR SHARE` 还是 FK**，并同步修订 SC-WSD-005 与 648 的 `no-new-FK` 约束 |
| ADJ-029 | `summarizeEvents` 静默丢弃不可解析行 | C1 代码评审 MINOR-2 + 测试评审 NIT-3 同指一处：`run-selection.mjs:79-82` `try{JSON.parse}catch{continue}`，与 `ci-evidence.mjs`「流不可解析即硬失败」不一致。**本轮未改** | **既有行为，非本 change 引入的回归**。风险：`go test -json` 流被截断或混入非 JSON 行时，run-selection 计数可能偏低而**仍报 PASS**；ci-evidence 侧不受影响（硬失败）。不修有规格依据：**SC-SEL-002 明文要求沿用旧判定、输出行逐字不变、既有断言不被改弱** | 若用户要求统一为硬失败，属**行为变更**，须修订 SC-SEL-002 并**重签 Gate 2**，同时复核 `run-selection.test.mjs` 既有断言不被改弱 |
| ADJ-032 | `.canon-index.yaml` 指向不存在的聚合 spec | C1 文档评审 minor 1：索引指向 `specs/agent/2026-11-12-….yaml` 与 `specs/code/2026-11-12-….yaml`，实际布局是 **5 个 per-capability 文件**。**本轮未改** | **功能上惰性**：generate 走 glob、verify 只校 proposal、Gate 2 哈希原始字节，故**不影响任何已验证结论**。将来若有人按索引路径读聚合 spec 会落空。与 ADJ-015 同源的 CLI 缺陷 | 与 **ADJ-015** 一并作为 CLI 缺陷处理，或在取得重签授权后同步修订索引与 Gate 2。Gate 3 呈报 |
| ADJ-033 | 14 个 agent CP description 在第 61 字符词中截断 | C1 文档评审 minor 2：如 CP-SEL-001 结尾「…含该 re」、CP-SEL-003「…；SHAL」、CP-WSD-002「…cr_execution_dispa」。**本轮未改** | 边界反证：CP-WSD-004 **恰好 61 字符且自然收在「。」**，CP-WSD-005（132 字符，R5 手工同步）完整 → 属**工具渲染缺陷而非撰写遗漏**。description 作为人读摘要不完整，但**验证语义由 action/assertions 承载**，不影响任何 CP 的可执行性与已验证结论 | 走 CLI 缺陷修复，或取得重签授权后手工同步（如 R5 对 CP-WSD-005 的做法）。Gate 3 呈报 |
| ADJ-037 | `_require_argv` 处同类 `item["cp"]` KeyError 残留 | ADJ-036 的同类残留点：该处在 kind 过滤**之前**求值且无 `.get` 保护。**本轮未修（stdd 只读）** | 本计划 **0 条 pytest check**，且 `_require_argv` 在 `:800-801` 要求 plan 声明 pytest 来源否则先 raise，故**本轮执行路径不可达**。将来任何同时含 manual 与 pytest 义务的计划会在此崩溃 | 属 **stdd 侧待办**，由该仓自己的变更处理，不在本 change 范围内修。（ADJ-036 的 `item.get("cp")` 已由**用户直接修改**） |
| ADJ-041 | `ci check-failures` 范围蔓延 WARN 口径缺陷（37 实为 36） | 实测复现：`git diff --stat HEAD~1` 报 38 files changed，同一正则解析出 **39 个 token**，汇总行数字 38 被当成文件路径（numeric-looking tokens 实测 `[38]`）。另有文件源为 HEAD~1→工作树，把上一提交（HEAD=`903a46c5a`、HEAD~1=`d5b348a17`）的归档文件混入范围判定。**本轮未修（stdd 只读）** | **该 WARN 不能作为本 change 范围蔓延的证据**。真实范围已手工逐文件核对：**49 个文件（22 改 + 27 新）全部可追溯到 C1–C10 或 constraints**；`packages/core/package.json` 仅新增一行 subpath export `./platform/storage`（C9 改回包导入后的必要解析入口）；`approval_crosscheck_test.go` 的 9 增 19 删是删除 `CRCTL_PATH` 别名与开发机相对回落、`t.Skip`→`t.Fatal/t.Fatalf`，**属收紧而非放宽断言** | 属 **stdd 侧待办**，由该仓自己的变更处理。本 change 侧以 §8.2 的 49/49 逐文件核对为权威范围结论 |
| ADJ-043 | C6 产物记录格式冲突（`.md` vs `.yaml`）**待用户裁定** | 两处口径冲突且都自称 3.0.7：用户级技能正文 B4/C6 仍写 `.yaml`（description 标 V3.0.5）；资源根 `.stdd/version.yaml` 为 3.0.7，其 `build.md:317` 明写生成 `design-adjustments.md`「不再生成或读取同名 .yaml」，`revision-rules.md:29`（自称 Gate 修订规则唯一来源）明写「同名 .yaml 不读、不计入任何 Gate」。实测 `multica/.stdd` 只有 `binding.yaml`（81 字节）、**无 skills 目录** → 按 AGENTS.md **资源根为权威** | C6 产物按资源根口径生成为 **`design-adjustments.md`，不生成同名 `.yaml`**；既有 `pending-adjustments.yaml`（**现 45 条**）**逐字保留，未迁移、未删除、未双写**；**未改任何技能文件，stdd 写入数 0**。已核实该台账**不在 Gate 1（2 项）或 Gate 2（20 项）内**，故新增或迁移调整记录**不会使 Gate 1/2 过期**，与 revision-rules §2「仅新增调整记录 → 仅重审 Gate 3」一致。（本条初稿误记 Gate 2 为 19 项，C7 已更正为实测 20 项，结论不受影响） | 取舍：只留 `.yaml` 则当前工具链不读不计，**C6 产物在 Gate 3 缺位**；双写会造成**两份真相源并漂移**，故只生成 `.md` 并逐条指明逐字来源。迁移约 **90KB** 既有台账属**记录搬移，须用户裁定后执行**，不擅自双写或删除原记录 |
| ADJ-044 | 「14 类失败模式」在资源根内**无权威逐项定义** | C7 编制 §7 时实测四处口径互不一致：①`build.md:308` 与 `revision-rules.md:41` 称 **14 类**；②`lite.yaml:105` thorough 档 `failure_modes` 只列 **a–l 共 12**（standard `:72` 同 12，lite `:42` 为 5）；③`ci.py` 只实现 **8 个字母** (a)(b)(d)(f)(g)(j)(k)(l)；④`ci-integration/spec.md:48` 称「**11 类**」、`:62` 称范围 **(a-k)**，且 `:54` 语义与实现不符（spec (b)=TC-ID 唯一、(c)=SHALL 关键字、(d)=AND≤5、(e)=TC 数≥Scenario 数；实现 (b)=范围蔓延、(d)=TC-ID 唯一、(f)=THEN 含 SHALL、(g)=AND 计数）。`:61` 引用的 `.stdd/templates/failure-check-report.md` **缺失**；唯一 a–n 枚举出现在 `onboarding/bootcamp/level_3/answer/specs/payment/test-report.md:7`（**教学样例，非权威**）。**本轮未修（stdd 只读）** | **不能声称「14 类检查全量执行通过」**。`(c)(e)(h)(i)(m)(n)` 在 §7.3 一律标注**未执行（资源根无权威定义）**，不虚构通过/失败。已执行部分证据不受影响：选定 run 的 `ci check-failures` 原文 **8 通过 / 1 警告 / 0 跳过 / 1 错误**、自动化检查覆盖 **10/10**；C4 README 记 **8 项检查完成、2 项命中、1 项观察** | 属 **stdd 侧待办**：需该仓自己统一 `build.md` / `revision-rules` / `lite.yaml` / `ci-integration spec` / `ci.py` 的**类别数与字母语义**，并补回缺失的 `failure-check-report.md` 模板。本 change 侧改为**分层如实呈报**（CLI 8 项按选定 run 原文；C4 语义 8 项按实读取证；无定义类别标注未执行） |

### 9.3 未执行 / 未闭合项（非调整记录，逐项说明）

#### 9.3.1 人工 TC 的闭合状态（前置原文取自 `test-plan.md`）

**2026-11-13 口径变更（ADJ-047）**：下列 4 项中 **TC-CBE-005 / TC-TOR-004 / TC-CCF-003 已移交后续 change**（不在本 change 分母内、不报通过）；**只剩 TC-TOR-005 待用户人工核对**。下表保留逐项原因与原文。

| TC | 前置条件（原文摘要） | 当前状态 | 未闭合原因 | 补完计划 |
|---|---|---|---|---|
| **TC-CBE-005** | 「CI 的 backend-tests 在修复后的 `ci.yml` 下运行（需推送授权与 tools pin 可用，见 design U1）」 | **SKIPPED / 未执行** | **真实 CI run 未执行**。tools pin 前置**已闭合**（用户授权后 `e52b8081f159` 已推送 origin，ADJ-025 resolved）；仍缺 **multica 推送授权**（未授权、未推送，且消耗私有库 Actions 额度）与**管理员 PAT**（TC-CCF-003） | 取得 multica 推送授权 + 管理员更新 PAT 后真实跑一次，验收报告 SHALL 记录 **run id、commit、各 job 结论**。**更正初稿措辞**：原写「checkout 会先失败」，实测可达性诊断步在 tools checkout 之前（`validation/gate3-followup/pin-reachability-order.txt`：transitions 第 3 步 vs 第 5 步、backend-tests 第 10 步 vs 第 12 步），pin 不可达时先失败的是诊断步 |
| **TC-TOR-004** | 「D1 的独立入口：`TestChannelIsolation` 经 WSL AIFI-ISO（root 加 `AIFI45_ISOLATION_PROFILE`），两个状态敏感探针经 run-selection 的 down/reapply 初始状态」 | **部分覆盖**：selection 半真实执行并通过；**隔离半 UNCOVERED** | WSL 内未装 Go、未建 uid 995/gid 994 与 profile 根（ADJ-024）。规格明文「任一项不能执行时 SHALL 如实列为未覆盖，**不得以同 uid 对照代替**」——本轮**未做任何同 uid 或 1500/1501 替代对照**。**用户已采纳「保持 UNCOVERED」**：规格本身接受如实标注，不为此搭环境 | 若将来要闭合：按 `wsl2-aifi45-v1` 重建隔离环境后真实运行，把命令、退出码、通过数记入验收报告（要求**每项通过数 ≥ 1、skip 为 0**）。**本轮不做，已记录为后续变更输入** |
| **TC-TOR-005** | 「change 的验收报告 `validation/acceptance-report.md`」 | **报告已生成，人工审阅留痕由报告 + Gate 3 确认原文承担** | 文档类验收，须**人工逐项核对**；AI 不得代签。**更正初稿措辞**：原写「用户核对后以同一 run id 执行 `stdd agent confirm …`」，暗示可单独确认本项——**实测不存在该路径**。`confirm_manual`（`evidence.py:717-770`）在 `:740` 取计划级全部必需 manual（4 条），`:761-764` 一次全写 `manual-pass` 共用同一 statement，`:745-748` 拒绝二次不同确认 → **全有或全无、一次性** | **本轮不执行任何 `agent confirm`**（否则等于同时断言另外 3 项通过）。**ADJ-047 后口径**：范围收窄使 `_manual_checks` 只剩本项，用户核对 `validation/acceptance-report.md`（§0 / §2.1′ / §2.4′）后即可**单独**以真实审阅原文确认，不再受另外 3 项拖累；3 项已移交（移交包 §7.1–§7.3） |
| **TC-CCF-003** | 「管理员已按最小权限更新 `AIFIRST_TOOLS_READ_TOKEN`」 | **未闭合** | 依赖**管理员动作与 CI 推送**，无法由本地命令代替。规格明文「管理员未完成更新时 SHALL 如实列为未闭合」，且「本 change **SHALL NOT 读取、创建或轮换凭据**」——本轮**未读取、未打印、未创建、未轮换任何凭据** | 管理员完成最小权限更新并推送后重跑 `transitions-contract-check`，该 job 通过方可确认 |

**结论：在册人工 TC 只剩 TC-TOR-005，尚未确认；3 项已移交后续 change（ADJ-047）。** 因此 CLI 覆盖判定恒为 **0/19**（ADJ-040），`verify` 的 `VERIFY_EXIT=1` 源于 `REVIEW_PENDING` **只列出 TC-TOR-005**，**不是 CP 失败**。

#### 9.3.2 其他未执行项（与 §5.2 一致，此处不重复计数）

| 项 | 原因 | 影响 | 补完计划 |
|---|---|---|---|
| `make test` / `scripts/check.sh` | 上游聚合入口依赖 Linux 工具链，本机 Windows 未执行 | 不能声称上游聚合入口全绿；已用 harness **173/173**、ci-scope 49/49、typecheck **10/10（`--force`，Cached 0）**、lint **7/7（`--force`，Cached 0）** 与真库 46 个叶子测试作为**替代且如实标注范围**的证据。**views 全量 vitest 本轮 1 失败 / exit 1，不在「全绿」之列**（§5.1.1） | 由真实 CI run（TC-CBE-005）覆盖 |
| 4 个 Linux-only daemon 测试文件 | `//go:build linux`，**Windows 基线从未编译它们** | `test-ownership.json` 中 `TestChannelIsolationChild` 的 allowed-skip 是**源码推导而非基线观测**，reason 已如实标注 | 在 CI-linux 或 WSL 隔离入口真实编译运行后，把该条从「源码推导」升级为「观测」 |
| 真实 CI run（含 script-checks 真跑） | **multica 推送未授权**（tools pin 前置已闭合：`e52b8081f159` 已在 origin）+ 管理员 PAT 未更新 | `ci.yml` 接线只做了**本地等价验证与变异测试**，不等于 CI 已验证；**本轮 CI run 次数 = 0** | 同 TC-CBE-005 |
| 管理员更新 PAT | 属管理员职责，本 change 禁止读取/创建/轮换凭据 | TC-CCF-003 未闭合 | 同 TC-CCF-003 |
| `gofmt -w` | **刻意未执行**：工作树 2466 个 `.go` 中 2206 个 CRLF（`core.autocrlf=true`），未触碰的 `cmd/migrate/main.go` 同样被 `gofmt -l` 点名 | 不引入全仓无关格式改动。已核实 `gofmt` 输出与去 CR 原文**逐字节一致** | 保持现状；如需统一格式须单独裁定 |
| 失败模式 `(c)(e)(h)(i)(m)(n)` | **资源根无权威定义**（ADJ-044） | §7.3 标注**未执行**，不虚构结论；**不能声称「14 类全量执行通过」** | 由 stdd 仓统一类别数与字母语义后再执行 |

#### 9.3.3 事故与遗留提醒

- **外部删除事故**（详见 §8.3）：C3 期间 multica 工作区被外部 C 盘清理删除，已按用户裁定「先护副本，再原地恢复」完成恢复，指纹核验 **22/22 numstat + 27/27 行数**精确一致，49/49 审查结论均基于逐字节一致内容。
- **⚠ 遗留提醒（须持续呈报）**：`D:\C_Cleanup_Backup_20261113\RESTORE.md` **§7 选项 C 把 D04 标为可删缓存**；**在恢复确认稳定前不得清理 D04**。现存三份副本：D04 原件（**全程未写入**）、`D:\multica-rescue-20261113`、C: 工作树。
- **事故的第二层损害（ADJ-045，本轮发现并修复）**：清理不仅删了 `node_modules`，还掏空了 **pnpm CLI 自身的切版 store**。全局 PATH 上的 pnpm 为 **11.22.0**，按项目 `packageManager: pnpm@10.28.2` 自动切版，而目标链接目录是**空壳**（1307 条目、无 `package.json`、`dist` 空、只剩 `bin/*.cjs`），`store/v11/files` 仅 **48K**，故 `pnpm --version` 报 `VERSION_SWITCH_FAIL` / `spawnSync ENOENT`。**两阶段处置**：①`pnpm install --frozen-lockfile` 重建依赖树（`INSTALL_EXIT=0`，Done in 21m31.4s，pg 8.20.0，manifests git 差异为空）；②**重命名隔离**空壳目录为 `hollow-backup-20261113`（**可回滚，未删除**），让 pnpm 从官方 registry 重取 → **10.28.2、exit 0**。**明确拒绝的替代方案**：corepack shim（机器级遮蔽 PATH）、self-update（等于降级全局 pnpm）、关闭自动切版（会让冻结 CP 在 pnpm 11 下执行）、改 CP 命令（Gate 2 冻结输入）。**未改 PATH、未装 shim、未降级全局 pnpm、未改任何 pnpm 配置或仓库文件。** 证据 `validation/gate3-followup/pnpm-install-restore.txt`、`pnpm-cli-restore.txt`、`c2-quality-round3/pnpm-version.txt`。
- **授权口径如实声明**：`pnpm install --frozen-lockfile` **宽于 U5 字面的「npm 安装 pg」**，但作用范围限于被 git 忽略的依赖路径，manifests 与 lockfile 无改动；已在 ADJ-045 记录该偏离，不冒充为字面授权。
- **修复后的残留义务已履行**：views typecheck 与 6 条真库 selection 随新 run `dfb7aad8…` 整轮重跑（§6.5）；C2 全量 typecheck/lint 以 `--force` 真跑（§5.1）；views 全量 vitest 重跑并如实记 **1 失败 / exit 1**（§5.1.1）。
- **⚠ 隔离保留物同样不得清理**：`hollow-backup-20261113`（pnpm 切版空壳目录的重命名隔离件，位于 pnpm store 内）是 ADJ-045 的**可回退凭据**，与 D04 一样在恢复确认稳定前**不得删除**。
- **待用户裁定项（本轮收敛后）**：ADJ-043 的 ~90KB 台账迁移（`.yaml` → `.md`）；ADJ-005 的 tools 白名单修法归属。**ADJ-042 已由用户裁定纳入本 change 并修完**；**ADJ-031 已裁定明确不做**（扩围超出 SC-CBE-004 的 `when`，需重签 Gate 2），二者不再列为待裁定。

### 9.4 本轮已处置项（从 §9.1/§9.2 移出，逐条说明处置性质）

| ID | 处置性质 | 实测依据 |
|---|---|---|
| **ADJ-025**（major） | **已解决＝真实执行了授权动作** | 用户原话「ADJ-025 授权执行推送 e52b808」。推送后实测 tools `HEAD` = `origin/main` = `git ls-remote origin refs/heads/main` = `e52b8081f159d581bf62f82447c76f818fc52426`，`merge-base --is-ancestor` → **YES**（`gate3-followup/tools-push-verified.txt`）。**只推该一个提交，未夹带该仓 6 处既有未提交改动**。**后半句「pin 可达性检查前移到 checkout 之前」＝要求已被现状满足，未改 `ci.yml`**：实测 transitions 第 **3** 步 < 第 **5** 步、backend-tests 第 **10** 步 < 第 **12** 步（`pin-reachability-order.txt:10`、`:35`）；`ci.yml` sha256 `72c16f6b9302bb97…` 与 C1 还原后一致。**此前「建议重排步骤」的说法被实测推翻，已更正** |
| **ADJ-042**（minor） | **已解决＝本轮真实修复（RED→GREEN）** | 用户原话「ADJ-042 纳入本 change。」`run-selection.mjs` +3 行（`:44` 分支、`:45` 抛错），新增 **1 个测试函数**。首次 RED **无效**（`ERR_MODULE_NOT_FOUND: pg`，属环境缺依赖而非缺陷）→ 修依赖后取得**有效 RED** exit 1（1/0/1，stderr `disposable runner failed: spawnSync podman ENOENT`）→ **GREEN** exit 0（1/1/0）。回归：该文件 **14/14/0**、harness **173/173/0/0/0**、ci-scope **49/49/0**。调用方安全：`parseArgs` 在 `main():161`、`startInstance` 在 `:170`，**拒绝发生在建实例之前**；`ci.yml` 与 `test-ownership.json` 均不含该调用。同目录 **7 个**含 `parseArgs` 的脚本实测**全部**对未知参数抛错（`ci-provision:132`、`ci-evidence:162`、`test-ownership:108`、`go-test-env-contract:75`、`tools-access:66`、`tools-pin:45`、`run-selection:45`）；run-selection 的报文含冒号、其余六个不含，**语义相同，标点刻意不统一**。**因改动落在声明输入内，旧 run 失效，必须整轮重执行**（§6.5）。CUSTOM.md **#333** 已登记 |
| **ADJ-045**（minor，本轮新增） | **已解决＝环境修复，非产品缺陷修复** | 见 §9.3.3 两阶段处置与授权口径声明 |
| **ADJ-030**（minor） | **已解决＝决定不做（不是已修复）** | 唯一调用点 `run-selection.mjs:141-150` 总传入 reconciliation 对象，该分支**不可达**；为不可能状态加防御属多余错误处理。`selection-decision.mjs` **一行未改** |
| **ADJ-031**（minor） | **已解决＝明确不做（不是已修复，也不是移交后续）** | G1 由 `ci-evidence.mjs` 的**运行时 skip 对账**承担，不依赖静态扫描器穷尽模式；扩围超出 SC-CBE-004 的 `when` 且需**重签 Gate 2**。**四个扫描正则一字未改**，受管集仍为 `{CRCTL_MJS, AIFI45_TOOLS_ROOT}`；契约 CLI 对真实仓库 exit 0「**119 file(s), 0 violations**」 |

**未决 major 的归属（用户已裁定不在本 change 完成）**：ADJ-005 属 **tools 仓**、ADJ-024 属 **WSL 隔离环境外部前置**、ADJ-038 与 ADJ-040 属 **stdd 仓**。用户原话「stdd的项不在本次完成，我以后单独完成」「不在本change完成的multica和tools仓库的修订记录在案，以后可以找回以便新开change」→ 取回点为 `design-adjustments.md` **§A / §D / §E**（含 ADJ-005 的 tools `show` 白名单细节、6 个受影响测试名、`crevents_test.go` 内联 fixture 回落的遮蔽修法、两条候选路径与明确不做项）。**本 Agent 对 stdd 仓写入数 = 0。**

## 10. 计划外守卫（不计入任何 TC 覆盖分子）

依据 ADJ-026 的明文要求：「C7 的 test-report 须如实区分『计划内 TC 覆盖』与『计划外新增守卫』，**不把后者算进前者**」。

| 来源 | 内容 | 新增测试函数数 | 验证 | 是否计入 TC 分子 |
|---|---|---|---|---|
| **ADJ-026**（S13，B4 小偏离） | `scripts/ci-scope.test.mjs` 除 TC-SEL-004 的 1 行表驱动用例外，另新增 **3 个独立测试**：①script-checks 跑 harness 且 pg 取失败不能存活；②backend-tests 一次性库/对账/收尾的**完整接线**（env 键、Setup Node.js、**10 步顺序**、各步 run 正文与 if 条件）；③两个 tools 消费者都改为**诊断而非只判非空** | **4**（含 TC-SEL-004 的 1 个） | 13.3 RED **49/47/2** → GREEN **49/49/0** exit 0；harness 目录全量接线前后各 **171/171/0/0** 零回归；**3 条变异全 DETECTED** 且 `ci.yml` 逐字节还原 | **否**。test-plan 的 TC 清单未列这 3 个测试，只作为锁定规格的**额外回归守卫**；该切片 `tc_coverage` 仍按计划的 TC-SEL-004 与 TC-TOR-004 记 **2/2**。长程约束 #3（新增测试 > 0）由这 4 项真实满足 |
| **ADJ-027**（C1 代码 MAJOR-1 修复） | `go-test-env-contract.test.mjs` 新增 **1 个测试函数**，钉住「治理范围内不得再出现 `os.Getenv("CRCTL_PATH")`」；`go-test-env-contract.mjs` 仅把 `goTestFiles` 改为 `export`（**1 词**）供守卫复用；**四个扫描正则一字未改**，`:71-80`「其他条件守卫不标记」用例含 `CRCTL_PATH` 样例**原样保留** | **1** | RED exit 1（12 tests/11 pass/1 fail，唯一红的是新守卫，点名 `approval_crosscheck_test.go:198`）→ GREEN exit 0（**12/12/0**）；契约 CLI 对真实仓库 exit 0「**119 file(s), 0 violations**」；`go vet ./internal/governance/ ./internal/handler/` exit 0；真库两条件各一次（**runner 自建一次性 podman 实例**）：变量齐备 `PASS crosscheck-crctl pass=13 fail=0 skip=0` exit 0（与 S4 基线 **7+3+3=13 逐名一致**，零回归），`env -u CRCTL_MJS` 后 **FAIL pass=0 fail=3 skip=0** exit 1，三个调用方各自打印 `CRCTL_MJS is required` 于 `:213/:384/:176`，**skip=0 证明不再走 skip**；变异 1 条 DETECTED，按原字节还原 sha256 `043054f75b5f1e65…` match true | **否**（属修复引入的守卫，不替代任何既有 TC） |
| **ADJ-034**（C1 测试 MAJOR-1 修复） | `tools-pin.test.mjs:166-172`「ci.yml takes the tools ref from the pin file」**就地强化既有测试函数**：对每一个 `repository` 行按 `/^ {10,}\S/` 收集所属 `with:` 块，断言块内 `ref` 行**恰好一条**且 trim 后等于 `ref: ${{ steps.tools-pin.outputs.ref }}`，失败报文点名 `ci.yml` 行号 | **0**（强化既有函数，不新增） | 四步验证：①缺口证明——`ci.yml` 两处 ref 变异为 `main`（实测命中 2 处），**旧测试 exit 0、15/15/0，#15 照样绿**；②RED——保持变异应用强化断言 → exit 1、**15 tests/14 pass/1 fail**，唯一红的是 #15，报文 `the tools checkout at ci.yml:136 must take its ref from the pin step output`；③还原——2 处改回原表达式，sha256 `72c16f6b9302bb97…` match true；④GREEN——exit 0、**15/15/0** | **否**。不替代任何既有 TC、不放宽任何断言、不新增规格要求，**TC-CBE-003 的覆盖分子不变** |
| **ADJ-042**（Gate 3 后续轮，用户裁定纳入本 change） | `run-selection.test.mjs` 新增 **1 个测试函数**「an unknown flag is rejected by name before any instance is created」：以 `--evidence-dirr out` 调用 runner，断言 ①退出码非 0 ②stderr **点名该 flag** ③stderr **不含 `podman`**（证明拒绝发生在创建任何实例之前）。生产侧 `run-selection.mjs` 只补 **3 行**（if/else-if 链末的 `else { throw … }`），与同目录其余 6 个 `parseArgs` 脚本同口径 | **1** | **首次 RED 无效并已重取**：依赖树受损时子进程在 ESM `import pg` 阶段即 `ERR_MODULE_NOT_FOUND`，到不了 `parseArgs`，该次 exit 1 不能归因本缺陷（ADJ-045）。修依赖后**有效 RED** exit 1、**1 test / 0 pass / 1 fail**，stderr `disposable runner failed: spawnSync podman ENOENT`（`red-unknown-flag.tap:29-32`）→ **GREEN** exit 0、**1/1/0**（`green-unknown-flag.tap:9-11`）。回归：该文件 **14/14/0/0**（`run-selection-after-fix.tap:87-94`）、harness **173/173/0/0/0/0**（`harness-after-adj042.txt:174-181`）、ci-scope **49/49/0/0**（`ci-scope-after-adj042.tap:297-304`）。**无调用方被打破**：`.github` 内无 `run-selection.mjs` 调用，`test-ownership.json` 只用 `--selections`/`--only`，均在受识别集内 | **否**。test-plan 的 TC 清单未列该测试；TC-SEL-002 的覆盖分子不变，本项只作为「证据产物与真实执行一一对应」（G2）的**额外回归守卫**。长程约束 #3 由该真实新增满足 |

**计数口径**：三批分开如实计数，不合并、不互相顶替——① ADJ-026（S13）**4 个**；② C1 两条 MAJOR 修复合计 **1 个**（ADJ-027 的 1 + ADJ-034 的 0）；③ Gate 3 后续轮 ADJ-042 **1 个**。harness 演进 **171 → 172 → 173**（+1 为 ADJ-027 的别名守卫，再 +1 为 ADJ-042 的未知参数守卫）；`run-selection.test.mjs` **13 → 14**。生产 `ci.yml` 在 C1 两轮变异后均**按原字节还原**，Gate 3 后续轮**一个字节未改**（sha256 `72c16f6b9302bb97…` 一致）。

**回归**：C1 两条 MAJOR 修复后 harness **172/172/0/0** exit 0、ci-scope **49/49/0** exit 0（证据 `validation/c1-review/harness-after-both-fixes.txt`、`ci-scope-after-both-fixes.tap`，**属 C1 当时口径，已被下一行取代**）。ADJ-042 修复后 harness **173/173/0/0/0/0** exit 0、ci-scope **49/49/0/0** exit 0（证据 `validation/gate3-followup/harness-after-adj042.txt:174-181`、`ci-scope-after-adj042.tap:297-304`）。

## 11. 边界与授权声明

本节各项均为**本轮重新实测**，不凭记忆或历史调用结论。

### 11.1 数据库与容器边界（用户约束原文：只使用 runner 自建的一次性 podman 实例）

| 项 | 实测结果 |
|---|---|
| 真库测试所用实例 | **全部由 runner 自建的一次性 podman 实例**。选定 run `dfb7aad8…` 的 CP 输出逐个点名实例（`agent-verify-round3.txt:15/62/66/70/74/78`）：`d979348e09b0`（ci-gate-identity）、`8c5ac051aaa9`（wsd-manifest）、`9aaf08ec1a0c`（wsd-delete）、`1622bc487691`（wsd-retain）、`266f7910fdf5`（wsd-atomic）、`65a73d2293eb`（wsd-no-recreate），六个均 `released … remaining=0`；ADJ-027 的 crosscheck 两条件亦各用一次性实例（C1 当时口径） |
| 是否连接 `localhost:5432` 旧库 | **否** |
| 是否操作旧 `multica-postgres` 容器 | **否** |
| 运行前后容器清单 diff | **IDENTICAL**（本轮实跑 `diff podman-before-round2.txt podman-after-round2.txt`，无输出，标记 `CONTAINER_LIST_IDENTICAL`） |
| 当前容器清单（只读 `podman ps -a`，**本轮报告定稿前再次实测**） | 仅 2 个，且**始终 Exited**：`55e215cf1066 multica-postgres Exited (0)`、`4d2f95af6982 multica-backend Exited (0)`；`podman volume ls` 仅 `multica-pgdata`。**无残留一次性实例**（均已 released） |
| 是否放宽 nonce 门禁 | **否**。`PASS ci-gate-identity pass=16 fail=0 skip=0`，SC-CBE-002 的每条单独退化都被拒绝且由独立命名子测试逐条归因 |
| 真库叶子测试合计 | **46**（16+2+1+23+1+3），**全部 skip=0** |

### 11.2 凭据边界（用户约束原文：不读取、打印 PAT 或其他凭据）

- **未读取、未打印、未创建、未轮换任何凭据**；secret 由管理员处理。
- TC-CCF-003 因管理员未完成 `AIFIRST_TOOLS_READ_TOKEN` 最小权限更新而**如实列为未闭合**。
- 一次性库口令为 `randomBytes(18)` 生成、**job 级**、随服务容器销毁，**不复用于任何非一次性资源**；handle 与本 change 写出的其他文件均不含明文口令。
- **唯一例外已如实呈报**（ADJ-009）：`::add-mask::<角色口令>` 是 GitHub Actions 规定的遮蔽协议，runner 只遮蔽它已见过的值，故该命令本身必然先把口令送到原始 stdout。TC-CBE-001 的断言口径是「**除这一条 mask 命令外**无任何日志行携带口令」，**不是**「stdout 全程不含口令」。

### 11.3 仓库边界（用户约束原文：不夹带他人未提交改动）

| 仓库 | 本轮实测 | 处置 |
|---|---|---|
| **multica**（PROJECT_ROOT） | HEAD `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`、branch `main`、tracked **7336**、**22 `M` + 27 `??`、0 deleted** | 与用户给定基线一致。本 change 的 49 个文件（22 改 + 27 新）即这 22+27；**未清理、未混入他人改动** |
| **tools**（sibling） | **本轮报告定稿前重新实测**：HEAD `e52b8081f159d581bf62f82447c76f818fc52426`、`origin/main` **同值**、本地领先 **0**；`git merge-base --is-ancestor e52b808… origin/main` → **YES**；`git ls-remote origin refs/heads/main` 亦同值（`gate3-followup/tools-push-verified.txt`）。该仓仍有 **6 处**既有未提交改动 | **pin 已在 origin 上**（ADJ-025 **resolved**）。用户授权原文「ADJ-025 授权执行推送 e52b808」→ **只推送该一个提交**（`f774ffb..e52b808`，exit 0），**未改 pin 文件、未夹带那 6 处改动**（推送前后逐字一致）。remote 核实为 `https://github.com/OldBoy405/AI-First-tools.git`，与 pin 的 repository 逐字一致，**非代理地址** |
| **记录仓**（AI First Platform） | 存在大量他人未提交改动 | **不清理、不混入**；只写本 change 目录下的记录文件 |
| **stdd 资源仓**（RESOURCE_ROOT） | 用户明令「不要再动 stdd 仓库的内容」 | **本 Agent 写入数 = 0**。全部 stdd 缺陷（ADJ-015/032/033/037/038/040/041/044）只登记不修；ADJ-036 的 `item["cp"]` → `item.get("cp")` 由**用户本人直接修改** |

### 11.4 授权边界

- **multica 的 Git 提交、推送、部署：本轮均未执行，且不从 Gate 确认自动推导授权。** 本报告与 Gate 3 呈报**不构成**任何提交/推送/部署授权；49 个文件仍全部停留在工作区（22 `M` + 27 `??`）。
- **tools 的推送是独立取得的显式授权，已执行且只执行了被授权的那一个提交**：用户原话「ADJ-025 授权执行推送 e52b808」→ `git push origin e52b8081f159…:refs/heads/main`（`f774ffb..e52b808`，exit 0）。**该授权不延伸到 multica，也不延伸到 tools 的其他改动**；推送前核实 remote、ahead/behind 与该 commit 的 5 文件 260 插入 10 删除，推送后核实那 6 处未提交改动逐字未变。
- 用户已授权的动作（U5）：一次性 podman 实例、启动 WSL AIFI-ISO、npm 安装 pg、推送触发 CI、管理员更新 PAT。**这不等于**授权读取或创建 PAT、擅自修改仓库 secret、部署或超范围操作。本轮行使情况：**一次性 podman 实例＝已行使**（6 个，均 released）；**推送＝只行使了 tools pin 那一半**，multica 推送未授权故 **CI run 次数 = 0**；**管理员更新 PAT＝未行使**（属管理员职责，TC-CCF-003 未闭合）；**WSL AIFI-ISO＝未行使**（ADJ-024 环境前置不成立，用户已裁定保持 UNCOVERED）。
- **授权口径偏离已如实声明（ADJ-045）**：为重建被清理事故掏空的依赖树，执行了 `pnpm install --frozen-lockfile`，**宽于 U5 字面的「npm 安装 pg」**；作用范围限于被 git 忽略的 `node_modules` 与 pnpm store，`pnpm-lock.yaml` 与 `package.json` 的 `git status` 为空。**不冒充为字面授权。**
- **U3**（若发现现有代码允许禁新建场景，停下报告由用户裁定）：S10 已按此上报，未擅自扩大范围。
- **U4**（前端先保证 views typecheck 与本地 vitest，如实报告；暴露其他功能性失败先报告再裁定）：typecheck **exit 0 / 0 条 TS 错误**、`use-logout.test.ts` **2/2 ✓** 已达成；**views 全量 vitest 本轮 1 failed / 6371 passed、exit 1，如实记为未通过**（§5.1.1）。失败项 `chat-window-messages.test.tsx:84` 已按名字与行号证明属 HEAD 既存 flake 成员（ADJ-020），单文件重跑 **4/4 exit 0**；**本轮报文是 `AssertionError`，与 ADJ-020 记录的 `Test timed out in 5000ms` 不同模式，已如实区分，不套用旧结论**。按「先报告再裁定范围」**未扩大范围**：未加 retry、未调超时、未 skip、未改任何上游测试。
- **D2**（不得仅改清单，不得擅自为 append-only 触发器开删除例外）：未开任何删除例外；ADJ-014 的两张 retain 表 TRUNCATE 守卫按用户裁定补齐。
- **multica fork 规则**：新逻辑置于新文件，上游改动仅为最小 `// AIFIRST:` 钩子，**代码注释用英文**，已按 `CUSTOM.md` 登记 **#317–#333 共 17 行**（M31 表头与汇总同步为 17；本轮重测每行**未转义竖线恰好 7 个 / 6 单元格**），使用**真实 STDD change ID** `2026-11-12-fork-ci-test-evidence-trust`，**未编造 CR 身份**。记录仓文档用中文。
- **URL 纪律（用户反复明令，本轮逐次核对）**：凡需 URL 的工具调用，其 URL 必须与当前任务目标一致，**严禁替换为 routify 等临时代理地址**；历史调用不代表正确。**本轮未调用任何需要 URL 的工具**；全部网络操作只有两类，且均指向已核实的真实地址：① `git push` / `git ls-remote` → `https://github.com/OldBoy405/AI-First-tools.git`（与 pin 的 repository 逐字一致）；② pnpm 自行从**官方** `https://registry.npmjs.org/` 重取被掏空的切版包。**未设置任何代理、未改任何 registry 配置。**
- **esbuild 修复**（ADJ-039，用户授权「授权修 esbuild 二进制后重跑」）：使用**官方 registry**，**未替换任何 URL 为临时代理地址**；含一次 no-op 重建的如实记录。

## 12. 证据索引

所有路径相对 change 根 `projects/multica/changes/2026-11-12-fork-ci-test-evidence-trust/`。

### 12.1 选定 run（同次执行证据）

| 路径 | 内容 |
|---|---|
| `validation/runs/dfb7aad8-7539-486b-aa59-297d57a87d1a/agent-verification-report.md` | 18 个 CP，各 `PASS (exit_code=0)`。**与旧 run 产物 sha256 相同属正常**：正文不嵌入 run id（`grep -c "dfb7aad8\|7cd120df"` → **0**），区分依据是 `run_id` 字段与目录名（§6.3） |
| `validation/runs/dfb7aad8-7539-486b-aa59-297d57a87d1a/tc-evidence.json` | 实测 `run_id` = `dfb7aad8…`、**checks 18 条**、`kind` 全为 `command`、`result` 全为 `pass`、**18 个不同 TC**、`inputs` **823**、`coverage` **[]**、manual **0**、1 个 artifact |
| `validation/runs/dfb7aad8-7539-486b-aa59-297d57a87d1a/inputs/` | `agent-specs/`（5 个 capability YAML）、`config.yaml`、`test-plan.md` |
| `validation/gate3-followup/agent-verify-round3.txt` | **94 行原文**：18 CP 全 `PASS: exit_code (expected: 0, got: 0)`；`Results: 18 passed, 0 failed`；`Report:` 指向新 run；`REVIEW_PENDING` 列 4 项人工 TC 与 confirm 命令；`VERIFY_EXIT=1` |
| `validation/gate3-followup/gate3-approve-refused.txt` | **Gate 3 approve 被拒原文 3 行**：「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」「Gate 3 拒绝批准：选定 run 证据不足。」`APPROVE_EXIT=1`。**ADJ-046 的唯一直接证据**；批准前无写入（`gate status` 仍 **Gate 3 ⬜ pending**、`.stdd.yaml` 无 `selected_evidence`），见 §1.1 |
| `validation/gate3-followup/ci-check-failures-round3.txt` | **29 行原文（第 3 轮，历史；当前见 `ci-check-failures-scopeB.txt`）**：✅8 ⚠1 ⏭0 ❌1；(l) `Anchoring: L4 >= L4`；`13 个切片均有验证证据`；(b) 范围蔓延 37 文件（口径缺陷见 ADJ-041）；❌ TC 覆盖 **0/22**＋`缺少或重复必需 check（当前运行未完成）`；自动化检查覆盖 **10/10**；`CHECKFAILURES_EXIT=1` |
| `validation/runs/add97e96-1676-4191-ae65-2ebd6524d585/agent-verification-report.md` | **第 5 轮（当前有效）**：18 个 CP 各 `PASS (exit_code=0)`；sha256 `c58c545d211d6e2465350a3781580acbf4742ac66f38f68dcc7a3f0ea52506b5`（与第 3 轮同：正文不含 run id） |
| `validation/runs/add97e96-1676-4191-ae65-2ebd6524d585/tc-evidence.json` | **第 5 轮**：`run_id` 同值、`selected_run` 同值；`checks` **18 条全 pass**、`artifacts` 1 条 `agent-report`、`inputs` **823**、`coverage_files` `[]`、`manual` 缺失（TC-TOR-005 未确认） |
| `validation/gate3-followup/agent-verify-scopeB.txt` | **91 行原文**：`Results: 18 passed, 0 failed`；`REVIEW_PENDING` 仅 `TC-TOR-005/main`；`VERIFY_EXIT=1` |
| `validation/gate3-followup/ci-check-failures-scopeB.txt` | **29 行原文**：✅8 ⚠1 ⏭0 ❌1；❌ TC 覆盖 **0/19**（18 ≠ 19）；`CHECKFAILURES_EXIT=1` |
| `validation/gate3-followup/podman-after-scopeB.txt` | 第 5 轮结束后容器清单：两条旧容器仍 `Exited (0)`；运行前为控制台观察（同值），未另存 |
| `validation/handoff/handoff-to-successor-change.md` | **175 行移交包**：3 个 Scenario 与 3 个 TC 定义（逐字）、缺失前置、复现命令、后继 change 5 条入口判据 |
| `validation/gate3-followup/harness-after-adj042.txt` | `:174-181` tests **173** / pass 173 / fail 0 / cancelled 0 / skipped 0 / todo 0，duration 2584.8845ms |
| `validation/gate3-followup/ci-scope-after-adj042.tap` | `:297-304` tests **49** / pass 49 / fail 0 / skipped 0 |
| `validation/gate3-followup/run-selection-after-fix.tap` | `:87-94` tests **14** / pass 14 / fail 0 / skipped 0（ADJ-042 修后，13→14） |
| `validation/gate3-followup/red-unknown-flag.tap`、`green-unknown-flag.tap` | ADJ-042 的**有效** RED（`:29-32` tests 1 / pass 0 / fail 1，stderr `spawnSync podman ENOENT`）与 GREEN（`:9-11` tests 1 / pass 1 / fail 0） |
| `validation/gate3-followup/tools-push-verified.txt` | 推送后只读核实：HEAD = origin/main = `ls-remote` = `e52b8081f159…`，`LSREMOTE_EXIT=0`、`ANCESTOR_EXIT=0`、ahead 0、6 处未提交改动未夹带、remote 为真实 GitHub 地址 |
| `validation/gate3-followup/pin-reachability-order.txt` | 两个消费者的完整步骤序列与 `=> reachability step index 3 < tools checkout index 5 : true`（`:10`）、`10 < 12 : true`（`:35`）→ 用户要求的「前移」**已满足，未改 ci.yml** |
| `validation/gate3-followup/podman-before-round2.txt`、`podman-after-round2.txt` | 运行前后容器/卷清单，`diff` 无输出 → `CONTAINER_LIST_IDENTICAL` |
| `validation/gate3-followup/pnpm-install-restore.txt`、`pnpm-cli-restore.txt`、`precheck-views-typecheck.txt`、`precheck-selection-identity.txt` | ADJ-045 两阶段环境修复原文（install exit 0 / Done in 21m31.4s / pg 8.20.0；pnpm 恢复 10.28.2 exit 0；两项预检 exit 0） |
| `validation/c2-quality-round3/pnpm-typecheck-force.txt` | **真实执行**：Tasks 10 successful/10 total、**Cached 0/10**、Time 1m20.851s、`TYPECHECK_FORCE_EXIT=0`、`error TS` 计数 **0** |
| `validation/c2-quality-round3/pnpm-lint-force.txt` | **真实执行**：7 successful/7 total、**Cached 0/7**、Time 29.296s、`LINT_FORCE_EXIT=0`；7 个包全 **0 errors**（warning：ui 3 / core 2 / views 21） |
| `validation/c2-quality-round3/pnpm-typecheck.txt`、`pnpm-lint.txt` | **缓存回放，不作为真实执行证据**：`Cached: 10 cached/10 total`＋`>>> FULL TURBO`（149ms）、`7 cached/7 total`（103ms）。保留以说明为何必须加 `--force` |
| `validation/c2-quality-round3/pnpm-version.txt` | `10.28.2`、`PNPM_VERSION_EXIT=0`（附外层 pnpm 11 的「pnpm field ignored」WARN，事故前同样存在） |
| `validation/c2-quality-round3/views-vitest.txt` | **8735 行**：`:8707` FAIL 行、`:8727` `Test Files 1 failed \| 505 passed (506)`／`Tests 1 failed \| 6371 passed (6372)`、Duration 199.70s、`VITEST_EXIT=1`；`:8161` `✓ auth/use-logout.test.ts (2 tests)` |
| `validation/c2-quality-round3/vitest-single-chat-window.txt` | 失败文件单独重跑：`Test Files 1 passed (1)`／`Tests 4 passed (4)`、`SINGLE_EXIT=0` |
| `validation/runs/7cd120df-d9d1-4f31-a9b5-e26b5a13606a/` | **旧 run，已失效不得沿用**（受审输入被 ADJ-042 改动 + 执行环境重建，见 §6.5）；产物保留留痕 |
| `validation/runs/97da35cc-fdac-4d9d-bbaa-60960538d76e/` | **旧 run，KeyError 崩溃，不可复用**（见 §6.5） |

### 12.2 C1–C5 产物

| 路径 | 内容 |
|---|---|
| `validation/c1-review/triage.md` | 三路评审返回概览与逐条处置；§4.1/§4.2 两条 MAJOR 的四步验证；§3.11–3.14 记录更正；docs_skills 重算 **20 个** Gate 2 manifest 哈希 + fingerprint、18 处 raw 逐字节匹配 |
| `validation/c1-review/mutation-ref-main-old-test.tap` | 缺口证明：ref 变异为 main，**旧测试照样绿**（15/15/0） |
| `validation/c1-review/red-ref-main-new-test.tap` | RED：15 tests/14 pass/1 fail，点名 `ci.yml:136` |
| `validation/c1-review/green-ref-restored.tap` | GREEN：还原后 15/15/0 |
| `validation/c1-review/harness-after-both-fixes.txt` | harness **172/172/0/0** exit 0 |
| `validation/c1-review/ci-scope-after-both-fixes.tap` | ci-scope **49/49/0** exit 0 |
| `validation/c2-quality/harness-full.txt` | **依赖重建前口径（已被 §12.1 的 173/173 取代）**：`:173-181` tests 172 / pass 172 / fail 0 / cancelled 0 / skipped 0 / todo 0，`EXIT_CODE=0` |
| `validation/c2-quality/ci-scope.txt` | **重建前口径**：`:297-305` tests 49 / pass 49 / fail 0 / skipped 0，`EXIT_CODE=0`（本轮重测同值，见 §12.1） |
| `validation/c2-quality/typecheck-views.txt`、`typecheck-core.txt` | **重建前口径**：各 `:6` `EXIT_CODE=0`（本轮由全量 turbo `--force` 10/10 覆盖） |
| `validation/c2-quality/pnpm-typecheck-after-fix.txt` | **重建前口径**：`:73-77` Tasks **10 successful/10 total**、Cached 0/10、`EXIT_CODE=0` |
| `validation/c2-quality/pnpm-lint.txt` | **重建前口径**：`:125-129` Tasks **7 successful/7 total**、Cached 0/7、Time 48.35s、`EXIT_CODE=0`（0 errors，仅 unused eslint-disable 类 warning） |
| `validation/c2-quality/agent-verify-round2.txt`、`ci-check-failures-round2.txt` | **旧 run `7cd120df…` 的同次执行证据，已失效不得沿用**（§6.5）；保留留痕，本轮以 `gate3-followup/*-round3.txt` 取代 |
| `validation/c3-diff/README.md` | **49/49** 逐文件审查（22 改 + 27 新）；§4.1 ADJ-042；删除事故与指纹核验 **22/22 numstat + 27/27 行数** |
| `validation/c4-failure-modes/README.md` | 143 行：**8 项检查完成、2 项命中、1 项观察**；§4 SKIPPED 表与边界理由 |
| `validation/c5-experiences/` | 新增 **EXP-2026-0006**；既有经验命中次数更新 |

### 12.3 切片证据（S1–S13）

`validation/s1-selection-decision/`、`s2-tools-pin/`、`s3-env-contract/`、`s4-baseline-ownership/`、`s5-ci-evidence/`、`s6-ci-provision/`、`s7-gate-conditions/`、`s8-wsd-manifest/`、`s9-wsd-behaviour/`、`s10-wsd-no-recreate/`、`s11-tools-access/`、`s12-views-typecheck/`、`s13-ci-wiring/`

重点引用：

| 路径 | 用途 |
|---|---|
| `validation/s4-baseline-ownership/windows-clock-granularity.md` | ADJ-006 的 UnixNano 证伪 |
| `validation/s8-wsd-manifest/regression-handler-failing-diff.txt` | handler 整包**按测试名逐条对账**口径（不得以计数差判回归） |
| `validation/s12-views-typecheck/full/`（含 `reconcile.mjs`） | ADJ-020 三组 A/B 实测，脚本可重跑 exit 0 |
| `validation/s13-ci-wiring/README.md` §3、§4、§7、§14 | ADJ-026 的 4 个新增测试、3 条变异全 DETECTED、`ci.yml` 逐字节还原 |
| `validation/s2-tools-pin/wsl-isolation-probe.txt` | ADJ-024 的只读探针原文（2026-11-13T02:19:23+0800） |

### 12.4 规划与调整记录

| 路径 | 内容 |
|---|---|
| `test-plan.md` | **在册 19 个 TC（18 command + 1 manual TC-TOR-005）**；3 个场景已移交（§七，ADJ-047）；证据计划 fence 现为 **19 条 check**；Gate 2 于 `2026-11-13T18:33:41` 重签 |
| `slices.md` | `:43-55` 13 切片 TC 映射；`:57` 规划断言（已被证伪，原文保留）；`:59` C1 更正 |
| `tasks.md`、`phase-context.md` | 任务清单与阶段上下文（14.10 仍**未勾选**） |
| `pending-adjustments.yaml` | **47 条**（ADJ-001…ADJ-047），**26 已处置 / 21 未决**（未决＝**5 major** + 16 minor）；逐字保留，YAML 可解析 |
| `design-adjustments.md` | **C6 权威产物**（按资源根 3.0.7 口径生成 `.md`，不生成同名 `.yaml`）：**47 条汇总行 + 47 条详细说明 + 修订需求清单 + 14 条 Gate 3 呈报要点**；ADJ-046 的三路径表与 ADJ-047 的收窄记录均在此 |
| `validation/acceptance-report.md` | **TC-TOR-005 的验收报告**（已按第 5 轮 run 更新 §0 / §2.1′ / §2.4′；旧章节标注为第 3 轮历史；**待用户人工核对**） |
| `validation/handoff/handoff-to-successor-change.md` | **3 个移交场景的取回点**（原文、缺失前置、复现命令、后继 change 入口判据） |
| `.stdd.yaml` | `design_adjustments.count: 47`（与台账条数实测相等）；`current_phase: build`、`mode: thorough`、`long_range.mode: full_auto`；`phases.build.slices_completed` 13 项证据字段；**`phases.build` 无 Gate 3 批准字段、无 `selected_evidence`（Gate 3 未批准）** |
