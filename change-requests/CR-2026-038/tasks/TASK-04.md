---
id: CR-2026-038-TASK-04
type: TASK
cr-ref: CR-2026-038
plan-ref: CR-2026-038-plan
sdd-ref: CR-2026-038-sdd
title: 一次性迁移 Writeback 调用方契约
slug: migrate-writeback-callers
status: pending
estimate: 6h
depends-on: [CR-2026-038-TASK-03]
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:22:00+08:00"
---

# TASK-04：一次性迁移 Writeback 调用方契约

## 1. 任务描述

在内部 Writeback 与 merge 契约稳定后，同一 TASK 一次性迁移所有 active 生产调用方：Pipeline/Skill 只传业务输入并消费结构化结果，删除 candidate/generator/manifest 路径和 baseline 后独立 `advance writing-back`。不保留双入口。

输入为 TASK-02 的 `applyWriteback()` 公共业务契约和 TASK-03 的稳定 merge 行为。输出为与新深原语一致的 Prompt、help、index 和旧测试调用。

## 2. 涉及文件 / 模块

- `skills/writeback/writeback-prd-sdd/SKILL.md`
- `skills/writeback/writeback-tasks/SKILL.md`
- `skills/writeback/writeback-traceability/SKILL.md`
- `pipeline-templates/feature-writeback.pipeline.json`
- `skills/shared/crctl/SKILL.md`
- `skills/_index.yml`
- `skills/shared/crctl/scripts/crctl.mjs` help 文本
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/writeback/scripts/test/writeback.test.mjs`（仅内部 ABI/静态契约所需）

## 3. 实现要点

1. baseline Skill 只校验业务输入、调用一次 `crctl writeback-apply --stage baseline`、分类 complete/noop/stale/history-rewritten/source error；删除 generator、candidate 与独立 advance。
2. tasks Skill 同样只调用一次 `--stage tasks`；traceability Skill 可起草 milestone 业务文件，但只把 workspace-relative milestone-file 作为业务输入。
3. feature-writeback 三节点只编排 Skill 和传递业务参数；删除 generator 命令、candidate dir/manifestPath、journal/CAS/commit/push 算法与 baseline 独立 advance。
4. crctl Skill、CLI help 与 `_index.yml` 只描述业务参数、固定内部 generator 和 baseline 原子语义。
5. 旧 archive/writeback 生产测试改为只传业务输入，直接断言 baseline 返回 writing-back 且同一 commit；恶意 manifest 用内部 seam 覆盖。
6. generator 脚本内部 `--candidate-out` ABI 和内容转换算法保持不变；README/Agent 全面文本留给 CR-2026-042。

## 4. 验收条件

- [ ] active 公共 CLI、三个 writeback Skill 和 feature-writeback Pipeline 不接受/传递 candidate、candidate-out、manifest 或 generator 路径。
- [ ] feature-writeback baseline 节点及生产测试不存在成功后独立 `advance --to writing-back`。
- [ ] Pipeline 节点不复制 preflight、journal、CAS、Git stage/commit/push 或状态机算法。
- [ ] 三个 Skill 的命令、参数和 TASK-02 产出的 `applyWriteback()` 契约一致，traceability milestone-file 保持业务职责。
- [ ] CLI help、crctl Skill 和 `_index.yml` 描述一致；废弃公共参数返回 BAD_ARGS。
- [ ] Pipeline JSON 可 `JSON.parse`，Prompt lint 和相关 contract tests 通过。
- [ ] README、Agent、状态机、gates、generator transformation 无 diff。

## 5. 完成标志

全仓 active 调用方静态扫描零旧公共路径参数、零 baseline 独立 advance；所有直接调用方在同一提交切换，无兼容层。

## 6. 接口契约

**消费 TASK-02**：

```text
crctl writeback-apply <cr> --stage <stage> --spec-id <id>
  --target-version <version> [--milestone-name <name>] [--brief <text>]
  [--milestone-file <workspace-relative-path>] --workspace <workspace>
-> {phase,changed,commit,status,files,warnings,recoverCommand}
```

**消费 TASK-03**：无新公共接口；现有 `crctl merge` 行为保持命令面兼容。

**产出给 TASK-05**：更新后的 active Skill/Pipeline/help/index 与静态扫描断言；不得产出兼容 adapter、registry 或第二命令入口。
