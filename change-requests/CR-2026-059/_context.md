---
cr: CR-2026-059
pipeline-node: review-tech-design（待评审）
status: tech-design-review-pending
updated: 2026-09-04T01:55:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 cr.md / review-loop.yml / traceability.yml / 评审记录为准。

## 当前状态

- status = `tech-design-review-pending`（`tech-designing` 经 `crctl advance --to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing` 推进）。
- `sdd.md` 已落盘（本 run，fix-mode 续写：上一 run 因成员语义冲突停在产出前；选项 A 裁决 + PRD 定点修订复评 PASS 后恢复）。
- 下一步 = 独立 `quality-reviewer-agent` 执行 `review-tech-design`（cr_id=CR-2026-059、reviewer=ai-reviewer、对象=本 worktree 的 sdd.md）。

## 本轮产出

- `change-requests/CR-2026-059/sdd.md`：9 章 + 既有实现依赖清单（38 项，全部绑定 multica HEAD `e8b252597a6d21718c2533d497fba4109a79b37b`）。
- 核心设计点：迁移 481–488 序列（481 agent_id 可空+FK SET NULL；482 kind；483/484 Private Ask 唯一索引同名收窄；485 shared 每项目一个 active；486 chat_message 作者列；487/488 chat_idempotency 表+索引）；`SendDiscussionMessage` 事务（幂等 PK 冲突收敛 + 协办触发 + 附件原子绑定）；`PatchChatSessionConfig`/`SendChatMessage`/消息列表按 kind 分流；settings 三态清除分支 + 锁内投影（与 Team Agent 关旧建新刻意不同，决策 D-5）；`events.Event.ChatSessionKind` + listeners kind 路由（fail-closed 缺省保持 private）；`revokeAndRemoveMember` 挂接 `DisconnectWorkspaceUser`；`GetProjectChatSessionForCreator` 加 `kind='private'` 过滤（三调用点语义保持）。
- SDD-CLOSE-01..10 关闭 PRD 延后设计项；决策记录 D-1..D-10；zero_diff 清单见 §9。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`.rayai-worktrees/knowledge-base/requirement/CR-2026-059`（本目录）。
2. 评审对象：`change-requests/CR-2026-059/sdd.md`；对照 `prd.md`（选项 A 修订版）。
3. 前置：`crctl gate CR-2026-059 --for tech-design-reviewing`（预检）→ `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（轮次记账）。
4. PASS：reviewer 落盘评审记录并回报；人工 `crctl approve --stage tech` 由 coordinator 发布。BLOCK：按 reviewLoop 回 `write-tech-design`（本 Skill 回修模式允许 `tech-designing`/block 态进入）。

## 已核实事实基线（设计基底，全部已并入 sdd §10）

multica worktree HEAD `e8b252597a6d21718c2533d497fba4109a79b37b`：迁移最大编号 480；`chat_session_agent_id_fkey` 无后续迁移引用；436 谓词不区分 kind；478 配置列在位；`CreateChatTask` issue_id 恒 NULL；`writeChatCompletionOutcome` 在 `server/internal/service/task.go:5057`（注意：不是 handler 目录，上一轮笔记的 `task.go` 路径已更正）；`BindUnboundDraftAttachments` 只写三靶、`LinkAttachmentsToChatMessage` 不写 task_id（故新增 `BindDraftAttachmentsToChatMessage`）；`GetProjectChatSessionForCreator` 三调用点（project_chat.go:343/378、autopilot.go:990）；chat.sql 的 INNER JOIN agent 查询均为 agent 作用域（builder/系统 runtime/creator 待办），不受 NULL agent_id 影响；实时 fail-closed 在 `server/cmd/server/listeners.go`；settings PATCH coordinator 分支无清除语义；`sendProjectChatCore`/`MergeForwardDiscussion`/`buildMergedForwardContent` 结构；`util.ParseMentions`；`SweepChatDraftAttachments` 168h 边界语义；Team Agent 会话是独立表 `project_chat_session`（472），与 `chat_session(kind=project_shared)` 不同。
