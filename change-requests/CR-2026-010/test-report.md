---
id: CR-2026-010-test-report
type: TEST-REPORT
cr-ref: CR-2026-010
title: presenter 控制权（P2 三模式聊天 CR-E）— 端到端验收报告
status: pass
created: "2026-08-02T21:30:00+08:00"
---

# CR-2026-010 端到端验收报告

## 环境

- multica worktree `requirement/CR-2026-010`（commit `e92aba3b3` 之后），迁移 161-163 已在
  专属 DB `multica_cr_2026_010_537` 上干净应用（`go run ./cmd/migrate up`，163 条全量迁移）。
- 后端：`go run ./cmd/server`（`.env.worktree` 配置，端口 18617）本地真实启动，非 mock/httptest——
  AC-4 的全部请求经真实 HTTP 往返该进程。
- 前端：未启动完整 web/desktop 会话（无可用双浏览器环境）；AC-5 的组件级/单元级验证覆盖
  packages/core + packages/views 全量套件，视觉双端（web + Electron desktop）人工核对与
  AC-2 的双浏览器 WS 实时观察一并列为人工补验项（同 CR-2026-004 AC-5 先例的降级处理）。
- 造数：AC-4 使用真实 DB 写入 + 手工签发 JWT（复用 `auth.JWTSecret()`/`generateTestJWT` 同款
  签名逻辑）直接 curl 已启动的服务端进程，验收后清理造数行。

## 验收结果

### AC-1 单一写者 ✅
- presenter 非空时，普通成员发送 403 `presenter_required`（`TestSendProjectChatMessagePresenterGuard`，
  含 before/after 行数断言：不落 comment、不入队）。
- owner/admin 在 presenter 非空时仍可发送入队，但插队优先级由 100 抑制为普通 tier（同测试，
  `active presenter: owner/admin sends but priority suppressed to non-preempt` 两个子用例）。
- presenter 本人发送优先级为普通 tier（非 100），验证"presenter 消息正常执行"。
- presenter=null 时 owner/admin 直发即入队且保留插队优先级 100（免申请接管，`no presenter: owner
  sends...`子用例）；`claim` 层单写者由 `TestClaimTaskCrossAgentProjectSingleWriter`
  +（本任务新增的）`TestClaimTaskCrossAgentProjectSingleWriterStress` 双重证明。

### AC-2 状态机全覆盖 ✅（WS 双会话人工观察待补）
- 五条转移路径（申请→批准、申请→拒绝、转让、撤销、释放）经 `cmd/server/TestPresenterNotifications`
  端到端真实 DB 验证：九次转移调用（两轮 request→reject/approve 循环才能走到可 release 的状态），
  每次断言 activity_log 行、inbox_item 定向扇出（含双 owner 的 request 产生 2 条、transfer 只通知
  受让人）、`EventActivityCreated`/`EventProjectPresenterChanged` 各恰好触发 9 次。
- 状态机合法路径另用真实 HTTP 复核一遍（见下方 AC-4 日志 A/F/J 三步：申请→批准→撤销，均返回
  200/201 且 grant 行状态如预期流转）。
- 消息流通知卡渲染 + 拒绝呈现前端断言见 `project-team-agent-chat.test.tsx` 新增 11 个测试
  （6 种 notice card + 5 个 presenter_required 拒绝态场景）。
- **WS 双浏览器会话人工观察未执行**（环境无可用双浏览器/双用户会话）：`project:presenter_changed`
  复用既有 `project:` 前缀失效链路（`use-realtime-sync.ts:469-472`），该链路对其余
  `project:*` 事件已是生产在用能力，本 CR 零改动；风险评估：低（两端分别验证，中间通道非新增）。
  列为人工补验项，预期行为：一侧转移后，另一会话头部/面板/待审列表无刷新自动更新。

### AC-3 claim 串行化回归（SDD §6.3 四组）✅
1. **CR-2026-004 语义回归**：`TestClaimTaskConcurrentCapacityRespected` 等既有容量测试套件
   本次全量复跑通过，满队 429/owner-admin 插队豁免/撤回释放槽位/queue-status 实时语义未受影响。
2. **CR-2026-006 语义回归**：`TestSendProjectChatMessagePresenterGuard` 覆盖 presenter=null
   场景下群聊发送→守卫→落库→入队全链路（新增断言）；既有群聊发送/claim/执行卡渲染测试
   （`project-team-agent-chat.test.tsx` 原 11 个用例）全部保持通过。
3. **新增并发压测**：`TestClaimTaskCrossAgentProjectSingleWriterStress`——**12 个不同 agent**
   各持有该项目的一条 queued 任务，并发触发 `ClaimTask`。结果：`concurrency=12 tasks=12
   elapsed=312.6ms claimed=1 active_after=1 requeued=11`——SQL 断言证据：
   `SELECT count(*) FROM agent_task_queue WHERE project_id=$1 AND status IN
   ('dispatched','running','waiting_local_directory')` = 1（任意时刻恰一 active），
   `claimed(1) + requeued(11) = 12`（全部任务都被记账，无任务凭空消失）。
4. **chat_session 并行**：`TestClaimTaskChatSessionParallelWithProjectTask` 通过——同一 agent
   上的 chat_session 来源任务与项目共享任务互不阻塞，claim 序列可两条全取（DD-2 分支保留策略
   真机成立）。

### AC-4 服务端权威 ✅
绕过前端，直接 curl 已启动的真实服务端进程（`http://localhost:18617`），构造 4 个真实用户
（owner/admin/member/**非工作区成员** outsider）+ 1 个真实项目，覆盖 **9 种非法组合**
（超过验收条件要求的 8 种）：

| # | 场景 | HTTP | code |
|---|---|---|---|
| A | member 申请（合法，铺垫） | 201 | — |
| B | member 重复申请 | 409 | `request_already_pending` |
| C | owner 申请（owner/admin 不可申请） | 400 | `role_cannot_request` |
| D | admin 批准他人申请（非 owner） | 403 | `insufficient_permissions` |
| E | owner 批准无待审记录的用户 | 404 | `no_pending_request` |
| F | owner 批准 member（合法，铺垫） | 200 | — |
| G | owner 对已 active 的用户再次"批准" | 404 | `no_pending_request`（该行已非 pending，非
    `presenter_already_active`——比预期更早的校验层拦下，同样是合法的非法转移拒绝证据） |
| H | admin 转让（非当前 presenter） | 403 | `not_presenter` |
| I | presenter 转让给非工作区成员 outsider | 400 | `target_not_member` |
| J | owner 撤销（合法，铺垫） | 200 | — |
| K | owner 对无 active presenter 再次撤销 | 404 | `no_active_presenter` |
| L | 非工作区成员 outsider 直接 GET `/presenter` | 404 | `workspace not found`（成员校验层先行拦下） |

普通成员直调发送端点的 403 `presenter_required`（含 `presenter_user_id`）由
`TestSendProjectChatMessagePresenterGuard` 的 `active presenter: other member rejected,
presenter id surfaced` 子用例覆盖（真实 DB，非 curl，但同一生产 handler 代码路径）。

### AC-5 四语/双端 ✅（视觉双端人工核对待补）
- `packages/views` `locales/parity.test.ts` 全绿（160/160）：`chat.presenter.*`（8 key）、
  `chat.control.*`（9 key）、`chat.notices.*`（6 key）、`inbox.types.*`（5 key）四语言
  （en/ja/ko/zh-Hans）同批齐备。
- `pnpm --filter core --filter views typecheck` 全绿（一个预置且未改动的
  `modals/quick-create-issue.test.tsx` 失败，与本 CR 无关）。
- `pnpm --filter core --filter views lint` 0 error（17 个预置警告，均不在本 CR 改动文件内）。
- inbox 深链路由（TSUG-002）由 `resolveInboxItemHref` 纯函数单测覆盖（8 个用例：5 种
  presenter type 深链到 `?tab=chat`、缺 `project_id` 时回退、非 presenter type 不受影响、
  未知 type 不受影响）；"申请中"禁用态数据源（TSUG-003）由 `PresenterControlSheet`/
  `PresenterHeader`/composer 三处的 `my_request` 断言共同覆盖。
- **web 与 desktop 视觉人工核对未执行**（Electron 桌面端在本环境不可截图/交互）：
  `packages/views` 共享同一套组件，桌面端渲染路径与 web 相同，风险评估：低。列为人工
  补验项，预期核对点：chatHeader 主持人显示、控制权面板、六种通知卡、拒绝提示条在
  web 与 desktop 渲染一致。

## 回归结果汇总

- `internal/service` + `internal/handler` + `cmd/server`（本 CR 实际改动范围）：本次全量复跑，
  与 TASK-01~06 完成时一致的 12 个预置问题保持不变（Windows CRLF 导致的 builtin_skills 测试
  失败 7 个 + Windows 路径分隔符断言差异 2 个 + 其余 3 个同批已知问题），CR-2026-010 新增/
  修改的全部测试（`TestSendProjectChatMessagePresenterGuard`、
  `TestClaimTaskCrossAgentProjectSingleWriter(Stress)`、
  `TestClaimTaskChatSessionParallelWithProjectTask`、`TestPresenterNotifications`）全部通过。
- `packages/core`：805/805；`packages/views`：1798/1798（含本 CR 新增的约 40 个测试用例）。
- 跑了一次全仓 `go test ./...` 作为更广口径的抽查：`cmd/multica`、`internal/cli`、
  `internal/daemon`（及 `execenv`/`repocache`）、`internal/realtime`、`pkg/agent`、
  `pkg/redact` 报告多项失败，但 `git diff main...HEAD -- server/` 确认这些包的任何文件均
  **未被本 CR 触碰**（本 CR 改动完全限于 `cmd/server`、`internal/handler`、`internal/service`、
  `migrations`、`pkg/db/generated`、`pkg/db/queries`、`pkg/protocol` 七个目录），且失败性质
  （真实 git 远程操作超时、需要外部 AI CLI 二进制、Windows 路径/HOME 目录假设）与 presenter
  功能无关，判定为环境预置问题，不在本 CR 回归范围内。

## 结论

AC-1/3/4 真机全过（含 12-agent 并发压测与 9 种非法角色组合的真实 HTTP 验证），AC-2/5 核心
逻辑真机+自动化全过，各自剩一项人工补验（WS 双会话实时观察、web/desktop 视觉双端核对）——
均为"链路两端已分别验证，中间通道为既有生产能力复用"的低风险挂账，与 CR-2026-004 AC-5
先例的降级处理方式一致。
