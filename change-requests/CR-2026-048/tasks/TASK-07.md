---
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

1. name 缺失 / 无 owner / 缺四字段任一 / content 含密钥，org 发布各返回对应 422 reason，`visibility` 不变。
2. org Skill 更新 content 含密钥 → 422（发布后重扫）；仅改 version/描述 → 正常放行。
3. 非 owner/admin 调 decide → 403；author 提交 appeal 幂等（同 appeal_id 第二次 no-op）；owner 放行后同内容重新发布通过。
4. runtime-local 覆盖导入含密钥 → 被拦。

## 完成标志

`go test ./internal/handler/ -run 'SkillPublish|SkillAppeal|LocalSkill.*Overwrite' -v`（按实际命名）全绿。

## 接口契约

- 消费：`skill.EvaluatePublish`/`AppealID`/`ProtectedPaths`（TASK-04）、`db.InsertSkillAppealEvent`/`GetAppealDecision`/`HasAppealSubmitted`/`UpdateSkill`（TASK-05）、`skillbundle.BuildManifest(...).Hash`（既有）。
- 产出：`UpdateSkillRequest{Visibility,OwnerActor,Version *string}`；HTTP `POST /api/skills/{id}/appeals`、`POST /api/skills/{id}/appeals/decide`；422 响应契约 `{code:"skill_publish_blocked", reasons[], findings[{file,line,pattern_id,excerpt}], warnings[]}`——供 TASK-09 前端消费。
