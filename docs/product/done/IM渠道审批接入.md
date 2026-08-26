# IM 渠道审批接入

> 状态：设计收敛
> 版本：v0.2
> 更新日期：2026-08-25
> 当前范围：飞书审批提醒卡片 + 既有 Web 审批入口

## 1. 背景与目标

当前 CR 人工审批已经有两条正式路径：

- 人类在交互式终端执行 `crctl approve`；
- 有权限的用户在 Web 项目会话中完成签名审批。

本次不新增第三套审批执行链路。首期只补齐“审批人及时得知有待审批事项”的体验：CR 进入人工审批门禁后，系统向项目所在 workspace 中已绑定飞书的 owner/admin 发送私聊提醒卡片；审批人点击“前往审批”，回到既有 Web 项目会话完成审批。

设计优先级是复用现有能力，不引入新的事务框架、审批协议或多渠道抽象。

## 2. 范围

### 2.1 本期包含

- 渠道仅支持飞书。
- 覆盖四个人工审批阶段：
  - `requirement-reviewing`：需求审批；
  - `tech-design-review-pending`：架构审批；
  - `task-breakdown`：开发启动审批；
  - `code-reviewing`：代码审批。
- 向项目所在 workspace 的所有 owner/admin 发送提醒，但只发送给已有有效飞书绑定的用户。
- 使用绑定记录中的 `open_id` 发送飞书私聊卡片。
- 卡片提供既有 Web 项目会话入口，不在飞书内执行批准或驳回。
- 通知采用单次、best-effort 投递；失败只记录日志，不阻塞 CR 状态推进。

### 2.2 本期不包含

- 飞书卡片内“批准 / 驳回”按钮及回调处理。
- 新的 action token、回调签名协议、审批证据打包器。
- 消息状态更新、卡片撤回或审批完成后的卡片 patch。
- 通知 outbox、持久化投递记录、重试队列或 exactly-once 保证。
- 新数据库表或 schema migration。
- Slack、钉钉、企业微信等其他渠道。
- `IMApprovalNotifier` 一类预设的多渠道接口。
- 用户级通知偏好或新的功能开关。
- 对 Web 审批页、审批 handler、grant daemon、crctl、tools Pipeline/Skill/README 的改造。

## 3. 已经解决的基础设施

以下能力是既有事实源，本次直接复用，不复制实现。

| 能力 | 现有实现 | 本次处理 |
|---|---|---|
| CR 状态、门禁、CAS、受控账本写入、审计、原子提交 | `../tools/skills/shared/crctl` 及其状态机 / gates | 零改动；不在 multica 或通知模块重写 |
| 人工审批权限 | Web 审批链路已有 owner/admin 校验 | 复用同一角色口径筛选收件人 |
| 审批签名、证据校验、漂移防护、幂等和 grant 入队 | `server/internal/governance/approval.go` 及现有 grant 流程 | 零改动；飞书卡片不直接调用审批 |
| CR 状态投影与事件消费 | `server/internal/governance/crsync.go` | 仅在可信的实际门禁进入点发布语义事件 |
| 项目、workspace、issue/CR 关联 | 现有项目会话和 `shell_issue -> project` 关系 | 用于定位收件 workspace 与 Web 落点 |
| 渠道用户绑定 | `channel_user_binding`；飞书绑定值为 `open_id` | 直接查询有效绑定，不新增绑定模型 |
| 飞书私聊和交互卡片发送 | `server/internal/integrations/lark` 已能按 `open_id` 私聊，并已有卡片模板 | 增加同类的专用提醒卡片入口 |
| Web 基地址与项目会话路由 | `appURLFromEnv()` 与 `/{workspaceSlug}/projects/{projectID}?tab=chat` | 复用生成 CTA 链接 |

这些能力分别留在其现有职责层：Agent 不接管状态机，Pipeline 不复制 Skill 算法，Skill 不手写账本操作，crctl 不承担通知业务判断，版本化脚本和 README 均不成为新的运行时事实源。

## 4. 本次最小改造

### 4.1 增加门禁进入语义事件

新增内部事件 `cr:approval-gate-entered`。只有同时满足以下条件时才发布：

1. 输入来自既有可信 CR 状态事件；
2. 状态转换合法且状态投影成功；
3. 旧状态与新状态不同；
4. 新状态是四个人工审批门禁之一。

事件只携带通知定位所需的最小标识，例如 CR/issue 标识、新状态和事件标识。项目、workspace、标题和审批人等可变信息在通知侧读取现有数据，不把完整审批证据复制进事件。

不得订阅通用 `EventCRUpdated` 作为通知触发源。checkpoint、reconcile 等路径也会发布该通用事件，使用它会把投影维护误当成新的审批请求。

### 4.2 增加飞书审批提醒器

在现有 Lark integration 内增加单一用途的审批提醒器，职责仅为：

1. 由 CR/issue 解析关联项目和 workspace；
2. 读取 workspace 的 owner/admin；
3. 查找这些用户当前有效的飞书 `open_id` 绑定；
4. 对 `open_id` 去重；
5. 生成最小提醒卡片并逐个发送一次；
6. 对跳过和失败结果记录结构化日志。

它不负责状态推进、审批执行、账本写入或重试调度。

### 4.3 复用飞书发送能力

现有飞书绑定提示已经能向 `open_id` 发送卡片。本次沿用相同边界，增加专用的 `SendApprovalReminderCard` 与最小参数类型；卡片模板继续封装在 client 内。HTTP client 可把现有按 `open_id` 发送交互卡片的逻辑提取为私有 helper，供绑定提示和审批提醒共同复用。

不公开任意卡片 JSON 接口，不抽象跨渠道 notifier，不新增卡片 DSL，不复制完整的飞书 client。

## 5. 运行流程

```text
crctl / Skill 推进状态
→ multica 消费可信状态事件并完成投影
→ 实际进入人工审批门禁时发布 cr:approval-gate-entered
→ 飞书提醒器查询项目、workspace、审批角色与绑定
→ 对每个绑定 open_id 单次发送提醒卡片
→ 审批人点击“前往审批”进入既有 Web 项目会话
→ Web 沿用现有签名审批、证据校验、grant 入队和 crctl 推进链路
```

通知是状态投影后的旁路体验，不参与状态事务。飞书 API 超时、限流或失败不得让状态消费回滚，也不得阻断其他审批渠道。

## 6. 卡片与链接

### 6.1 卡片最小内容

- 标题：`待人工审批`；
- CR ID 与 CR 标题；
- 当前审批阶段；
- 固定说明：`自动评审已通过，等待人工审批`；
- 唯一操作：`前往审批`。

完整 PRD/SDD、评审证据、diff、风险和批准/驳回操作继续由 Web 展示。飞书卡片不复制证据包。

### 6.2 Web 落点

CTA 使用现有项目会话地址：

`/{workspaceSlug}/projects/{projectID}?tab=chat`

只有能通过 `shell_issue -> project` 解析到项目的 CR 才发送。历史 CR 或异常数据无法解析项目时，跳过并记录原因，不新增兜底页面或第二套路由。

Web 基地址复用现有 `appURLFromEnv()` 解析；部署环境应提供 `MULTICA_APP_URL`。无法得到可用基地址时跳过并记录原因，不发送无效链接。

## 7. 投递语义与失败处理

- 每个门禁实际进入事件只触发一次内存态投递处理。
- 同一状态事件被正常重放时，若投影已处于目标状态，不再次发布门禁进入事件。
- checkpoint、reconcile 和普通 CR 更新不触发提醒。
- 每个收件人只尝试一次；发送失败记录 CR、stage、workspace、recipient 和错误类别。
- 进程在状态投影后、消息发出前崩溃时，允许丢失该次提醒。
- 不为消除上述 crash window 增加 outbox、通知表、幂等键或补偿扫描。
- 无项目、无 Web 基地址、无 owner/admin、无有效飞书绑定均按可观测跳过处理，不影响 CR。

## 8. 配置与启用条件

不新增审批通知配置。满足以下既有条件时自动工作：

- 飞书 integration 已启用并可发送消息；
- 目标用户具有 workspace owner/admin 角色；
- 目标用户已有有效飞书绑定；
- CR 可解析到项目；
- Web 基地址可用。

任一条件不满足时跳过并记录原因。

## 9. 代码影响面

预计只修改 multica，且保持最小边界：

| 位置 | 最小改造 |
|---|---|
| `server/internal/governance/crsync.go` | 声明内部 `cr:approval-gate-entered`，并在可信的实际门禁进入点发布 |
| `server/internal/integrations/lark/approval_notifier.go` | 查询收件人、组卡并 best-effort 发送 |
| `server/internal/integrations/lark/client.go`、`http_client.go` | 增加专用提醒卡片方法，私有复用按 `open_id` 发送逻辑 |
| `server/cmd/server/router.go` | 注入既有依赖并订阅事件 |
| 对应测试文件 | 覆盖触发、过滤、收件人、链接和失败隔离 |

明确零改动：

- `../tools/` 全部模块，包括 Agent、Pipeline、Skill、crctl、版本化脚本和 README；
- 数据库 schema 和账本；
- `server/internal/governance/approval.go`；
- Web 审批页面与 API；
- grant daemon 和 task-token 流程。

## 10. 验收标准

- [ ] CR 实际进入四个审批门禁中的任一个时，发布一次专用语义事件。
- [ ] 通用 CR 更新、checkpoint、reconcile 和同状态重放不会发送提醒。
- [ ] 项目所在 workspace 的每个已绑定 owner/admin 各收到一张飞书私聊卡片。
- [ ] 非 owner/admin、无有效绑定用户不收到卡片。
- [ ] 卡片只包含最小摘要，并以“前往审批”链接到正确的既有 Web 项目会话。
- [ ] Web 中的批准/驳回仍完整走现有签名、证据、漂移检查、grant 和 crctl 链路。
- [ ] 飞书发送失败或缺少项目、基地址、收件人时有结构化日志，且不影响 CR 状态推进。
- [ ] 未新增数据库表、投递重试、消息 patch、多渠道抽象或 tools 改动。

## 11. 后续演进条件

只有在通知型 MVP 的使用数据证明“跳转 Web”确实构成主要审批阻力，并且业务愿意承担回调鉴权、身份绑定、token 防重放、漂移证据和结果回写的额外复杂度时，才单独设计飞书卡片内审批。该能力不属于本版本的兼容性承诺。
