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

零改动：`pkg/db/queries/**`、`pkg/db/generated/**`（DD-2：不加 sqlc 查询、不重跑 `make sqlc`）、任何迁移、`channel_store.go`、`installation.go`、`feishu_channel.go`。验收 7② 的失败注入只得建/删**测试专用的私有 schema**，**不得改动 `public` schema 的任何对象**。

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
   **这条空集分支就是 AC-4 情形①（非 owner/admin）的原因载体**（SDD §4.6 第 7 条）：收件人集合的**唯一**来源是本查询的结果集，非 owner/admin 的用户从不进入循环，因此不存在挂在其身上的收件人级记录。**两条硬约束**：① 不得为每个非 owner/admin 成员记一条收件人级 `no-approver`（会把它从 PRD §4.4 的事件级 partition 搬到收件人级，且需额外查全量 `member`、日志量随 workspace 规模膨胀）；② 不得新增 `role-ineligible` 一类第 10 个 reason（TASK-05 已把 9 项枚举声明为闭集常量）。**不得**把 `role` 过滤放宽成全量 `member` 查询再在 Go 侧筛——FR-4 声明的读面就是 `role IN ('owner','admin')`。
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
4. **AC-4 四情形不发送各留可区分原因（按 SDD §4.6 第 7 条的一一对应表；情形① 与 ②③④ 作用域不同）**：
   - **情形①非 owner/admin = 两条互补断言**（不是一条）：
     - (a) *可区分原因*：造一个 workspace，其全部成员 `role='member'`（`member` 表无「必须存在 owner」约束，`migrations/001_init.up.sql:26-33` 只有 `CHECK (role IN ('owner','admin','member'))` + `UNIQUE(workspace_id,user_id)`，真库可直接 INSERT），该成员**有效飞书绑定齐备** → 断言恰一条**事件级** `result=skipped reason=no-approver`、**无任何 `recipient_*` 字段**、客户端零调用；
     - (b) *零发送*：混合 workspace（1 名 `admin` + 1 名 `member`，**两人都有有效飞书绑定、open_id 不同**） → 断言客户端恰被调用 **1 次**、`receive_id` = admin 的 `open_id`，且全部日志行中 **不出现** `member` 的 `recipient_user_id`（证明它从未进入收件人集合，而不是“进了又被跳过”）。
   - **情形②③④ = 收件人级**：无 feishu 绑定行 → `binding-missing`；安装 `revoked` → `installation-revoked`；`installation_id` 悬空 orphan → `installation-missing`；三条均带 `recipient_user_id`。
   - **反向断言（防漂移）**：上述全部用例的日志中不得出现**收件人级** `reason=no-approver`，也不得出现 9 项枚举之外的任何 `reason`（逐行 `json.Unmarshal` 后比对常量集，不用 `strings.Contains`）。
   - 四条可区分原因互不相同：`no-approver`（事件级）/ `binding-missing` / `installation-revoked` / `installation-missing`（收件人级）。
5. **AC-10 跨 workspace 负向 + 载荷伪造**：`issue`/`project`/绑定/安装任一层 `workspace_id` 与锚点不一致 → 零发送 + `workspace-mismatch`；载荷 `shell_issue_id` 被伪造成另一 workspace 的 issue → 仍以 `cr` 行为准解析（零发送）；CR 自身 `shell_issue_id IS NULL` → `project-unresolved`。附静态核对：`grep` 断言提醒器内无"仅按主键/仅按外键"的查询（每条 SQL 都含 `workspace_id`）。
6. **AC-5 CTA 与基地址**：断言发送参数的 `ApproveURL == appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`，且 slug 取自锚定 workspace（跨 workspace slug 回归：另一 workspace 的同名 project 不影响生成结果）。
7. **AC-7 事件级/收件人级 failed**。**强制 DB 报错的手段（架构评审 cycle 2 建议 2）**：`Pool` 是具体类型 `*pgxpool.Pool`，**无接口替身可注入**，因此禁止写成“注入报错的 pool 替身”，两条断言各自用可执行手段：
   - ① **项目链查询失败（事件级）**：另建一份**独立**真池（`pgxpool.New(ctx, 同一 DSN)`）并立即 `Close()` 后传入——已核实 `Close()` 后取连接返回 `puddle.ErrClosedPool`（`"closed pool"`），是**报错而非 panic**（plan.md §5.3）；**不得关掉共享的测试池**。断言：恰一条 `result=failed`、`step=project-chain`、`error_class=other`、**无 recipient 字段、无 `reason` 字段**。
   - ② **绑定候选查询失败（收件人级）**：前两跳（项目链、成员）必须**成功**、只让第三跳失败。**严禁改动 `public` schema**——原 `ALTER TABLE channel_user_binding RENAME` + `t.Cleanup` 方案**已废弃**（dev-plan 评审 attempt 1 BL-2：`scripts/test-go.sh` 把全部 regular packages 交给**同一次** `go test`、按默认包级并行运行且共享同一个 `DATABASE_URL`（已核实，见 plan.md §5.3），重命名窗口内其它包可访问该表；且测试进程被强杀/崩溃时 `t.Cleanup` 无法恢复表名，“包内触库用例均不 `t.Parallel()`”不足以做安全前提）。改用**私有 schema 遮蔽 + 专用池 `search_path`**（零 `public` 改动）：
     1. 用共享测试池建一个**唯一命名的私有 schema**。**命名算法必须长度有界、且不包含任何变长输入**（dev-plan 评审 attempt 2 BL-2 回修：原 `ac7_<sanitize(t.Name())>_<pid>_<unixnano>` 以 `t.Name()` 作变长中缀，长测试名会撞上 PostgreSQL 标识符 **63 字节**上限并**静默截断尾部唯一后缀**，强杀遗留后重跑就可能 `CREATE SCHEMA` 冲突，恰好推翻“清理非必需、可稳定复跑”的结论）。**直接复用 multica 仓已有的私有 schema 命名先例**（`cmd/migrate/migrate_invalid_index_test.go:20-30`，**全仓 10 处 / 6 个测试文件同型**，已核实，见 plan.md §5.3）：`schema := "ac7_binding_shadow_" + fmt.Sprintf("%d_%d", time.Now().UnixNano(), rand.Uint32())`（`math/rand/v2`）、`schemaIdent := pgx.Identifier{schema}.Sanitize()`。
        - **`t.Name()` 不再进入名称**，因此截断这一类问题**按构造即不存在**：固定前缀 19 B + `UnixNano` ≤ 19 B + `_` + `rand.Uint32()` ≤ 10 B = **最长 49 B**，恒 ≤ 63；字母表恒为 `[a-z0-9_]`（无需引号）。唯一性不依赖测试名：`UnixNano` + `rand.Uint32()` 使每次进程、每次重跑均得新名，强杀遗留同名 schema 后重跑仍不冲突。
        - 名称**只计算一次**存入 `schema`，CREATE / `search_path` / DROP **一律复用它**（DDL 用 `schemaIdent`，`search_path` 用裸 `schema`——字母表已排除需要引号的字符），**禁止在三个位置各自拼一次**。
        - schema 内只建一个**列不兼容的同名遮蔽表**：`CREATE TABLE <schemaIdent>.channel_user_binding (id uuid PRIMARY KEY)`（故意不含 `workspace_id` / `multica_user_id` / `channel_user_id` / `installation_id` / `channel_type` / `bound_at`）。
        - **权限不足时的退化（评审非阻塞建议，attempt 2 落入）**：`CREATE SCHEMA` 的 err 若 `errors.As` 成 `*pgconn.PgError` 且 `Code == "42501"`（`insufficient_privilege`，即测试角色无 `CREATE` 权限）则 `t.Skipf`；其余 err 一律 `t.Fatalf`（**不得静默降级**）。**硬门禁不变**：`--- SKIP` 只表示“未测”，**不得据此把 TASK 标 done**（完成标志要求留下 `--- PASS` 输出）。
     2. 造数与前两跳仍全部落在 `public`；传给提醒器的是一个**专用池**：`cfg, _ := pgxpool.ParseConfig(dsn)` → `cfg.ConnConfig.RuntimeParams["search_path"] = schema + ", public"`（**复用步骤 1 那一个 `schema` 变量**，不重新拼名）→ `pgxpool.NewWithConfig(ctx, cfg)`，`defer pool.Close()`（`RuntimeParams` 在连接启动时下发为会话默认值，已核实，见 plan.md §5.3）。于是 `cr`/`issue`/`project`/`workspace`/`member`/`channel_installation` 仍解析到 `public`（前两跳确定成功），**只有 `channel_user_binding` 命中遮蔽表**。不得修改共享测试池的 `search_path`。
     3. 该失败发生在**语句准备期**（`42703 undefined_column`，如 `column b.workspace_id does not exist`），**与表中有无数据无关**，故确定性、可重复；它不是 `pgx.ErrNoRows`，必然进实现要点 3 的 `logFail` 分支。
     4. 清理：`t.Cleanup` 里 `DROP SCHEMA IF EXISTS <schemaIdent> CASCADE`（**复用同一个 `schemaIdent`**；`IF EXISTS` + 失败只 `t.Logf` 不 `t.Fatalf`，与先例 `migrate_invalid_index_test.go:26-30` 一致）。但**正确性与隔离性均不依赖清理被执行**——遗留物是一个唯一命名的私有 schema，`search_path` 不含它的任何会话（= 其它包、其它用例、生产代码）完全看不见它；对照被重命名的 `public` 表：遗留即全局破坏。本用例仍不得调 `t.Parallel()`（守住触库用例串行的包内成规），但该约束不再是安全性的必要条件。
     断言：恰一条**收件人级** `result=failed`、`step=binding-query`（而非 `binding-missing`）、带 `recipient_user_id`、`error_class=other`；另断言同一事件下 `step=project-chain` 与 `step=approver-query` 零 `failed`（证明只有第三跳失败）。
     **取证前提自检（与提醒器行为断言分开写）**：
     - **注入确实生效**：同一用例内直接用该专用池执行一次同形 SQL，断言返回的 err 可 `errors.As` 成 `*pgconn.PgError` 且 `Code == "42703"`（证明是服务端真实查询失败，而非 Go 侧守卫短路）；
     - **`public` 未被动过**：用共享测试池断言 `to_regclass('public.channel_user_binding') IS NOT NULL`；
     - **标识符长度有界（attempt 2 BL-2，静态、无需 DB）**：断言 `len(schema) <= 63`（Go 的 `len(string)` 即 UTF-8 **字节**长度；字母表 `[a-z0-9_]` 均为单字节，故字节数 = 字符数），且 `schema` 匹配 `^[a-z][a-z0-9_]*$`（同时守住“不需引号”这一前提）；
     - **未被截断的直证（比长度算术更强）**：CREATE 之后用共享测试池断言 `SELECT count(*) FROM pg_namespace WHERE nspname = $1`（参数为 `schema` 原值）返回 **1** —— 服务端存下的名字与本地计算的名字逐字节一致，直接排除服务端截断（不以“63 字节上限”这条记忆作为断言基础，而是让用例当场证伪）。
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
