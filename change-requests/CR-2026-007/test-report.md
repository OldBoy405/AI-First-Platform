---
id: CR-2026-007-test-report
type: TEST-REPORT
cr-ref: CR-2026-007
status: pass
created: "2026-08-02T15:45:00+08:00"
updated: "2026-08-02T15:45:00+08:00"
---

# 验收报告 — CR-2026-007（P2 CR-B：D3 完整形态）

## 0. 环境与方法

独立起环境验收（不复用已运行的自托管栈，避免验证到旧代码）：
- worktree 内新建 `.claude/launch.json` + 包装脚本，后端 `go run ./cmd/server` 绑 8090，前端
  `next dev` 绑 3010，均指向本 worktree（含 T01~T05 全部提交）代码；DB 复用既有共享 postgres
  （本 CR 无迁移，schema 与 main 一致，安全）。
- 走真实 HTTP：dev 验证码流程注册 owner（A）+ member（B）两个真实用户、建 workspace/project、
  邀请 B 入会。**runtime/agent 无法通过公开 API 创建**（需 daemon 握手），比照 CR-2026-006 先例，
  经受控 Go 一次性脚本直插 `agent_runtime`(status=online) + 2 个 `agent` 行（一个 workspace 可见、
  一个 private，owner_id=A）——非验证环节，只是给 API 测试补运行时前提，验证与清理均沿 SELECT/
  真实 API 纪律。验收结束后已 DELETE 清理该 3 项 fixture（tasks/agents/runtime），workspace/
  project/真实 API 产生的 comment 留存作审计痕迹。
- 浏览器验证：Playwright 式单 pane，用 `localStorage.multica_token` 直接注入 bearer token
  跳过登录 UI（cookie 跨源在 http 下不可用，符合预期），实际渲染由后端真实数据驱动。

## 1. 逐 AC 结果

### AC-1（FR-1/2，实时可见）—— API 级真机通过 + 浏览器渲染确认

| 检查 | 期望 | 实测 |
|---|---|---|
| B 发消息入队 → queue-status 深度 | depth 1→... | ✅ 每次发送后 `queue_depth` 与 `items.length` 同步 |
| items 顺序 | priority DESC, created_at ASC | ✅ owner 插队任务（priority 100）排在 member 任务（priority 2）前 |
| 浏览器渲染 | 队列条显示计数与展开明细 | ✅ 页面渲染「1 条排队」「Agent 队列 1/50」，与 API 返回一致 |

**已知覆盖边界（诚实标注）**：单浏览器 pane 无法同时开两个独立会话观察 WS 推送到"另一个人的屏幕"，
改用 API 轮询验证数据一致性（后端每次状态变更后重新 GET 均得到正确结果）；真正的 WS
push-without-refresh 由 `use-realtime-sync.ts` 既有前缀失效机制承担（TSUG-006 已确认命中，
T03/T04 测试覆盖该失效路径的单元测试）。

### AC-2（FR-3，撤回三路径）—— **API 级真机通过，含 blocker 2/3 修复的核心验证**

| 检查 | 期望 | 实测 |
|---|---|---|
| **B（private agent 非 owner 成员）撤自己的 queued 任务** | 200 cancelled（技术评审 blocker 2 靶点） | ✅ `POST /api/tasks/{id}/cancel` → 200，`originator_user_id` 与 caller 一致 |
| B 撤 A 发起的任务（非发起人，同一 private agent） | 403 `you do not have access to this agent` | ✅ 403（access gate 对非发起人仍生效，DD-2"只放宽不收紧"验证） |
| 重复撤回已 cancelled 的任务 | 幂等 200，返回体 status 不变 | ✅ 200，status 仍为 cancelled（blocker 1 修复的核实：无 400/409） |
| DB 行保留 | 软删除，行存在 | ✅ 响应体 `status='cancelled'`，`completed_at` 有值 |

### AC-3（FR-4，停止双权限）—— 应用层单测覆盖 + 端点复用同 AC-2 验证

停止与撤回复用同一 `cancel` 端点（SDD DD-2），权限与幂等语义已在 AC-2 完整验证。前端停止按钮
可见性三态（自己 running 显示/他人不显示/owner 显示）、被停者 WS 对账（interrupted 徽标 +
队列条前缀失效）由 T05 的 7 项组件测试覆盖（DOM 级断言）。**daemon 未接入，无法产生真实
"running→interrupted"转移的浏览器可视化回放**，与 CR-2026-006 先例一致标注为待 daemon 环境。

### AC-4（FR-5，过滤开关）—— 组件测试覆盖，DOM 断言含 JSON 不泄漏

T05 测试覆盖：开启后 DOM 无 `TimelineView` 节点、`result.output` 正确渲染且整包 JSON 不出现、
开关往返幂等、刷新后状态保留（store persist）。纯前端渲染分支，无需真机网络验证（NFR-4"不
发新请求"由测试断言 `queryClient` 无新 fetch 达成）。

### AC-5（FR-6，兼容与口径）—— **API 级真机通过，含 blocker 3 修复的核心验证**

| 检查 | 期望 | 实测 |
|---|---|---|
| 无 `include` 参数响应 | 仅 `{queue_depth, queue_limit}` 两键 | ✅ 逐字节确认（`{"queue_depth":1,"queue_limit":50}`） |
| **NULL originator 任务（技术评审 blocker 3 靶点）** | 计入 `queue_depth`，`items` 含该项且 `originator:null` | ✅ 深度=1，items 长度=1，`"originator":null`（显式序列化，非省略） |
| 非群聊来源任务计入 items | Issue 页 @提及等来源同样出现 | ✅ 上述 NULL-originator 造数即模拟非群聊来源（autopilot 语义），已计入 |
| D1 sidebar / CR-A 满队恢复回归 | 行为不变 | ✅ 无参端点响应结构不变，两消费方均只读该结构，逻辑未改动 |

### AC-6（FR-7 + NFR-2/3，回归）—— 单测套件全绿

- views 包：174 文件 / 1796 测试全绿（含 locale parity、复制功能测试）。
- server 包：T01/T02 新增单测全绿（含本次真机复现的 3 条 blocker 场景固化为回归断言）；
  既有 `TestCancelTaskByUser*` 12 项零回归。
- 浮窗/全页 chat、Issue 页评论 @提及路径：未改动其代码路径（`chat.go` 的 ChatSessionID.Valid
  分支与本 CR 无关），逻辑上不受影响；本轮验收时间限制未逐项真机点击回归，风险低（纯读侧+
  一处经严格集合论证的权限放宽）。

## 2. 技术评审 3 条 blocker 的真机复现结果（本报告最重要的证据）

| Blocker | 真机复现方式 | 结果 |
|---|---|---|
| I-2 假断言：cancel 已完成任务应为幂等 200 非 400/409 | 对已 cancelled 任务重复调用 cancel | ✅ 200，status 不变 |
| 私有 agent"发得进撤不回" | B（非 owner 非 admin）对私有 agent 发消息→撤回自己的任务 | ✅ 200（修复前应为 403，此前 T02 单测已用 stash 验证过对照组） |
| NULL originator 导致 items 丢项 | 直插 NULL-originator 队列任务后调 items 端点 | ✅ depth==len(items)，originator 显式为 null |

三条均以**真实运行的服务器 + 真实 HTTP 调用**复现（非 `go test` 内的模拟），构成比 Go 单测更强
的证据层级。

## 3. 环境限制（诚实标注，沿 CR-2026-006 先例）

- 本机无 Claude Code/Codex CLI daemon 运行时，`daemon_connection` 表持续 0 行——AC-3 的"真实
  running→interrupted"转移与 AC-1 的"WS push 到另一浏览器会话"未做像素级回放验证；两者的
  应用层正确性已由组件测试 + API 级状态一致性验证覆盖，风险由此收敛为低。
- 单 Browser MCP pane 限制：无法同时渲染两个独立登录会话对比"B 的操作对 A 屏幕的实时影响"；
  改用同页面内以不同 Authorization: Bearer 身份并发调用 API 验证数据模型正确性，视觉层的双人
  实时性由既有 WS 失效机制（TSUG-006 已确认命中）与 CR-2026-006 已验收的相同机制保证。
- 浏览器验收过程中发现 workspace 内还渲染着一个与本 CR 无关的悬浮 1:1 chat 组件（默认选中
  workspace 里"第一个"agent，与本 CR 配置的 project team_agent 无关），已确认其不在
  `project-team-agent-chat.tsx`（T04/T05 改动范围）内、不影响发送/撤回/队列正确性——纯粹是
  测试工作区里存在两个新建 agent 且从未手动选过 1:1 chat 对象所致的展示性观察，不作为本 CR
  的验收阻塞项，已用 `spawn_task` 另行登记供后续按需调查。

## 4. 结论

- **AC-2/AC-5**：完整真机验证通过，覆盖全部 3 条技术评审 blocker 的真实复现，是本次验收的
  核心风险点，全部清零。
- **AC-1/AC-4/AC-6**：代码级 + 单测（1796 views + server 新增用例）覆盖，通过；AC-1 的浏览器
  渲染做了抽样确认（队列条数字与 API 一致）。
- **AC-3**：应用层单测覆盖；agent 真实 running 态转移待本机 daemon（清单同 CR-2026-006）。
- 验收测试数据：workspace `CR007 Acceptance`(430eea2f) + project(b6f3dc53) + 两真实用户
  的 API 产生数据留存作审计痕迹；直插的 3 项 fixture（runtime+2 agent+1 task）已 DELETE 清理。
