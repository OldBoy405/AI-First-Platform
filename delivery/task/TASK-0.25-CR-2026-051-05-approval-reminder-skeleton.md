---
spec-id: ai-first-platform
version: "0.25"
id: CR-2026-051-TASK-05
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: 审批提醒器骨架：构造/无条件订阅/零 I-O 回调/日志四入口/过载与 panic 兜底
slug: approval-reminder-skeleton
status: pending
estimate: 8h
depends-on: [CR-2026-051-TASK-01, CR-2026-051-TASK-04]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

建立 `ApprovalReminder` 的骨架与全部"不做 I/O 就能判定"的部分：构造契约（依赖缺失不返回 nil、不 panic）、无条件订阅、同步回调零 I/O + 非阻塞信号量、异步执行体的 `recover` 与超时外壳、飞书可用性与 `appURL` 两道零 DB 前置判定，以及三类结果日志的四个统一入口与常量闭集（SDD §3.2.3 / §4.1 / §4.6，FR-8.1~8.3）。

读链、绑定分类、凭据水化与实际发送在 TASK-06 接续；本 TASK 结束时 `deliver` 走到"前置判定通过"后调用一个**本 TASK 定义、TASK-06 实现**的私有方法（骨架内先返回一条 `feishu-disabled` 之外的可判定形态，见实现要点 7），保证本 TASK 自身可编译、可测、可回归。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/internal/integrations/lark/approval_reminder.go`（新，本 TASK 建立骨架；TASK-06 在同文件追加读链，不回改本 TASK 的构造契约）
- `server/internal/integrations/lark/approval_reminder_test.go`（新，本 TASK 建立；TASK-06 追加真库用例）

零改动：`client.go`（TASK-04 已定稿）、`http_client.go`、`outbound.go`（`CredentialsResolver` 原样复用）、`installation.go`。

## 实现要点

1. **窄依赖接口**（不改上游签名，`*InstallationService` 现成满足）：

   ```go
   type installationCredentialSource interface {
       CredentialsResolver // DecryptAppSecret(inst Installation) (string, error)
       GetInWorkspace(ctx context.Context, id, workspaceID pgtype.UUID) (Installation, error)
   }
   ```

2. **配置与构造**：`ApprovalReminderConfig{ Pool *pgxpool.Pool; Client APIClient; Credentials installationCredentialSource; AppURL string; Logger *slog.Logger; MaxInFlight int; EventTimeout, RecipientTimeout time.Duration }`。`NewApprovalReminder(cfg) *ApprovalReminder` **永不返回 nil**：`Pool`/`Client`/`Credentials` 任一为 nil 时记一条 **`phase=construct` + `missing=<按固定顺序 pool,client,credentials 逗号连接的缺失项>` 的 dependency-missing `Error`**（不带 `result` 字段，口径见要点 9 末段）并返回标记为不可用的真实对象。零值退化仅三处且文档化：`MaxInFlight == 0 → 8`、`EventTimeout == 0 → 60s`、`RecipientTimeout == 0 → 10s`；**非零值一律生效，不得静默忽略**（CONTRIBUTING.AIFIRST 规则六）。`Logger == nil → slog.Default()`。
3. **订阅**：`func (r *ApprovalReminder) Register(bus *events.Bus)` → `bus.Subscribe(protocol.EventCRApprovalGateEntered, r.handleEvent)`；`bus == nil` 时记一条 **`phase=register` + `missing=bus` 的 dependency-missing `Error`**（不带 `result` 字段，与要点 2 的构造期 Error 同属要点 9 末段的**三值 `phase` 闭集**）并**直接返回、不订阅、不 panic**。无条件可调用是 FR-8.3 的前提。
4. **同步回调零 I/O**：`handleEvent(e events.Event)` 只做：`parsePayload(e.Payload)` 真类型断言 + 字段非空校验（失败记 Warn 返回）→ `approvalGateStageLabels` 闭集二次过滤（非四门禁直接返回，防御性）→ `e.WorkspaceID == ""` 记 Warn 返回 → `select { case r.sem <- struct{}{}: go r.deliver(p, e.WorkspaceID); default: r.logSkipEvent(p, e.WorkspaceID, reasonOverloaded) }`。禁止任何 DB/HTTP 调用（AC-11 用零调用替身断言）。
5. **异步外壳**：`deliver(p protocol.ApprovalGateEnteredPayload, anchorWorkspaceID string)` 首两行 `defer` 自持 `recover()`（记一条 **`phase=panic-recovered`** 的 Error，进程存活；`events.Bus` 的 recover 覆盖不到派生 goroutine）与 `defer func(){ <-r.sem }()`；随后 `ctx, cancel := context.WithTimeout(context.Background(), r.eventTimeout)` + `defer cancel()`（脱离请求 ctx）。
6. **两道零 DB 前置判定**（顺序不可换，必须在任何 DB 访问之前）：① `r.pool == nil || r.client == nil || !r.client.IsConfigured() || r.credentials == nil` → `logSkipEvent(reasonFeishuDisabled)` 返回（覆盖"飞书未启用"与"依赖未装配"两种形态，**不新增第 10 个 reason**）；② `r.appURL == ""` → `logSkipEvent(reasonAppURLMissing)` 返回。
   **typed-nil 不属于本 TASK 的责任面（SDD §3.2.3 口径硬化，dev-plan 评审 BL-3）**：`r.credentials == nil` 对 typed-nil 接口（`var s *InstallationService; cfg.Credentials = s`）**为假**，这是已知且有意的设计选择（提醒器内不反射）。因此本 TASK **不得**写"灌 typed-nil 仍得 `feishu-disabled`"这类断言（不可满足）；typed-nil 的回归锁在 TASK-07 的 wiring 层。
7. **读链 seam**：前置判定通过后调用 `r.deliverToRecipients(ctx, p, anchorWorkspaceID)`（本 TASK 声明并给出**临时实现**：记一条 `logFailEvent(stepProjectChain, errorClassOther)` 并返回，附 `// TODO(CR-2026-051 TASK-06)` 英文注释指明由 TASK-06 替换）。这样本 TASK 的用例只断言前置判定与外壳行为，不产生"半个读链"的假语义；TASK-06 用真实现替换该函数体，其上层调用点与签名不变。
8. **常量闭集**（集中声明，禁止散拼字符串）：9 个跳过原因常量严格取 PRD FR-8.2 枚举 —— `project-unresolved`、`workspace-mismatch`、`no-approver`、`binding-missing`、`installation-revoked`、`installation-missing`、`app-url-missing`、`feishu-disabled`、`overloaded`；4 个 `error_class` —— `timeout`、`rate-limited`、`not-configured`、`other`；6 个 `step` —— `project-chain`、`approver-query`、`binding-query`、`credential-hydrate`、`credential-decrypt`、`send`。
9. **日志入口（SDD §4.6 的四类结果；`skipped` 按作用域拆成两个函数，字段口径不变）**（字段口径按 SDD §4.6，字段名与 PRD §4.4 表一致）：
   - `logSent(p, workspaceID, userID, openID)`：`cr_id`、`stage`、`workspace_id`、`event_id`、`recipient_user_id`、`recipient_open_id`、`result=sent`；
   - `logFail(p, workspaceID, userID, openID, step, errClass)`：同上 + `result=failed` + `error_class` + `step`（`openID` 为空时省略该字段）；
   - `logFailEvent(p, workspaceID, step, errClass)`：`cr_id`、`stage`、`workspace_id`、`event_id`、`result=failed`、`error_class`、`step`，**无 recipient 字段**（审批已确认的可观测性细化，plan.md §0）；
   - `logSkipEvent(p, workspaceID, reason)` / `logSkipRecipient(p, workspaceID, userID, reason)`：四个必填 + `result=skipped` + `reason`（+ 收件人级的 `recipient_user_id`）。
   `stage` 一律取 CR status 字面值（`p.Status`），**不取卡片中文阶段名、不取 `approval_record.stage`**。`error_class` 由私有 `errorClassOf(err) string` 归类（`context.DeadlineExceeded`/`context.Canceled` → `timeout`；`ErrAPIClientNotConfigured` → `not-configured`；含限流语义的飞书错误码 → `rate-limited`；其余含 DB 与解密错误 → `other`），**不得**把响应体原文、token、凭据、diff 写进日志。
   **非 result 类 `Error` 日志 = 恰三条，构成本 TASK `Error` 级输出的完整闭集（dev-plan 评审 attempt 2 BL-1 回修）**（均不带 `result` 字段，靠互斥的 `phase` 值与四类结果日志、以及彼此相互区分）：
   | `phase` | 触发点 | 附加字段 |
   |---|---|---|
   | `construct` | 要点 2：`Pool`/`Client`/`Credentials` 任一为 nil | `missing`（按固定顺序 `pool,client,credentials` 逗号连接的缺失项） |
   | `register` | 要点 3：`Register(bus == nil)` | `missing=bus` |
   | `panic-recovered` | 要点 5：异步体 recover 兜底 | `cr_id`/`stage`/`workspace_id`/`event_id` |

   `phase` 是**诊断字段而非结果分类**：它不进 PRD FR-8.2 的 9 项 `reason` 闭集、不新增第 10 个 reason，也不改 SDD §4.6 的四类结果口径。三个值互斥、可判定，是验收 1 与验收 4 断言的基础。**“唯一”的准确说法是这张表就是闭集**：除上表三行外，本 TASK 不得产出任何其它 `Error` 级日志（attempt 2 BL-1 根因即原文一边要求 `Register(nil)` 记 Error、一边宣称构造/兜底两条是“唯一的 Error 级输出”，两条无法同时成立；现由第三个 `phase` 值 `register` 收编，闭集从两条扩为三条，取代 §5.6 BL-1 中“两条”的旧描述）。**计数口径**：所有验收里对 Error 的“恰一条”一律**按 `phase` 值分别计数**，不对 Error 级总行数计数（attempt 1 的 `construct` / `panic-recovered` 断言数值因此不受本次扩集影响）。
10. **展示层映射与闭集合并（对 SDD 的一处显式收敛，非静默偏离）**：SDD §4.1 的过滤集 `approvalGateStatuses` 与 §4.3 的展示映射本是同一个四元闭集，故合并为**一份**声明 `var approvalGateStageLabels = map[string]string{"requirement-reviewing": "需求审批", "tech-design-review-pending": "架构审批", "task-breakdown": "开发启动审批", "code-reviewing": "代码审批"}`；`func stageLabel(status string) string` 查表命中返回中文名、未命中回退 `status` 原文（= SDD §4.3 要求的 `default` 语义，新增门禁状态不会渲染空白），实现要点 4 的二次过滤用 `_, ok := approvalGateStageLabels[p.Status]`。这样同包内四个状态字面量只出现一次；语义与 SDD 完全一致，仅声明形态从「switch + 另一个 map」收敛为「一个 map + 查表函数」。展示映射仅供卡片，不落日志（日志 `stage` 恒为 `p.Status`）。**该 map 必须不导出、初始化后只读**（运行期零写入，`stageLabel` 只查表）——这是架构评审 cycle 2 建议 3 的采纳形态（取其前半句）；SDD §4.3 已定下“map + 查表函数”，因此**不**改写为单个 switch helper（不制造计划层对已审批 SDD 的新偏离）；只读约束由验收 8 的静态断言守住。
11. multica 仓注释英文；新文件预算 < 400 行；**不新增包级可变全局状态**——包级变量仅要点 10 的 `approvalGateStageLabels` 一个，不导出、初始化后只读、运行期零写入（由验收 8 的静态断言守住）；其余依赖与参数全走构造注入。

## 验收条件

1. **依赖缺失不 panic，且逐依赖隔离取证（AC-12 部分；dev-plan 评审 BL-3 回修）**：`Pool`/`Client`/`Credentials` 任一为 nil 时 `NewApprovalReminder` 返回非 nil。行为断言拆成 **四个依赖子用例 (a)~(d)（每个只置一项为 nil、其余依赖均健康）+ 一个 `bus` 子用例 (e)**（attempt 2 BL-1 新增，见下）：(a) 只 `Credentials = nil`；(b) 只 `Client = nil`；(c) `Client` 非 nil 但 `IsConfigured() == false`；(d) 只 `Pool = nil`。(a)~(d) 每个子用例：`Register(bus)` + `bus.Publish(真事件)` 后进程存活、恰一条 `result=skipped reason=feishu-disabled`、**零 DB 访问**。
   逐依赖隔离是**硬要求**：一次性把三个依赖都置 nil 时，`feishu-disabled` 只能证明"四条条件里至少一条命中"，单条分支全部未被证明（其他 nil 依赖会把断言短路成假证）。
   **构造期 Error 是预期输出，不是断言噪音（dev-plan 评审 attempt 1 BL-1 回修）**：要点 2 规定 `Pool`/`Client`/`Credentials` 任一为 nil 时构造函数**必然**记一条 dependency-missing Error，因此本验收**不得**写成"无 Error 日志"（那与要点 2 直接冲突、按计划自身即不可满足）。断言口径改为按 `phase` 区分（要点 9 末段）：
   - **正向**：(a)(b)(d) 各有且**仅有一条** `phase=construct` 的 Error，且其 `missing` 恰等于该子用例置 nil 的那一项（顺带兑现要点 2 的逐依赖可观测性）；(c) 无 nil 依赖，故 `phase=construct` 行数为 **0**；
   - **反向（(a)~(d) 四个子用例共同）**：日志中**不存在任何 `result=failed` 行**，也**不存在任何 `phase=panic-recovered` 行**；且四子用例的 `Register` 均传**真 bus**，故 `phase=register` 行数恒为 **0**（计数按 `phase` 分别计，见要点 9 末段）。
   - **(e) `bus == nil` 子用例（要点 3 的第三个 `phase` 值，attempt 2 BL-1 新增）**：三依赖**全部健康**（`Pool` 取“非 nil 但连不通的真池”，同下方取证形态），调 `Register(nil)` 后断言：进程存活（不 panic）、恰**一条** `phase=register` 的 Error 且 `missing == "bus"`、`phase=construct` 行数为 **0**（依赖健康）；随后向一个**另建的真 bus** 发布一条真事件，断言日志中**不出现任何 `result=*` 行**——这直接兑现要点 3 的“记 Error 后直接返回、**不订阅**”，而非“订阅了一半”。本子用例不需要额外的零 DB 断言（未订阅 ⇒ 回调从不执行）。
   **零 DB 的取证形态（架构评审 cycle 2 建议 2；plan.md §5.5）**：`Pool` 字段是具体类型 `*pgxpool.Pool`，**不存在接口替身、也不存在“pool 替身调用计数”这种东西**，禁止写成“pool 替身零调用”。按子用例分两种可执行取证：
   - (a)(b)(c)（`Pool` 必须健康）：传一个**非 nil 但连不通**的真池——`pool, _ := pgxpool.New(ctx, "postgres://x:x@127.0.0.1:1/x")`（`defaultMinConns`/`defaultMinIdleConns` 均为 0，构造期零连接尝试且不报错，已核实，见 plan.md §5.3），`defer pool.Close()`。零 DB 的**正向**断言是：日志中**不存在任何 `result=failed` 行**——若前置判定失灵、真走到查询，连接被拒会确定性地留下一条 `step=project-chain` 的 `failed`；
   - (d)：`Pool: nil`，查询在结构上不可能发生。零 DB 的可执行证据是上面那条**反向**断言（无 `result=failed` + 无 `phase=panic-recovered`）：若前置判定失灵真走到查询，nil 受体 panic 会被要点 5 的 recover 捕获并确定性留下一条 `phase=panic-recovered`，故该断言可判定，且与构造期的 `phase=construct` Error 互不干扰。
   有真库环境时可**附加**（非必须）：用真测试池并断言 `pool.Stat().AcquireCount()` 前后不变。
   **本 TASK 不含 typed-nil 用例**：typed-nil `*InstallationService` 在提醒器内本就检不出（`r.credentials == nil` 为假，SDD §3.2.3），强行断言只会得到 panic/recover 日志或靠另一个 nil 依赖短路的假证。typed-nil 防护的唯一验证点是 **TASK-07 验收条件 3**（wiring 层条件赋值）。
2. **回调零 I/O（AC-11）**：客户端替身的 `IsConfigured()` 阻塞 500ms，断言 `bus.Publish` 的返回耗时 < 50ms（回调只做断言 + channel send）；同时断言回调期无任何 DB 访问（取证形态同验收 1）。
3. **过载丢弃（AC-13）**：`MaxInFlight = 1`，第一条事件在 `IsConfigured()` 上阻塞占满额度，紧接第二条事件断言恰一条 `result=skipped reason=overloaded`，且未派生第二个 goroutine（客户端替身调用计数仍为 1）、无排队无重试。
4. **panic 自恢复（AC-13）**：客户端替身的 `IsConfigured()` 直接 `panic("boom")`，断言进程存活、恰一条 `phase=panic-recovered` 的 Error 级日志（口径见要点 9 末段，按 `phase` 分别计数；本用例三依赖均健康故 `phase=construct` 行数为 0，`Register` 传真 bus 故 `phase=register` 行数为 0）、信号量已释放（后续事件仍能被处理）。
5. **前置判定顺序**：`appURL == ""` 且飞书可用时恰一条 `reason=app-url-missing`；飞书不可用且 `appURL` 也为空时只记 `feishu-disabled`（证明顺序为先可用性后基地址），两种情形下均无 DB 访问（取证形态同验收 1）。
6. **载荷校验**：`parsePayload` 对 `map[string]any`、异类型、字段空串（`CRID`/`Status`/`EventID` 任一为空）一律返回 `ok == false` 且零 DB/HTTP；非四门禁 `Status` 被二次过滤丢弃。
7. **零值退化与显式值**：`MaxInFlight/EventTimeout/RecipientTimeout` 为 0 时取 8/60s/10s；显式传 `MaxInFlight = 3`、`EventTimeout = 5s`、`RecipientTimeout = 1s` 时以显式值生效（断言可观测：并发上限 3 时第 4 条才 `overloaded`）。
8. `cd server && go build ./... && go vet ./internal/integrations/lark/` 零报告；`go test ./internal/integrations/lark/ -run 'ApprovalReminder' -v -count=1` 全部 `--- PASS`（本 TASK 用例**不依赖真库**：`Pool` 取 nil 或“非 nil 但连不通的真池”，见验收 1）。
   另加一条**静态断言**（读 `approval_reminder.go` 源文本，兼现要点 11 的“包级只读”承诺；架构评审 cycle 2 建议 3）：`approvalGateStageLabels` 不导出（首字母小写），且除声明处外全文不存在对它的写入（无 `approvalGateStageLabels[…] =`、无 `delete(approvalGateStageLabels…`、无重赋值）。

## 完成标志

上述 8 条全通过；日志断言通过"`slog.NewJSONHandler` 写入 mutex 保护的 buffer 后逐行 `json.Unmarshal`"实现（先例：`internal/realtime/hub_test.go:326` 的 `lockedWriter`），不靠字符串 `strings.Contains` 糊过去；`crctl task done CR-2026-051 --task CR-2026-051-TASK-05 --workspace <kb worktree>` 已登记。

## 接口契约

- **消费**：TASK-01 的 `protocol.EventCRApprovalGateEntered`、`protocol.ApprovalGateEnteredPayload{CRID, Status, EventID, ShellIssueID *string}`；TASK-04 的 `APIClient.SendApprovalReminderCard(ctx, ApprovalReminderParams) error`（本 TASK 只依赖其存在以满足接口实现，实际调用在 TASK-06）。既有：`events.Event{Type, WorkspaceID, ActorType, Payload}`、`(*events.Bus).Subscribe(string, func(events.Event))`（`internal/events/bus.go:52`）、`CredentialsResolver.DecryptAppSecret(Installation) (string, error)`（`outbound.go:159`）、`(*InstallationService).GetInWorkspace(ctx, id, workspaceID pgtype.UUID) (Installation, error)`（`installation.go:110`）、`(*InstallationService).DecryptAppSecret`（`installation.go:96`）、`ErrAPIClientNotConfigured`、`NewStubAPIClient`。
- **产出**（TASK-06 与 TASK-07 直接引用，签名固定）：
  - `type lark.ApprovalReminderConfig struct { Pool *pgxpool.Pool; Client APIClient; Credentials installationCredentialSource; AppURL string; Logger *slog.Logger; MaxInFlight int; EventTimeout time.Duration; RecipientTimeout time.Duration }`；
  - `func lark.NewApprovalReminder(cfg ApprovalReminderConfig) *ApprovalReminder`（永不返回 nil）；
  - `func (r *ApprovalReminder) Register(bus *events.Bus)`（TASK-07 的唯一调用面）；
  - 包内私有：`type installationCredentialSource interface{...}`（见实现要点 1）、`(r *ApprovalReminder) handleEvent(e events.Event)`、`(r *ApprovalReminder) deliver(p protocol.ApprovalGateEnteredPayload, anchorWorkspaceID string)`、`(r *ApprovalReminder) deliverToRecipients(ctx context.Context, p protocol.ApprovalGateEnteredPayload, anchorWorkspaceID string)`（TASK-06 替换其实现体）、`parsePayload(v any) (protocol.ApprovalGateEnteredPayload, bool)`、`stageLabel(status string) string`、`approvalGateStageLabels map[string]string`、`errorClassOf(err error) string`、日志四入口（签名见实现要点 9）、三组常量（9 reason + 4 error_class + 6 step）。
