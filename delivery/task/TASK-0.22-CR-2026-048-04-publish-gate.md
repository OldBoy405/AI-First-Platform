---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-04
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: 发布门禁纯函数 PublishGate + AppealID 哈希
slug: publish-gate
status: pending
estimate: 8h
depends-on: [CR-2026-048-TASK-02, CR-2026-048-TASK-03]
created: 2026-08-20T14:32:57+08:00
---

# TASK-04 发布门禁纯函数

## 任务描述

新建纯函数包 `internal/skill/publish_gate.go`，把发布校验（frontmatter 必填、owner、元数据卡四字段、敏感扫描、protectedPaths 警告、申诉放行）收敛为一个可测试函数。handler 只负责调用，不做业务判断。SDD §4.2、§3.2。

## 涉及文件 / 模块

- `server/internal/skill/publish_gate.go`（新建）
- `server/internal/skill/publish_gate_test.go`（新建）

## 实现要点

```go
type PublishReason string
const (
    ReasonFrontmatterNameMissing PublishReason = "frontmatter_name_missing"
    ReasonFrontmatterDescriptionMissing PublishReason = "frontmatter_description_missing"
    ReasonOwnerMissing PublishReason = "owner_actor_missing"
    ReasonMetadataFieldMissing PublishReason = "metadata_field_missing" // 附字段名，见 GateResult
)
type PublishWarning string // WarningProtectedPaths = "permission_declaration_touches_protected_paths"
type GateResult struct {
    Reasons      []string          // 含字段名细化，如 "metadata_applicable-scenarios_missing"
    Findings     []redact.Finding  // 去重后；已按 approved 过滤
    Warnings     []PublishWarning
}
func EvaluatePublish(content string, files map[string]string, ownerActor string, approved map[string]bool) GateResult
func AppealID(skillRef, contentHash, file string, line int, patternID string) string // sha256 hex，std 库 crypto/sha256
var ProtectedPaths = []string{"change-requests/", "specs/", "delivery/", "docs/", "dir-graph.yaml", "AGENTS.md"}
```

- 四字段常量：`applicable-scenarios`/`context-dependencies`/`permission-declaration`/`failure-handling`。
- 扫描范围 = content + 全部 skill_file 内容（超集扫描）；findings 逐条构造 `AppealID(...)`，命中 `approved` 则剔除。
- `contentHash` 由 handler 用 `skillbundle.BuildManifest(skill).Hash` 计算后传入（本 TASK 不 import skillbundle 的类型，只接收字符串——保持纯函数无 DB/无 service 依赖）。
- `ProtectedPaths` 常量注释标明权威源 tools `rules.json#protectedPaths.deny`；测试与 tools 清单对拍（测试内硬编码 tools 现状路径列表）。

## 验收条件

1. 空 name/空 description/空 owner/缺任一四字段 → 对应 reason；四字段齐 + owner 齐 + 无 finding → `GateResult` 空且无阻断。
2. content 或任一 file 含 `ghp_xxx` → Findings 含 github_token；含 `C:\Users\a\` → personal_path；Excerpt 无明文。
3. `permission-declaration` 含 `change-requests/` → Warnings 含 protectedPaths；不含则无。
4. 同一 finding 的 AppealID 在 approved 中 → 从 Findings 剔除；AppealID 对同一输入确定性、对不同 contentHash 不同。

## 完成标志

`go test ./internal/skill/ -run PublishGate -v` 全绿（表驱动覆盖所有 reason 与扫描/放行分支）。

## 接口契约

- 消费：`redact.Findings`/`redact.Finding`（TASK-02）、`skill.SkillMetadata`/`ParseSkillMetadata`（TASK-03）、`contentHash string`（由 handler 经 `skillbundle.BuildManifest` 算好传入）。
- 产出：`skill.EvaluatePublish(content string, files map[string]string, ownerActor string, approved map[string]bool) GateResult`、`skill.AppealID(...) string`、`skill.ProtectedPaths`、`skill.PublishReason`/`PublishWarning`——供 TASK-07 接线。
