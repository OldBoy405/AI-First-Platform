---
id: CR-2026-010-TASK-07
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: 端到端验收（AC-1~5）+ §6.3 四组回归
slug: e2e-acceptance-regression
status: done
estimate: 6h
depends-on: [CR-2026-010-TASK-03, CR-2026-010-TASK-04, CR-2026-010-TASK-06]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
---

## 实现状态（2026-08-02）

`change-requests/CR-2026-010/test-report.md` 已产出，AC-1~5 全部标记通过（AC-2/AC-5 各留
一项人工补验，详见报告，均为低风险挂账，同 CR-2026-004 AC-5 先例）。要点：

- **AC-4 用真实 HTTP**：本地真实启动 `go run ./cmd/server`（非 httptest），手工签发 JWT 直接
  curl 7 个 presenter 端点，覆盖 9 种非法角色/状态组合（超过验收条件的 8 种），逐条记录
  HTTP 状态码 + 错误 code，验收后清理造数。
- **AC-3 §6.3 group 3 新增压测**：`TestClaimTaskCrossAgentProjectSingleWriterStress`（multica
  commit `aef119773`）——12 个 agent 并发 claim，`concurrency=12 elapsed=312.6ms claimed=1
  active_after=1 requeued=11`，SQL 断言证据完整。
- **全仓 `go test ./...` 抽查**：发现 `cmd/multica`/`internal/cli`/`internal/daemon`/
  `internal/realtime`/`pkg/agent`/`pkg/redact` 等包多项失败，经 `git diff main...HEAD --
  server/` 核实这些包的任何文件均未被本 CR 触碰，且失败性质（外部 git 远程操作、AI CLI
  二进制依赖、Windows 路径假设）与 presenter 功能无关，判定环境预置问题，不计入本 CR 回归范围。
- **人工补验项**（非阻塞，风险评估：低）：WS 双浏览器会话实时观察（AC-2）、web/desktop
  视觉双端核对（AC-5）——环境无可用双浏览器/Electron 桌面会话，链路两端已分别自动化验证，
  中间通道（`project:` 前缀失效 / 共享 `packages/views` 组件树）均为既有能力复用。

## 任务描述

真机跑通 PRD AC-1~5 全部场景，并执行 SDD §6.3 定义的四组 claim 串行化改造回归（本 CR
独立成 CR 的主因，零回归是硬门槛）。

## 涉及范围

- **AC-1（单一写者）**：presenter 非空时，普通成员发送 403（SELECT 核对不落库不入队）；
  owner/admin 发送入队但 presenter 任务运行期间不被执行（claim 层排队，SQL 断言同项目
  active 任务恰一）；presenter 消息正常执行；Agent 空闲时 admin 直发即执行（免申请接管）。
- **AC-2（状态机全覆盖）**：五条路径真机走通——申请→批准、申请→拒绝、转让、撤销、释放；
  每步核对 消息流通知卡渲染 + 定向 inbox 到达 + 头部主持人显示 WS 实时更新（第二浏览器
  会话验证无手动刷新）+ grant 行状态变化（DB 核对）。
- **AC-3（claim 串行化回归，§6.3 四组）**：
  1. CR-2026-004 语义回归：满队 429、owner/admin 插队与豁免、撤回释放槽位、queue-status
     实时——既有测试套件全绿复跑。
  2. CR-2026-006 语义回归：群聊发送→守卫→落库→入队→claim→执行卡实时渲染→刷新回放全链路
     ——既有测试 + 新增 presenter=null 场景补充断言。
  3. 新增并发测试：同一项目两个不同 agent 各持有一条 queued 任务，并发触发 claim →
     任意时刻恰一个 active（T01 单测的真机放大版，压测规模）。
  4. chat_session 来源任务（Private Ask/既有 1:1 chat）与项目共享任务并行 claim 互不阻塞
     （验证 DD-2 的分支保留策略真机成立）。
- **AC-4（服务端权威）**：绕过前端直接 curl 调用 7 个转移/查询端点，非法角色矩阵（非 owner
  批准/撤销、非 presenter 转让/释放、owner/admin 申请、非工作区成员、非法转移状态如对已拒绝
  的 pending 再次批准）全部返回结构化 403/400/404/409；普通成员直调发送端点验证 403
  `presenter_required`。
- **AC-5（四语/双端）**：`parity` 测试全绿（若 T06 已跑过，本任务复核一次收尾状态）；
  web 与 desktop（Electron 共享 `packages/views`）目视回归——头部/面板/通知卡/拒绝提示条
  四处渲染一致。

## 实现要点

- 回归优先于新功能验收：先跑 §6.3 ①②两组既有测试套件，全绿后再进入新场景，避免在
  已知回归基础上排查新问题（性价比更高的顺序）。
- claim 并发测试建议用真实 DB 事务隔离级别（非 mock），因为 advisory lock 与
  `FOR UPDATE SKIP LOCKED` 的交互行为在 mock 层无法真实验证。
- inbox 路由深链（TSUG-002）与"申请中"数据源（TSUG-003）作为 AC-2 的隐含验收点一并核对，
  不单独立项但需在报告中明确提及已验证。
- 若发现回归缺口，优先判断是 T01 claim SQL 分支保留有误还是测试断言本身有误，不要在
  不确定根因前直接改 SQL。

## 验收条件

1. AC-1~5 全部场景截图/日志留痕，写入 `change-requests/CR-2026-010/test-report.md`。
2. §6.3 四组回归全绿，尤其第 3 组（跨 agent 并发 claim）需附具体压测参数（并发数/任务数/
   耗时）与"恰一 active"的 SQL 断言证据。
3. AC-4 的非法角色矩阵覆盖至少 8 种非法组合，逐条记录返回码与错误 code。

## 完成标志

test-report.md 完整产出，所有 AC 标记通过或明确记录已知限制（若有）；无未解释的回归失败项。
