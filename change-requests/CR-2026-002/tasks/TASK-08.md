---
id: CR-2026-002-TASK-08
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 签名审批服务端（approval.go + grant 签发 API + 私钥方案 + daemon 下发）
status: done
estimate: 16h
depends-on: [CR-2026-002-TASK-04, CR-2026-002-TASK-03]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-4/D4 服务端：审批 API（RequireHumanActor + 证据比对 + 角色策略）→ Ed25519 签名 → approval_record + grant 签发；daemon 轮询下发落盘 `.crctl/grants/`。仓库：multica。

## 涉及文件
- 新增 `server/internal/governance/approval.go`（+ `approval_test.go`）
- 修改 `server/cmd/server/router.go`：用户会话组挂审批三端点、DaemonAuth 组挂 grants pending/ack（AIFIRST 标记）
- daemon 侧：grants 轮询与落盘（可并入 crevents.go 同周期）
- 私钥：`APPROVAL_SIGNING_KEY`（base64 env，Docker 部署）为主方案；文件 0400 为备选——启动时公私钥互验 smoke test，失败拒绝启动

## 实现要点
- canonical 串与签名格式严格按 SDD §3/§4.2；digest 算法与 T03 的 fixture 向量对齐（Go 实现必须过同一组测试向量）。
- RequireHumanActor：中间件级拒绝 `mat_` 前缀令牌（403）；approver 取会话用户，不信 payload。
- 证据比对：请求的 stage 对应最新 cr_sync_event 的 evidence digest；不一致 409。
- 角色策略：审批人 ∈ cr.owners 对应角色或具备管理员角色（简单起步，策略可配留 TODO）。
- reject：写 approval_record（decision=reject，多条留痕）+ 签发 decision=reject 的 grant。
- 公钥 `.crctl/keys/{key_id}.pub` 生成后**提交进 knowledge-base 仓**（人工步骤，写进完成记录）。

## 验收条件
1. 单测三拒绝路径：mat_ 403 / 证据漂移 409 / 验签失败 403（AC-4⑤）。
2. Go digest 实现通过 T03 共享测试向量。
3. 启动 smoke test：错配公私钥 → 进程拒绝启动（AC-4④）。
4. 端到端：Web/API 批准 → grant 落盘 → `crctl approve --grant` 放行 → 级联 advance（AC-4①，与 T03/T06 联测）。
5. 同证据先 reject 后 approve：两条记录都在，无唯一键冲突（SDD-SUG-001 验证）。

## 完成标志
go test 绿 + 端到端 grant 链路实测 + 公钥入库 + 完成记录回填。

## 完成记录（2026-07-31）

- **提交**：multica worktree 8a7e31f71（已推 fork）+ tools@d214e60（配套：advance 进入待审批状态时附证据快照——服务端签发前必须知道"这版证据"，原 T02 只在 approve 级联带证据，时点太晚；这是实施期发现的设计缺口）。
- **approval.go**：`RequireHumanActor`（X-Actor-Source=task_token → 403，该头由上游 Auth 中间件强制覆写不可伪造）→ 证据漂移比对（审批卡显示的 digest ≠ 当前 → 409）→ Ed25519 签发（canonical 串与 crctl 逐字节一致）→ `approval_record` 幂等落库（approve 部分唯一索引撞键时返回**首次签发的 grant**——approved_at 在签名里，重签会产生第二个有效签名，故必须回放原件，grant_json 列存原件即为此）→ reject 多条留痕。
- **密钥管理（§B.5 落地）**：`APPROVAL_SIGNING_KEY`（base64 PKCS#8，容器 orchestrator 注入）+ `APPROVAL_SIGNING_KEY_ID`；未配置=审批端点不挂载（自托管无此功能照常启动），配置但无效=**拒绝启动**；启动做签verify冒烟；日志只出 key_id；签名单点收口 signGrant()。`PublicKeyPEM()` 输出即应提交进 knowledge-base `.crctl/keys/{key_id}.pub` 的内容。
- **daemon 下发**：pending/ack 队列（approval_record.delivered_at）；daemon 在 crevents 同 tick 轮询、落盘 `{root}/.crctl/grants/{cr}-{stage}.grant.json`、ack；ack 失败仅重投（幂等）。
- **测试 16/16**，最关键的一个是**跨工具接缝测试**（approval_crosscheck_test.go）：Go 服务签发的 grant → 真实 crctl `approve --grant` 在临时 workspace 里验签放行并级联 advance 到 requirement-approved、approval.yml 记 via: server-approve——AC-4① 的核心链路在两个语言实现间闭合。另：digest 共享向量 parity（AC-7⑤ Go 半边）、mat_ 403、漂移 409、密钥三种编码加载+垃圾拒绝、投递队列 drain（AC-4⑤ 服务端三拒绝路径全覆盖）。
- **角色策略简化（记录在案）**：当前策略=workspace 成员（RequireWorkspaceMemberFromURL）+ 人类身份；"审批人 ∈ cr.owners 对应角色"未实现——owners 里是外部名字（Ray），与平台 user 无映射关系，源方案也标注"策略可配"。留待用户体系与 owners 打通后收紧。
- **迁移 158 增列**（分支未合并期直接修订）：cr_sync_event.evidence、approval_record.workspace_id/grant_json/delivered_at；本机库已同步 ALTER。
- **待 T11**：Web UI 发起审批的全链（本任务用 API 直测）；公钥实际提交 knowledge-base 仓（生产 key 生成时做）。
