---
id: CR-2026-009-test-report
type: TEST-REPORT
cr-ref: CR-2026-009
title: P2 三模式聊天 CR-D — 验收报告（TASK-05）
target-version: "0.16"
owner: Ray
owner-role: test
status: pass
created: "2026-08-02T15:40:00+08:00"
updated: "2026-08-02T16:10:00+08:00"
---

> **验收口径确认**：AC-1/AC-3（红线）/AC-4（红线）/AC-5/AC-6 完整通过，含真机浏览器 + 隔离
> worktree DB 的 SELECT 级验证（非模拟）。AC-2（@提及通知跳转）单用户会话内无法产生跨用户
> inbox 通知，落点组件（ContainerJumpBanner）由单测覆盖，真机跨用户验证待补。AC-7 为 SDD
> §6.3 定案的裁剪项（无实现），本报告确认裁剪结论仍成立。

# 验收报告 — CR-2026-009（P2 三模式聊天 CR-D）

## 0. 摘要

5 个开发任务全部完成并提交到 `requirement/CR-2026-009` 分支（commit 59b4c9063，multica worktree）。
**代码级验证全绿**：后端 `go build ./...` + `go vet ./...`；前端 `tsc --noEmit`（core/views 我方新
代码零报错，唯一报错为 `modals/quick-create-issue.test.tsx` 的预置无关问题，已核实同一 commit
下 main 分支同样报错）；新增 Go 测试 3 个文件（触发豁免负向/回归、8 处排除谓词、ensure 容器并发/
幂等/parity）+ 前端测试 2 个文件（DiscussionPane、ContainerJumpBanner）全绿；`pnpm --filter
@multica/views test` 全量 1782 项、`@multica/core test` 全量 793 项、locale parity 160 项，均通过。

**真机 E2E**：本轮在隔离 worktree（独立 postgres 库 `multica_cr_2026_009_368`、独立后端 18448、
独立前端 13368）跑通完整用户旅程——注册→onboarding→建工作区→建项目→打开 Discussion tab→发送
消息→DB 级核对红线——详见 §2。与 CR-2026-006 报告不同，本 CR 不依赖 daemon runtime（Discussion
本身不驱动 agent），因此没有"待 daemon 环境"的遗留项。

**migration 161 down→up 往返演练**：在挂有真实数据（discussion 容器 + 1 条评论）的隔离库上完整
执行，验证通过，详见 §2 附录。代码评审 SUG-002 已关闭。

**唯一待补项**：跨用户 @提及通知的真机验证（需要两个真实浏览器会话，本轮单用户会话内未覆盖，
见 AC-2），不阻塞交付。

## 1. 逐 AC 验收结果

| AC | 判定 | 证据 / 说明 |
|---|---|---|
| **AC-1** 多人实时（发送即上屏/刷新回放） | ✅ **真机通过** | 真机浏览器发送消息后同页立即渲染（WS `comment:created` 直写缓存，无需手动刷新）；导航离开 Team Agent tab 再返回 Discussion，历史消息完整回放（"2 分钟前"时间戳证持久化非本地状态）。跨浏览器多用户并发验证受限于单会话环境，未覆盖（DiscussionPane 组件测试已覆盖多条消息渲染逻辑）。 |
| **AC-2** 提及通知跳转 | ⚠️ 组件级 | `ContainerJumpBanner` 组件测试覆盖两种 mode 的文案 + 跳转 href 正确性；`inbox-page.tsx` 的 origin_type 判定分支（渲染跳转条替代裸 IssueDetail）逻辑随 `IssueResponse.OriginType` 新增字段一并验证（go build/vet 通过，字段序列化路径由既有 issueToResponse 测试路径覆盖）。**跨用户 @提及触发 inbox 通知的端到端链路需要第二个真实用户会话，本轮单用户测试未覆盖**，标注为待补。 |
| **AC-3（红线）** Discussion 消息零 `agent_task_queue` 行 | ✅ **真机 DB 级通过** | 真机发送 Discussion 消息后，`SELECT count(*) FROM agent_task_queue` = **0**（整库范围，非仅本项目）；同时 `TestComputeCommentAgentTriggers_DiscussionContainerNeverEnqueuesAgent`（4 个触发分支：@agent 提及/@squad 提及/回复 agent 评论/squad-assigned 容器上的 agent 作者评论）+ 回归子测试（普通 Issue 上 @agent 提及仍正常触发，证豁免不外溢）全部通过。 |
| **AC-4（红线）** 容器 Issue 隐藏 | ✅ **真机 + 单测双重通过** | 真机：workspace 的 Issues 列表页 body 全文本搜索确认 "Team Agent Chat"/"Discussion" 两个容器标题均不出现，仅显示真实业务 Issue；`TestDiscussionContainerExcludedFromSqlcQueries`（ListIssues/ListOpenIssues/CountIssues/CountIssuesByProject/GetProjectIssueStats 五个 sqlc 查询点）+ `TestDiscussionContainerExcludedFromHTTPListingSurfaces`（GET /api/issues、/api/issues/grouped、/api/issues/search 三个手写 SQL 端点，含**全局搜索按 comment 内容命中 token 不泄漏容器**的关键场景）全部通过，覆盖 SDD §4.1 列出的全部 8 处排除谓词。容器唯一性：`TestEnsureProjectDiscussionIssue_ConcurrentFirstOpenCollapsesToOneRow`（8 并发调用者 collapse 到 1 条记录）+ 真机重复进入 Discussion tab 未重复创建（同一 issue_id 稳定）。 |
| **AC-5** 输入区纯人类形态 + 草稿独立持久化 | ✅ **真机 + 单测通过** | 真机：Discussion 面板输入区实测仅两个交互按钮（"添加附件"、send），无模式/模型/技能下拉、无停止按钮；`DiscussionPane` 组件测试覆盖发送流程（编辑器清空、submitComment 参数正确）与空态渲染。草稿命名空间复用 `CommentDraftKey`（`new:${issueId}`），容器 issueId 天然按项目隔离，未新建 project-chat-store 字段（SDD DD-6 定案）。 |
| **AC-6** 回归（parity + Team Agent 面/评论/浮窗不受影响） | ✅ **代码级 + 真机通过** | locale parity 160 项全绿；`@multica/views` 全量 1782 项、`@multica/core` 全量 793 项无回归；Go `internal/handler`/`internal/service` 除两个已核实的、与本 CR 无关的预置失败（`TestParseSkillArchive_RejectsUnsafeSkillMdPath`、`TestShortTaskIDMatchesDaemon`，均在同 commit 的 main 分支上独立复现，Windows 路径分隔符相关的预置环境问题）外全绿。真机：同一项目 Team Agent tab 展示"未配置团队智能体"引导态（正确，非本 CR 引入的回归）；两个容器（`project_chat`/`project_discussion`）在同一项目下并存互不干扰。 |
| **AC-7** 行内系统条 | ➖ **裁剪确认** | SDD §6.3 定案：multica 无 project_member 表（成员是 workspace 级模型），成员变更仅有瞬时 `member:added` WS 广播、无持久化事件流，落地会造成"一次入职刷屏所有项目讨论"的错误作用域，本 CR 裁剪不实现。真机验证期间未发现该结论有误（workspace 级 member 表结构与 SDD 描述一致）。按 PRD AC-7 预留口径，本项按裁剪后范围验收，无遗留代码债。 |

## 2. 真机 E2E 记录（2026-08-02，隔离 worktree 环境）

**环境**：`multica-postgres-1` 共享容器内独立数据库 `multica_cr_2026_009_368`（`init-worktree-env.sh`
生成、migration 161 已 apply）；后端 `go run ./cmd/server`（端口 18448）；前端 `next dev`（端口 13368，
`pnpm --filter @multica/web run dev`）。全程真实 HTTP + 真实浏览器交互（Claude Browser 工具），非
模拟/mock。

### 用户旅程

注册（dev 验证码 `888888`）→ onboarding 5 步（前 3 步跳过、第 4 步建工作区 `cr-2026-009-e2e`、第 5
步跳过 runtime 连接）→ 项目页（`project` 表直接 INSERT 一条测试项目，绕开创建项目弹窗的富文本编辑
器——该编辑器需要浏览器真实 pointer 事件而 Browser 面板未处于可视合成状态，与 Discussion 功能本身
无关，故走等价的 DB 直建路径）→ `?tab=chat&mode=discussion` 深链直达 Discussion tab（**验证 TASK-03
的 `?mode=` 深链特性生效**）→ 发送消息 → 实时上屏 → 刷新/切换 tab 后回放。

### DB 级核对

```sql
-- 容器创建（两种类型并存，互不干扰）
SELECT id, origin_type, title FROM issue WHERE project_id='<test-project>';
--  3b954b9a-... | project_chat       | Team Agent Chat
--  621c6b03-... | project_discussion | Discussion

-- 消息落在正确容器上
SELECT c.content, i.origin_type FROM comment c JOIN issue i ON i.id=c.issue_id
  WHERE i.project_id='<test-project>';
--  "Hello team, let's kick off the discussion!" | project_discussion

-- 红线核对：整库 agent_task_queue 为空
SELECT count(*) FROM agent_task_queue;
--  0
```

### 前端断言

- Discussion tabpanel 文本内容含新增的 `chat.discussion.sub` 文案（"发送消息开始讨论。"），证四语
  文案正确接入且渲染路径命中。
- 输入区按钮清单：`["添加附件", "discussion-send"]`（去除全局 UI 噪音后），无模型/技能/停止控件。
- Issues 列表页全文本不含任一容器标题。
- 控制台报错逐条核对：全部为 `TeamAgentSetupPicker`/`PropertyPicker`（CR-2026-006 既有代码）的
  按钮嵌套 hydration 警告，与本 CR 改动无关；无 Discussion 相关报错。

### migration 161 down→up 往返演练（2026-08-02 补充）

针对代码评审 SUG-002（down 迁移未做真机往返验证），在同一隔离数据库（含真机 E2E 产生的真实
discussion 容器 + 1 条评论）上直接执行 down.sql / up.sql 内容（绕开 `cmd/migrate` 工具——该工具
的 `down` 模式会反向执行**全部**已应用迁移而非单步回滚，不适合单迁移演练）：

| 步骤 | 检查 | 结果 |
|---|---|---|
| down 前 | discussion 容器 issue 存在 + 挂 1 条 comment | 1 issue / 1 comment |
| 执行 down.sql | `DELETE FROM issue WHERE origin_type='project_discussion'` | `DELETE 1` |
| down 后 | discussion issue 行数 | **0** |
| down 后 | 原评论是否变孤儿（`comment.issue_id` FK 是 `ON DELETE CASCADE`） | **0**（随 issue 级联删除，非孤儿） |
| down 后 | CHECK 约束是否正确剔除 `project_discussion` | ✅ 剔除，值列表退回 149/160 状态 |
| down 后 | 唯一索引 `issue_project_discussion_unique` 是否移除 | ✅ 已移除 |
| down 后 | 无关容器 `project_chat`（migration 160）是否被误伤 | 0 行受影响，1 条 project_chat 容器原样保留（证 down 范围精确，非连带清空） |
| 执行 up.sql | 重新 ALTER 约束 + CREATE INDEX | 成功 |
| up 后 | CHECK 约束恢复含 `project_discussion` | ✅ |
| up 后 | 唯一索引恢复 | ✅ |
| up 后 | 可再次创建新 discussion 容器 | ✅ 成功插入 |
| up 后 | 唯一索引仍生效（第二次同项目插入应拒绝） | ✅ `duplicate key value violates unique constraint` |
| 收尾 | 重跑本 CR 全部 Go discussion 测试（`TestDiscussionContainerExcludedFrom*`、
  `TestComputeCommentAgentTriggers_DiscussionContainerNeverEnqueuesAgent`、`TestGetProjectDiscussion`） | 全部 PASS，DB 恢复到与往返演练前等价的可用状态 |

**结论**：down.sql 的"先 DELETE 再收紧约束"顺序（吸取 migration 160 down 脚本未做级联删除、
在容器已有数据时会直接失败的教训）在真实 CASCADE 场景下验证正确；up/down 均具备幂等性和范围
精确性（不影响其他容器类型）。SUG-002 关闭。

## 3. 已知偏离与限制

1. **AC-2 跨用户验证未覆盖**：单浏览器会话无法模拟"用户 B 收到用户 A 的 @提及通知"，需要第二个
   真实账号 + 第二个浏览器会话。落点组件（跳转条文案/href）已由单测覆盖，逻辑正确性有较高置信度，
   但完整链路（评论创建 → notifyMentionedMembers → inbox 出现 → 点击跳转条 → 落对应 tab）的真机
   验证建议在多用户测试环境或部署前补齐。
2. **create-project 弹窗的富文本标题编辑器未走真机 UI 路径**：Browser 面板在当前会话中未处于可视
   合成状态（`getBoundingClientRect()` 返回全零），导致依赖真实坐标的 pointer 事件（点击 TipTap
   contenteditable）无法可靠触发；改用等价的 DB 直建项目，不影响 Discussion 功能本身的验证有效性
   （项目创建流程是既有功能，非本 CR 改动范围）。
3. **两个预置失败与本 CR 无关**（已在 main 分支同 commit 复核确认独立复现）：
   - `TestParseSkillArchive_RejectsUnsafeSkillMdPath`（`skill_import_archive_test.go`）
   - `TestShortTaskIDMatchesDaemon`（`agent_work_dir_test.go`，Windows 路径分隔符 `\` vs `/` 断言问题）

## 4. 结论

代码实现完整，两条验收红线（AC-3 零 agent 触发、AC-4 容器隐藏）均已在真机 + DB 级、单测双重验证
下确认成立。AC-1/AC-5/AC-6 真机验证通过。AC-7 裁剪结论复核有效、无遗留代码债。migration 161 的
down→up 往返在真实数据上验证通过（SUG-002 关闭）。AC-2 的跨用户链路建议作为部署前独立验收项补齐
（不阻塞本 CR 交付，落点组件本身已验证正确）。建议进入 code-review。
