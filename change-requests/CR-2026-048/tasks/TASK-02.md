---
id: CR-2026-048-TASK-02
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: redact 扩展：Findings 定位入口 + 第 17 条个人路径模式
slug: redact-findings
status: pending
estimate: 6h
depends-on: []
created: 2026-08-20T14:32:57+08:00
---

# TASK-02 redact 扩展

## 任务描述

在 `server/pkg/redact` 增加 `Findings` 定位入口与第 17 条个人路径模式，供发布门禁（TASK-04）拦截时返回"第几行命中了什么"。**必须与 `Text()` 共用同一个 `patterns` 变量，不平行第二份正则表**。SDD §4.4。

## 涉及文件 / 模块

- `server/pkg/redact/redact.go`（改：`secretPattern` 加 `name`、16 条补 name、新增第 17 条、新增 `Finding`/`Findings`）
- `server/pkg/redact/redact_test.go`（改/增）

## 实现要点

- `type Finding struct { PatternID string; Line int; Excerpt string }`，`func Findings(s string) []Finding`：按 `strings.Split(s, "\n")` 逐行跑 patterns 的 `FindStringIndex` 取 1-based 行号；`Excerpt = Text(line)` 截断 ≤120 字符（复用 `Text()`，响应天然无明文，NFR-4）。
- `secretPattern` 增加 `name string` 字段；16 条既有模式各补唯一 name（`aws_access_key_id`、`aws_secret`、`pem_private_key`、`github_token`、`github_fine_grained_pat`、`openai_anthropic_key`、`slack_token`、`slack_app_token`、`gitlab_token`、`google_api_key`、`stripe_key`、`jwt`、`bearer`、`connection_string`、`generic_credential`……照既有注释命名，缺一不可）。
- 第 17 条 name=`personal_path`：覆盖 `/Users/<x>`、`C:\Users\<x>`、`/home/<x>`（正则 `(?i)(?:/Users/|C:\\Users\\|/home/)[A-Za-z0-9._-]+`）。
- `patterns` 保持未导出；不改变 `Text()` 的既有输出（既有 redact_test 不得回归）。

## 验收条件

1. （AC-10）`Findings` 对含 `ghp_xxx` 与 `C:\Users\alice\` 的两行输入，返回两条 Finding，`Line` 分别指向正确行、`PatternID` 为 `github_token`/`personal_path`、`Excerpt` 含 `[REDACTED ...]` 且不含明文密钥。
2. （AC-10）新增测试断言 `len(patterns)==17` 且所有 `name` 唯一非空（防平行正则表）。
3. `go test ./pkg/redact/ -v` 全绿；既有 `Text()` 行为不回归。

## 完成标志

`go test ./pkg/redact/ -v` 通过，17 条 name 唯一非空测试通过。

## 接口契约

- 消费：无（根任务）。
- 产出：`redact.Finding{PatternID string; Line int; Excerpt string}`、`redact.Findings(s string) []Finding`——供 TASK-04 门禁引用。
