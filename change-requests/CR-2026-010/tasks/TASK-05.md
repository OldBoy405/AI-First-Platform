---
id: CR-2026-010-TASK-05
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: presenter 数据层（schemas/client/queries/mutations）+ chatHeader 主持人显示
slug: presenter-data-layer-header
status: done
estimate: 3h
depends-on: [CR-2026-010-TASK-02, CR-2026-010-TASK-04]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
---

## 实现状态（2026-08-02）

代码已在 multica worktree（`requirement/CR-2026-010`，commit `2563e65c1`）落地：
`schemas.ts` 的 `ProjectPresenterGrantSchema`/`ProjectPresenterStateSchema`
（均 `.loose()`，对齐 `ProjectChatSchema` 写法）+ `EMPTY_*` 兜底；`client.ts` 的
`getProjectPresenter` + 6 个 POST（全部经 schema 解析后返回，不直接强转裸 JSON，
符合 CLAUDE.md API 兼容性规则）；`queries.ts` 的 `projectPresenterOptions`
（WS 侧确认 `project:presenter_changed` 与既有 `project:` 前缀失效路径天然
命中，未加任何新代码）；`mutations.ts` 的 6 个非乐观 mutation（`onSettled`
同时 invalidate presenter 与 chat 两个 query key）；`project-chat-panel.tsx`
的 `PresenterHeader`（挂 TabsList 右侧空位，仅 Team Agent tab 显示；空态显示
「Owner/Admin」，非空显示「当前主持人：{{name}}」；一个占位控制按钮，
本地 useState，面板本体归 T06）。

**范围偏差说明**：locale 侧新增了 `locales/parity.test.ts` 强校验四语 key
一致（本任务开工前未预料到有这道门禁），迫使 5 个 inbox presenter_* type
与 3 个 chat.presenter.* key 提前补齐 ja/ko/zh-Hans 译文（而非按原计划全部
留给 T06）——T06 仍可精修措辞，但不能让门禁一直红着。

**已验证**：`pnpm --filter core --filter views typecheck` 全绿（一个预置且
未改动的 `modals/quick-create-issue.test.tsx` 失败无关）；`packages/core`
全量套件 805/805 绿，`packages/views` 全量套件 1777/1777 绿（含新增
`PresenterHeader` 渲染测试 3 个覆盖两态+tab 作用域、`mutations.test.tsx`
新增 12 个覆盖 6 个 mutation 的成功/失败路径，均断言双 query key invalidate）。

## 任务描述

在 multica 前端落地 SDD §5.1/§5.2：presenter 的数据层契约（schema/client/query/mutation）与
头部「当前主持人」显示。这是 T06（面板/通知卡/拒绝态）的共同前置。

## 涉及文件

- `packages/core/api/schemas.ts`：`ProjectPresenterState` schema
  `.loose()`（对齐 `ProjectChatSchema` :338-354 的写法）+ `EMPTY_PROJECT_PRESENTER_STATE`
  兜底；字段对齐 T02 的响应体 `{presenter, pending_requests, my_request}`。
- `packages/core/api/client.ts`：`getProjectPresenter` + 6 个 POST
  （`requestPresenter/approvePresenter/rejectPresenter/transferPresenter/revokePresenter/
  releasePresenter`），沿 `getProjectChat`/`sendProjectChatMessage`（:1967-1995）的
  `parseWithFallback(raw, Schema, EMPTY, {endpoint})` 模式。
- `packages/core/projects/queries.ts`：`projectPresenterOptions(wsId, projectId)`，
  queryKey 挂 `projectKeys` 树下（利用既有 `project:` 前缀失效自动覆盖，无需新增 WS handler）。
- `packages/core/projects/mutations.ts`：6 个 mutation，形状照抄
  `useSendProjectChatMessage`（:62-89）；**非乐观**（跨用户权限数据，遵循
  `use-realtime-sync.ts:106-122` 的红线：presenter 归属是权限语义，不做客户端乐观直写）；
  成功后 `onSettled` 同时 invalidate presenter query 与 chat query（转移可能影响发送权限态）。
- `packages/core/projects/index.ts`：统一 re-export 新增的 options/mutations。
- `packages/views/projects/components/project-chat-panel.tsx`：`:74` 的
  `<TabsList variant="line">` 行右侧空位（TabsTrigger 均 `flex-none`，右侧天然留白）加
  `PresenterHeader` 组件：`ActorAvatar(size="sm")` + `useActorName()` 取名字 + 「当前主持人」
  label；`presenter=null` 时显示口径文案（`chat.presenter.default`，对应 Owner/Admin 隐式态）；
  右侧一个 icon 按钮作为控制面板开关入口（面板本体归 T06，本任务只放置触发按钮，onClick
  先留 TODO 或本地 useState 占位）。

## 实现要点

- schema `.loose()` 是 CR-A 既有的向后兼容写法（后端先发新字段不炸前端），presenter 字段
  沿用同一模式，不引入新的 parse 策略。
- 数据源全部走 `projectPresenterOptions`，WS 侧无需任何新代码——`project:` 前缀失效
  （`use-realtime-sync.ts:469-472`）已覆盖 `project:presenter_changed` 事件（T04 已发布该事件，
  前缀匹配自动生效）。
- `PresenterHeader` 只做展示 + 开关触发，不含面板内容——面板本体（Sheet + 成员列表 + 操作
  按钮）是 T06 的独立交付物，两者通过一个 `open`/`onOpenChange` 的受控 prop 或轻量 zustand
  slice 衔接（实现时任选，不强制具体机制）。

## 验收条件

1. `projectPresenterOptions` 的 mock 数据驱动测试：presenter 非空/为空两态下 `PresenterHeader`
   渲染文案正确。
2. 6 个 mutation 的成功/失败路径单测（沿 `project-chat-panel.test.tsx`/
   `project-team-agent-chat.test.tsx` 的 stub 模式）。
3. WS 事件到达后（模拟 `project:presenter_changed` 消息）头部文案在无手动刷新下更新
   （利用 `use-realtime-sync.ts` 的既有前缀失效路径，测试只需验证 query invalidate 触发）。

## 完成标志

上述测试全绿；`tsc` 零报错；头部按钮可点击（面板内容留待 T06，占位不报错）。
