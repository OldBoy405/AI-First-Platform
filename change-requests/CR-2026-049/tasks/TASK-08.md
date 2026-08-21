---
id: CR-2026-049-TASK-08
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: 声明与生成器 — commit_prefixes 白名单 + config_gen.go
slug: commit-prefix-declaration-generator
status: pending
estimate: 8h
depends-on: []
created: 2026-08-20T20:59:46+08:00
---

# TASK-08 — 声明与生成器：commit_prefixes 白名单 + config_gen.go

## 1. 任务描述

knowledge-base `dir-graph.yaml` 为三仓写入已核实的 `remote` 与 `commit_prefixes`（SDD §3.3 锁定值）；multica 新增严格生成器 `generate-prefixes.mjs`（照抄 `maturity/gen/generate-config.mjs` 模式），产出只读 Go 副本 `config_gen.go`（文件头记源 SHA），`--check` 漂移非零；coverage fixture 校验三仓 trunk 最近 200 条 subject 全部可分类（SDD §3.3，TD-B5）。

## 2. 涉及文件 / 模块

- knowledge-base：`dir-graph.yaml#repositories[].remote/commit_prefixes`
- `server/internal/commitprefix/gen/generate-prefixes.mjs`
- `server/internal/commitprefix/config_gen.go`（生成，提交入库）
- `server/internal/commitprefix/config.go`（DTO 与访问器）
- generator 测试 fixture（三仓 subject 样本、--check 漂移、非法声明行）

## 3. 实现要点

- remote 使用已核实值：`OldBoy405/AI-First-Platform`（master）、`OldBoy405/AI-First-multica`（main）、`OldBoy405/AI-First-tools`（custom/main）。
- 前缀采用大小写敏感 `strings.HasPrefix`；值含分隔符（`feat(` 不误匹配 `feature`）；`wip:` 是优先分类保留字，不进入合法白名单。
- 生成器：只解析 `repositories[].id/remote/trunk/commit_prefixes`；行级解析，未知结构硬错误（纪律 #1）；要求源文件相对 HEAD clean；源 SHA = `git log -1 --format=%H -- dir-graph.yaml`。
- `GeneratedPrefixes() map[string]RepoPrefixDecl`、`GeneratedConfigRev() string`；`RepoPrefixDecl{ID, CanonicalURL, Owner, Repo, Trunk string, Prefixes []string}`。
- CI 采用独立 generator-sync job（显式 checkout KB 源 SHA）；multica 普通 build 不 checkout KB；pre-commit 传 `--source`。

## 4. 验收条件

1. 三个 `repositories[]` 均有非空 `commit_prefixes` 且与 SDD §3.3 一致；`wip:` 不在白名单内。
2. 三仓 trunk 最近 200 subject coverage fixture 全匹配或每项显式归类为预期 finding（人工分类记录进 fixture 注释）。
3. 改声明后 `--check` 非零；非法声明行（未知字段/空前缀）生成器非零退出；`config_gen.go` 头含源 SHA。

## 5. 完成标志

knowledge-base 声明与生成副本一致；`--check` 干净；coverage fixture 全绿；普通 build 无 KB checkout。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：
  - `commitprefix.GeneratedPrefixes() map[string]RepoPrefixDecl`、`GeneratedConfigRev() string`、`RepoPrefixDecl`（供 TASK-09/10 消费）。
  - knowledge-base `dir-graph.yaml` 声明（E5 单一事实源）。
