---
cr: CR-2026-059
pipeline-node: review-tech-design（fix-mode 定点修复后复评待发起）
status: tech-design-review-pending
updated: 2026-09-04T11:36:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 cr.md / review-loop.yml / traceability.yml / 评审记录为准。

## 当前状态（复评技术中止后 fix-mode 定点修复）

- status = `tech-design-review-pending`（本轮：`review-tech-design:block -> write-tech-design` 进入 `tech-designing` → 定点修复落盘 → `write-tech-design-complete` 推回）。
- 修复背景：上一轮独立复评因环境前置**技术中止**（未生成 verdict、未落盘、未 advance）：硬因 ① multica/tools 资源 worktree 脏（quality-reviewer prompt 误放，Ray 拍板 A 后 coordinator 已还原，三仓复归 healthy/clean）；硬因 ② SDD §10 证据基线 SHA 与 multica CR worktree HEAD 字面不一致（wip checkpoint 前推 → 还原提交对冲）。附带观察：§2.6 SQL 示例一文件两语句，与「一迁移一条语句、索引全 CONCURRENTLY」口径不一致。
- 本轮修复（定点，未改任何依赖条目内容与已确认方案）：
  1. §10 证据基线 SHA 对齐：文件头引导句、§10 引导句、38 条依赖条目共 40 处 `e8b252597a6d21718c2533d497fba4109a79b37b` → `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（= 当前 multica CR worktree HEAD，还原提交，树与 main `e8b25259` 逐字节一致）；§10 引导句新增注记行。
  2. §2.6 SQL 示例拆分：`487_chat_idempotency.up.sql`（仅 CREATE TABLE）+ `488_idx_chat_idempotency_created.up.sql`（仅 `CREATE INDEX CONCURRENTLY`）。
  3. 一致性清扫：§1.2「481–487（7 个新迁移）」→「481–488（8 个新迁移）」；§2 引导句「编号 481–487 连续」→「编号 481–488 连续」；全文已确认零残留。
- 下一步 = 独立 `quality-reviewer-agent` 新开 `review-tech-design` 复评（对象=修复后 sdd.md，fresh run）；**复评必须先落盘**：`crctl gate CR-2026-059 --for tech-design-reviewing` + `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（上两轮均未落盘，tech-design 环至今未开出，人工 approve --stage tech 的 evidence 门禁过不去）。

## 本轮产出

- `change-requests/CR-2026-059/sdd.md`：9 章 + 既有实现依赖清单（38 项，全部绑定 multica HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`）。
- 核心设计点：迁移 481–488 序列（481 agent_id 可空+FK SET NULL；482 kind；483/484 Private Ask 唯一索引同名收窄；485 shared 每项目一个 active；486 chat_message 作者列；487/488 chat_idempotency 表+索引）；`SendDiscussionMessage` 事务（幂等 PK 冲突收敛 + 协办触发 + 附件原子绑定）；`PatchChatSessionConfig`/`SendChatMessage`/消息列表按 kind 分流；settings 三态清除分支 + 锁内投影（与 Team Agent 关旧建新刻意不同，决策 D-5）；`events.Event.ChatSessionKind` + listeners kind 路由（fail-closed 缺省保持 private）；`revokeAndRemoveMember` 挂接 `DisconnectWorkspaceUser`；`GetProjectChatSessionForCreator` 加 `kind='private'` 过滤（三调用点语义保持）。
- SDD-CLOSE-01..10 关闭 PRD 延后设计项；决策记录 D-1..D-10；zero_diff 清单见 §9。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`.rayai-worktrees/knowledge-base/requirement/CR-2026-059`（本目录）。
2. 评审对象：`change-requests/CR-2026-059/sdd.md`；对照 `prd.md`（选项 A 修订版）。
3. 证据基线：multica CR worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（还原提交，树 = main `e8b25259`；§10 依赖事实不因 SHA 刷新而变）。
4. 前置：`crctl gate CR-2026-059 --for tech-design-reviewing`（预检）→ `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（轮次记账，无论 PASS/BLOCK 都落盘）。
5. PASS：reviewer 落盘评审记录并回报；人工 `crctl approve --stage tech` 由 coordinator 发布。BLOCK：按 reviewLoop 直连回 `write-tech-design`（@ dev-agent，不走 coordinator）。

## 已核实事实基线（设计基底，全部已并入 sdd §10）

multica worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（树与 main `e8b25259` 逐字节一致）：迁移最大编号 480；`chat_session_agent_id_fkey` 无后续迁移引用；436 谓词不区分 kind；478 配置列在位；`CreateChatTask` issue_id 恒 NULL；`writeChatCompletionOutcome` 在 `server/internal/service/task.go:5057`（注意：不是 handler 目录）；`BindUnboundDraftAttachments` 只写三靶、`LinkAttachmentsToChatMessage` 不写 task_id（故新增 `BindDraftAttachmentsToChatMessage`）；`GetProjectChatSessionForCreator` 三调用点（project_chat.go:343/378、autopilot.go:990）；chat.sql 的 INNER JOIN agent 查询均为 agent 作用域（builder/系统 runtime/creator 待办），不受 NULL agent_id 影响；实时 fail-closed 在 `server/cmd/server/listeners.go`；settings PATCH coordinator 分支无清除语义；`sendProjectChatCore`/`MergeForwardDiscussion`/`buildMergedForwardContent` 结构；`util.ParseMentions`；`SweepChatDraftAttachments` 168h 边界语义；Team Agent 会话是独立表 `project_chat_session`（472），与 `chat_session(kind=project_shared)` 不同。
