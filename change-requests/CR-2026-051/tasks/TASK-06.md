---
id: CR-2026-051-TASK-06
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: 异步读链与投递：workspace 闭合两条 SQL + 绑定分类 + 凭据水化 + 单次发送
slug: approval-reminder-delivery-chain
status: pending
estimate: 12h
depends-on: [CR-2026-051-TASK-05]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

实现提醒器异步执行体的主干：一条四跳全带 workspace 谓词的项目链查询、成员（owner/admin）查询、每收件人一次的绑定候选查询 + `chooseEffective` 可区分分类、`GetInWorkspace` 凭据水化 + 双层租户闭合复核、`attemptedOpenIDs` 发送前登记、单次发送与三类结果日志（SDD §4.2 / §4.3 / §4.4 / §4.6；FR-3~FR-7、AC-3、AC-4、AC-7、AC-10）。同时落地 BL-1（凭据路径）、BL-2（登记早于任何可失败动作）、BL-3 消费侧（载荷 `shell_issue_id` 不进查询）三条回修的实现与回归。

本 TASK 用真实现替换 TASK-05 的 `deliverToRecipients` 临时实现体，**不改其签名、不改构造契约**。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/internal/integrations/lark/approval_reminder.go`（改：追加读链、`chooseEffective`、水化与发送；替换 `deliverToRecipients` 实现体并删除其 TODO）
- `server/internal/integrations/lark/approval_reminder_test.go`（改：追加真库用例）

零改动：`pkg/db/queries/**`、`pkg/db/generated/**`（DD-2：不加 sqlc 查询、不重跑 `make sqlc`）、任何迁移、`channel_store.go`、`installation.go`、`feishu_channel.go`。

## 实现要点

1. **项目链查询**（一次往返，四跳全带锚点，`INNER JOIN` 即 fail-closed）：

   ```sql
   SELECT p.id::text, w.slug, c.title
     FROM cr c
     JOIN issue   i ON i.id = c.shell_issue_id AND i.workspace_id = $1
     JOIN project p ON p.id = i.project_id     AND p.workspace_id = $1
     JOIN workspace w ON w.id = $1
    WHERE c.workspace_id = $1 AND c.cr_id = $2;
   ```

   `$1` 只能是 `anchorWorkspaceID`（事件 envelope 的可信锚点），`$2` 为 `p.CRID`。**载荷的 `p.ShellIssueID` 不得出现在任何 SQL 参数里**（BL-3 硬约束）。
2. **零行的原因判定**（只为选日志原因，仍带 workspace 谓词，不产出任何收件人）：`SELECT shell_issue_id IS NULL FROM cr WHERE workspace_id = $1 AND cr_id = $2` —— 为真或无行 ⇒ `project-unresolved`；否则 ⇒ `workspace-mismatch`。`slug == ""` 同样归 `workspace-mismatch`。
3. **DB 报错不当零行**：项目链查询、原因判定、成员查询、绑定候选查询的 `err != nil`（且非 `pgx.ErrNoRows`）一律走 `logFailEvent`/`logFail` + 对应 `step` + `errorClassOf(err)`，**不复用任何 `reason`**（否则"库挂了"会伪装成"用户未绑定"）。
4. **成员查询**：`SELECT user_id::text FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')`；报错 → `logFailEvent(stepApproverQuery, …)`；空集 → `logSkipEvent(reasonNoApprover)`。
5. **CTA**：`approveURL := r.appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`（FR-7；`appURL` 已由 TASK-05 前置判定非空，且 `appURLFromEnv` 已 `TrimRight(…,"/")`；slug 与 projectID 均取自实现要点 1 那条锚定查询的返回值）。**不新增 URL 合法性校验器**。
6. **绑定候选查询**（每收件人一次，`LEFT JOIN` 让悬空 `installation_id` 可观测为 `installation-missing` 而不是塌成 `binding-missing`）：

   ```sql
   SELECT b.id::text, b.channel_user_id, b.installation_id::text,
          ci.id::text, ci.workspace_id::text, ci.channel_type, ci.status
     FROM channel_user_binding b
     LEFT JOIN channel_installation ci ON ci.id = b.installation_id
    WHERE b.workspace_id = $1 AND b.multica_user_id = $2 AND b.channel_type = 'feishu'
    ORDER BY b.bound_at DESC, b.id ASC;
   ```

   `ci.*` 只取回、**不进 WHERE**（进 WHERE 会把 missing/revoked/mismatch 三种失效全塌成零行，AC-4 就无法验收）。可空列扫进 `*string`（pgx v5 `pointerPointerScanPlan` 承接 NULL）。
7. **`chooseEffective(rows []approvalBindingCandidate, anchorWorkspaceID string) (*approvalBindingCandidate, string)`**：按 SQL 已给的确定性顺序遍历，`installation_id` 或 `ci` 为 NULL → `seenMissing`；`ci.workspace_id != anchor` 或 `ci.channel_type != 'feishu'` → `seenMismatch`；`ci.status != 'active'` → `seenRevoked`；首个三条件全过的行即命中（每用户一张卡）。无命中时按"最具体优先"返回唯一原因：`workspace-mismatch` > `installation-revoked` > `installation-missing` > `binding-missing`（末项为 rows 非空时的兜底）。纯函数，可独立单测（无需 DB）。
8. **BL-2 登记点**：`attemptedOpenIDs map[string]struct{}` 语义是"已尝试"。命中候选后**先**判重（已在集合内 → `continue`，不记重复日志）、**再**登记，**然后**才做水化/解密/发送。登记必须早于任何可失败动作。
9. **BL-1 凭据水化**：`inst, err := r.credentials.GetInWorkspace(ctx, installationUUID, anchorWorkspaceUUID)`（`installationUUID`/`anchorWorkspaceUUID` 由 `util.ParseUUID` 转换，`internal/util` 已被 lark 包 import）。`errors.Is(err, ErrInstallationNotFound)` → `logSkipRecipient(reasonInstallationMissing)`；其他 err → `logFail(stepCredentialHydrate, …)`。水化后**再复核一次**：`util.UUIDToString(inst.WorkspaceID) != anchorWorkspaceID` → `workspace-mismatch`；`inst.Status != "active"` → `installation-revoked`（封住"分类→发送"之间的撤销窗，分类与水化不一致时**以水化结果为准**）。随后 `creds, err := installationCredentialsFor(inst, r.credentials)`（既有 helper，零改动复用），err → `logFail(stepCredentialDecrypt, …)`。**裸 SQL 绝不自行解 `config` JSONB、不自行做 base64 宽容解码**。
10. **单次发送**：`rctx, rcancel := context.WithTimeout(ctx, r.recipientTimeout)`（默认 10s，用完立即 `rcancel()`，不 defer 进循环）→ `r.client.SendApprovalReminderCard(rctx, ApprovalReminderParams{InstallationID: creds, OpenID: pick.OpenID, CRID: p.CRID, CRTitle: title, StageLabel: stageLabel(p.Status), ApproveURL: approveURL})`；err → `logFail(stepSend, errorClassOf(err))`；否则 `logSent`。单收件人失败不影响同批其他人，**不重试、不撤回**。
11. **不做的事**（PRD §7 范围排除，逐条守住）：异步开始时不重读 CR 状态；不写库、不开事务；不加安装级凭据缓存；不做 drain/join；不新增表/outbox/幂等键/多渠道抽象。
12. multica 仓注释英文；两条裸 SQL 上方各写 `// AIFIRST: CR-2026-051 …` 注释，说明为何不复用 `FindChannelBindingForMember`（不闭合 `ci.workspace_id`/`channel_type`，且 `LIMIT 1 + INNER JOIN active` 会塌掉三种失效原因）与为何 `ci.*` 不进 WHERE。

## 验收条件

真库用例（C6 口径，`--- SKIP` 视为未测）。造数复用 lark 包既有形态（参照 `channel_store_scope_test.go:21-31` 的连库 helper 与 `channel_store_rebind_test.go` 的绑定/安装造数），CR/issue/project 造数参照 `governance/project_gates_test.go:49-51`。

1. **AC-3 happy path 多收件人**：3 个 owner/admin，其中 2 人有有效飞书绑定 → 恰 2 张卡；某用户有 2 条绑定（`bound_at` 不同）→ 只发 1 张且用最新那条的 `open_id`；两个不同 user 指向同一 `open_id` → 只发 1 张。
2. **BL-2 回归（首个尝试失败 + 重复 open_id）**：两个不同 user 同一 `open_id`，第一次发送返错 → 断言客户端**只被调用一次**、第二个用户既无发送也无重复"尝试"日志；同型用例覆盖"首次解密失败"与"首次发送超时"（`context.DeadlineExceeded`）。
3. **BL-1 凭据水化四态**：① happy —— 发送时 `InstallationCredentials` 的 `AppID`/`AppSecret`/`TenantKey`/`Region` 与库中一致（真库 + 真 `secretbox` 加解密）；② `ErrInstallationNotFound` → `installation-missing`；③ 分类时 `active`、水化前改成 `revoked` → `installation-revoked`；④ 水化返回的 `inst.WorkspaceID` 与锚点不符 → `workspace-mismatch`。另断言安装属另一 workspace 时 `GetInWorkspace` 本身即查不到（上游谓词生效）。
4. **AC-4 四类不发送各留可区分原因**：`member` 角色（不在收件人集合内）、无 feishu 绑定行 → `binding-missing`、安装 `revoked` → `installation-revoked`、`installation_id` 悬空 orphan → `installation-missing`；四条日志的 `reason` 互不相同且均带 `recipient_user_id`。
5. **AC-10 跨 workspace 负向 + 载荷伪造**：`issue`/`project`/绑定/安装任一层 `workspace_id` 与锚点不一致 → 零发送 + `workspace-mismatch`；载荷 `shell_issue_id` 被伪造成另一 workspace 的 issue → 仍以 `cr` 行为准解析（零发送）；CR 自身 `shell_issue_id IS NULL` → `project-unresolved`。附静态核对：`grep` 断言提醒器内无"仅按主键/仅按外键"的查询（每条 SQL 都含 `workspace_id`）。
6. **AC-5 CTA 与基地址**：断言发送参数的 `ApproveURL == appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`，且 slug 取自锚定 workspace（跨 workspace slug 回归：另一 workspace 的同名 project 不影响生成结果）。
7. **AC-7 事件级/收件人级 failed**：注入报错的 pool 替身（或临时改名的表/权限）使项目链查询失败 → 恰一条 `result=failed`、`step=project-chain`、**无 recipient 字段、无 `reason` 字段**；使绑定候选查询失败 → 收件人级 `result=failed`、`step=binding-query`（而非 `binding-missing`）。
8. **`chooseEffective` 纯函数单测**（无 DB）：覆盖 4 种原因 + 命中最新绑定 + rows 非空但全失效时的原因优先级（mismatch > revoked > missing）。
9. `cd server && go build ./... && go vet ./internal/integrations/lark/` 零报告；`go test ./internal/integrations/lark/ -run 'ApprovalReminder' -v -count=1` 全部 `--- PASS`；`go test ./internal/integrations/lark/ -count=1` 整包通过（对照 CUSTOM.md 基线排除既有失败）。
10. `git diff --name-only` 在本 TASK 范围内只有 `approval_reminder.go` + `approval_reminder_test.go`；`git diff` 确认 `pkg/db/queries`/`pkg/db/generated` 零改动。

## 完成标志

上述 10 条全通过并留下 `-v` 的 `--- PASS` 输出；`approval_reminder.go` 总行数 < 400（SDD §7.3 规则五预算）；`crctl task done CR-2026-051 --task CR-2026-051-TASK-06 --workspace <kb worktree>` 已登记。M2 里程碑到此闭合：提醒器可端到端投递，仅剩装配。

## 接口契约

- **消费**（签名固定，来自上游 TASK 与既有代码）：
  - TASK-05：`(r *ApprovalReminder) deliverToRecipients(ctx context.Context, p protocol.ApprovalGateEnteredPayload, anchorWorkspaceID string)`（替换其实现体）、`r.pool`/`r.client`/`r.credentials`/`r.appURL`/`r.recipientTimeout`、日志四入口、9 reason + 4 error_class + 6 step 常量、`stageLabel(status string) string`、`errorClassOf(err error) string`；
  - TASK-04：`APIClient.SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error` 与 `ApprovalReminderParams{InstallationID InstallationCredentials; OpenID OpenID; CRID string; CRTitle string; StageLabel string; ApproveURL string}`；
  - TASK-01：`protocol.ApprovalGateEnteredPayload`（只读 `CRID`/`Status`/`EventID`；`ShellIssueID` 仅可写入日志/诊断，禁止进 SQL）；
  - 既有：`installationCredentialsFor(inst Installation, resolver CredentialsResolver) (InstallationCredentials, error)`（`feishu_channel.go:104`）、`(*InstallationService).GetInWorkspace(ctx, id, workspaceID pgtype.UUID) (Installation, error)`（`installation.go:110`）、`ErrInstallationNotFound`（`installation.go:131`）、`Installation{WorkspaceID, Status, AppID, TenantKey, Region}`（`store.go:42-59`）、`util.ParseUUID(string) (pgtype.UUID, error)`（`internal/util/pgx.go:19`）、`util.UUIDToString(pgtype.UUID) string`（`:41`）、`(*pgxpool.Pool).Query/QueryRow`。
- **产出**（包内私有，TASK-07/TASK-08 不直接调用，仅通过 `Register` 生效）：`type approvalBindingCandidate struct { BindingID string; OpenID OpenID; InstallationID *string; InstWorkspaceID *string; InstChannelType *string; InstStatus *string }`、`chooseEffective(rows []approvalBindingCandidate, anchorWorkspaceID string) (*approvalBindingCandidate, string)`、`deliverToRecipients` 的真实现。
