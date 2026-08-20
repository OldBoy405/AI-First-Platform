---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-07
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: 发布门禁接线 + 申诉两端点 + runtime-local 覆盖重扫
slug: publish-appeal-endpoints
status: pending
estimate: 10h
depends-on: [CR-2026-048-TASK-04, CR-2026-048-TASK-05]
created: 2026-08-20T14:32:57+08:00
---

# TASK-07 发布/申诉端点接线

## 任务描述

把门禁接进唯一写入口 `UpdateSkill`，新增申诉提交/决定两端点，并让 runtime-local 覆盖导入路径同样重扫。SDD §3.1、§3.3。

## 涉及文件 / 模块

- `server/internal/handler/skill.go`（改：UpdateSkillRequest 加三字段 + UpdateSkill 门禁接线）
- `server/internal/handler/skill_appeal.go`（新建：SubmitSkillAppeal / DecideSkillAppeal）
- `server/internal/handler/runtime_local_skills.go`（改：覆盖导入路径复用门禁）
- `server/cmd/server/router.go`（改：appeals 两端点挂载进 `/api/skills` 组）
- 对应 `*_test.go`

## 实现要点

- `UpdateSkillRequest` 增加 `Visibility *string`、`OwnerActor *string`、`Version *string`。
- `UpdateSkill` 内、更新 SQL 之前判断门禁触发：`(skill.Visibility=="private" && *req.Visibility=="org") || (skill.Visibility=="org" && (req.Content!=nil || len(req.Files)>0))`。触发时：`contentHash := BuildManifest(...).Hash`（用有效 content + 有效文件构造 `skillbundle.Skill`）；`approved := resolveApprovedAppealIDs(...)`（对每个 pending finding 调 `GetAppealDecision` 构造 map）；`gate := skill.EvaluatePublish(content, files, owner, approved)`。`gate` 有阻断 → 422 `{code:"skill_publish_blocked", reasons, findings, warnings}`，事务回滚；否则正常更新。
- `resolveApprovedAppealIDs`：对 `redact.Findings` 命中项逐个 `AppealID(...)` 后查 `GetAppealDecision`，命中则放行该条。
- 申诉端点：`SubmitSkillAppeal`（`canManageSkill` 权限）body `{file, line, pattern_id}` → 重算 `AppealID`，`HasAppealSubmitted` 幂等检查，`InsertSkillAppealEvent` action=`skill_appeal_submitted`；`DecideSkillAppeal`（workspace owner/admin）body `{appeal_id, approve}` → action=`skill_appeal_approved`/`skill_appeal_rejected`，非 owner/admin 403。
- runtime-local 覆盖导入（`canOverwriteSkillByLocalImport` 路径）改写 org Skill 的 content/files 时，复用同一 `EvaluatePublish`（不新增函数）。
- 三个 action 常量与 `governance.auditActions` 同风格的封闭集合（定义于 `skill_appeal.go`，测试断言只有这三个值可写入）。

## 验收条件

1. （AC-6）name 缺失 / description 缺失，org 发布各返回对应 422 reason，`visibility` 保持 private（失败不部分更新）。
2. （AC-7）无 owner / 缺四字段任一 → 422 且错误指出字段名；齐备后发布成功。
3. （AC-8）frontmatter 结构校验失败 → 422 且 visibility 不变；`permission-declaration` 含 `change-requests/` → 发布**成功**但响应含 protectedPaths 警告（不阻断、不改写声明）。
4. （AC-10）org Skill 更新 content 含密钥 → 422 带 file/line/pattern_id（发布后重扫）；仅改 version/描述 → 正常放行。
5. （AC-11）非 owner/admin 调 decide → 403；author 提交 appeal 幂等（同 appeal_id 第二次 no-op，行数不增）；owner 放行后同内容重新发布通过；**改变 content 后旧 appeal 失效、仍被拦**。
6. （AC-2）改内容不改 `version`：服务端以 `BuildManifest().Hash` 变化判定内容已变（重扫触发）；改 `version` 不改内容：hash 不变、不触发重扫；代码中不存在任何以 `version` 值比较作为内容变更依据的分支（diff 为证）。
7. （AC-9）代码中不存在针对 builtin 的可编辑性特判分支（无 `is_builtin` 类字段/分支，diff 为证）；尝试编辑内置 Skill 因其在 `skill` 表无行而自然 404/失败。
8. （AC-10）runtime-local 覆盖导入含密钥的 org Skill → 被拦。

## 完成标志

`go test ./internal/handler/ -run 'SkillPublish|SkillAppeal|LocalSkill.*Overwrite' -v`（按实际命名）全绿，且 AC-2/AC-6/AC-7/AC-8/AC-9/AC-10/AC-11 逐条有对应用例。

## 接口契约

- 消费：`skill.EvaluatePublish`/`AppealID`/`ProtectedPaths`（TASK-04）、`db.InsertSkillAppealEvent`/`GetAppealDecision`/`HasAppealSubmitted`/`UpdateSkill`（TASK-05）、`skillbundle.BuildManifest(...).Hash`（既有）。
- 产出：`UpdateSkillRequest{Visibility,OwnerActor,Version *string}`；HTTP `POST /api/skills/{id}/appeals`、`POST /api/skills/{id}/appeals/decide`；422 响应契约 `{code:"skill_publish_blocked", reasons[], findings[{file,line,pattern_id,excerpt}], warnings[]}`——供 TASK-09 前端消费。
