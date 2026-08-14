---
spec-id: ai-first-platform
version: "tbd"
id: CR-2026-032-TASK-03
type: TASK
cr-ref: CR-2026-032
plan-ref: "change-requests/CR-2026-032/plan.md"
sdd-ref: "change-requests/CR-2026-032/sdd.md"
title: 同步 Archive Skill 与 README 业务语义
slug: archive-doc-contract
status: pending
estimate: 4h
depends-on: [CR-2026-032-TASK-02]
created: "2026-08-13T09:52:00+08:00"
---

# TASK-03 同步 Archive Skill 与 README 业务语义

## 1. 任务描述

将 TASK-02 已实现的固定返回和两阶段业务语义同步到直接消费者。输入是 `ArchiveResult` 与 outbox warning 契约；输出是 `cr-archive` Skill、README 及条件性的 crctl 用途表更新。文档必须让使用者理解 authority 已发布与 cleanup-pending 的区别，但不得复制 cleanup 分类、journal phase、lease push 或 ancestry 算法。

## 2. 涉及文件 / 模块

- tools：`skills/cr/cr-archive/SKILL.md`
- tools：`README.md`
- tools：`skills/shared/crctl/SKILL.md`（仅当现有 archive 一行无法表达固定返回/outbox warning 时修改）

## 3. 实现要点

- `cr-archive/SKILL.md` 的结果分类和输出显式透传：`commit`、`lastCleanupError`、`remaining`、`preservedRefs`、`recoverCommand`、`warnings`。
- `cleanup-pending` 表述固定为“终态 authority 已发布，仅安全资源清理未完成”；`lastCleanupError=null` + remaining 非空代表保守保留，非空错误码代表 cleanup 执行异常。
- warning `EMIT_FAILED/archive` 表示实时投影发送失败，不表示 Git archive 失败；禁止指导用户回滚 commit、重建 commit 或手工生成事件。
- README 回写归档流程说明：archive 先发布终态事实，再尝试 cleanup；处理返回现场后只重跑同一 `recoverCommand`。
- 明确禁止手工删除 dirty、unknown、未证明已合入或 `preservedRefs` 中的资源。
- README 不出现 worktree/ref 分类表、journal phase、lease push 重建或 `merge-base` 算法；这些继续由 archive 深模块封装。
- feature-writeback pipeline 节点、参数和 `cr-archive` 调用方式不变。

## 4. 验收条件

1. README 与 Skill 均能回答：archive authority 是否已发布、pending 的是什么、如何区分异常/保留、唯一恢复入口是什么。
2. Skill 输出字段与 TASK-02 `ArchiveResult` 精确一致，无第二套字段或错误码。
3. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`、Skill matrix、Agent contract 与 feature-writeback Pipeline JSON parse 全部通过。
4. `rg` 审计确认 README 未复制 cleanup 分类/ancestry/journal 算法，也未建议手工删除保留资源。
5. 除三项白名单文档外无 prompt/pipeline/index 变化；条件性的 crctl Skill 若无需修改则保持零 diff。

## 5. 完成标志

直接消费者与实现契约一致，静态检查全部通过，无实现算法泄漏到 README/Skill；`tasks/_index.yml` 中 TASK-03 经 `crctl task done` 标记 done。

## 6. 接口契约

- **消费**：TASK-02 产出的 `ArchiveResult` 和 `crctl archive <cr> [--spec-id] --workspace <main>` 命令接口。
- **产出**：供 system-orchestrator/用户消费的文档契约；不产出代码接口，不修改 Pipeline 调用签名。
