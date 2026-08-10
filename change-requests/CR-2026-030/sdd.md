---
id: CR-2026-030-sdd
type: SDD
cr-ref: CR-2026-030
title: tools TCA-001～004 最小优化 - 技术设计
status: draft
owner: Ray
owner-role: development
created: "2026-08-11T02:10:31+08:00"
updated: "2026-08-11T02:10:31+08:00"
version: v0.1.0
refs:
  upstream:
    - CR-2026-030-prd
    - docs/analysis/tools-tca-001-004-optimization-plan.md
  downstream: []
components:
  - tools/crctl
  - tools/lint-prompts
  - tools/skills
  - tools/pipeline-templates
  - multica/governance-crosscheck-test
---

# SDD - tools TCA-001～004 最小优化

> 本文设计对应已审批 PRD `CR-2026-030-prd`。实现阶段以 PRD、tools `dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json` 和 grant v1 为权威来源；本文不复制第二份可执行状态机或签名协议。

## 1. 架构概览

### 1.1 设计目标

本设计在现有模块内闭合四条契约漂移：

1. `cr-init` 显式接收三角色 Owner，注册提交成功后才产生绑定真实 SHA 的注册事件。
2. `owner-set` 同步更新 Owner 双投影、唯一责任历史和通知事实，并形成只含两份受控账本的正式提交。
3. `approve --grant` 对 approve/reject 共用完整验证，合法 reject 执行权威回退并支持紧邻结果态幂等。
4. `review-dev-plan` 使用权威 trigger；R7 直接读取状态机声明并静态拒绝错误字面量。

### 1.2 已有架构约束

设计逐条遵守 tools `ARCHITECTURE.md`：

- `crctl.mjs` 保持状态与账本唯一写者，不拆分 `commands/` 模块。
- Skill 只做业务编排，Pipeline 只做节点顺序、路由与重放。
- 状态仍只由 `crctl advance` 写入 `cr.md`。
- 账本写入继续使用 CAS 和 `.crctl/audit.log`，不增加会话脚本或第二写入口。
- 仅使用 Node 标准库；YAML 采用现有严格行级解析与定点改写。
- 所有文本解析先执行 `CRLF -> LF` 规范化；结构不完整时硬失败。
- Git 是权威事实，outbox 是可失败、可重放的非阻断投影。
- 状态机保持 15 个具名状态加注册前 `(new)`、27 条声明转移、wildcard 展开 49 条，不新增状态或转换。

Multica 在本 CR 中不是 production 实现目标，只承载既有 Go 到 crctl 的 test-only 跨接缝验证。该仓无 `ARCHITECTURE.md`；按已审批 PRD 的精确白名单，不新增该文件。Multica 改动遵循根 `CLAUDE.md`：Go 标准风格、检查所有错误、代码注释一律英文，并同步 `CUSTOM.md` 台账。

### 1.3 仓库和文件边界

| 仓库 | 角色 | 设计改动 | 禁止事项 |
|---|---|---|---|
| tools | production 契约与实现 | `crctl.mjs`、R7、测试、8 个 Skill、4 个 Pipeline、3 份人读文档 | 新依赖、新状态、新命令模块、修改 CI |
| knowledge-base | CR 权威文档 | 本 SDD、后续评审与审批证据 | 实现代码、`specs/` 提前回写 |
| Multica | test-only 验证 | 扩展 `approval_crosscheck_test.go`，更新 `CUSTOM.md` | production Go、迁移、handler/service、Runner、owners/inbox 消费 |

### 1.4 组件划分

| 组件 | 职责 | 现有落点 | 本次变化 |
|---|---|---|---|
| Registration writer | 分配 CR-ID，生成三文件候选并 CAS 写入 | `cmdCrInit()` | 三 Owner、三条初始历史、无 outbox、结构化返回深化 |
| Controlled Git adapter | 白名单校验、执行 Git、提交模板 | `controlledGit()`、`cmdGit()` | 只读无审计查询选项；register commit 返回 SHA 并发 status/owners 事件 |
| Worktree resolver | 生成 bucket/path | `cmdWorktreePath()` | 增加 canonical `branch` |
| Owner handover writer | Owner 变更和正式提交 | `cmdOwnerSet()` | clean 前置、双投影、历史、通知、提交、回滚、owners/inbox outbox |
| Approval consumer | TTY 或签名 grant 审批 | `cmdApprove()`、`approveWithGrant()` | approve/reject 共用验证、业务回退和紧邻结果态幂等 |
| Advance core | 状态机、门禁、状态提交和 status outbox | `cmdAdvance()` | 提取内部可复用执行核心，供 reject 回退复用；外部 CLI 不变 |
| Prompt drift linter | Skill/Pipeline 静态漂移检查 | `lint-prompts.mjs` R7 | 严格读取权威 transitions，校验 `(to, trigger)` 字面量 |
| Skill/Pipeline adapters | 业务入口和流程路由 | 8 个 Skill、4 个 Pipeline | 删除命令复制、无效输入和第二 Owner 写入口 |
| Cross-tool seam test | Go grant 到真实 crctl 验证 | Multica `approval_crosscheck_test.go` | 增加 reject 回退和幂等向量，不新增测试框架 |

### 1.5 依赖方向

```text
Pipeline templates
       |
       v
Skill contracts
       |
       v
crctl public CLI
       |
       +--> dir-graph.yaml / gates.json / controlled-shell/rules.json
       +--> Git + change-requests ledgers
       +--> .crctl/audit.log + .crctl/outbox

Multica approval_crosscheck_test.go --(signed grant)--> real crctl approve --grant
```

`crctl` 不调用 Skill，不根据自然语言选择下一节点。Skill 和 Pipeline 不解析 Git HEAD、不拼接 branch/path/SHA、不复制状态转换。

### 1.6 关键流程总览

#### Registration

```text
requirement-register
  -> cr-init(3 owners, one timestamp, CAS 3 files, no outbox)
  -> crctl git add(exact registration files)
  -> crctl git commit --template register --cr CR-ID
       -> real HEAD
       -> status(new -> drafting) outbox
       -> owners(initial-assignment x3) outbox
  -> push trunk
  -> worktree-path(repo) for each active repo
  -> create worktrees
  -> execution_context
```

#### Formal handover

```text
handover-cr
  -> owner-set
       -> tracked clean precheck
       -> owner projection consistency check
       -> one timestamp + two in-memory candidates
       -> casWriteMulti(cr.md, _backlog.yml)
       -> git add(exact two paths)
       -> staged-set + unstaged isolation check
       -> one formal commit
       -> success audit
       -> owners + inbox outbox attempts
  -> push-progress
```

#### Signed reject

```text
approve-* Skill
  -> approve --grant
       -> envelope/ownership/state/evidence/key/signature validation
       -> reject: authoritative rollback transition
       -> APPROVAL_DECLINED_ROLLED_BACK (nonzero business result)
  -> Pipeline aborts current forward flow
```

## 2. 数据模型

### 2.1 持久化边界

本 CR 不新增持久化文件或 schema。只扩展以下既有结构的写入内容：

| 存储 | 权威性 | 变化 |
|---|---|---|
| `change-requests/{cr}/cr.md` | status、当前 Owner、唯一 Owner 历史 | 三 Owner 初始历史；正式移交当前投影和一条 `formal-handover` 历史 |
| `change-requests/_backlog.yml` | 在途 CR 索引和同步元数据 | 三 Owner 当前投影；handover notify-log/notify-pending |
| `change-requests/_index.yml` | CR 注册索引 | 注册行为不变 |
| `change-requests/{cr}/approval.yml` | approve 审批事实 | approve 路径不变；reject 不新增记录 |
| `.crctl/audit.log` | 本地操作审计 | registration/owner/grant 的结构化结果；不记录证据正文 |
| `.crctl/outbox/*.json` | 非阻断投影 | 新增 `owners`、`inbox` 事件；registration status 事件改由真实 commit 产生 |

### 2.2 Owner 投影

逻辑类型：

```ts
type OwnerRole = "requirement" | "development" | "test";

type OwnerSlot = {
  id: string;
  "assigned-at": string; // 带偏移 ISO 8601
};

type OwnerProjection = {
  requirement: OwnerSlot;
  development: OwnerSlot;
  test: OwnerSlot;
};

type OwnerChange = {
  role: OwnerRole;
  from: string;
  to: string;
  at: string;
  reason: "initial-assignment" | "formal-handover";
  note?: string;
};
```

不变量：

1. `cr.md.owner == cr.md.owners.requirement.id`。
2. `_backlog.yml.owner == _backlog.yml.owners.requirement.id`。
3. 两个文件的三个 `owners.{role}` 必须逐项相等。
4. Registration 的三个 `assigned-at` 与三条 initial history 的 `at` 使用同一个 `registrationAt`。
5. Formal handover 的两处 slot、history、notify、audit payload 和 outbox payload 使用同一个 `handoverAt`。
6. `owner-history` 是唯一责任历史；`handover-history` 只读兼容，不再追加。

### 2.3 Git clean snapshot

`owner-set` 的 clean 前置和隔离复核使用只读结构：

```ts
type TrackedChangeSet = {
  staged: string[];   // git diff --name-only --cached
  unstaged: string[]; // git diff --name-only -- .
};
```

- 路径统一为 Git 输出的 `/` 分隔形式，过滤空行并去重排序。
- untracked 文件不属于该结构，不阻塞 owner-set。
- 命令开始时必须满足 `staged=[] && unstaged=[]`。
- commit 前必须满足：
  - `staged` 精确等于 `change-requests/{cr}/cr.md` 与 `change-requests/_backlog.yml`；
  - `unstaged=[]`。

### 2.4 Notification fact

Backlog 中的 handover 通知继续使用既有 notify 结构，不新增第二历史：

```yaml
notify-log:
  - at: "<handoverAt>"
    event: owner-handover
    to: ["<new-owner>"]
    payload:
      role: development
      from: old-owner
      to: new-owner
      handover_at: "<handoverAt>"
      note: "<optional>"
    handled: false
notify-pending: ["<new-owner>"]
```

payload 不含 `subject`/`body`。展示文案由消费者负责。

### 2.5 Outbox envelope 和 payload

沿用 `emitOutboxEvent()` 的 v1 envelope：

```ts
type OutboxEvent = {
  v: 1;
  event_kind: "status" | "owners" | "inbox" | string;
  cr_id: string;
  from_status: string;
  to_status: string;
  trigger: string;
  commit_sha: string;
  actor: string;
  evidence: Record<string, unknown>;
  payload: Record<string, unknown>;
  occurred_at: string;
};
```

新增 payload：

```ts
type OwnersPayload = {
  owners: OwnerProjection;
  changes: OwnerChange[];
  handover_at?: string;
};

type InboxPayload = {
  event: "owner-handover";
  to: string[];
  role: OwnerRole;
  from: string;
  owner: string;
  handover_at: string;
  note?: string;
};
```

Registration 的 `owners.changes` 固定三项 `initial-assignment`；handover 固定一项 `formal-handover`。同一业务操作的事件共享真实 commit SHA，envelope `occurred_at` 可不同。

### 2.6 Grant v1 和审批幂等键

不改变 grant schema。验证和幂等比较使用以下已签名字段：

```ts
type GrantV1 = {
  v: 1;
  cr_id: string;
  stage: "requirement" | "tech-design" | "dev-start" | "code";
  decision: "approve" | "reject";
  approver: string;
  approved_at: string;
  evidence_digest: string;
  key_id: string;
  signature: string;
};
```

approve 紧邻目标态重放时，`approval.yml` 对应 section 必须满足：

- `via == server-approve`；
- `approver == grant.approver`；
- `key-id == grant.key_id`；
- `signature == grant.signature`；
- `grant-approved-at == grant.approved_at`；
- `evidence-digest == grant.evidence_digest`；
- `target-status == stageCfg.to`。

reject 不持久化 approval section；其重放依据是当前状态恰好等于 `REJECT_ROLLBACK[stage].to`，且当前 evidence digest 与签名仍有效。

## 3. 接口契约

### 3.1 `crctl cr-init`

```text
crctl cr-init \
  --title <text> \
  --owner-requirement <id> \
  --owner-development <id> \
  --owner-test <id> \
  [--year <YYYY>] [--summary <text>] [--source <text>] [--target-version <text>]
```

成功输出：

```json
{
  "op": "cr-init",
  "cr": "CR-2026-031",
  "status": "drafting",
  "owners": {
    "requirement": { "id": "R", "assigned-at": "..." },
    "development": { "id": "D", "assigned-at": "..." },
    "test": { "id": "T", "assigned-at": "..." }
  },
  "files": {
    "crMd": "change-requests/CR-2026-031/cr.md",
    "backlog": ".../_backlog.yml",
    "index": ".../_index.yml"
  }
}
```

错误：

| code | 条件 | 写入 |
|---|---|---|
| `BAD_ARGS` | 缺 title 或任一 Owner | 零写入 |
| `CAS_CONFLICT` | CR-ID 分配或三文件并发冲突 | 三文件零写入 |
| 既有结构错误码 | backlog/index 缺失或结构错误 | 零写入 |

`cr-init` 只写一条成功 audit，不发 outbox。

### 3.2 Register commit

公开调用保持：

```text
crctl git commit --template register --cr <CR-ID> -m <subject> --cwd <knowledge-base-trunk>
```

register 模板成功时，`cmdGit()` 在 controlled commit 返回后读取真实 HEAD 和 `cr.md` Owner，并扩展输出：

```json
{
  "ok": true,
  "exit": 0,
  "commit": { "sha": "<real-head-sha>" },
  "outbox": {
    "status": "<file-or-null>",
    "owners": "<file-or-null>"
  },
  "warnings": []
}
```

- 非 register 模板和普通 `crctl git commit` 保持现有输出。
- commit 失败不读 HEAD、不发注册事件。
- 单个 outbox 写出失败时对应值为 `null`，`warnings[]` 增加 `{code:"EMIT_FAILED", event_kind}`，commit 仍成功。
- `emitOutboxEvent()` 的失败 audit 增加 `cr`、`event_kind`，不记录 payload 正文。

### 3.3 `crctl worktree-path`

```text
crctl worktree-path <CR-ID> --repo <repo-id>
```

输出新增：

```json
{
  "op": "worktree-path",
  "cr": "CR-2026-030",
  "repo": "tools",
  "bucket": "tools",
  "branch": "requirement/CR-2026-030",
  "path": "<canonical-absolute-path>"
}
```

branch 只在此处生成，Skill/Pipeline 不再拼接。

### 3.4 Registration incomplete

`REGISTRATION_INCOMPLETE` 是 `requirement-register` 对原语结果的编排级错误，不新增 crctl 顶层命令：

```ts
type RegistrationIncomplete = {
  code: "REGISTRATION_INCOMPLETE";
  cr_id: string;
  failed_step: "commit" | "push" | "worktree";
  completed_steps: string[];
  commit_sha: string | null;
  created_worktrees: Array<{repo: string; path: string}>;
  warnings: Array<Record<string, unknown>>;
};
```

一旦 `cr-init` 成功，Skill 固定复用返回的 `cr_id`；任何后续失败都不得再次调用 `cr-init`，也不得输出 `execution_context`。

### 3.5 `crctl owner-set`

```text
crctl owner-set <CR-ID> \
  --role <requirement|development|test> \
  --id <new-owner> \
  [--note <text>]
```

成功变化：

```json
{
  "op": "owner-set",
  "cr": "CR-2026-030",
  "changed": true,
  "role": "development",
  "from": "Old",
  "to": "New",
  "handoverAt": "...",
  "files": [".../cr.md", ".../_backlog.yml"],
  "commit": {"sha": "...", "message": "[cr] owner handover ..."},
  "outbox": {"owners": "...", "inbox": "..."},
  "warnings": []
}
```

同值幂等：

```json
{"op":"owner-set","cr":"CR-2026-030","changed":false,"role":"development","id":"New"}
```

错误矩阵：

| code | 条件 | 副作用 |
|---|---|---|
| `OWNER_WORKTREE_DIRTY` | 开始时存在 tracked staged/unstaged 变更 | YAML/audit/commit/outbox 零新增；返回两个路径数组 |
| `OWNER_PROJECTION_DRIFT` | cr.md 与 backlog 的 owner/owners 不一致 | 零写入 |
| `OWNER_COMMIT_FAILED` | add/commit/commit 前隔离检查失败且成功恢复 clean baseline | `changed=false`、`rolled_back=true`；无成功 audit/outbox |
| `OWNER_COMMIT_ROLLBACK_FAILED` | CAS 恢复、撤销暂存或 clean 复核失败 | 中止并列出受影响文件；不吞掉外部变化 |
| `OWNER_GIT_CHECK_FAILED` | 受控 Git 只读查询无法执行 | 零 YAML 写入，保留底层 code/detail |
| 既有错误码 | 参数错误、终态、账本结构异常、CAS 冲突 | 按现有 fail-fast 语义 |

### 3.6 受控 Git 内部接口

为满足 dirty 拒绝路径“audit 完全不变”，扩展内部签名，不增加 CLI 旗标：

```ts
controlledGit(
  ws: string,
  sub: string,
  args: string[],
  cwd?: string,
  caller?: string,
  options?: { audit?: boolean }
): ControlledGitResult
```

`options.audit` 缺省 `true`，所有既有调用行为不变。仅 `owner-set` 的纯只读 clean 查询传 `{audit:false}`；白名单、forbidden flags、spawn 参数和 fail-closed 行为仍全部执行。写操作、失败恢复中的 add/commit 和其他调用仍保留 Git audit。

现有 `rules.json` 已允许以下形态，无需修改 guard 文件：

```text
git diff --name-only --cached
git diff --name-only -- .
git add change-requests/<CR>/cr.md change-requests/_backlog.yml
git commit -m [cr] ...
git rev-parse HEAD
```

### 3.7 `crctl approve --grant`

公开接口不变：

```text
crctl approve <CR-ID> --stage <stage> --grant [<path>]
```

统一结果：

| 决定/状态 | 结果 | exit |
|---|---|---:|
| approve，审批前置态 | 原子写 approval+status，`changed=true` | 0 |
| approve，紧邻目标态且审批字段一致 | `changed=false` | 0 |
| reject，审批前置态 | 状态回退，`APPROVAL_DECLINED_ROLLED_BACK/changed=true` | 非 0 业务结果 |
| reject，紧邻回退态 | `APPROVAL_DECLINED_ROLLED_BACK/changed=false` | 非 0 业务结果 |
| 其他状态 | `GRANT_STATE_MISMATCH` | 非 0 技术错误 |

`APPROVAL_DECLINED_ROLLED_BACK` 输出至少包含：

```json
{
  "code": "APPROVAL_DECLINED_ROLLED_BACK",
  "decision": "reject",
  "stage": "tech-design",
  "rolledBackTo": "tech-designing",
  "trigger": "approve-tech-design:reject -> write-tech-design",
  "changed": true
}
```

不含 `rerunHint`、下一 Skill、未签名 reason 或 annotation 文案。

### 3.8 `review-dev-plan` 结构化结果

Skill 输出固定为：

```ts
type DevPlanReviewResult =
  | { route: "pass"; verdict: "pass"; blockers: []; status: "task-breakdown" }
  | { route: "normal"; verdict: "block"; review_feedback: object; status: "tech-design-reviewed" }
  | { code: "UPSTREAM_DESIGN_BLOCKER"; route: "upstream"; verdict: "block"; review_feedback: object; status: "tech-design-review-pending" };
```

NORMAL 由 Skill 执行完整 trigger；UPSTREAM 由 Skill 执行 upstream trigger。Pipeline 只判断 route 和 `replayNodes`，不含具体 `advance` 命令。

### 3.9 R7 输入和输出

R7 从当前 lint root 的 `dir-graph.yaml#change-request-track.state_machine.transitions` 构造只读集合：

```ts
type TransitionLiteral = { to: string; trigger: string };
```

对 Skill 内可静态确定的 `crctl advance` 命令：

- 缺 `--to`/`--trigger`：沿用当前 R7 finding。
- `(to, trigger)` 不在权威集合：输出 `CONTRADICTS`。
- 任一值含 `{...}`、`{{...}}` 或 `$...`：标记为动态并跳过 literal 校验。
- 不推断 `from`；完整合法性仍由运行时 `findTransition()` 裁决。
- 状态机块缺失、重复、空或任一声明无法完整解析：lint 以 `STATE_MACHINE_PARSE_FAILED` 非零退出，禁止空集合继续。

## 4. 关键算法与流程

### 4.1 三 Owner Registration

伪代码：

```text
cmdCrInit(flags):
  require title + owner-requirement + owner-development + owner-test
  read backlog/index snapshots
  cr = scanMax + 1
  registrationAt = nowIso() exactly once
  owners = build three explicit slots(registrationAt)
  crMdCandidate = render cr.md(owners, three initial histories)
  backlogCandidate = append entry(owners, compatibility owner=requirement)
  indexCandidate = append index entry
  casWriteMulti(cr.md new, backlog hash, index hash)
  audit success with owners + changes
  return owners + files
```

实现要点：

- 将现有局部 `yamlScalar` 提升为文件内通用 helper，继续做最小标量转义，不引入 YAML 库。
- 删除 `ownerId` 复制逻辑和 `event_kind=cr-init` outbox。
- `auditLog` 的业务记录包含 Owner projection 和三项 change，但不写 branch、SHA 或 outbox 成功声明。
- 缺参数检查必须发生在读取/创建 CR 目录之前。

### 4.2 Register commit 后置事件

`applyCommitTemplate()` 改为返回 `{args, templateContext}`，其中 register context 含已校验 CR-ID；普通模板也可复用该结构，但只对 register 执行后置事件。

```text
cmdGit(commit, template=register):
  context = applyCommitTemplate(...)
  result = controlledGit(commit)
  if failed: return failure, no event
  sha = controlledGit(rev-parse HEAD)
  owners = read + validate cr.md frontmatter
  emit status(new -> drafting, sha)
  emit owners(initial-assignment x3, sha)
  collect null emissions into warnings
  return sha/outbox/warnings
```

如果 HEAD 读取或 `cr.md` Owner 校验失败，commit 已是权威事实，不回滚；返回结构化 warning 并记 audit，后续 registration 结果为 incomplete，不得虚构成功上下文。

### 4.3 Registration 编排失败边界

`requirement-register` 维护内存 `completedSteps` 和 `createdWorktrees`：

1. `cr-init` 成功后立即锁定 `cr_id`。
2. add/commit 成功后保存真实 SHA 和 warnings。
3. push 成功后追加 `push`。
4. 每个 worktree 创建成功后立即追加 repo/path。
5. 任一步失败组装 `REGISTRATION_INCOMPLETE` 并中止。
6. 只有全部成功时组装 `execution_context`。

Skill 不执行恢复删除，不回收 CR-ID，不做跨进程续跑。

### 4.4 Owner 双投影解析和候选生成

新增文件内 helper，保持单文件架构：

```ts
readOwnerState(ws, cr): {
  crMd: {path, text, hash, owners, compatibilityOwner},
  backlog: {path, text, hash, owners, compatibilityOwner}
}

assertOwnerProjectionConsistent(state): void
buildOwnerCandidates(state, role, newId, note, handoverAt): {
  crMdText: string,
  backlogText: string,
  change: OwnerChange,
  owners: OwnerProjection
}
```

读取用现有 `matchFrontmatter()`、`parseYaml()` 和 `loadBacklogEntry()`；写入仍是严格定点文本改写：

- `editCrOwnerProjection()` 更新一个 slot，requirement 时更新顶层 owner，并向 `owner-history` 追加一项。
- `editBacklogOwnerProjection()` 更新一个 slot，requirement 时更新兼容 owner，并在同一候选中追加 notify-log/notify-pending。
- 所有 editor 显式接收 `handoverAt`，内部不得再次调用 `nowIso()`。
- 每个目标块必须唯一命中；缺失、重复或缩进异常均 `LEDGER_PARSE_FAILED`，不静默创建替代结构。

### 4.5 Owner clean precheck

```text
queryTrackedChanges(audit=false):
  staged = controlledGit(diff --name-only --cached, audit=false)
  unstaged = controlledGit(diff --name-only -- ., audit=false)
  if query failed -> OWNER_GIT_CHECK_FAILED
  return normalized sets

cmdOwnerSet:
  validate args/status
  dirty = queryTrackedChanges(audit=false)
  if dirty -> OWNER_WORKTREE_DIRTY(changed=false, staged, unstaged)
  read + validate both owner projections
  if target owner equals current -> changed=false
  handoverAt = nowIso() exactly once
  build candidates
  casWriteMulti(two ledgers)
  continue isolated commit
```

clean 查询不写 audit，确保 dirty 和同值重放路径满足零副作用。untracked 文件不会出现在两条 diff 命令中。

### 4.6 Owner 隔离 commit

```text
expectedPaths = sorted([cr.md relative path, _backlog.yml relative path])
git add expectedPaths
isolation = queryTrackedChanges(audit=false)
if isolation.staged != expectedPaths or isolation.unstaged not empty:
  rollback OWNER_COMMIT_FAILED
commit "[cr] owner handover <CR> <role> <from> -> <to>"
if commit failed:
  rollback OWNER_COMMIT_FAILED
sha = rev-parse HEAD
success audit(handover_at)
emit owners(sha)
emit inbox(sha)
return changed=true
```

commit message 以 `[cr] ` 开头，命中现有 controlled-shell 白名单。成功 audit 必须在 commit 成功后写；outbox 写出在 audit 之后逐项尝试，失败只形成 warning 和 `EMIT_FAILED` audit。

### 4.7 Owner 失败回滚

开始时 baseline 已被证明 clean，因此恢复目标是 clean，而不是复杂的任意 index 快照：

```text
rollback(originalSnapshots, candidateHashes):
  casWriteMulti(
    cr.md expected=candidateHash -> originalText,
    backlog expected=candidateHash -> originalText
  )
  controlledGit(add exact two paths) // 原文等于 HEAD，清除本次 staged diff
  clean = queryTrackedChanges(audit=true)
  if CAS/add/query failed or clean not empty:
    fail OWNER_COMMIT_ROLLBACK_FAILED(affected files)
  fail OWNER_COMMIT_FAILED(changed=false, rolled_back=true)
```

并发安全：

- 同一目标文件被外部修改时，candidate hash 不匹配，CAS 拒绝覆盖。
- 其他路径出现并发 staged/unstaged 变化时，只撤销本次两个路径；最终 clean 复核失败并报告外部路径。
- 禁止调用 `reset`、`checkout`、stash 或生成补偿 commit。
- 进程在 CAS 后直接崩溃仍属已知窗口；下一次 clean precheck 会以 dirty 暴露，不当作同值成功。

### 4.8 Approval 公共验证核心

把 `approveWithGrant()` 拆为三个文件内 helper，不新增模块：

```ts
readAndValidateGrantEnvelope(path, cr, stage): GrantV1
classifyGrantState(current, stageCfg, rollback, decision):
  | "fresh"
  | "adjacent-approve"
  | "adjacent-reject"
validateGrantEvidenceAndSignature(...): {digest, signatureOk}
```

固定顺序：

1. JSON/schema v1/decision 枚举。
2. `cr_id` 和 stage 归属。
3. 当前状态分类；非前置态或合法紧邻结果态统一返回 `GRANT_STATE_MISMATCH`。
4. approve 执行 passCondition 和 requireFiles；reject 跳过 passCondition，但仍按 stage evidence 计算 digest。
5. 比对 evidence digest。
6. 查 key 并验证 Ed25519 signature。
7. 根据 decision/state 进入副作用或幂等分支。

伪造、挪用、漂移和错误状态均在写入前失败。

### 4.9 Advance 内核复用

当前 `cmdAdvance()` 同时做业务逻辑、输出和 `process.exit()`，不能被 grant reject 安全复用。提取内部 `performAdvance()`：

```ts
performAdvance(ws, cr, gates, flags): AdvanceResult
cmdAdvance(...): ok(performAdvance(...))
```

`performAdvance()` 保留现有转换查找、门禁、CAS/状态写入、提交、audit 和 status outbox 语义，但不直接打印 JSON。调用方：

- `cmdAdvance()`：正常成功输出，commit 失败后设置退出码。
- TTY reject：执行回退后返回统一业务 decline 结果。
- grant reject：执行回退后返回统一业务 decline 结果。

不新增 public command，不改变 `findTransition()` 或 gates 来源。

### 4.10 Grant approve/reject 幂等

```text
if decision=approve:
  if state=fresh:
    approveAndAdvance(existing atomic path)
  if state=adjacent-approve:
    validate persisted approval exact match
    return changed=false, no audit/commit/outbox

if decision=reject:
  if state=fresh:
    result = performAdvance(authoritative rollback)
    return APPROVAL_DECLINED_ROLLED_BACK changed=true
  if state=adjacent-reject:
    return APPROVAL_DECLINED_ROLLED_BACK changed=false
```

幂等路径仍执行 digest 和签名验证，但不写任何持久化副作用。reject 不创建 `approval.yml` section，也不接受/传播未签名 `reject_reason`。

### 4.11 Dev-plan 三路路由

`review-dev-plan/SKILL.md` 修改：

- NORMAL 精确命令：
  `crctl advance --to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown --embedded`。
- UPSTREAM 精确命令保持权威字面量并增加统一结构化业务结果。
- PASS 不推进状态。

`code-implementation.pipeline.json` 删除两个具体 advance，只保留：

- `route=pass` 继续；
- `route=normal` 重放 `write-dev-plan -> write-dev-tasks -> review-dev-plan`；
- `route=upstream` 中止当前 Pipeline。

NORMAL/PASS 按既有 review-record bump；UPSTREAM 沿用现有 `resolveDevPlanRoute()` 跳过 NORMAL attempt。

### 4.12 R7 权威 transitions 解析

`loadJudgements(root)` 增加严格 loader：

```text
read root/dir-graph.yaml
normalize CRLF -> LF
locate exactly one change-request-track.state_machine.transitions block by indentation
for each non-empty sequence line:
  match complete inline mapping {from,to,trigger}
  decode quoted trigger
  if mismatch -> STATE_MACHINE_PARSE_FAILED
require at least one transition
return Set(to + NUL + trigger)
```

选择严格读取当前权威 inline mapping，而不是引入 YAML 依赖。若权威文件未来改为多行 transition，linter 会硬失败，迫使同次变更更新解析器和测试，不会静默丢转移。

命令字面量解析：

```text
for each paragraph line containing "crctl advance":
  choose containing backtick span when present, else current logical line
  parse --to and --trigger, supporting single quote/double quote/unquoted token
  preserve current missing-flag/full-width checks
  if both values static and pair absent -> R7 CONTRADICTS
```

测试 fixture 的 root 必须包含最小合法 `dir-graph.yaml`；畸形/空/CRLF fixture 分别验证 hard fail 和等价行为。

## 5. 技术选型与替代方案

### 5.1 采用方案

| 决策 | 采用 | 理由 |
|---|---|---|
| crctl 组织 | 保持单文件，新增少量内部 helper | 符合 tools 架构强内聚约束，避免为四个修复创建模块层 |
| Owner 隔离 | 全仓 tracked clean 前置 | 简化成功提交和失败回滚，不需要保存任意 index/worktree 双层 patch |
| Git 查询 | controlledGit 白名单校验 + 内部 audit=false | 满足 fail-closed 与 dirty 零副作用，既有调用默认不变 |
| 多文件写 | 现有 `casWriteMulti()` | 已有三阶段 CAS 语义和测试，无需 WAL |
| Approval | 复用 grant v1、canonical digest、REJECT_ROLLBACK | 不产生第二协议或 rejection 账本 |
| reject 状态写 | 提取 `performAdvance()` 内核 | 避免复制状态机、门禁、commit/outbox 逻辑，也避免内部调用打印两份结果 |
| R7 parsing | 标准库加严格行级 parser | 零依赖、符合当前 dir-graph 格式和硬失败纪律 |
| Multica 验证 | 扩展既有 Go test | 已有真实 Go 签名到 Node 验签接缝，不新建集成框架 |

### 5.2 否决方案

| 方案 | 否决原因 |
|---|---|
| 新增 `owner-handover` 命令 | 与 PRD 最小边界冲突；`owner-set` 已是受控原语 |
| owner-set 自动 stash/提交既有变更 | 会改变调用者 index/worktree 分层，失败恢复复杂且有数据损失风险 |
| 只要求两个账本 clean | 其他 tracked 文件仍可能在 owner commit 前并发进入 staged set；全仓 clean 契约更可验证 |
| 回滚使用 `git reset`/`checkout` | 可能吞掉外部并发变化，且 destructive 命令不在受控白名单 |
| 新 grant v2/rejection 文件 | v1 已签 decision；当前缺口只是消费顺序和回退 |
| Pipeline 执行 reject advance | 复制状态机字面量和业务算法，且当前无 Runner 保证分派 |
| linter 复制 transition 常量 | 状态机变化后必漂移，违反单一事实源 |
| 引入 YAML parser | 违反 crctl/tools 零第三方依赖和定点改写原则 |
| 新增 Multica production consumer | 超出 PRD，owners/inbox/reconcile 仍由 CUSTOM-TODO-003～005 承接 |
| 新增 Multica `ARCHITECTURE.md` | Multica 仅 test-only 参与，且文件不在已审批白名单 |

本轮决策均在既有边界内可逆，不新增 ADR。

## 6. FR 到技术实现映射

| FR | 技术实现 | 核心测试 |
|---|---|---|
| FR-1 | `cmdCrInit()` 三 Owner 必填、一次时间戳、三文件 CAS、三条 initial history | 不同 Owner、缺参零写、CAS conflict |
| FR-2 | register template context、commit 后真实 SHA 双事件、worktree branch、Skill incomplete envelope | commit/outbox failure、execution context 来源断言 |
| FR-3 | clean precheck、双投影 parser/editor、唯一 owner-history、同值幂等 | drift、staged/unstaged/并存/untracked、单时间戳 |
| FR-4 | `handover-cr` 只调用 owner-set 后 push；resume 删除 Owner 输入和写入 | Skill/Pipeline 静态断言、push failure 语义 |
| FR-5 | 两文件 CAS、staged-set 复核、正式 commit、CAS 回滚、owners/inbox outbox | add/commit/isolation/rollback failure 注入 |
| FR-6 | grant 公共验证核心、reject 跳过 passCondition 后权威回退 | 四 stage reject、伪造/挪用/漂移 |
| FR-7 | approve 持久化字段精确比较；reject 邻接状态验证 | approve/reject changed=false、其他状态 mismatch |
| FR-8 | review-dev-plan 持有两条 advance；Pipeline 只路由/replay | PASS/NORMAL/UPSTREAM 黑盒与 attempt 断言 |
| FR-9 | R7 strict transition loader 和 literal pair 校验 | 完整/短 trigger、模板跳过、CRLF、parse fail |
| FR-10 | 8 Skill、4 Pipeline、crctl SKILL 与 3 份人读文档同步 | lint-prompts enforce、文件白名单和节点数量检查 |

FR 覆盖率：10/10。

## 7. 测试设计与 AC 追踪

### 7.1 crctl Node 黑盒测试

在现有 `crctl.test.mjs` 增加表驱动向量，不新增测试文件或框架：

| AC | 向量 |
|---|---|
| AC-1～2 | 三个不同 Owner 的 cr.md/backlog/audit/JSON；逐个缺参零文件/零 audit/outbox |
| AC-3～6 | cr-init 无 outbox；register commit 真实 SHA 双事件；commit/outbox failure；worktree branch；incomplete 由 Skill 静态契约覆盖 |
| AC-7～10 | 双投影 drift；requirement/development/test handover；note 边界；唯一时间戳；同值零副作用 |
| AC-11～12 | handover/resume Skill 与 Pipeline 静态文本断言；节点数不变 |
| AC-13～16 | owners/inbox 同 SHA；outbox failure；add/commit/isolation failure；CAS/unstage/clean failure；dirty 三类与 untracked-only |
| AC-17～22 | 四 stage approve/reject；错误 grant；reject 业务结果；approve/reject 邻接幂等；其他状态 mismatch |
| AC-23～26 | review-dev-plan PASS/NORMAL/UPSTREAM；完整 trigger 可运行；Pipeline 无命令复制 |

Git fixture 必须初始化真实 repo，并提交 clean baseline。dirty 用例分别构造：

1. 仅 staged tracked file。
2. 仅 unstaged tracked file。
3. 同一路径 staged 后再修改，以及不同路径 staged+unstaged。
4. untracked-only。
5. clean 成功后用 `git show --name-only HEAD` 或等价测试取证确认 commit 只含两账本。

失败注入沿用现有 `runCrctlWrapped()`/组件注入模式，不修改 production API 以迎合测试。

### 7.2 lint-prompts 测试

在现有 `lint-prompts.test.mjs` fixture builder 中写入最小合法 `dir-graph.yaml`，新增：

- 完整 NORMAL `(to,trigger)` 通过。
- 短 trigger 命中 `R7/CONTRADICTS`。
- 存在 trigger 但 to 不匹配时命中。
- 模板变量 to 或 trigger 明确跳过 literal 校验。
- LF/CRLF 同结果。
- transitions 缺失、空、单行畸形、block 截断均以 `STATE_MACHINE_PARSE_FAILED` 非零退出。

### 7.3 Multica 跨接缝测试

扩展现有 `TestGrantCrossVerifiesWithCrctl`，提取最小 fixture helper，并新增 table/subtests：

1. Go `ApprovalService` 签 approve grant，真实 crctl 推进。
2. Go 签 reject grant，真实 crctl 回退并返回 `APPROVAL_DECLINED_ROLLED_BACK`。
3. 同一 reject grant 在紧邻回退态重放，返回 `changed=false`。
4. 必要时增加 approve 紧邻目标态重放。

测试要求：

- 优先要求显式 `CRCTL_PATH`；保持当前无 Node/crctl 时 skip 的上游兼容行为。
- fixture 创建 `cr.md` 和 v2 backlog 所需最小结构，不能依赖旧 backlog status 回退。
- 所有新增 Go 注释使用英文。
- `CUSTOM.md` 按当时表结构登记 CR-2026-030 和对应 TASK。
- 不修改 Multica production code。

### 7.4 静态和全量验证

实现完成后必须执行 PRD AC-32 全部命令：

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e <parse all pipeline JSON>
```

另在 Multica 执行定向跨接缝测试，必须确认测试未因 `CRCTL_PATH`/Node 缺失而 skip。基线测试数当前为 crctl 189、writeback 9；实现后数量只能按新增向量增加，不能以删除既有测试换绿。

### 7.5 完整 AC 验证矩阵

| AC | 技术验证点 |
|---|---|
| AC-1 | 三个不同 Owner 在 cr.md、backlog、audit、JSON 中逐项相等；兼容 owner 只取 requirement；三条 history 同时戳 |
| AC-2 | 分别缺 requirement/development/test Owner，断言三文件、audit、outbox 全部不变 |
| AC-3 | cr-init 后 outbox 为空；register commit 后 status+owners 两事件使用同一真实 HEAD，owners changes 恰为三项 |
| AC-4 | 注入 commit 失败断言零注册事件；逐项注入 outbox 失败断言 commit 存在、warning 和 EMIT_FAILED audit 存在 |
| AC-5 | worktree-path 返回 branch/bucket/path；静态扫描 Skill/Pipeline 不含 branch/path/SHA/event 手工拼接 |
| AC-6 | commit/push/第 N 个 worktree 失败分别返回完整 incomplete envelope，不产生第二 CR-ID 或成功 execution_context |
| AC-7 | 两投影任一角色或兼容 owner 漂移，owner-set 零副作用；一致时允许变化/幂等 |
| AC-8 | 三角色 handover 分别验证 owner-history 只加一条、不加 handover-history；note 只出现于 history/inbox |
| AC-9 | 两投影、history、notify、business audit 和两个 outbox payload 的 handover timestamp 全相等；两账本同 CAS |
| AC-10 | clean 同值重放断言时间、history、notify、audit、commit、outbox 不变；handover Skill 仍进入 push-progress |
| AC-11 | 静态断言 handover 无 skip_push 且顺序唯一；模拟 push 失败保留 owner commit 并返回未完成 |
| AC-12 | resume Skill/Pipeline 输入与正文均不含 new_owner/new_owner_role/owner-set，恢复后调用 crctl next |
| AC-13 | commit 后 owners/inbox 两事件 SHA 相同；payload 无 subject/body，owners change 一项且时间戳与 AC-9 相同 |
| AC-14 | outbox failure 不回滚；add/commit/isolation failure 成功恢复原文和 clean baseline，返回 OWNER_COMMIT_FAILED |
| AC-15 | 分别注入恢复 CAS、撤销暂存、clean 复核失败，返回 OWNER_COMMIT_ROLLBACK_FAILED；外部变化保持原样 |
| AC-16 | staged-only、unstaged-only、同/异路径 mixed、untracked-only、clean success 五组 Git fixture；成功 commit 只含两账本 |
| AC-17 | 四个 stage 的 approve grant 正常推进；无 grant 非 TTY 拒绝；Pipeline 无 grant path/CLI 拼接 |
| AC-18 | 四个 stage 的 reject 在 schema、decision、归属、状态、digest、key、signature 全部通过后执行各自权威回退 |
| AC-19 | 伪造、跨 CR、跨 stage、证据漂移、错误状态逐项断言 cr.md/approval/audit/outbox 零业务写入 |
| AC-20 | 合法 reject 返回统一 business code、target、trigger、changed；JSON 不含 rerunHint/下一 Skill/reason/annotation 文案 |
| AC-21 | approve 目标态 exact replay 和 reject 回退态 replay 均 changed=false，且仍复核 digest/signature |
| AC-22 | 非邻接状态、approve 持久字段任一不一致均 GRANT_STATE_MISMATCH；幂等前后 audit/HEAD/outbox 不变 |
| AC-23 | PASS 仅在 pass+空 blockers，状态保持 task-breakdown 并输出 route=pass |
| AC-24 | NORMAL 完整 trigger 可执行并只进入三节点 replay；短 trigger lint/runtime 双拒；第 4 次 bump LOOP_EXHAUSTED |
| AC-25 | UPSTREAM 回到 tech-design-review-pending，返回业务结果并中止；NORMAL attempt 不增 |
| AC-26 | Skill 中恰有两条具体 advance；Pipeline 中为零，只含 route/replay/abort；节点数与 index 不变 |
| AC-27 | R7 从 fixture dir-graph 读取 transition；完整 pair 通过，短 trigger/to 错配均 CONTRADICTS |
| AC-28 | LF/CRLF 等价；transitions 缺失、空、截断、任一声明畸形均 STATE_MACHINE_PARSE_FAILED |
| AC-29 | to/trigger 模板变量分别跳过 literal 校验；静态 pair 只匹配 to+trigger，不依赖 from 或文件位置 |
| AC-30 | changed-files 与 FR-10.1 白名单精确比较；Multica production 和 CI workflow diff 为空；CUSTOM-TODO 不误报已交付 |
| AC-31 | 四个 Pipeline 分别做 schema/静态断言：输入收敛、Owner 只读、三路 route、审批不复制 CLI；JSON parse 和节点计数通过 |
| AC-32 | PRD 六条全量命令全部退出 0；Multica reject 跨接缝以显式 CRCTL_PATH 真执行且无 skip |

## 8. Prompt 采纳影响

本 CR 修改 `crctl.mjs` 的既有 dispatch 分支和命令语义，因此本节必填。`protectedPaths.deny` 不变，`rules.json` 不修改。

### 8.1 必须采纳扩展原语的 Skill

| Skill | 现状 | 应改为 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 只传 requirement Owner；自行描述 branch/path；注册事件时点失真 | 显式传三 Owner；消费 cr-init/register commit/worktree-path 返回；失败输出 incomplete |
| `skills/sync/handover-cr/SKILL.md` | pre-push、手写双投影步骤、独立 inbox、可 skip push | 唯一调用 `owner-set -> push-progress`；消费 changed/commit/warnings；删除 `skip_push` |
| `skills/sync/resume-from-remote/SKILL.md` | 接受新 Owner 并调用 owner-set | 删除 Owner 输入和写入，仅恢复 worktree、读状态、调用 `crctl next` |
| `skills/requirement/approve-requirement/SKILL.md` | 对平台 reject/技术失败区分不足 | 平台用默认 grant，本地用 TTY；识别 decline 业务结果并中止正向流程 |
| `skills/develop/approve-tech-design/SKILL.md` | 同上 | 同上，stage=`tech-design` |
| `skills/develop/approve-dev-start/SKILL.md` | 同上 | 同上，stage=`dev-start` |
| `skills/develop/approve-code/SKILL.md` | 同上 | 同上，stage=`code` |
| `skills/develop/review-dev-plan/SKILL.md` | NORMAL 使用短 trigger | 持有完整 NORMAL 和 UPSTREAM advance，输出三路结构化结果 |

`skills/shared/crctl/SKILL.md` 同步 public CLI、结果和错误码，但不得复制 helper 算法。

### 8.2 Pipeline 收敛

| Pipeline | 删除 | 保留 |
|---|---|---|
| `requirement-authoring.pipeline.json` | `cr_id` input/透传、单 Owner cr-init、branch/path/SHA/event 拼接、审批 CLI 算法 | 三 Owner 输入、execution_context 透传、节点数量 |
| `architecture-design.pipeline.json` | approval CLI/reject 回修算法副本 | 决定传递、技术失败 abort、reviewLoop |
| `code-implementation.pipeline.json` | dev-plan 两条 advance、审批 CLI 算法 | PASS/NORMAL/UPSTREAM route、replayNodes、abort |
| `resume-cr.pipeline.json` | `new_owner`、`new_owner_role`、Owner 写入 | 远端检查、worktree 恢复、`crctl next` |

### 8.3 人读契约

`README.md`、`AGENTS.md`、`ARCHITECTURE.md` 只修正现状描述：

- Registration 三 Owner 与真实 commit 事件。
- 正式移交唯一入口和 resume 只读。
- grant 双模式及当前无 Pipeline Runner 的诚实边界。
- crctl 仍是单文件、状态/账本唯一写者。

不得登记 CUSTOM-TODO-001～006 为已交付。

## 9. 安全、性能与兼容性

### 9.1 安全

- Owner clean 查询仍经过 controlled-shell 白名单和 forbidden flags；`audit:false` 只关闭只读查询日志，不降低命令校验。
- 不将 `identity(ws)` 解释为强认证；Owner-set 只保证本地可信环境的数据一致性。
- grant 必须在任何写入前完成归属、状态、evidence、key 和签名验证。
- reject reason 未被 v1 签名，本 CR 不持久化或传播。
- 错误输出不包含 evidence 正文、私钥、公钥材料或完整通知正文。
- 回滚不使用 destructive Git 命令，不覆盖并发外部变化。

### 9.2 性能

- `cr-init` 仍为一次 backlog/index 扫描和一次三文件 CAS。
- `owner-set` clean 成功路径增加两次 preflight diff、一次 add 后两次 isolation diff、一次 commit 和一次 HEAD 查询；CR 仓规模下为常数次本地 Git 调用。
- dirty 快速失败仅执行两次只读 diff，不解析/写入 YAML。
- R7 状态机读取一次并构建 Set；对 prompt 的检查为 O(文件文本长度 + advance 命令数)。
- 无网络同步调用；outbox 继续本地文件写入。

### 9.3 兼容性

- `controlledGit()` 新参数有缺省值，既有调用行为不变。
- `crctl git` 非 register 模板输出不变。
- approve 成功路径和本地 TTY 人在环保持；TTY reject 可统一结果，但仍执行同一权威回退。
- `inbox-emit` 其他调用方不变。
- Pipeline 节点数量和 `_index.yml#nodes` 不变。
- 不修改 CI workflow、状态机或 gates。
- `cr-init` 三 Owner 是有意的破坏性参数收紧；所有已知调用点在同一 CR 内同步，不保留隐式复制兼容层。

## 10. 可观测性和错误处理

### 10.1 Audit

| 操作 | 成功 audit | 失败 audit |
|---|---|---|
| cr-init | owner projection + 三项 initial change | 参数/CAS 失败零成功记录 |
| register commit | controlled Git commit；outbox failure 时 EMIT_FAILED | commit failure 仅 controlled Git failure |
| owner dirty/no-op | 无 | dirty 路径无 audit；Git query failure 返回结构化错误 |
| owner change | commit 成功后 business owner-set audit，含 `handover_at` | add/commit/rollback 操作保留技术 Git 记录，不写成功 owner audit |
| grant approve | 沿用 approve audit | 验证失败零 approval 写入 |
| grant reject | fresh 回退记录 advance/decline；幂等无新增 | 验证失败零副作用 |

`emitOutboxEvent` 失败 audit 记录 `event_kind`、`cr` 和错误摘要，不记录 payload。

### 10.2 错误分类

- 参数/结构：`BAD_ARGS`、`LEDGER_PARSE_FAILED`、`OWNER_PROJECTION_DRIFT`。
- 并发/一致性：`CAS_CONFLICT`、`OWNER_WORKTREE_DIRTY`、`OWNER_COMMIT_ROLLBACK_FAILED`。
- Git 技术错误：`SHELL_UNAVAILABLE`、`OWNER_GIT_CHECK_FAILED`、`OWNER_COMMIT_FAILED`。
- grant 技术错误：`GRANT_*`、`EVIDENCE_DRIFT`、`SIGNATURE_INVALID`、`GRANT_STATE_MISMATCH`。
- 人工业务结果：`APPROVAL_DECLINED_ROLLED_BACK`、`UPSTREAM_DESIGN_BLOCKER`。
- 静态治理错误：`LINT_DRIFT`、`STATE_MACHINE_PARSE_FAILED`。

Pipeline 只对业务结果做 route/abort；技术错误一律 abort，不伪装为回修意见。

## 11. 部署与运行时

- 无数据库迁移、服务部署、feature flag 或新环境变量。
- tools 继续要求 Node 标准运行时；CI 入口不变。
- Multica 定向测试需要显式 `CRCTL_PATH=<tools worktree>/skills/shared/crctl/scripts/crctl.mjs`，并确认 Node 可用。
- outbox 新 event_kind 在本 CR 中只保证写出，不保证 Multica 消费；消费者和 reconcile 由既有 CUSTOM-TODO 承接。
- 正式发布仍按仓库既有 merge/writeback 流程，不在技术设计阶段推送主分支。

## 12. 风险与回滚

| 风险 | 控制 | 回滚方式 |
|---|---|---|
| owner-set 在 CAS 后崩溃 | 下一次 tracked clean precheck 暴露脏文件；不误判同值成功 | 人工核对 Git diff 后按权威账本修复，不自动 reset |
| Git 查询 audit 抑制被滥用 | 选项仅内部、缺省 true；只在两条 read-only diff 调用使用，并加静态测试 | 删除该调用点的 `audit:false` 即恢复全审计 |
| register commit 成功但事件失败 | commit 返回 warning + EMIT_FAILED；Git 保持权威 | daemon/reconcile 后续补偿，本 CR 不反转 commit |
| grant reject 状态竞态 | 状态分类后由 advance 的 expect/CAS 再校验 | 返回 mismatch/CAS，零错误回退 |
| R7 parser 对格式变化敏感 | 严格 hard fail 和 malformed fixture | 同次更新 parser；不得空集合降级 |
| Multica test 静默 skip | 实施验证显式设置 CRCTL_PATH，检查 verbose 输出 | 未实际执行则测试报告不得标 pass |
| 文档描述未交付 Runner/consumer | AC-30 静态扫描和 review-tech-design 人工核对 | 删除越界描述，保留 CUSTOM-TODO |

代码回滚按原子提交拆分执行：测试向量、registration、owner handover、grant、Skill/Pipeline、docs 分开提交。若某一能力需撤回，revert 对应提交并同步其契约文本；不得只回滚实现而保留宣称已交付的 Skill/Pipeline 文案。

## 13. 实施顺序

1. 增加 TCA-001～004 红色测试、R7 fixture 和 Multica reject 跨接缝向量。
2. 实现三 Owner cr-init、register commit 事件和 worktree branch。
3. 实现 Owner clean query、双投影候选、隔离 commit、回滚和双 outbox。
4. 提取 advance 内核，实现 grant 公共验证、reject 回退和 approve/reject 幂等。
5. 实现 R7 strict transitions loader 和 literal pair 校验。
6. 更新 8 个 Skill、4 个 Pipeline、crctl Skill 和人读契约。
7. 运行 Node 全量验证与 Multica 定向跨接缝测试。
8. 核对 changed-files 精确白名单、Multica `CUSTOM.md` 和三个 worktree 清洁度。

## 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-11 | v0.1.0 | Ray | 初始技术设计：闭合 Registration、Owner 正式移交、grant reject、dev-plan trigger/R7；定义 clean baseline、失败回滚、接口和测试映射 |
