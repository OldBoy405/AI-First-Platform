---
id: CR-2026-010-TASK-06
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: chatControlPanel 权限面板 + 消息流通知卡 + 拒绝呈现 + 四语文案
slug: presenter-panel-notices-i18n
status: pending
estimate: 6h
depends-on: [CR-2026-010-TASK-05]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
---

## 任务描述

在 multica 前端落地 SDD §5.3/§5.4/§5.5/§5.6：presenter 控制权面板、消息流内六种通知卡、
非 presenter 发送被拒的输入区呈现、以及全部新增文案的四语落地。

## 涉及文件

- `packages/views/projects/components/project-chat-panel.tsx`（或同目录新文件
  `presenter-control-sheet.tsx`）：受控 `<Sheet side="right">`（照抄
  `project-detail.tsx:597-603` 的 mobile Sheet 写法——已核实聊天面板内无既有成员抽屉可复用）。
  内容：
  - 成员列表 = workspace 成员（`memberListOptions`，已核实无项目级成员概念），行结构照抄
    `members-tab.tsx:74-182` 的 `MemberRow`（`ActorAvatar` + 名字 + 角色 `Badge`
    `{owner:Crown, admin:Shield}`）；当前 presenter 行加高亮徽标。
  - 按角色渲染操作：普通成员见「请求 Agent 访问权限」按钮（若 `my_request` 非空 → 显示
    "申请中"禁用态，数据源为 T05 的 `my_request` 字段，对应 TSUG-003 定案）；owner 对
    `pending_requests` 中每行见 批准/拒绝 按钮、对 active 行见 撤销；presenter 本人见
    转让（选人弹层照抄 CR-A `project-chat-panel.tsx:272-283` 的 `TeamAgentSetupPicker`
    PropertyPicker 骨架）与 释放。
  - 面板开关状态不持久化（会话内 `useState`，YAGNI——不接入 `project-chat-store` 持久化）。
- `packages/views/projects/components/project-team-agent-chat.tsx`：
  - `:66-69` 的 timeline filter 放宽：保留既有 `type==="comment" && actor_type==="member"`
    之外，追加 `type==="activity" && action.startsWith("presenter_")` 的条目。
  - `TeamAgentStreamView`（:99-118）合并循环加第三个 for：push
    `{key:"p:"+id, at, node:<PresenterNoticeCard/>}`，既有排序逻辑（`:116`）不动。
  - 新组件 `PresenterNoticeCard`：内联系统状态条样式（居中窄条，icon+文案+时间，比
    `issue-detail.tsx` 的 `ActivityBlock` 骨架更贴聊天语境，对应设计稿提到的 CodeBanana
    系统状态卡形态）；文案从 `chat.notices[action]` 同构字典取（与既有 `chat.tabs[mode]`
    动态索引写法同型），from/to 用户名用 `useActorName()` 插值。
  - `handleSend` 的 code 分支链（:390-405）加 `presenter_required` 分支：复用既有 429
    黄条的位置与样式（:424-439）渲染「当前主持人为 {name}，需请求 Agent 访问权限」+「请求
    权限」按钮（onClick 直调 T05 的 request mutation）；`locked` 计算并入该状态（与 429
    禁用态 or 关系，两者可并存不冲突）。
- `packages/views/issues/components/issue-detail.tsx`：`:984` 的 `NEVER_COALESCE_ACTIONS`
  加入 6 个 `presenter_*` action（防御性一致——容器 Issue 本身被隐藏不会进 issue-detail，
  但保持审计类 action 全局不可合并的一致性）。
- `packages/views/inbox/components/inbox-detail-label.tsx`（及路由跳转逻辑，
  可能在 `inbox-page.tsx` 或类似文件）：**TSUG-002 定案**——5 个 presenter inbox type 的
  点击路由改走 `details.project_id` 深链到项目 Chat tab（`?tab=chat`），不使用默认的
  `issue_id` 路由（默认路由会指向被全入口隐藏的容器 Issue 页，用户点开会是空白/404）。
- `packages/views/locales/{en,ja,ko,zh-Hans}/projects.json`：`chat` 子树新增（沿 CR-A 的
  `chat.stream.*`/`chat.tabs.*` 组织先例）：
  `chat.presenter.{label,default,request_cta,requested,locked_title}`、
  `chat.control.{title,approve,reject,revoke,transfer,release,pending_badge,presenter_badge}`、
  `chat.notices.{presenter_requested,presenter_approved,presenter_rejected,
  presenter_transferred,presenter_revoked,presenter_released}`（六键同构字典，代码内
  `t($ => $.chat.notices[action])` 动态索引）。
- `packages/views/locales/{en,ja,ko,zh-Hans}/inbox.json`：5 个新 inbox type 的展示文案。

## 实现要点

- Sheet 内容与 T05 的头部触发按钮通过 T05 预留的 `open`/`onOpenChange` 衔接，本任务实现
  Sheet 本体与内部交互，不重复造开关状态。
- `chat.notices` 与 `chat.tabs`/`chat.control` 等字典的动态索引写法必须与 CR-A 既有约定
  完全一致（同一 ns 下同构字典 + `[key]` 索引），否则类型推断（`I18nResources` 模块增强）
  报错。
- 四语必须同批提交（`parity.test.ts` 强制 EN⊆L 且 L⊆EN 双向比对），任何遗漏都会让测试红。
- `PresenterNoticeCard` 与既有 `TaskExecutionCard`/`UserBubble` 视觉不同（系统条 vs 消息
  气泡），不要复用消息气泡的容器样式。

## 验收条件

1. 组件测试：面板按角色（普通成员/owner/presenter 本人）渲染的按钮集合正确；「申请中」
   禁用态在 `my_request` 非空时生效。
2. 消息流测试：六种 activity action 各自渲染出对应 `PresenterNoticeCard`，文案与
   `chat.notices[action]` 一致；既有 comment 与工具执行卡渲染不受影响（回归）。
3. 拒绝呈现测试：`presenter_required` 错误码触发禁用 + 提示条 + 请求按钮；与 429 场景
   分别构造，确认两种禁用文案不混淆。
4. `pnpm test locales` / parity 测试全绿（四语 key 集合与既有 ns 一致）。
5. inbox 5 个新类型点击后路由落点为项目 Chat tab（非 Issue 详情页）。

## 完成标志

上述测试全绿；`tsc`/lint 零报错；web 与 desktop（共享 `packages/views`）目视核对面板与
通知卡渲染一致。
