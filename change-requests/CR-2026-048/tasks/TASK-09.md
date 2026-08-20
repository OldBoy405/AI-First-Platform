---
id: CR-2026-048-TASK-09
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: Market 前端：排行/元数据卡/发布确认/申诉流
slug: market-frontend
status: pending
estimate: 14h
depends-on: [CR-2026-048-TASK-07, CR-2026-048-TASK-08]
created: 2026-08-20T14:32:57+08:00
---

# TASK-09 Market 前端

## 任务描述

在既有 `SkillsPage`/`SkillDetailPage` 上扩展 Market 能力：列表排行与筛选、详情页元数据卡与版本、发布确认框、申诉流。不新开页面/路由。SDD §1、§3.3。

## 涉及文件 / 模块

- `packages/core/api/client.ts`（增 market/publish/appeal 方法）、`packages/core/types/skill.ts`（增类型，snake_case wire → camelCase 域模型，沿用既有边界）
- `packages/views/skills/components/skills-page.tsx`（改：visibility 筛选 + 排行列 + session-export 筛选）
- `packages/views/skills/components/skill-detail-page.tsx`（改：四字段使用说明卡 + version + 运行时要求标签 + 发布按钮/确认框 + 申诉面板）
- `packages/views/locales/*/skills.json`（增文案）

## 实现要点

- 复用既有 `SkillList`/`SkillDetailPage` 结构与 Dialog 组件；发布确认框文案含"发布 = 授权团队复用该工作方法"。
- 元数据卡四字段 + 运行时要求标签 + `source: session-export` 均来自后端已解析数据（经 API），前端不另写 frontmatter 解析。
- 422 响应渲染 `reasons`/`findings`（findings 的 excerpt 已脱敏，直接展示）；申诉提交/决定调 TASK-07 两端点，非 owner 决定按钮不可见（按 403 回退隐藏）。
- 排行用 `usage_count` 列，builtin 与 workspace 同榜（不同 badge）。

## 验收条件

1. （AC-12/AC-13）Market 列表：org Skill 显示 version 与 usage_count；builtin 可上榜；private 不出现；session-export 筛选只留带标记的。
2. （AC-12）详情页：四字段使用说明卡、version、运行时标签渲染（无法识别的要求不报错）；发布确认框含“发布 = 授权”语义。
3. （AC-2）作者更新 `version` 后，列表与详情页均展示新版本号（纯展示，不影响任何内容判定）。
4. （AC-10/AC-11）含密钥发布 → 弹 findings（含行号、脱敏 excerpt、申诉入口）；Owner 放行后重发成功；非 Owner 无 decide 按钮。
5. `pnpm -C packages/core typecheck` + `pnpm -C packages/views typecheck` + 相关 `vitest` 全绿。

## 完成标志

typecheck + vitest 全绿 + 上述 3 条手测/组件测试通过。

## 接口契约

- 消费：`GET /api/skills/market`（TASK-08）、`POST /api/skills/{id}/appeals[/decide]`（TASK-07）、`UpdateSkill` 的 422 契约（TASK-07）。
- 产出：无跨 TASK Go 符号；前端 `core` 导出 `fetchSkillMarket`/`submitSkillAppeal`/`decideSkillAppeal`/`updateSkillVisibility` 等方法供 views 使用。
