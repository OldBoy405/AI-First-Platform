# B10 E2E 证据（disposable CR-2026-956，真实网页/daemon/Agent/signed-grant 五节点链路）

## 结论

architecture-design Runner Core 五节点链在真实后端 `http://localhost:18080` + 真实 daemon +
真实 Agent + 真实网页人工审批 + 真实 Ed25519 signed grant 下端到端跑通，`phase=complete`。

## 五节点最终状态（run b0c9fd5a-d072-4765-b1fd-42df470055db）

| seq | node | kind | status | attempt |
|-----|------|------|--------|---------|
| 1 | write-tech-design | skill | passed | 1 / 2 |
| 2 | review-tech-design | skill | blocked(1) → passed(2) | 1 / 2 |
| 3 | human_approval | human_approval | passed | 1 |
| 4 | approve-tech-design | skill | passed | 1 |
| 5 | push-progress | skill | passed | 1 |

- pipeline_run.status = `completed`（completed_at 2026-08-18 08:52:21.719503+00）
- cr.status = `tech-design-reviewed`，needs_reconcile = false
- `crctl next` → `write-dev-plan`（架构阶段终点，humanApproval=false）

## 真实审批与 signed grant

| 字段 | 值 |
|------|-----|
| 有效 grant 审批记录 id | `38f688e0-5400-47eb-9763-2b94c2db6f6d` |
| stage / decision | tech-design / approve |
| evidence_digest | `482e59249c8b3e0ccaea2574bb4beee0e6ebbe8b7b7e373df63bee34a1c4400b`（sdd.yml） |
| key_id | `cr045-e2e` |
| signature | present（Ed25519） |
| delivered_at（daemon ACK） | 2026-08-18 08:52:21.681044+00 |
| 网页审批时间（approve POST） | 2026-08-18 08:28:45（server log request_id=3e6d679c） |

旧漂移 grant（stale）`c393dcfb-...` evidence_digest=95d935e（requirement.yml），
已作为「stale grant → EVIDENCE_DRIFT」负向路径证据保留。

## Agent 任务

| task | id | 结果 |
|------|-----|------|
| approve-tech-design | `a5fda446-b97b-46b1-b86b-24ca28ec42bb` | completed；`crctl approve --grant` 推进 → tech-design-reviewed |
| push-progress（checkpoint） | `ba6340e1-5172-41c3-bbcb-a34f8c6bdd61` | completed（checkpoint 由 crctl checkpoint 深原语执行） |

## checkpoint（push-progress）

- 命令：`crctl checkpoint CR-2026-956 --message 架构设计已审批`
- phase = `complete`，changed = true
- batchId = `ceb13d1afacac5cd`
- metadataCommit = `197927fe7d32080d84581eef7ed7e4ef87d22336`
- repos：ai-first-platform-docs / multica / tools 全部 confirmed（refs/heads/requirement/CR-2026-956）
- cr_sync_event #852（event_kind=checkpoint，commit_sha=197927fe，processed）

## 负向路径证据（真实触发）

1. **workspace dirty 前置拦截**：approve-tech-design 首次运行时 operational workspace
   有 tracked 未提交（review-annotations/sdd.yml + traceability.yml），`crctl workspace inspect`
   返回 classification=dirty，任务报 `PIPELINE_CRCTL_UNAVAILABLE: workspace resource is dirty`
   （零写入、不推进状态）——workspace authority 检查按预期工作。
2. **stale grant → EVIDENCE_DRIFT**：首个 tech-design grant 以 requirement.yml 摘要
   （95d935e）签发，`crctl approve --grant` 验出 evidence_digest ≠ 当前 sdd.yml 摘要
   （482e5924），返回 `EVIDENCE_DRIFT` 并 abort（零写入）——证据漂移检测按预期工作。

## 本 E2E 发现的问题（供正式 CR 复盘，均非 CR-2026-045 Runner Core 本体缺陷）

1. **multica 主线迁移回归**：migration 259/263 重建 `issue_origin_type_check` 约束时
   丢掉了 `project_chat`/`project_discussion`，导致项目聊天容器 issue 创建失败
   （`GET /api/projects/:id/chat` 500）。已在 E2E 数据库手工恢复完整约束。
2. **review-record 证据同步缺口**：`crctl review-record` 的 outbox 事件不带 evidence 字段，
   使 tech-design 评审证据（sdd.yml）从未进入服务端 `cr_sync_event`，审批 grant 因此以
   陈旧 requirement.yml 证据签发。需要跟进 CR 修复（review-record 补 evidence）。
3. **投影漂移**：daemon crevents 快照扫描主工作区（master，c82d8bd review-pending 快照），
   覆盖了 worktree 的 tech-design-reviewed 投影。属 E2E 环境配置问题（daemon 应扫描
   operational worktree 而非主工作区快照）。
4. **push-progress agent 卡死**：prompt 的 `<installation-workspace>` 占位符未解析，
   agent 无法定位 crctl，退化为全盘 `find /` 挂起。属 prompt/环境清晰度问题。

## 数据一致性

- 三仓 checkpoint 推送后 source SHA：
  - ai-first-platform-docs `90da162ca8c9ec5a8bad4fb20653c3272b0f2c7d`
  - multica `58d2a888c3b748829ef93bff970b9514a53636f7`
  - tools `b6def12adef0befc21fedbb5d3cb996faa5e417f`
- knowledge-base metadataCommit `197927fe7d32080d84581eef7ed7e4ef87d22336`
