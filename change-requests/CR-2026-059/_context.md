---
cr: CR-2026-059
pipeline-node: review-tech-design（回修复评待发起）
status: tech-design-review-pending
updated: 2026-09-04T09:48:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 cr.md / review-loop.yml / traceability.yml / 评审记录为准。

## 当前状态（cycle 3 attempt 2 BLOCK 定点回修后）

- status = `tech-design-review-pending`（本轮回修：`review-tech-design:block -> write-tech-design` 进入 `tech-designing` → 回修落盘 → `write-tech-design-complete` 推回）。
- 回修背景：reviewer BLOCK 未落盘（仅评论），coordinator 裁决事实冲突（PRD FR-7/FR-21 已授权 481 FK 转换；PRD L74 是 §1.4 基线描述非目标态），选项 b（重开 PRD）排除，采纳选项 a（SDD 补引注）。
- 本轮回修改动（定点，未重写已确认方案）：§2.1 增加授权引注块（PRD FR-7 L127/L129 + FR-21 L234–L249 SQL 逐字一致 + L74 基线区分）；§2 引导句加引注指针；§2.3 483→484 窗口量化（同一 `cmd/migrate up` 顺序应用，窗口 ≤5 分钟保守上界）；§4.6 “至少 24h”口径澄清（保留下限 [24h,25h)，固定 24h 阈值不引入可配置）；§9 follow_up 增 ⑤ 幂等保留期可配置化；frontmatter updated 刷新。
- 下一步 = 独立 `quality-reviewer-agent` 新开 `review-tech-design` 复评（对象=回修后 sdd.md）；**复评必须先落盘**：`crctl gate CR-2026-059 --for tech-design-reviewing` + `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（上一轮 BLOCK 未落盘，tech-design 环尚未开出）。

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
