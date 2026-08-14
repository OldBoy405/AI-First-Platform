# merge-feature-branch Skill 优化方案

## 1. 背景

当前 `tools/skills/writeback/merge-feature-branch/SKILL.md` 已具备以下正确方向：

- 从目标 workspace 的 `dir-graph.yaml#repositories` 动态解析参与仓和 trunk；
- 全仓预检完成前不修改任何 trunk；
- 全部本地 merge commit 生成后才开始远端发布；
- 跨仓部分 push 失败时执行补偿；
- merge metadata 只能通过 crctl 写入；
- worktree 和远端 requirement 分支统一交由 `cr-archive` 清理；
- 发布联调和 merge 验证归 merge pipeline，不再创建开发 TASK；
- 通过 `merge-verification.md` 留下发布联调完成证据。

但现有 Skill 仍存在以下主要问题：

1. `advance --embedded` 与逐仓 `merge-metadata` 分开执行，可能留下 `status=merging`、metadata 仅部分写入的半状态；
2. `merge-feature-branch` 只允许从 `code-approved` 开始，出现上述半状态后无法幂等重试；
3. `merge-recovery` 被要求写入 `_backlog.yml`，但不存在合法 crctl 写入入口；
4. 发布联调在陈旧 CR worktree 中执行 `crctl next`，可能错误返回 `merge-feature-branch`，却仍被认定为验证正常；
5. merging 状态下要求回到 `review-tech-design`，与现有状态机不兼容；
6. 无改动仓、commit 失败、远端 stale、补偿后重试等场景缺少唯一、可执行的恢复判据；
7. Skill、Pipeline prompt 和错误处理表重复描述同一算法，形成多份事实源。

本方案的核心是：**新增 `crctl merge-finalize`，由 crctl 原子完成 status 与全部 merge metadata，并据此收敛 merge-feature-branch 的执行与恢复契约。**

---

## 2. 设计目标

把当前由 Skill 编排的：

```text
crctl advance --to merging --embedded
→ 多次 crctl merge-metadata
→ git add
→ git commit
```

收敛为一个深模块接口：

```powershell
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs `
  merge-finalize CR-2026-NNN `
  --from .crctl/tmp/merge-finalize.yml `
  --workspace <knowledge-base主checkout>
```

由 crctl 一次完成：

1. 校验 `code-approved → merging` 合法转换；
2. 校验目标态 `merging` 的现有 gate；
3. 校验 payload 覆盖全部 active repo；
4. 校验每个 merge SHA 已存在于对应远端 trunk；
5. 在内存中生成完整 `cr.md` 与 `_backlog.yml` 候选文本；
6. 通过 `casWriteMulti` 原子写入：
   - `cr.md status=merging`；
   - 全部 `merge-commits[]`；
7. 在一个 Git commit 中提交两份文件；
8. commit 成功后再写 audit 和 status outbox；
9. 支持 commit 失败、输出中断和重复调用的幂等恢复。

### 2.1 原子性边界

本方案所说的原子性包括：

- knowledge-base 本地 `cr.md` 与 `_backlog.yml` 的同批 CAS；
- status 与全部 merge metadata 的同一 Git commit；
- commit 成功后才发布 status outbox。

本方案不声称以下操作具备分布式原子性：

- 多个独立 Git remote 的 trunk push；
- knowledge-base metadata commit 与其他代码仓 merge commit 的跨仓事务；
- Git 托管平台上的网络发布。

跨仓远端发布仍采用“预检 + 顺序发布 + 补偿/恢复”的 saga 语义。

---

## 3. 新增 crctl 接口

### 3.1 命令

```text
crctl merge-finalize <cr_id>
  [--from <payload.yml>]
  --workspace <knowledge-base>
```

默认 payload 路径：

```text
.crctl/tmp/merge-finalize.yml
```

规则：

- 成功后删除 payload；
- 失败时保留 payload，供诊断与重试；
- 不允许调用方传入 status；
- 不允许调用方传入 actor、时间戳或 merged-at；
- 不使用重复 `--repo/--sha` 参数；
- 不通过命令行 JSON 承载多仓 metadata，避免 Shell 转义和参数组合产生半份事实。

### 3.2 Payload 契约

```yaml
cr: CR-2026-030

repos:
  - repo: tools
    trunk: custom/main
    result: merged
    source-sha: 1111111111111111111111111111111111111111
    merge-sha: 2222222222222222222222222222222222222222

  - repo: multica
    trunk: main
    result: skipped-no-change
    source-sha: 3333333333333333333333333333333333333333

  - repo: ai-first-platform-docs
    trunk: master
    result: merged
    source-sha: 4444444444444444444444444444444444444444
    merge-sha: 5555555555555555555555555555555555555555
```

字段规则：

| 字段 | 规则 |
|---|---|
| `cr` | 必须等于命令中的 CR-ID |
| `repos[]` | 必须与 `dir-graph.yaml#repositories` 的 active repo 集合完全一致 |
| `repo` | 不允许重复、遗漏或出现未声明 repo |
| `trunk` | 必须等于对应 `repo.trunk`，调用方不能自定义 |
| `result` | 仅允许 `merged` / `skipped-no-change` |
| `source-sha` | 必须是完整 40 位 SHA |
| `merge-sha` | `result=merged` 时必填，其他情况禁止填写 |

`_backlog.yml#merge-commits[]` 只写入 `result=merged` 的 repo。无改动仓只出现在命令结果、临时执行上下文和 `merge-verification.md` 中。

---

## 4. merge-finalize 内部实现

### 4.1 前置状态与门禁

初次执行只允许：

```text
status = code-approved
```

内部复用现有状态机和门禁能力：

```javascript
findTransition(
  stateMachine,
  'code-approved',
  'merging',
  'merge-feature-branch'
)

runGateChecks(ws, cr, 'merging', gates, flags)
```

不得在 `merge-finalize` 内复制状态转换或 code approval 校验规则。

### 4.2 active repo 完整性校验

从目标 workspace 的：

```text
dir-graph.yaml#repositories
```

读取 `active != false` 的 repo，断言：

```text
payload repos 集合 === active repositories 集合
```

同时校验每一项的 `trunk` 等于声明值。

错误优先复用现有错误码：

- `BAD_ARGS`
- `SCHEMA_INVALID`
- `REPO_TRUNK_UNRESOLVED`
- `CR_STATUS_CURRENT_MISMATCH`
- `GATE_BLOCKED`
- `CAS_CONFLICT`

仅对远端发布事实增加必要错误：

```text
MERGE_SHA_NOT_PUBLISHED
```

### 4.3 发布事实校验

Skill 在调用 `merge-finalize` 前先对所有仓执行 `fetch origin`。

crctl 对每个 `merged` repo 验证：

```text
git merge-base --is-ancestor {merge-sha} origin/{trunk}
```

不要求 `origin/{trunk}` 严格等于 merge SHA。merge 后可能已有其他合法提交，只要求 merge SHA 是远端 trunk 的祖先。

对 `skipped-no-change` repo 验证：

```text
git merge-base --is-ancestor {source-sha} origin/{trunk}
```

这同时作为“无改动仓”的唯一机器判据，避免不同执行者分别使用 SHA 相等、commit count、tree diff 或 changed files 得出不同结论。

任一验证失败时：

- 不修改 `cr.md`；
- 不修改 `_backlog.yml`；
- 不写 success audit；
- 不写 status outbox；
- 不删除 payload。

### 4.4 在内存生成候选文件

复用已有纯函数：

```javascript
crMdStatusText(crMdText, 'merging')
```

新增批量纯函数：

```javascript
function appendMergeMetadataBatch(backlogText, cr, mergeCommits)
```

要求：

- 读入后先统一 `\r\n → \n`；
- 唯一锚定目标 CR 条目；
- payload 顺序按 `dir-graph.yaml#repositories` 排列；
- 每个 repo 最多一项；
- 同 repo、同 SHA 幂等；
- 同 repo、不同 SHA 硬失败；
- 解析失败不得返回原文或静默降级；
- `branch` 继续由 crctl 推导为 `requirement/{cr}`，不从 payload 接收。

候选 `_backlog.yml` 示例：

```yaml
merge-commits:
  - repo: tools
    trunk: custom/main
    sha: 2222222222222222222222222222222222222222
    branch: requirement/CR-2026-030
  - repo: ai-first-platform-docs
    trunk: master
    sha: 5555555555555555555555555555555555555555
    branch: requirement/CR-2026-030
```

### 4.5 原子写入

执行一次：

```javascript
casWriteMulti([
  {
    path: crMdPath,
    expectedHash: sha256(originalCrMd),
    newText: candidateCrMd,
  },
  {
    path: backlogPath,
    expectedHash: sha256(originalBacklog),
    newText: candidateBacklog,
  },
])
```

CAS 前必须执行：

```javascript
assertCandidateStatus(candidateCrMd, 'merging')
```

同时重新解析候选 backlog，确认：

- merged repo 数量正确；
- repo 集合正确；
- SHA 与 payload 完全一致；
- 不存在重复 repo。

任一校验或 CAS 失败时，两份权威文件均不落盘。

继续接受 `casWriteMulti` 已声明的连续 rename 微小崩溃窗口，不新增事务框架、数据库或锁服务。

### 4.6 单次 Git commit

`merge-finalize` 自己通过 controlled Git 执行：

```text
git add change-requests/_backlog.yml
        change-requests/{cr}/cr.md

git commit -m "[cr] finalize merge CR-2026-030 status+metadata"
```

Skill 不再手工执行 metadata 的 `add/commit`。

成功输出示例：

```json
{
  "op": "merge-finalize",
  "cr": "CR-2026-030",
  "from": "code-approved",
  "to": "merging",
  "mergeCommits": [
    {
      "repo": "tools",
      "trunk": "custom/main",
      "sha": "2222222222222222222222222222222222222222"
    },
    {
      "repo": "ai-first-platform-docs",
      "trunk": "master",
      "sha": "5555555555555555555555555555555555555555"
    }
  ],
  "skippedRepos": [
    {
      "repo": "multica",
      "reason": "no-change"
    }
  ],
  "files": [
    "change-requests/CR-2026-030/cr.md",
    "change-requests/_backlog.yml"
  ],
  "commit": {
    "message": "[cr] finalize merge CR-2026-030 status+metadata",
    "sha": "..."
  }
}
```

### 4.7 Audit 与 outbox

只有 commit 成功后才记录 success audit：

```javascript
auditLog(ws, {
  kind: 'merge-finalize',
  cr,
  from: 'code-approved',
  to: 'merging',
  repos: mergeCommits.map(({ repo, sha }) => ({ repo, sha })),
  skippedRepos,
  actor: identity(ws),
  result: 'success',
})
```

并发布一个 status outbox：

```javascript
emitOutboxEvent(ws, {
  event_kind: 'status',
  cr_id: cr,
  from_status: 'code-approved',
  to_status: 'merging',
  trigger: 'merge-feature-branch',
  commit_sha: gitHeadSha(ws),
  actor: identity(ws),
  payload: {
    merge_commits: mergeCommits,
    skipped_repos: skippedRepos,
  },
})
```

不再产生本节点的 `pending:*` embedded status 事件。

---

## 5. 幂等与恢复语义

### 5.1 初次成功后重复调用

若当前：

```text
status = merging
```

且 `_backlog.yml#merge-commits[]` 与 payload 完全一致，则返回：

```json
{
  "op": "merge-finalize",
  "result": "already-finalized",
  "cr": "CR-2026-030"
}
```

不得重复写入、重复 commit 或重复发布 outbox。

### 5.2 CAS 成功但 commit 失败

此时两份文件已经同时处于候选状态，但尚未提交。

命令返回：

```text
MERGE_FINALIZE_COMMIT_FAILED
```

并满足：

- status 和全部 metadata 同时保留在工作区；
- 不发 status outbox；
- payload 不删除；
- 不尝试把状态回滚成 `code-approved`。

再次执行同一命令时：

1. 检测两份文件与 payload 完全一致；
2. 重试同一 `git add/commit`；
3. commit 成功后再发 audit/outbox。

### 5.3 commit 后、输出前进程中断

再次执行时：

- status 已为 `merging`；
- metadata 完整；
- 工作区无对应 diff。

返回 `already-finalized`，不生成第二个 commit。

### 5.4 检测到旧流程半写

若：

```text
status = merging
```

但 metadata 只是 payload 的子集，或同 repo 存在不同 SHA，则返回：

```text
MERGE_FINALIZE_STATE_MISMATCH
```

不得自动猜测、追加或覆盖。

这是旧版 `advance → 多次 merge-metadata` 可能留下的异常，不纳入新流程正常恢复路径。

---

## 6. 优化后的 merge-feature-branch 流程

### Phase 1：全仓预检

1. 读取 workspace `AGENTS.md`、`dir-graph.yaml`；
2. 解析所有 active repo；
3. 通过 `crctl worktree-path` 获取 worktree，不再由 Skill 自行拼路径；
4. 先对所有 repo 执行 `fetch origin`；
5. 校验：
   - CR status=`code-approved`；
   - CR worktree clean；
   - trunk checkout clean；
   - 远端 requirement 分支存在；
   - 本地 worktree HEAD 等于远端 requirement SHA；
   - Git user.name/user.email 可用；
6. 通过 ancestry 判定无改动仓；
7. 对需要合并的仓执行 `merge-tree --write-tree`。

任一失败时不得修改任何 trunk。

### Phase 2：本地 prepare

对所有需要合并的仓依次执行：

```text
checkout trunk
pull --ff-only origin trunk
merge --no-commit --no-ff origin/requirement/{cr}
```

全部成功后才逐仓 commit。

本阶段保存临时执行记录：

```text
.crctl/tmp/merge-execution-{cr}.yml
```

记录：

- preflight trunk SHA；
- source SHA；
- local merge SHA；
- 当前阶段；
- 是否已 push；
- 补偿 SHA。

该文件只是临时恢复上下文，不是第二事实源。权威事实仍为 Git 与 `_backlog.yml`。

若 commit 阶段失败：

- 对仍处于 merge 状态的 repo 执行 `merge --abort`；
- 已生成本地 merge commit 的 repo 保留现场；
- 下次执行根据 execution payload 验证并恢复；
- 不再仅输出“重新运行”而不说明已有本地 commit 的处理方式。

### Phase 3：远端发布

push 前再次 fetch，并确认远端 trunk 未从 preflight SHA 漂移。

随后逐仓 push。

部分 push 失败时继续执行补偿，但恢复记录必须包含：

```yaml
repos:
  - repo: tools
    merge-sha: ...
    push: success
    compensation-sha: ...
```

补偿完成后的重试不得再次直接 merge 原 requirement 分支。由于原 merge commit 已进入 trunk ancestry，Git 会认为该分支已经合入。应通过：

```text
revert compensation-sha
```

重新应用变更，或在 requirement 分支产生新的修复提交。

### Phase 4：原子 finalize

全部 repo 发布成功后，生成：

```text
.crctl/tmp/merge-finalize.yml
```

然后只调用：

```powershell
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs `
  merge-finalize {cr_id} `
  --workspace {knowledgeBaseRepo.path}
```

删除原有组合：

```text
advance --embedded
逐仓 merge-metadata
git add metadata
git commit metadata
```

随后执行：

```text
crctl git push origin {knowledgeBaseRepo.trunk}
```

并确认 finalize commit 是 `origin/{knowledgeBaseRepo.trunk}` 的祖先。

### Phase 5：metadata 发布恢复

metadata push 失败时，不再因为一次 non-fast-forward 立即回滚所有代码仓。

处理顺序：

1. fetch knowledge-base origin；
2. 若 finalize SHA 已在 origin trunk，视为发布成功；
3. 若只是远端并发提交导致 non-fast-forward：
   - 对本地 finalize commit 与 origin trunk 做 merge-tree dry-run；
   - 无冲突则合并远端 trunk 后重新 push；
4. 有冲突则写入：
   ```text
   change-requests/{cr_id}/merge-recovery.yml
   ```
5. CR 不进入 writeback，保留全部 worktree；
6. metadata 发布恢复后继续联调验证。

优先恢复 metadata 而不是回滚所有已发布代码，避免产生“requirement 分支已是 trunk 祖先，但内容又被 revert”的复杂重合入问题。

### Phase 6：发布联调验证

只在 knowledge-base 主 checkout 判断流程状态：

```text
crctl status {cr_id} --workspace <主checkout>
crctl next {cr_id} --workspace <主checkout>
```

硬断言：

```text
status = merging
next = writeback-prd-sdd
```

CR worktree 仅用于：

- clean 检查；
- `worktree-path` 路径检查；
- 快照状态记录。

不得再把 CR worktree 上的 `next=merge-feature-branch` 当成正常的写回期路由结果。

---

## 7. merge-verification.md 契约

建议固定为：

```yaml
---
cr: CR-2026-030
verified-at: "2026-08-11T10:00:00+08:00"
verified-by: Ray
verdict: pass
repos:
  - repo: tools
    trunk: custom/main
    result: merged
    merge-sha: 2222222222222222222222222222222222222222
  - repo: multica
    trunk: main
    result: skipped-no-change
  - repo: ai-first-platform-docs
    trunk: master
    result: merged
    merge-sha: 5555555555555555555555555555555555555555
checks:
  status: pass
  next: pass
  worktree-path: pass
  custom-ledger: pass
---
```

约束：

- 只有 `verdict=pass` 才能继续 writeback；
- `result=merged` 必须有完整 merge SHA；
- `result=skipped-no-change` 禁止填写 `merge-sha: skipped`；
- CUSTOM.md 仅在目标仓实际存在该文件时核对；
- 查找 CR 条目使用 `{cr_id}`，不使用歧义占位符 `CR-{id}`；
- 写入后调用 `crctl validate` 或扩展现有 validate-doc 校验。

发现阻断异常时：

```yaml
verdict: block
```

停止 writeback，并创建新的修复 CR。不得声称 `merging` 状态可以回到 `review-tech-design`。

---

## 8. Skill 文档精简

优化后的 `merge-feature-branch/SKILL.md` 只保留：

1. 用途与原子性边界；
2. 参数；
3. 六阶段主流程；
4. `merge-finalize` payload；
5. 恢复矩阵；
6. `merge-verification.md` schema；
7. 输出；
8. 错误码。

删除：

- “Agent 绕过 crctl 直跑裸 git”的说明；
- 与主流程矛盾的 `cr.md` 自动冲突解决章节；
- 重复的历史 CR 说明；
- 多处重复的“禁止手写账本”；
- Pipeline prompt 中复制的完整算法。

预计：

```text
SKILL.md：247 行 → 约 160 行
Pipeline merge prompt：10 步 → 约 4 行
```

Pipeline prompt 可收敛为：

```text
执行 merge-feature-branch：
- cr_id={{inputs.cr_id}}
- 按 Skill 契约完成全仓预检、发布、补偿、crctl merge-finalize 与 merge-verification
- merge-finalize 前不得推进 merging
- merge-verification.verdict=pass 后节点才成功
- 输出 node-1.md 摘要
```

---

## 9. 恢复矩阵

| 失败阶段 | 权威状态 | 恢复方式 | 是否允许 writeback |
|---|---|---|---|
| dry-run 失败 | `code-approved` | 修复冲突后重跑 | 否 |
| 本地 no-commit merge 失败 | `code-approved` | 对 merge 中仓执行 abort，按 execution payload 恢复 | 否 |
| 本地 commit 部分成功 | `code-approved` | 保留已生成 commit，按 execution payload 识别，不盲目重复 merge | 否 |
| 远端部分 push，补偿成功 | `code-approved` | 记录 compensation SHA；重试时 revert compensation commit 重新应用 | 否 |
| 远端部分 push，补偿失败 | `code-approved` | 写 merge-recovery.yml，人工处理远端事实 | 否 |
| merge-finalize 校验失败 | `code-approved` | 修正 payload 或远端发布事实后重跑 | 否 |
| merge-finalize CAS 冲突 | 原状态 | 重新读取权威文件后重跑 | 否 |
| merge-finalize commit 失败 | 工作区为完整 `merging` 候选 | 原命令幂等重试 commit | 否 |
| finalize commit 已成功但未 push | 本地 `merging` | 重试 metadata push | 否 |
| metadata push 被并发更新拒绝 | 本地 `merging` | 合并远端 trunk 后重推；冲突则写 recovery | 否 |
| merge verification block | `merging` | 新建修复 CR，不回退原 CR 到设计态 | 否 |
| merge verification pass | `merging` | 进入 writeback-prd-sdd | 是 |

---

## 10. 需要修改的文件

| 文件 | 修改内容 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 新增 `merge-finalize`、批量 metadata 候选生成、原子写入与幂等恢复 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 增加集合完整性、发布证明、CAS、commit 重试和幂等测试 |
| `skills/shared/crctl/SKILL.md` | 登记 `merge-finalize` 接口、写入与失败契约 |
| `skills/_index.yml` | 更新 crctl brief |
| `skills/writeback/merge-feature-branch/SKILL.md` | 按六阶段重写，删除多事实源与不可达流程 |
| `pipeline-templates/feature-writeback.pipeline.json` | 删除重复算法，只保留输入、调用和结果契约 |
| `README.md` | 更新 merge 节点说明 |
| `skills/shared/validate-doc/` 或 crctl validate | 增加 merge-verification schema 校验 |

`gates.json` 与状态机无需新增副本。`merge-finalize` 直接复用现有 `merging` gate 和 `code-approved → merging` 状态机声明。

---

## 11. 验收测试

至少覆盖以下场景：

1. 两个 merged repo + 一个 skipped repo，status 与全部 metadata 同批写入；
2. payload 少一个 active repo，零写入；
3. payload 多一个 repo，零写入；
4. payload repo 重复，零写入；
5. payload trunk 与 dir-graph 不一致，零写入；
6. merge SHA 不是 origin trunk 祖先，零写入；
7. skipped source SHA 不是 trunk 祖先，零写入；
8. merging gate 失败，零写入；
9. cr.md CAS 冲突，两文件均不写；
10. backlog CAS 冲突，两文件均不写；
11. commit 失败时两文件共同保留且不发 outbox；
12. commit 重试成功，不重复 metadata；
13. commit 后进程中断，重跑返回 `already-finalized`；
14. status=merging 但 metadata 部分存在时硬失败；
15. `crctl next --workspace <主checkout>` 返回 `writeback-prd-sdd`；
16. merge-verification 中 `merge-sha: skipped` 被 schema 拒绝；
17. 无改动仓不写入 `_backlog.yml#merge-commits[]`，但进入 verification repos；
18. 现有 crctl 与 writeback 测试继续全绿。

---

## 12. 实施边界

本方案不引入：

- 新 Runner；
- 新状态机；
- 数据库事务；
- 跨仓锁服务；
- 动态加载框架；
- 第二份 repositories 声明；
- workspace/tools 或 PACKAGE_ROOT 回退；
- 会话内临时账本编辑脚本。

新增的核心能力只有一个：

```text
crctl merge-finalize
```

其价值是把原本暴露给 Skill 的“状态推进顺序、逐仓 metadata 写入、CAS、commit、audit、outbox、幂等恢复”全部藏进 crctl，实现更深的模块、更小的调用接口和更明确的失败边界。

该改动涉及 CR 状态唯一写入面、merge metadata 账本写入和 feature-writeback 主流程，应通过独立 CR 完成需求、设计、开发、评审和回写，不应直接修改 tools trunk。
