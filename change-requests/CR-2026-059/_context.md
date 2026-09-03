---
cr: CR-2026-059
pipeline-node: write-tech-design
status: tech-designing
updated: 2026-09-03T23:30:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 cr.md / review-loop.yml / traceability.yml / 评审记录为准。

## 当前状态

- status = `tech-designing`（本 run 由 `requirement-approved` 经 `crctl advance --to tech-designing --trigger write-tech-design --expect requirement-approved` 合法推进）。
- `crctl next` = `write-tech-design`（why: sdd.md 缺失）。sdd.md **尚未落盘**——本 run 在 Step 2 术语硬化/事实核实时发现阻断点，按 Skill「语义冲突不得自行裁决」与 coordinator 交接「事实冲突/需人工裁决停下回报」停止。

## 阻断原因（待人工裁决）

**FR-25 / AC-28 / AC-29 的「项目成员」ACL 与 multica 数据模型冲突**：

1. PRD FR-25 的负向契约表要求区分「当前项目成员」「同 workspace 非本项目成员」「已被移出项目的旧成员」三类调用者（403/404/退订），且以「请求当时的项目成员资格」为准。
2. multica 仓（worktree HEAD `e8b252597a6d21718c2533d497fba4109a79b37b`）**不存在任何项目级成员模型**：
   - 无 project_member 表（迁移全量核查，仅 `project` 表含 `lead_id`，034_projects.up.sql）；
   - 无成员端点（`router.go:1999` `/api/projects` 路由块全量核查，无 members 子路由）；
   - 代码先例明示：`packages/views/projects/components/presenter-control-sheet.tsx:31` 注释「there is no project-level membership concept to filter by」（CR-2026-010）；
   - 现有全部项目面（Team Agent chat GET/发送、Discussion 容器、presenter、resources）均为 workspace 成员级门禁，无 per-project ACL。
3. 两个方向都改变已批语义、不可自行裁决：
   - A. 「项目成员 := workspace 成员」→「同 workspace 非本项目成员」类为空，AC-28 按字面不可测，需修订 FR-25/AC-28/AC-29 措辞；
   - B. 本 CR 引入最小项目成员子系统（表 + 增删端点 + 迁移 + 初始播种 + 管理面）→ 超出已批范围，无任何 FR 覆盖成员管理。

## 已核实、无需裁决的事实（回修恢复后可直接使用）

- 迁移最大编号 480（`480_issue_project_chat_session_origin_uidx.up.sql`）；481 起可用。
- `chat_session_agent_id_fkey`（033_chat.up.sql:7 内联 FK 自动命名）**无任何后续迁移引用**——FR-21/AC-19 的 481 转换方案前提成立。
- `436_chat_session_project.up.sql` `chat_session_project_creator_active_unique` 谓词为 `project_id IS NOT NULL AND status='active'`（不区分 kind）——FR-6 必须收窄为仅 `kind='private'`，另增 shared 唯一索引。
- `478` 已加 `base_model/base_thinking_level/model_override/thinking_level_override`——FR-9 复用前提成立。
- `CreateChatTask`（chat.sql:1107）`issue_id` 恒 NULL；`writeChatCompletionOutcome`（task.go:5057）按 `task.ChatSessionID` 写 assistant 消息——FR-12 回复链路可复用。
- `BindUnboundDraftAttachments`（attachment.sql:205）只绑 issue/comment/task 三靶——Discussion 发送需新增 chat 形（chat_session_id+chat_message_id+可空 task_id）绑定查询，复用同一 `LockUnboundDraftAttachments` 锁序。
- `chat_message` 无作者列——shared 多人会话的展示与 merge-forward 渲染（buildMergedForwardContent 含署名）需要作者归属，SDD 拟增可空 `author_type/author_id`（设计决策，非冲突）。
- 实时聊天事件单收件人投递（`listeners.go:253-270`：ChatSessionID 非空必须带 ChatRecipientID，SendToUser，fail-closed）——FR-20 需 kind 感知的多成员投递改造（设计工作）。
- 无通用幂等记录存储（仅 `publicapi/v1/foundation.go` 头常量）——FR-24 需设计幂等记录表（24h 保留、指纹、并发收敛）。
- 项目 settings PATCH（project.go:547 起）已有 coordinator key 校验分支，但**无清除/解绑分支**（非字符串即 400）——FR-26 解绑需补清除语义 + 锁内投影事务。
- `GetProjectChatSessionForCreator`（chat.sql:12）未按 kind 过滤——不收窄会让 shared session 命中 Private Ask 查询（FR-5 泄漏点，SDD 必修）。
- 草稿附件上传者门已就位（file.go `loadAttachmentForRequest` §4.9 gate）；已发送 shared 附件的「非成员 404」扩展点同在此处。

## 恢复入口

1. 人工（需求负责人 Ray）就成员语义裁决（选项 A：workspace 成员口径 + PRD 措辞修订；选项 B：引入成员子系统扩范围）。
2. 若选 A 且需 PRD 修订：由 coordinator 按流程路由需求侧定点修订 FR-25/AC-28/AC-29 并复评/重批；本 CR 回到 `write-tech-design` 承接（status 若仍在 `tech-designing` 则按回修模式进入）。
3. 裁决落定后，dev-agent 以本文件「已核实事实」清单为底稿继续产出 sdd.md，其余设计点（迁移 481+ 序列、作者列、多收件人实时、幂等表、settings 解绑投影、kind 分流）均已有成型方案，无其他阻断。
