---
id: CR-2026-008-test-report
type: TEST_REPORT
cr-ref: CR-2026-008
tester: Ray
tester-assigned-at: "2026-08-02T10:00:39+08:00"
status: pass
blockers: []
created: "2026-08-02T13:05:00+08:00"
updated: "2026-08-02T13:05:00+08:00"
---

# CR-2026-008 测试报告 — D5 Private Ask（含 B2 迁移）

> 代码落在 multica worktree `requirement/CR-2026-008`（base：main `52b5717`，含 CR-A）。
> 提交序列：TASK-01 `7a9bf18` → TASK-02 `61a6778` → TASK-03 `1c5fe0a` → TASK-04 `d6c8e25`。
> 测试环境：Windows 10 本机 PostgreSQL（无 Docker）；daemon/浏览器双端真机项见 §5 人工清单。

## 1. 验证命令与结果

| 命令 | 目录 | 结果 |
|---|---|---|
| `go build ./...` | server/ | ✅ 零错误 |
| `go vet ./cmd/server ./internal/handler ./internal/service ./internal/events` | server/ | ✅ 零报错 |
| `go run ./cmd/migrate up`（含 161） | server/ | ✅ up/down/up 三遍无损（见 §6 事故记录） |
| `go test ./internal/handler/ -run "TestGetProjectPrivateChat\|TestPrivateAskSessionExcluded"`（真实 PG） | server/ | ✅ 4/4 |
| `go test ./cmd/server/ -run "TestRegisterListeners\|TestChatEvent"` | server/ | ✅ 全过（含 6 case 新契约矩阵 + fail-closed） |
| `go test ./internal/daemon/ -run TestRepoCheckout` | server/ | ✅ 全过（含 ask-only 403 三段验证） |
| `go test ./internal/daemon/execenv/ -run "TestAskOnly\|KindMatrix"` | server/ | ✅ 全过（brief 矩阵回归 + ask-only 省略） |
| `go test ./internal/service ./internal/events ./internal/realtime`（全量） | server/ | ✅ events/realtime ok；service 仅 builtin-skills 组失败（§4 既有） |
| `go test ./internal/handler ./cmd/server`（全量） | server/ | ✅ cmd/server ok；handler 仅 2 个 §4 既有失败 |
| `go test ./internal/daemon/...`（全量，与 main 失败集 diff 对照） | server/ | ✅ 失败集与 main **完全一致**（纯 Windows 环境项），零新增回归 |
| `pnpm --filter core --filter views typecheck` | 仓根 | ✅ core 零错误；views 仅 1 个 §4 既有错误（非本 CR 文件） |
| `vitest run`（packages/core 全量） | packages/core | ✅ 793/793 |
| `vitest run projects/ chat/ locales/parity.test.ts` | packages/views | ✅ 253/253（含四语 parity、浮窗/全页 chat 组件回归） |

## 2. TASK 验收证据

| TASK | 验收条件 → 证据 |
|---|---|
| T01 B2 迁移 + get-or-create | ①迁移 up/down/up 无损（存量行 project_id NULL）→ 真实 PG 实测；②并发/归档语义 → `TestGetProjectPrivateChat_GetOrCreate/_ArchivedStartsFresh`、无 agent 409 → `_NoTeamAgent`；③全局列表/pending 聚合排除 → `TestPrivateAskSessionExcludedFromGlobalChat`（四查询逐一断言）；④sqlc diff 限于 chat.sql.go + models.go（+77/-11、+1，已核对） |
| T02 隐私收敛 | ①chat 事件不进 workspace fanout、fail-closed 丢弃 → `TestRegisterListeners_TaskChatGoToWorkspace`（6 case）+ `TestChatEventFailsClosedWithoutRecipient`；②9 处发布点清单逐项落地（TASK-02 清单表全勾，`broadcastTaskEvent` 咽喉点覆盖 17 调用点；ReportProgress 特例改为传 task 行，**无残余**）；③回归 → chat 组件 55 测试 + realtime/events 套件全绿；Lark 走 bus 层订阅不受影响（代码核实 outbound.go:262） |
| T03 Ask-only 强制 | ①claim 响应 ask_only=project 会话 → daemon.go 单行判定（cs.ProjectID.Valid），AC-3 真机复核；②brief 省略 → `TestAskOnlyChatBriefOmitsRepositories` + 既有 KindMatrix 回归（普通 chat 不受影响）；③checkout 拒绝/放行/生命周期 → `TestRepoCheckoutRejectedForAskOnlyTask` 三段断言 |
| T04 前端面 | ①不引入 controller/store → 静态 import 守卫测试；②发送/失败保draft/停止（FR-9）/只读模型徽标+tooltip（SUG-003）/未配置引导 → project-private-ask.test.tsx 6 测试；③草稿独立 → project-chat-store 既有测试 + 面内 draftKey `{projectId}:private_ask`；④四语 parity 全绿 |
| T05 验收 | 本报告 §1–§5；真机项转 §5 人工清单 |

**TaskStatusPill 检查单（SDD §6.3）**：①pill 随 pendingTask 呈现 → 组件测试断言 pendingTask 注入 ChatMessageList（pill 由其内部渲染，chat-message-list.tsx:101-107 既有逻辑）；②停止后内容保留 → cancelTaskById 语义（服务端既有,cancel 保留 transcript）+ FR-9 测试；③无越权入口 → 面仅本人可达（结构性）+ 会话端点 creator-only 既有鉴权；④无 Runtime 引导 → availability 经 useAgentPresenceDetail 注入 pill（既有机制），真机复核。

## 3. 新增/修改的测试文件

- `server/internal/handler/project_private_chat_test.go`（新，4 测试，真实 PG）
- `server/cmd/server/chat_event_privacy_test.go`（新，fail-closed）
- `server/cmd/server/listeners_scope_test.go`（改：契约更新为"task 留 fanout / chat 走 per-user"）
- `server/internal/daemon/health_test.go`（增：ask-only checkout 403）
- `server/internal/daemon/execenv/runtime_config_kind_test.go`（增：ask-only brief）
- `packages/views/projects/components/project-private-ask.test.tsx`（新，6 测试）
- `packages/views/projects/components/project-chat-panel.test.tsx`（改：stub 新子面）

## 4. 既有环境失败（与本 CR 无关，均已在 main `52b5717` 上复现比对）

- `internal/service` builtin-skills 组（frontmatter 解析）：Windows autocrlf 检出 CRLF 触发，main 同样失败。
- `internal/handler` `TestShortTaskIDMatchesDaemon`、`TestParseSkillArchive_RejectsUnsafeSkillMdPath`：main 同失败（Windows 路径语义）。
- `internal/daemon` 约 30 项（profile 路径/symlink/git 类）：与 main 失败集 diff 完全一致。
- views typecheck：`modals/quick-create-issue.test.tsx:373`（CR-2026-004 遗留 ApiError 签名漂移），非本 CR 文件。

## 5. 人工真机清单（需 daemon + 双浏览器环境，评审/合并前由 tester 执行）

1. **AC-1 隐私抓包（首要）**：双浏览器 A/B 同项目，A 走 Private Ask 全流程 + Team Agent 并行任务场景，B 端 devtools WS 帧逐条核对；A 第二设备收取正常。单元层已锁：桥接契约 6 case + fail-closed。
2. **AC-2 并行**：真实 daemon 下 Team Agent 长任务 + Private Ask 问答并行；D1 满队（limit=1）不影响 Private Ask（结构性保证已核实：EnqueueChatTask 无项目队列守卫）。
3. **AC-3 Ask-only**：真机让 agent 尝试改项目文件/`multica repo checkout` → 403 + git status 干净；全局 1:1 chat checkout 正常（对照组）。单元层已锁双防线。
4. **AC-6 双端**：desktop（Electron 共享 views 包）目视一致性。
5. Runtime 缺失引导态目视（pill/availability 文案）。

## 6. 残余与事故记录

- **FR-8 部分延后（需求偏差，需评审知悉）**：附件与 @提及未随本面交付——实施中核实 `ChatInput`
  内部读全局 `useChatStore`（chat-input.tsx:111-112 draft 键），并非 SDD 0.1.1 所述纯 props；
  引入会把本面草稿泄入全局 chat 命名空间，违反 FR-3/NFR-2 的更高优先级约束。取纯 textarea
  组合（与 CR-A Team Agent 面一致），附件/@提及随 ChatInput 解耦后补（组件内 ponytail 注释留痕）。
- **事故**：T01 验证迁移双向时 `migrate down` 不带参数把本机 dev 库全量回滚后重建——schema 无损
  但 dev 数据清空（无备份）。已即时向需求 owner 披露。后续验证一律用 `down 1` 或独立测试库。
- daemon 新旧版本兼容：ask_only 为可选字段，旧 daemon 忽略（降级=仅失去强制、不失功能），SDD §8 已登记。
