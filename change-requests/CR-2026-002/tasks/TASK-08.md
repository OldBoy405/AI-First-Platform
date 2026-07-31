---
id: CR-2026-002-TASK-08
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 签名审批服务端（approval.go + grant 签发 API + 私钥方案 + daemon 下发）
status: pending
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
