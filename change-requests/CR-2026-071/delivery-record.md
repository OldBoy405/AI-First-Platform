---
id: CR-2026-071-delivery-record
type: delivery-record
cr-ref: CR-2026-071
title: CR-2026-071 交付记录（P0/P1 实现、所跑测试、线上核验、未覆盖边界）
target-version: 0.44
created: 2026-09-28T14:10:00+08:00
---

# CR-2026-071 交付记录

> TASK-05 落盘物（AC-3 / AC-6）。判据唯一事实源：`plan.md` §5 checklist、§6 证据命令表与机械判定；
> 授权依据：Ray 在 AIFI-36 评论 `01a0e687-ef04-71fd-899d-086a432847e2`（裁定「包 1」）与
> `01a0e68a-2a5d-72fc-9a54-5da9bdc5aaa0`（(B) 定案：主镜像自行修 `review-dev-plan`，071 内不改该文件）。
> 本记录不含 checkpoint / 发布 / merge / 审批语义（B-03）。

## 1. P0/P1 实现

### 1.1 P0 — 委派投递判定统一（FR-1、FR-2）

- **唯一规范源**：`multica/cr-prompts-revised/delegation-contract.md`（`CONTRACT-BEGIN/END` 之间 666 字节正文）；
  平台侧事实源直指 `server/internal/handler/admission.go` 的 `DispatchStatus` / `DispatchReasonCode`。
- **四份提示词全文替换**（multica `6bf26d1a6`）：`cr-prompts-revised/{requirement-writer,dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md`
  各 1 处委派判定子句替换（`quality-reviewer-agent.md` 命中 2 行），`enqueued` 成功语义与
  `target_unavailable` status 语义双清零。
- **`bak/` 审计与修正**（multica `1c4f53ee6`）：`bak/README.md` 留处置表（维护 2：`cr-coordinator-agent.md`、`quality-reviewer-agent.md`；
  排除 4，各留一行理由），两份维护副本内联合同全文；回归按该表解析「需维护」集合，集合与留痕不各自漂移。
- **四个线上 Agent 指令同步**：`agent update` 注入合同全文，ID / 绑定 / model / skill 列表 / 并发数不变
  （TASK-04 记 `changedFields=[]`）；更新前快照 4 份（KB `6ba719fc`）按 B-04 只作审计件、**不是回滚目标**
  （回滚走「向前写回合同正文 + 重跑 cmd-04～07」）。
- **定制台账**：multica `CUSTOM.md` #97（multica `8bf330e54`，工作区纪律 #10 强制登记）。

### 1.2 P1 — 单一合同源与漂移回归（FR-3）

- 合同源即唯一事实源（§1.1 第一项）：四份提示词、2 份维护 bak、四个线上 Agent 三处逐字内联同一正文，
  运行时不读路径引用（PRD 口径）。
- 回归 `multica/cr-prompts-revised/test/delegation-contract.test.mjs`（multica `daced27c2`）：
  ① 枚举对齐断言直读 `admission.go` 源字面量（平台新增 status 而合同未同步即变红）；
  ② 7+3 场景向量（含 AIFI-35 的 `status=queued, reason_code=queued` 判成功、零 `DELEGATION_FAILED`）；
  ③ 四份提示词 + 2 份维护 bak 无漂移。

### 1.3 FR-4 — requirement-authoring 评审前 checkpoint 恢复（TASK-02）

- tools CR worktree（`requirement/CR-2026-071`）落盘：`aee0208`（3 声明文件）+ `045d8d6`（第 4 授权件）。
- **文件集口径「3 声明 + 1 授权」**（SDD v0.2 §4.4 授权偏离注）：
  - 声明 3：`pipeline-templates/requirement-authoring.pipeline.json`、`pipeline-templates/_index.yml`、
    `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`；
  - 授权 1：`skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` —— 机械必需件（其 T05 断言枚举
    requirement-authoring 的 `push-progress` 节点集合为空集，恢复 `...0003` 后必然红），非新增范围。
- **结构事实**（cmd-03 / cmd-02 实测）：`nodes=6`；节点序
  `requirement-register → write-requirement-prd(…0002) → push-progress(…0003) → review-requirement(…0004) → 需求审批 → approve-requirement`；
  评审前 `push-progress` 恰 1（id `00000000-0000-0000-0011-000000000003`）、审批后 `push-progress` 为 0；
  `_index.yml` 台账 `nodes: 5 → 6`；`reviewLoop` repair 仍指回 node-2，回修后正向流必经本节点。
- **SDD v0.2 修订**（KB `1927dbe6`）：dep-7 / §4.4 / §6 FR-4 / §9 `scope_in` 订正为 4 文件并引用授权评论 id；
  结论不受影响（节点恢复与结构测试语义未变，仅补齐 FR-4 的机械必需件）。

## 2. 所跑测试（plan §6 cmd-01～cmd-14）

| 证据 | 表行命令（repo / cwd） | 结果 |
|---|---|---|
| cmd-01 | multica・`.`：`node --test cr-prompts-revised/test/delegation-contract.test.mjs` | **19 tests / 19 pass / 0 fail**（exit 0） |
| cmd-02 | tools・`.`：`node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | **36 / 36 / 0**（exit 0；原红项经 tools 主镜像 `09085f0` 修复、`d8ef2db` 合入本 CR 分支后转绿，见 §2.1） |
| cmd-03 | tools・`.`：`node -e "JSON.parse(…requirement-authoring.pipeline.json…)"` | `pipeline-json-ok` |
| cmd-04～07 | `multica agent get <id> --output json` ×4 | 四份全部合同正文逐字命中、`enqueued=0`、`target_unavailable` 仅 reason_code 语义（见 §3） |
| cmd-08 | AIFI-35 `--roots-only --summary` | 3 根，与启动基线一致（§4） |
| cmd-09 | 逐根 `--thread <root> --tail 30`（模板，3 次） | 3 根尾序列评论 id 与基线逐一相同（§4） |
| cmd-10 | `multica issue get 01a0ddf8…` | `status=in_progress`、`revision=57`、`updated_at=2026-09-27T02:01:52Z`，与基线一致（§4） |
| cmd-11 | KB：`crctl git diff --stat origin/master HEAD -- change-requests/CR-2026-001` | 回执 `ok=true / exit=0`；正文去空白 0 字符 → 零文件变更 |
| cmd-12 | KB：`crctl git diff --unified=3 … -- change-requests/_backlog.yml` | 回执绿；正文**无** `CR-2026-001` 子串 |
| cmd-13 | KB：`crctl git diff --stat … -- change-requests/_history.yml change-requests/_index.yml` | 回执绿；正文 0 字符 → 零变更 |
| cmd-14 | KB：无路径限定 `crctl git diff --stat origin/master HEAD`（非空阳性对照） | 回执绿；正文非空；文件集仅 `change-requests/CR-2026-071/**` + `change-requests/_backlog.yml`（无 `CR-2026-001` 路径）；数值见 §2.3 与文末《最终复测》 |

附（TASK-02 第 4 件对应回归）：`skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` = **23 tests / 23 pass / 0 fail**。

### 2.1 cmd-02：原红项根因、修复与复跑（Ray 授权，comment `01a0e6ac`）

- **TASK-05 执行期现状**（tools CR worktree `045d8d6`）：`36 tests / 35 pass / 1 fail`；唯一红项
  `✖ CR-2026-066 AC-3/AC-4: 四 review SKILL 的 clean 前置 + PASS 发布 + 对账 + 权限面四处载体（断言 A/B/C/D）`，
  `AssertionError [ERR_ASSERTION]: skills/develop/review-dev-plan/SKILL.md 缺对账失败语义 CONTRACT_DRIFT`。
- **BASE 对照**（tools 主镜像 `3b4a131`，当时不含本 CR 任何改动）：同命令 `36 tests / 35 pass / 1 fail`，
  唯一红项同名、同断言消息、同根因 → 该红项与 071 改动**无因果关系**（FR-4 相关断言——6 节点 /
  评审前 `push-progress` 恰 1 / `...0003` 在位 / 审批后 0——在该测试内全绿；行号偏移 `:673` → `:684` 系本 CR 在该文件
  新增断言所致）。
- **修复事实**：Ray 在 tools 主镜像提交 `09085f0`
  （`docs(review-dev-plan): 恢复 CONTRACT_DRIFT 判定并补 BLOCK 分支不发布说明`，两处字面落位 `:164`/`:167`，
  与 CR worktree 副本逐字节相同：`sha256 63e1e10682bee99fbc4f955e2914e7bd12d6236e28572e20fd063cd6407b7286`），
  并以 `d8ef2db`（`Merge origin/main (09085f0) into requirement/CR-2026-071：对齐 trunk 基线`）合入本 CR 分支。
- **复跑实测**（tools CR worktree `d8ef2db`，命令同表行）：`tests 36 / pass 36 / fail 0 / skipped 0`、exit 0 ——
  与 `write-test-report` 机器区 cmd-02 逐项一致。
- **范围影响**：本 CR diff 因此含 `skills/develop/review-dev-plan/SKILL.md`（经 tools 主镜像合并带入，非本 CR 新增编辑）；
  本 CR 未改该文件断言、未改 `pipeline-structure.test.mjs`、未为过门禁放宽任何守卫断言。
- 遗留瑕疵（不阻塞门禁，留待后续小改）：`:164` 的 ` - 判定不等 → **`CONTRACT_DRIFT` 技术中止**……` 接在第 4 条原文末尾（同行续写），
  断言只做字面包含；Ray 决定先按落盘字节随本 CR 合并，渲染整理另开一次小改。

### 2.2 AIFI-35 七证据合取（AC-6）

- cmd-08 ∧ cmd-09 ∧ cmd-10 ∧ cmd-11 ∧ cmd-12 ∧ cmd-13 ∧ cmd-14 逐条通过，明细见 §2 表与 §4；
  机械判定按 plan §6（回执绿 ∧ 正文判定 + cmd-14 非空阳性对照），**不是** raw stdout 为空。
- 作用域声明（B-02）：文件账本面以 KB `merge-base origin/master HEAD = 9ce4cde52d2237810cf0c7121b47d87762139f09`
  为 BASE，锚定语义是「本 CR 未改动 CR-2026-001 文件与账本」，不是「CR-2026-001 自身历史无变化」；
  multica / tools 两仓无 CR-2026-001 路径，其改动集由各 TASK 文件侧范围核验锁定。

### 2.3 cmd-14 两次实测

- 交付记录提交前：`… | 21 files changed, 1432 insertions(+), 3 deletions(-)`。
- 交付记录提交后（最终）：见文末《最终复测》。

## 3. 线上核验（cmd-04～cmd-07 成品原文）

| 证据 | Agent | id | instrLen | 合同正文逐字 | `enqueued` | `target_unavailable` |
|---|---|---|---|---|---|---|
| cmd-04 | requirement-writer | `6317495b-d913-4d47-be79-0c0b342b03fd` | 3715 | true | 0 | 1（仅 `…是 reason_code，不得当作 status` 子句） |
| cmd-05 | dev-agent | `ff6fcbb6-6bb6-42fb-9d88-03493c771411` | 4450 | true | 0 | 1（同上） |
| cmd-06 | quality-reviewer-agent | `2ed1a9de-4c8e-4b78-bfb1-055af99c6681` | 2770 | true | 0 | 1（同上） |
| cmd-07 | cr-coordinator-agent | `87ca2271-f4d8-4865-aef1-9a24523e1a20` | 5957 | true | 0 | 1（同上） |

四条 `instrLen` 与 TASK-04 交付记录所载更新后长度（requirement-writer 3715 / dev-agent 4450 /
quality-reviewer-agent 2770 / cr-coordinator-agent 5957）逐一相等，且合同正文逐字命中 →
TASK-04 之后线上指令无漂移。判定三元组 `status=queued|coalesced|deferred` 四份齐备；
`blocked + reason_code` 失败、目标缺失 outcome 失败、仅 mention 人类成员不失败三句四份齐备。

## 4. AIFI-35 零改动核验（启动基线 vs 全部验证完成后复测）

| 证据 | 启动基线 | 复测 | 判定 |
|---|---|---|---|
| cmd-08 根 id 集合 | 3 根：`01a0de2a…b858`(rc=15, la=2026-09-26T17:31:05Z)、`01a0dec7…8d50`(rc=17, la=2026-09-27T01:16:43Z)、`01a0e076…52bf`(rc=8, la=2026-09-27T02:01:52Z) | 同上（id / reply_count / last_activity_at 全等） | 新根零新增 ✔ |
| cmd-09 逐根尾 30 条 | root1 16 条、root2 18 条、root3 9 条（含根） | id 序列逐一相同 | 零新增评论 id、零新增 reviewer verdict、零新 reviewer run ✔ |
| cmd-10 Issue 对象 | `status=in_progress`、`revision=57`、`updated_at=2026-09-27T02:01:52Z` | 全等 | ✔ |
| cmd-11 / cmd-13 | KB 分支 vs `merge-base 9ce4cde5…`：`change-requests/CR-2026-001`、`_history.yml`、`_index.yml` 正文 0 字符 | 同 | 零变更 ✔ |
| cmd-12 | `_backlog.yml` 正文无 `CR-2026-001` 子串 | 同 | ✔ |
| cmd-14 | 正文非空、文件集仅本 CR 路径 + `_backlog.yml` | 同（数值见文末） | 阳性对照成立 ✔ |

跨会话交叉核对：本轮启动基线（3 根 / `revision=57`）与 TASK-04 交付评论所载 AIFI-35 前置只读确认值一致 →
本 CR 全程未触碰 AIFI-35 的状态、账本与评审，亦未重复触发其 reviewer。

## 5. 未覆盖边界（含 SDD §9 `follow_up`）

1. reviewer `crctl git` 写禁令与 Skill 提交顺序的矛盾二选一（窄放行 `files[]` vs 提交移出 reviewer）**待决策**，
   不在本 CR 范围。
2. 平台未来新增 status 时，合同回归会变红 → 须以跟进 CR 同步合同与四处内联（本 CR 只保证「变红可见」）。
3. `bak/` 排除副本（`dev-agent.md`、`requirement-writer.md`、`delivery-agent.md`、`squad-CR协调小组.md`）
   若日后重新启用为部署来源，须先补进回归覆盖再部署。
4. cmd-02 原红项（`review-dev-plan/SKILL.md` 缺两 token）已由 Ray 在 tools 主镜像 `09085f0` 修复、
   `d8ef2db` 合入本 CR 分支；cmd-02 复跑 `36/36` 绿（§2.1），该文件随本 CR diff 一并交付。
5. 未执行（不适用，B-03）：`crctl checkpoint` / 发布 / merge / 审批；线上指令以 `agent update` 即时生效，
   无 feature flag 灰度，故「回滚」按 TASK-04 §2 的向前恢复策略而非开关回退。
6. 未改平台 admission 返回值（`scope_out`）：本 CR 只统一 Agent 侧判定与回归，不改变平台回执语义。

## 6. 交付提交索引

| 仓 | 提交 | 内容 |
|---|---|---|
| multica | `6bf26d1a6` | TASK-01 四份提示词判定子句全文替换 |
| multica | `daced27c2` | TASK-03 合同源 + 漂移/枚举/场景回归 |
| multica | `1c4f53ee6` | TASK-04 `bak/README.md` 处置表 + 2 份维护副本修正 |
| multica | `8bf330e54` | `CUSTOM.md` #97 台账 |
| tools | `aee0208` + `045d8d6` | TASK-02 checkpoint 恢复（3 声明 + 1 授权件；受控 `crctl git revert a285c31 d398a4c` 原样恢复） |
| tools | `09085f0` | 主镜像修复 `review-dev-plan/SKILL.md` 两处守卫字面（Ray 授权，comment `01a0e6ac`）（Phase 2 门禁修复） |
| tools | `d8ef2db` | `09085f0` 合入 `requirement/CR-2026-071`（本 CR 分支从 trunk 取得该修复） |
| KB | `6ba719fc` | TASK-04 四个 Agent 更新前快照（审计件） |
| KB | `e137986f` / `f83cbc28` | TASK 台账（TASK-01/03/04；TASK-02） |
| KB | `1927dbe6` | SDD v0.2 授权偏离订正 |
| KB | 本记录提交 | TASK-05 交付记录 |

---

## 最终复测（交付记录提交后，同表行、同受控入口）

- 锚定（TASK-05 启动 → 复测）：`origin/master = 9ce4cde52d2237810cf0c7121b47d87762139f09`（未前移）；
  `HEAD` 启动 `f83cbc28613dca24f0bd8a102235cc0da0fce4ac` → 记录提交 `40c78df1b5dca9d72f2b462a7a8a146c73a23db8`。
- cmd-11：回执 `ok=true / exit=0`；正文去空白 0 字符。✔
- cmd-12：回执绿；正文无 `CR-2026-001` 子串。✔
- cmd-13：回执绿；正文 0 字符。✔
- cmd-14：回执绿；正文非空，`22 files changed, 1587 insertions(+), 3 deletions(-)`；文件集 =
  `change-requests/CR-2026-071/**`（含本记录自身）+ `change-requests/_backlog.yml`，无 `CR-2026-001` 路径。✔
  （较提交前 21 文件恰多本记录自身一项。）
- AIFI-35 复测（同 §4）：cmd-08 3 根、cmd-09 三根尾序列、cmd-10
  `status=in_progress / revision=57 / updated_at=2026-09-27T02:01:52Z` 均与启动基线全等。✔
- 文件侧范围核验（plan §6 标准，受控 `crctl git`）：BASE `f83cbc28` → C（记录提交）文件集 = 本文件单项；
  `crctl git status --short` 干净。

---

## 附录 A — 线上指令指纹（复核用）

复核方式：`multica agent get <id> --output json` 取 `instructions`，`\r\n → \n` 规范化后求 sha256，与下表比对；
合同正文指纹取 `cr-prompts-revised/delegation-contract.md` 中 `CONTRACT-BEGIN/END` 之间正文（trim 后、同样规范化）。

| 对象 | 长度 | sha256（LF 规范化） |
|---|---|---|
| 合同正文 | 666 | `53bb3f35a8155ca332627b1d8412fc7ea379f3fe514198afdf09baab4a9a8a2d` |
| requirement-writer instructions | 3715 | `01fa074d935a5ed3b5bc7a89b691a866822430a41ba41b4263c8b3c5853e2629` |
| dev-agent instructions | 4450 | `c6b4c3b2cf64e64d1ed5d34dfa9b7873d141f1574a8503932ff6e0813d99ca0a` |
| quality-reviewer-agent instructions | 2770 | `af6261e584bb1196f9fcf7ebddfa8b7e679ae4227d77e78d01997a9dbf62e97a` |
| cr-coordinator-agent instructions | 5957 | `e764f29f5d1b59604e2a4d821a084c9c11d48b6eb809d173c52270a4bf12e023` |

合同正文在四份 instructions 中的逐字命中位置（`indexOf`）= 1853 / 1851 / 2260 / 2834。

## 附录 B — AIFI-35 cmd-09 尾 30 条评论 id 基线（启动 = 复测，逐 id 相同）

- root `01a0de2a-ad26-72be-925a-847aa812b858`（16 条，含根）：
  `01a0de2a-ad26-72be-925a-847aa812b858, 01a0de31-0e04-7363-9334-c092a70631fb, 01a0de4c-5a7c-7125-9771-be0e1d1f5291, 01a0de55-95d6-7570-8cbd-9abf14499978, 01a0de5b-da67-73c9-b31c-c92494cd5fcb, 01a0de6c-263a-7673-ae5f-bb863e09e9ad, 01a0de7c-fb0f-7033-8251-a1860dacc84f, 01a0de8c-96ad-7b04-9c7a-84811f8b5dd0, 01a0deae-bd99-7cad-843a-6ce9317525a8, 01a0deb0-bc76-7d17-8319-02f630b1005d, 01a0deb3-3369-730b-89e1-47b8e6a17ffd, 01a0deb7-9afe-7855-90ad-2bc60057c901, 01a0deb9-6a86-7166-91d0-daed21542d3a, 01a0debd-0358-727d-a1d2-e6790d4d67db, 01a0dec0-9a36-7d7f-93e4-7e947d3562ec, 01a0dec5-443e-7024-ad64-2e01e5522fb6`
- root `01a0dec7-bad2-72e5-a1e4-964ed98b8d50`（18 条，含根）：
  `01a0dec7-bad2-72e5-a1e4-964ed98b8d50, 01a0deca-687c-764b-b553-bead16ba079a, 01a0ded2-b6bc-7593-b598-760c2926f882, 01a0ded8-187a-7331-bfa3-b45df8d1fd6e, 01a0dede-bd01-7bbb-97aa-e317ff778d39, 01a0e035-d77a-731b-8861-e14d9566c673, 01a0e039-966d-7269-b70f-137d434de3a5, 01a0e044-0f8a-7010-9bd1-0edbf08f214e, 01a0e045-2212-7803-bd5f-20756c2737a6, 01a0e04a-cf71-7942-9f87-68763a3af432, 01a0e050-3914-7be7-88e1-508680165cab, 01a0e05a-fe26-728b-a58f-08da2cfe32d4, 01a0e05b-ec4d-7f3b-854f-0de51cd44c21, 01a0e05f-f106-7ba7-9ae3-99716c8a5d50, 01a0e067-60c9-7d3c-a23e-262d2c2497dc, 01a0e067-d295-7351-ab0f-61003db4d1b0, 01a0e06d-9653-7bce-8a1a-ff6314974f19, 01a0e06f-9237-73cf-8fab-ca8b2631c5dc`
- root `01a0e076-7f5e-762b-ac62-b4f1818652bf`（9 条，含根）：
  `01a0e076-7f5e-762b-ac62-b4f1818652bf, 01a0e078-2fe7-7f03-96b4-18190ba8220b, 01a0e07b-0b9f-7eed-a8f8-4cd30981bda2, 01a0e07e-87a1-7e99-a0ed-28453598615b, 01a0e081-0e27-73a9-b764-babf9d764259, 01a0e087-290e-702f-a304-86ca665dad5f, 01a0e090-396f-7cf3-ac4b-355a73e78345, 01a0e095-8ecf-7514-81d6-98651a636c15, 01a0e098-e98a-712c-b7c7-cfe89b8efdd6`
