---
id: CR-2026-012-test-report
type: TEST-REPORT
cr-ref: CR-2026-012
title: P2 三模式聊天 CR-G — 验收报告（TASK-08）
target-version: "0.19"
owner: Ray
owner-role: test
status: pass
created: "2026-08-03T23:10:00+08:00"
updated: "2026-08-03T23:10:00+08:00"
---

> **验收口径确认**：AC-1/2/3/4 的核心链路在**隔离测试库（`multica_cr_2026_012`，迁移应用到
> 166）上的 handler/service 集成级真实调用**中完整走通（真实 SQL 读写、真实 enqueue/claim/
> complete HTTP handler 链路，非 mock）；AC-6/7/8 由各 TASK 的 Go/TS 测试套件与 locale parity
> 覆盖。涉及**真实 daemon 进程执行、双浏览器实时推送、真机 UI 走查**的验证项（AC-2 的 work_dir
> 审计实跑、AC-5 的 requirement-register 实跑、AC-7 的真机隔离走查）本环境无法驱动，已在 §4
> 列为部署前待执行清单。

# 验收报告 — CR-2026-012（P2 三模式聊天 CR-G：D8 DC 协调者 + 讨论转执行）

## 0. 摘要

8 个开发任务全部完成并提交到 `requirement/CR-2026-012` 分支（multica worktree，commit
3793151bf..91acef8ee，共 8 个原子提交，每 TASK 一个便于 revert）。

**代码级验证全绿**：
- 后端 `go build ./...` + `go vet` 全绿；`internal/handler`（含本 CR 新增 3 个测试文件约 40 项
  用例）、`internal/service`、`internal/agenttmpl` 完整套件通过。新增覆盖：DC settings 读取
  7 分支、claim ask_only 双向、trivial 豁免双向、触发过滤 11 分支（5 旧 + 6 新）、路由 re-target
  3 场景、merge-forward 端点 6 场景、薄发送端点附件 3 场景、AC-1/2/3 全链路集成 2 条。
- 前端 `@multica/core`（826 测试）+ `@multica/views`（1866 测试）全绿；`tsc --noEmit` core/views
  双包零报错；eslint 改动文件零报错。新增覆盖：project-chat-store 附件槽 6 项、ChatInputCore
  双重锁定 5 项、DiscussionPane 多选/预览/错误分支 9 项、两面 composer shim 化回归 39 项。
- locale parity 测试全绿，四语（en/ja/ko/zh-Hans）新增 `chat.merged_forward.*`（14 键）+
  `chat.dc.*`（5 键）齐备，同 commit 落位。

**集成级 E2E（本轮亮点）**：`discussion_coordinator_e2e_test.go` 在真实测试库上把
「配置 DC → @DC 激活入队 → claim 断言 ask_only=true → trivial 输出完成 → Discussion 容器
可见输出（豁免生效）→ DC @团队Agent 路由 → chat 容器路由 comment + 任务 + originator=激活
人类」整条链用真实 handler 调用跑通；merge-forward 链把「端点 201 → 1 comment + 1 task →
daemon claim 的 TriggerCommentContent 含完整三段合并结构」跑通。详见 §6。

## 1. 逐 AC 验收结果

| AC | 判定 | 证据 / 说明 |
|---|---|---|
| **AC-1** 静默边界（未配置全拒 + 已配置仅两类放行 + 纯文本名字不触发，DB 级零增量） | ✅ 集成级通过 | `TestComputeCommentAgentTriggers_DiscussionContainerNeverEnqueuesAgent`（5 分支，未配置红线原样）+ `..._TwoClassFilter`（6 分支：@DC 放行 / 成员 @第三方拒 / 纯文本 DC 名字不触发 / DC @团队放行 / DC @第三方拒 / DC @DC 自触发拒）+ `TestDiscussionCoordinator_SilentBoundaryAndActivationChain` 的 AC-1 段（配置项目内普通消息与纯文本名字 → trigger 零、`agent_task_queue` DB 级零增量断言）。 |
| **AC-2** 激活与可见输出（@DC → ask_only 入队 → 完成 → 容器 agent comment；trivial 豁免；只读沙箱） | ✅ 集成级通过（沙箱实跑待真机） | 入队/claim：`TestClaimTaskByRuntime_DiscussionContainerTaskIsAskOnly`（discussion 容器任务 claim `ask_only=true`，普通 issue 不受影响）+ e2e 链同款断言。可见输出：`TestCompleteTask_DiscussionContainer_DoesNotSuppressTrivialDoneOutput`（trivial "Done." 仍落 agent comment，普通 issue trivial 抑制不变的对照用例同绿）+ e2e 链 AC-2 段（真实 CompleteTask 调用后 DB 断言可见输出="Done."）。只读沙箱机制面：AskOnly 复用 CR-C 整链（brief 无 Repositories 段、checkout 拒绝形态沿 `daemon/health_test.go` 的 `TestRepoCheckoutRejectedForAskOnlyTask`，本 CR 未改该路径）；**真实 daemon 进程的 work_dir 无写入审计未执行**（§4）。 |
| **AC-3** 路由（DC 输出 @团队Agent → chat 容器路由 comment + 任务；满队 → system comment） | ✅ 集成级通过 | `TestDiscussionRoute_RetargetsToChatContainer`（路由 comment 落 chat 容器 + 任务 trigger=路由 comment + **originator=激活人类**，TSUG-001 显式解析链 parent_id 穿透）+ e2e 链 AC-3 段（含 Discussion 容器零执行任务泄漏断言）。满队：`TestDiscussionRoute_QueueFullPostSystemComment` + `TestDiscussionActivation_QueueFullPostSystemComment`（429 → discussion 容器 DC 署名 system comment 含 N/M 结构，无 ghost 路由 comment）。 |
| **AC-4** 合并转发（多选 N 条 → 预览 → 1 comment + 1 task；claim 内容含合并结构；取消零副作用；429 保留预览） | ✅ 集成级通过（预览 UI 真机目视待补） | 端点：`TestMergeForwardDiscussion_MergesIntoSingleCommentAndTask`（三段结构 + 计数 + 乱序去重升序 + register_cr=false 无指令块）+ `..._RegisterCRAppendsInstructionBlock` + `..._InvalidSelections`（空选/51 条/普通 Issue comment/他项目 discussion comment → 400 `invalid_comment_selection`）+ `..._QueueFull429NoGhost` + `..._PresenterRequiredForPlainMember`（403/429 结构与既有 writer 复用断言）。claim 侧：`TestMergeForward_EndToEndClaimCarriesMergedStructure`（真实 claim 的 `trigger_comment_content` 含 `## Trigger message`/引用块/`## Conversation history (2 messages)` 全结构）。前端：`discussion-pane.test.tsx` 9 项（多选/升序预览/confirm 调用参数/429 保留多选与预览/gates 报错默认不勾/取消零副作用/权限分支）。 |
| **AC-5** 升级 CR（register_cr=true → 指令块 → Team Agent 实跑 requirement-register → CR 壳 + 回报 CR-ID） | ⚠️ 代码级通过，实跑待真机 | 指令块组装与传递：`TestMergeForwardDiscussion_RegisterCRAppendsInstructionBlock` + `TestMergeForward_EndToEndClaimCarriesMergedStructure` 反向断言（false 无块）+ 默认态逻辑 `defaults register-CR to unchecked when the gates endpoint errors`（TSUG-003）。**真实 Team Agent 执行 requirement-register Skill 落 knowledge-base CR 壳并回报 CR-ID 需要运行中的 daemon + agent runtime，本环境无法驱动**（§4）——服务端零 CR 写路径是设计保证（DD-8），不存在服务端侧可失败的环节。 |
| **AC-6** 解耦锁定（自定义 adapter 不触碰 useChatStore 成为结构性事实） | ✅ 完整通过 | `chat-input.test.tsx` 双重锁定 5 项：静态锁（渲染 ChatInputCore + 自定义 adapter，useChatStore mock **零调用**）+ 4 项行为锁（输入/上传/发送 commit/restore 各动作路由到 adapter 方法，全局 store state 快照逐字节不变）。既有 17 项 ChatInput 默认包装用例全量跑在 `useGlobalChatDraftAdapter` 上证明等价（含 restore 会话感知、commit handoff、上传门禁）。 |
| **AC-7** 两面回填（附件/仅成员提及/富文本 + 跨项目跨模式隔离） | ✅ 代码级通过（真机走查待补） | 附件槽：`project-chat-store.test.ts` 6 项（projectId×mode 隔离 / upsert / 无 id 忽略 / 替换与空清 / `setDraft("")` 联动清附件 / 旧快照 rehydrate 兼容）。仅成员提及：`mentionItemTypes` 过滤落在 buildSyncItems + context items + MentionList 服务端搜索分支三处（搜索分支在类型不含 issue/project 时直接跳过 round-trip）。发送链路：薄发送端点 `attachment_ids` 3 场景（绑定成功/缺省行为不变/非法 400 零持久化）+ `sendChatMessage` 既有签名复用。**真机富文本编辑与跨项目切换目视走查未执行**（§4）。 |
| **AC-8** 回归（parity + CR-D/A/C 三面 + 浮窗 + presenter/容量守卫 + approvalSvc 未配置冒烟） | ✅ 完整通过 | locale parity 全绿（四语无缺键）。CR-D Discussion：discussion-pane 既有 4 项用例（草稿/发送/空态/禁用）在重构后全绿，useCommentDraftStore 草稿语义保留（SDD §5.3 末条）。CR-A Team Agent：`project-team-agent-chat.test.tsx` 全绿（发送/502/429/presenter/model selector 四态/canConfigure 豁免）。CR-C Private Ask：`project-private-ask.test.tsx` 全绿（发送/pending bubble/失败保草稿/stop/FR-3 静态守卫）。presenters 与容量守卫：merge-forward 复用 `sendProjectChatCore` 同一内核，403/429 用例同链路验证。approvalSvc 未配置：gates query 报错 → register-CR 默认不勾且预览无错（TSUG-003 用例）。 |

## 2. 评审建议（TSUG）落地核对

- **TSUG-001**（originator 解析穿透）：核实结论——`resolveOriginatorForIssueTask` 对 service 直建
  的路由 comment **不具备穿透能力**（其链走 `comment.source_task_id`，直建 comment 无该字段）。
  落地为 re-target 处沿路由 comment 的 `parent_id` 链显式解析激活人类并经
  `enqueueMentionTaskWithCommentPlanAndOriginator` 透传；解析失败沿 a2a 直通语义 + 日志。
  证据：`TestDiscussionRoute_RetargetsToChatContainer` 与 e2e 链的 originator 断言。
- **TSUG-002**（DC 输出可见性是机制而非约定）：落地为 `issueIsDiscussionContainer` 豁免
  `isTrivialDoneOutput` 抑制（一行容器判定，fail-closed），双向用例 + e2e 链 trivial 边界证据。
- **TSUG-003**（approvalSvc 未配置环境的升级 CR 默认态）：落地为 gates query `isError` →
  默认不勾、预览零报错，专项用例覆盖。

## 3. 已知偏离与简化（工程纪律留痕）

1. **SDD §4.5 "新 key 零后端改动" 论述不成立**（事实断言先核实，纪律 #4）：`project.go` 的
   settings 更新是白名单 patch（仅 team_agent_queue_limit / team_agent_id 两 key 放行），自由
   JSONB 写入会被静默丢弃。T01 已按 team_agent_id 同款形态补 `discussion_coordinator_agent_id`
   校验分支（UUID 合法性 + 工作区内存在性）。结论受影响范围：仅增加一个校验分支，DD-1 设计不变。
2. **SDD 引用的 `health_test.go:437` 实为 `server/internal/daemon/health_test.go`**（
   `TestRepoCheckoutRejectedForAskOnlyTask`），非 `server/cmd/server/`。引用已按实际位置理解，
   无需代码修正。
3. **合并转发持久内容的节标题为服务端固定英文**（`## Trigger message` / `## Conversation
   history (N messages)`），register_cr 指令块按 SDD 原文中文。`chat.merged_forward.*` locale
   键服务前端预览 Dialog 的 chrome 与文案；持久 markdown 是 agent-facing 内容，不做 i18n。
4. **restore 会话感知用例补了一次显式 rerender**：真实 zustand 写入会通知订阅者触发重渲染，
   测试 mock store 无订阅机制，旧实现依赖 `setIsEmpty` 状态翻转的副作用掩盖了这一点；拆分后
   wrapper 与 Core 分层使该副作用消失，测试按"模拟 store 通知"显式 rerender（注释已留痕）。
5. **DC 绑定的读取面**：SDD §4.5 未定义 `GetProjectDiscussion` 响应携带绑定，T07 补
   `coordinator_agent_id` 响应字段（omitempty，缺省 ""），与 `GetProjectChat` 的
   `team_agent_id` 形态对齐。

## 4. 真机 E2E 待执行清单（供部署前独立验收）

| # | 场景 | 依赖 | 预期证据 |
|---|---|---|---|
| 1 | AC-2 沙箱审计实跑 | 运行中 daemon + agent runtime | DC 任务 claim 后 brief 无 Repositories 段；`multica repo checkout` 403；work_dir 无文件写入 |
| 2 | AC-2 双浏览器实时 | 两个浏览器会话 | DC 完成输出经 `comment:created` 广播在另一会话实时出现 |
| 3 | AC-3 Team Agent 面执行 | 运行中 daemon | 路由任务被 Team Agent 真实执行，输出落 chat 容器 |
| 4 | AC-5 requirement-register 实跑 | daemon + agent runtime + knowledge-base 仓写权限 | register_cr=true 转发后 Team Agent 按 Skill 注册合规 CR 壳并在会话回报 CR-ID |
| 5 | AC-7 真机走查 | web 前端 | 两面附件上传/删除/发送后清空、@列表仅成员（含搜索）、富文本列表/加粗、跨项目跨模式草稿与附件不串 |
| 6 | 多选预览真机目视 | web 前端 | 预览三段结构与计数、429/403 提示后多选与预览保留 |

## 5. 环境性失败留痕（与本 CR 无关，基线即失败）

- `TestBuiltinSkillsConformToTemplate` 等 10 项 builtin_skills 契约测试：Windows autocrlf 检出
  CRLF 导致 frontmatter 解析失败（主仓干净基线同样失败，纪律 #1 已知环境问题）。
- `TestParseSkillArchive_RejectsUnsafeSkillMdPath`、`TestShortTaskIDMatchesDaemon`：Windows
  路径分隔符差异（主仓基线通过、本 worktree 失败的唯一差异是检出环境，代码未触碰相关路径）。

## 6. 集成级 E2E 证据链（discussion_coordinator_e2e_test.go）

两条链均使用真实测试库 + 真实 handler/service 调用（非 mock）：

**链 A — AC-1/2/3 激活-路由全流程**（`TestDiscussionCoordinator_SilentBoundaryAndActivationChain`）：
1. 配置项目（settings 含 DC + Team Agent 绑定）+ Discussion 容器；
2. AC-1：普通消息 / 纯文本 DC 名字 → trigger 零，DB 级 `agent_task_queue` 零增量；
3. AC-2：成员 @DC → 唯一触发 → `EnqueueTaskForMention` 真实入队 → `ClaimTaskByRuntime` 真实
   HTTP claim → 响应 `ask_only=true` 断言 → 模拟 StartTask → `CompleteTask`（trivial "Done."）
   → DB 断言 Discussion 容器出现 DC 署名 agent comment "Done."（豁免生效）；
4. AC-3：DC 路由 comment（parent=激活 comment）@团队Agent → 触发计算 → re-target 入队 →
   DB 断言 chat 容器出现路由 comment + Team Agent 任务（trigger=路由 comment，
   originator=激活人类 testUserID），且 Discussion 容器零 Team Agent 任务泄漏。

**链 B — AC-4 端点到 claim 全结构**（`TestMergeForward_EndToEndClaimCarriesMergedStructure`）：
1. 两条 discussion 消息 → `MergeForwardDiscussion` 真实 HTTP 调用 → 201；
2. DB 断言 chat 容器恰好 1 comment + 1 task；
3. `ClaimTaskByRuntime` 真实 claim → `trigger_comment_id` = 合并 comment、
   `trigger_comment_content` 含 `## Trigger message` / `> the API needs retries` /
   `## Conversation history (2 messages)` / 两条消息全文，且 register_cr=false 时无指令块。
