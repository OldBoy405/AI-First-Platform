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
| cmd-02 | tools・`.`：`node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | **36 / 35 / 1**（机械判据，见 §2.1） |
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

### 2.1 cmd-02 机械判据（授权口径：071 内不改 `review-dev-plan/SKILL.md`）

- **071 现状**（tools CR worktree `045d8d6`）：`36 tests / 35 pass / 1 fail`；唯一红项
  `✖ CR-2026-066 AC-3/AC-4: 四 review SKILL 的 clean 前置 + PASS 发布 + 对账 + 权限面四处载体（断言 A/B/C/D）`，
  `AssertionError [ERR_ASSERTION]: skills/develop/review-dev-plan/SKILL.md 缺对账失败语义 CONTRACT_DRIFT`。
- **BASE 对照**（tools 主镜像 `3b4a131`，不含本 CR 任何改动）：同命令 `36 tests / 35 pass / 1 fail`，
  唯一红项同名、同断言消息、同根因。
- **判据成立**：唯一失败项与 BASE **逐字一致**（测试标题与断言消息相同）；行号偏移（BASE `:673` → 071 `:684`）
  与本 TASK 在该文件新增 11 行断言一致，属预期差异。该红项与 071 改动无因果关系：
  FR-4 相关断言（6 节点 / 评审前 `push-progress` 恰 1 / `...0003` 在位 / 审批后 0）在该测试内全绿。
- **(B) 定案**：Ray 在 tools 主镜像自行补回 `review-dev-plan/SKILL.md` 的两条等价措辞（`CONTRACT_DRIFT` 对账失败语义、
  BLOCK 分支不含发布调用），**071 内不改该文件**（含 worktree 副本）；修复后 071 的 cmd-02 预期转为 36/36，
  本 CR 不为此改守卫断言、不把该文件带进本 CR diff。

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
4. cmd-02 既有红项（`review-dev-plan/SKILL.md` 缺两 token）由 Ray 在 tools 主镜像修复，071 内不改；
   本 CR 以 §2.1 机械判据记录，未把该文件带进本 CR diff。
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
| KB | `6ba719fc` | TASK-04 四个 Agent 更新前快照（审计件） |
| KB | `e137986f` / `f83cbc28` | TASK 台账（TASK-01/03/04；TASK-02） |
| KB | `1927dbe6` | SDD v0.2 授权偏离订正 |
| KB | 本记录提交 | TASK-05 交付记录 |
