---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-03
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: frontmatter 扩展：ParseSkillMetadata 提取元数据卡字段
slug: skill-metadata-parse
status: pending
estimate: 4h
depends-on: []
created: 2026-08-20T14:32:57+08:00
---

# TASK-03 frontmatter 扩展

## 任务描述

扩展 `internal/skill/frontmatter.go`，在既有泛型 map 解码基础上新增 `ParseSkillMetadata`，一次性提取 name/description 与全部标量字段（元数据卡四字段、`source`、requirements 等），供门禁与前端使用。SDD §3.4。

## 涉及文件 / 模块

- `server/internal/skill/frontmatter.go`（改）
- `server/internal/skill/frontmatter_test.go`（改/增）

## 实现要点

- 新增 `type SkillMetadata struct { Name string; Description string; Fields map[string]string }`，`func ParseSkillMetadata(content string) SkillMetadata`：复用既有 `frontmatterPattern` + `coerceFrontmatterValue`，把解码后的 `map[string]any` 中每个标量（nil→""，string→原值，其他 scalar→literal，序列/映射→JSON）塞进 `Fields`；`Name`/`Description` 取 `Fields["name"]`/`Fields["description"]` 并 `TrimSpace`。
- 既有 `ParseSkillFrontmatter(content) (name, description string)` 改为薄包装调用 `ParseSkillMetadata`，签名与返回值不变（现有调用方零改动）。
- 零新解析库、零新列。

## 验收条件

1. （AC-7/AC-13）带 `applicable-scenarios`/`context-dependencies`/`permission-declaration`/`failure-handling`/`source: session-export` 的 frontmatter，`ParseSkillMetadata` 五个字段全部按原值落进 `Fields`。
2. 缺 frontmatter / malformed YAML 返回空 `Fields` 不 panic；块标量 `description: |` 的尾换行被 Trim。
3. `ParseSkillFrontmatter` 既有测试全绿（行为不变）。

## 完成标志

`go test ./internal/skill/ -v` 通过，新旧函数测试齐。

## 接口契约

- 消费：无（根任务）。
- 产出：`skill.SkillMetadata{Name, Description string; Fields map[string]string}`、`skill.ParseSkillMetadata(content string) SkillMetadata`——供 TASK-04 门禁与 TASK-09 前端（经 API）消费。
